//
//  CameraService.swift
//  VeraSnap
//
//  Camera Capture using AVFoundation
//  © 2026 VeritasChain Standards Organization
//

import Foundation
@preconcurrency import AVFoundation
import UIKit
import Combine
import CoreMotion
import CoreLocation

// MARK: - Camera Service

@MainActor
final class CameraService: NSObject, ObservableObject {
    
    // MARK: - Flash Mode
    
    enum FlashMode: String, CaseIterable {
        case off = "OFF"
        case auto = "AUTO"
        case on = "ON"
        
        var avFlashMode: AVCaptureDevice.FlashMode {
            switch self {
            case .off: return .off
            case .auto: return .auto
            case .on: return .on
            }
        }
        
        var icon: String {
            switch self {
            case .off: return "bolt.slash.fill"
            case .auto: return "bolt.badge.automatic.fill"
            case .on: return "bolt.fill"
            }
        }
        
        var next: FlashMode {
            switch self {
            case .off: return .auto
            case .auto: return .on
            case .on: return .off
            }
        }
    }
    
    @Published var isAuthorized = false
    @Published var isCameraReady = false
    @Published var currentImage: UIImage?
    @Published var error: CameraError?
    @Published var flashMode: FlashMode = .auto
    
    // 動画録画関連
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingProgress: Double = 0  // 0.0-1.0
    @Published var isMicrophoneAuthorized = false  // マイク許可状態
    @Published var autoStoppedVideoResult: VideoCaptureResult?  // 1分自動停止時の結果
    
    let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var movieOutput = AVCaptureMovieFileOutput()  // 動画録画用
    private var currentDevice: AVCaptureDevice?
    private var audioDevice: AVCaptureDevice?  // マイク用
    
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var currentAccelerometer: [Double]?
    private var currentHeading: Double?
    
    private var captureCompletion: ((Result<CaptureResult, CameraError>) -> Void)?
    private var videoCompletion: ((Result<VideoCaptureResult, CameraError>) -> Void)?  // 動画用
    private var recordingTimer: Timer?  // 録画時間計測用
    private var recordingStartTime: Date?
    private var isSetupComplete = false  // 重複セットアップ防止
    private var isSensorInitialized = false  // センサー初期化状態
    
    /// 最大録画時間（秒）
    static let maxRecordingDuration: TimeInterval = 60.0  // 1分
    
    /// セッションが実行中かどうか
    var isSessionRunning: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return captureSession.isRunning
        #endif
    }
    
    override init() {
        super.init()
        // センサー初期化は遅延実行（カメラ許可後）
    }
    
    // MARK: - Authorization
    
    func checkAuthorization() async {
        // 既にセットアップ済みの場合はスキップ
        guard !isSetupComplete else { return }
        
        #if targetEnvironment(simulator)
        // シミュレーターではカメラ不要なので常に準備完了
        isAuthorized = true
        isCameraReady = true
        isSetupComplete = true
        print("[CameraService] Simulator mode - camera ready")
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            // カメラ起動を遅延（ビューのレイアウト確定を待つ）
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            await setupCamera()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isAuthorized = granted
            if granted {
                // 権限ダイアログが閉じた後、UIの準備を待つ
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                await setupCamera()
            }
        case .denied, .restricted:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
        #endif
    }
    
    /// マイク許可を確認（動画録画用）
    func checkMicrophoneAuthorization() async {
        #if targetEnvironment(simulator)
        isMicrophoneAuthorized = true
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            isMicrophoneAuthorized = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            isMicrophoneAuthorized = granted
        case .denied, .restricted:
            isMicrophoneAuthorized = false
        @unknown default:
            isMicrophoneAuthorized = false
        }
        #endif
    }
    
    // MARK: - Camera Setup
    
    private func setupCamera() async {
        // 重複セットアップ防止
        guard !isSetupComplete else { return }
        isSetupComplete = true
        
        captureSession.beginConfiguration()
        
        // 写真と動画の両方に対応するプリセット
        captureSession.sessionPreset = .high
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            error = .deviceNotAvailable
            return
        }
        
        currentDevice = device
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            // 写真出力
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
                photoOutput.maxPhotoQualityPrioritization = .quality
            }
            
            // 動画出力
            if captureSession.canAddOutput(movieOutput) {
                captureSession.addOutput(movieOutput)
                
                // 最大録画時間を設定
                movieOutput.maxRecordedDuration = CMTime(seconds: Self.maxRecordingDuration, preferredTimescale: 600)
                
                // ビデオ接続の安定化設定
                if let connection = movieOutput.connection(with: .video) {
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .auto
                    }
                }
            }
            
            // オーディオ入力（マイク）- マイク許可がある場合のみ
            // 🔴 重要: マイク許可なしでAVCaptureDeviceInputを作成するとクラッシュする
            let audioAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if audioAuthStatus == .authorized {
                do {
                    if let audioDevice = AVCaptureDevice.default(for: .audio) {
                        self.audioDevice = audioDevice
                        let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                        if captureSession.canAddInput(audioInput) {
                            captureSession.addInput(audioInput)
                            print("[CameraService] Audio input added successfully")
                        }
                    }
                } catch {
                    print("[CameraService] Audio input setup failed (will record without audio): \(error.localizedDescription)")
                    // オーディオなしで続行
                }
            } else {
                print("[CameraService] Microphone not authorized (status: \(audioAuthStatus.rawValue)), video will be recorded without audio")
            }
            
            captureSession.commitConfiguration()
            
            // バックグラウンドスレッドでセッション開始（完了を待つ）
            let session = captureSession
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                    DispatchQueue.main.async {
                        continuation.resume()
                    }
                }
            }
            
            isCameraReady = true
            print("[CameraService] Session started with video support, isRunning: \(captureSession.isRunning)")
            // センサーは撮影直前まで遅延初期化（初回撮影で初期化）
            
        } catch {
            self.error = .setupFailed(error.localizedDescription)
        }
    }
    
    /// センサー類の遅延初期化（初回撮影時に呼ばれる）
    private func ensureSensorsInitialized() {
        guard !isSensorInitialized else { return }
        isSensorInitialized = true
        
        setupLocationManager()
        setupMotionManager()
        print("[CameraService] Sensors initialized on demand")
    }
    
    // MARK: - Photo Capture
    
    func capturePhoto() async throws -> CaptureResult {
        // 初回撮影時にセンサーを初期化（遅延初期化）
        ensureSensorsInitialized()
        
        #if targetEnvironment(simulator)
        // シミュレーターではダミー画像を生成
        return generateSimulatorCaptureResult()
        #else
        
        // セッションが停止している場合は再開を試みる
        if !captureSession.isRunning {
            print("[CameraService] Session not running, attempting restart before capture...")
            await resumeSessionAfterAuth()
            
            // それでも動いていない場合はエラー
            if !captureSession.isRunning {
                throw CameraError.cameraNotReady
            }
        }
        
        guard isCameraReady else { throw CameraError.cameraNotReady }
        
        let sensorSnapshot = captureSensorData()
        let cameraSettingsSnapshot = captureCameraSettings()
        let capturedFlashMode = flashMode.rawValue  // 撮影時のフラッシュモードを記録
        
        return try await withCheckedThrowingContinuation { continuation in
            captureCompletion = { result in
                switch result {
                case .success(var captureResult):
                    captureResult.sensorData = sensorSnapshot
                    captureResult.cameraSettings = cameraSettingsSnapshot
                    captureResult.flashMode = capturedFlashMode
                    continuation.resume(returning: captureResult)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            
            let settings = AVCapturePhotoSettings()
            settings.flashMode = self.flashMode.avFlashMode
            
            // フラッシュ使用時の最適化: 速度優先モード
            // これによりプリフラッシュ測光が簡略化される
            if self.flashMode != .off {
                settings.photoQualityPrioritization = .speed
            } else {
                settings.photoQualityPrioritization = .balanced
            }
            
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
        #endif
    }
    
    // MARK: - Video Recording
    
    /// マイク許可を確認し、必要に応じてオーディオ入力をセッションに追加
    // 🔴 マイク関連機能は一時的に無効化（Info.plist問題を回避）
    // 動画は音声なしで録画されます
    // 将来的にユーザーが設定アプリでマイク許可した場合のみ音声を含める
    
    /// 動画録画を開始
    func startRecording() async throws {
        // 初回録画時にセンサーを初期化
        ensureSensorsInitialized()
        
        #if targetEnvironment(simulator)
        // シミュレーターでは録画をシミュレート（マイク設定不要）
        isRecording = true
        recordingStartTime = Date()
        startRecordingTimer()
        print("[CameraService] Simulator: Recording started (simulated)")
        return
        #else
        
        // 🔴 マイク許可要求を削除（Info.plist問題を回避）
        // 動画は音声なしで録画されます
        print("[CameraService] Recording will be without audio (microphone disabled)")
        
        guard !isRecording else {
            print("[CameraService] Already recording")
            return
        }
        
        // セッションが停止している場合は再開
        if !captureSession.isRunning {
            print("[CameraService] Session not running, attempting restart before recording...")
            await resumeSessionAfterAuth()
            
            if !captureSession.isRunning {
                throw CameraError.cameraNotReady
            }
        }
        
        guard isCameraReady else { throw CameraError.cameraNotReady }
        
        // 一時ファイルのパスを生成
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "VID_\(formatter.string(from: Date())).mp4"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        // 既存ファイルがあれば削除
        try? FileManager.default.removeItem(at: tempURL)
        
        // 録画開始
        movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        
        isRecording = true
        recordingStartTime = Date()
        startRecordingTimer()
        
        print("[CameraService] Recording started: \(filename)")
        #endif
    }
    
    /// 動画録画を停止
    func stopRecording() async throws -> VideoCaptureResult {
        #if targetEnvironment(simulator)
        // シミュレーターではダミーの動画結果を返す
        stopRecordingTimer()
        isRecording = false
        let duration = recordingDuration
        recordingDuration = 0
        recordingProgress = 0
        return generateSimulatorVideoCaptureResult(duration: duration)
        #else
        
        guard isRecording else {
            throw CameraError.recordingNotStarted
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            videoCompletion = { result in
                continuation.resume(with: result)
            }
            
            movieOutput.stopRecording()
            stopRecordingTimer()
        }
        #endif
    }
    
    /// 録画をキャンセル（保存しない）
    func cancelRecording() {
        guard isRecording else { return }
        
        #if !targetEnvironment(simulator)
        movieOutput.stopRecording()
        #endif
        
        stopRecordingTimer()
        isRecording = false
        recordingDuration = 0
        recordingProgress = 0
        videoCompletion = nil
        
        print("[CameraService] Recording cancelled")
    }
    
    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
                self.recordingProgress = min(self.recordingDuration / Self.maxRecordingDuration, 1.0)
                
                // 最大時間に達したら自動停止
                if self.recordingDuration >= Self.maxRecordingDuration {
                    print("[CameraService] Max recording duration reached, stopping...")
                    // 自動停止の場合はcompletionを呼ばない（UIで処理）
                }
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartTime = nil
    }
    
    #if targetEnvironment(simulator)
    /// シミュレーター用のダミー動画結果生成
    private func generateSimulatorVideoCaptureResult(duration: TimeInterval) -> VideoCaptureResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "VID_\(formatter.string(from: Date())).mp4"
        
        // 🔴 シミュレーター: 最終保存先にダミーファイルを作成
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mediaDir = documentsDir.appendingPathComponent("media")
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        let videoURL = mediaDir.appendingPathComponent(filename)
        
        // ダミーのMP4データを作成（最小限のMP4ヘッダー）
        let dummyMP4Data = createMinimalMP4Data(duration: duration)
        try? dummyMP4Data.write(to: videoURL)
        
        print("[CameraService] 🎬 Simulator: Created dummy video at \(videoURL.path)")
        
        return VideoCaptureResult(
            videoURL: videoURL,
            filename: filename,
            mimeType: "video/mp4",
            captureTimestamp: Date(),
            duration: duration,
            resolution: VideoResolution(width: 1920, height: 1080),
            frameRate: 30.0,
            codec: "h264",
            hasAudio: true,
            fileSize: dummyMP4Data.count,
            assetHash: "sha256:simulator_video_hash_\(UUID().uuidString)",
            sensorData: SensorData(
                gps: GPSData(
                    latitudeHash: "sha256:\("35.6584".sha256Hash)",
                    longitudeHash: "sha256:\("139.7015".sha256Hash)",
                    altitude: 35.0,
                    accuracy: 5.0
                ),
                accelerometer: [0.0, 0.0, 9.81],
                compass: 0.0,
                ambientLight: 500.0
            ),
            cameraSettings: CameraSettings(
                focalLength: 4.25,
                aperture: 1.8,
                iso: 100,
                exposureTime: 0.033,
                flashMode: "OFF"
            ),
            rawLatitude: 35.6584,
            rawLongitude: 139.7015,
            thumbnail: generateVideoThumbnail(duration: duration)
        )
    }
    
    /// シミュレーター用の最小限のMP4データを生成
    private func createMinimalMP4Data(duration: TimeInterval) -> Data {
        // 最小限のMP4ファイル構造（ftyp + moov ボックス）
        var data = Data()
        
        // ftyp box (file type)
        let ftypSize: UInt32 = 20
        data.append(contentsOf: withUnsafeBytes(of: ftypSize.bigEndian) { Array($0) })
        data.append("ftyp".data(using: .ascii)!)
        data.append("isom".data(using: .ascii)!)
        data.append(contentsOf: [0x00, 0x00, 0x02, 0x00]) // minor version
        data.append("isom".data(using: .ascii)!)
        
        // moov box (movie header) - minimal
        let moovSize: UInt32 = 8
        data.append(contentsOf: withUnsafeBytes(of: moovSize.bigEndian) { Array($0) })
        data.append("moov".data(using: .ascii)!)
        
        // ダミーデータを追加してファイルサイズを調整
        let targetSize = Int(duration * 100_000) // 約100KB/秒
        let paddingSize = max(0, targetSize - data.count)
        data.append(Data(repeating: 0, count: paddingSize))
        
        return data
    }
    
    private func generateVideoThumbnail(duration: TimeInterval) -> UIImage {
        let size = CGSize(width: 320, height: 180)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // グラデーション背景
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // 再生アイコン
            let playIcon = "▶"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48),
                .foregroundColor: UIColor.white
            ]
            let textSize = playIcon.size(withAttributes: attrs)
            playIcon.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2), withAttributes: attrs)
            
            // 録画時間
            let durationText = String(format: "%.1fs", duration)
            let durationAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium),
                .foregroundColor: UIColor.white
            ]
            durationText.draw(at: CGPoint(x: 10, y: size.height - 24), withAttributes: durationAttrs)
        }
    }
    #endif
    
    #if targetEnvironment(simulator)
    /// シミュレーター用のダミー画像生成
    private func generateSimulatorCaptureResult() -> CaptureResult {
        let size = CGSize(width: 1920, height: 1080)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            // グラデーション背景
            let colors = [
                UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1).cgColor,
                UIColor(red: 0.6, green: 0.3, blue: 0.9, alpha: 1).cgColor
            ]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            
            // VeraSnapロゴ（中央）
            let logoRect = CGRect(x: size.width/2 - 80, y: size.height/2 - 120, width: 160, height: 160)
            let shieldPath = UIBezierPath()
            let cx = logoRect.midX
            let cy = logoRect.midY
            let w = logoRect.width * 0.4
            let h = logoRect.height * 0.5
            
            shieldPath.move(to: CGPoint(x: cx, y: cy - h))
            shieldPath.addLine(to: CGPoint(x: cx + w, y: cy - h * 0.6))
            shieldPath.addLine(to: CGPoint(x: cx + w, y: cy + h * 0.2))
            shieldPath.addQuadCurve(to: CGPoint(x: cx, y: cy + h), controlPoint: CGPoint(x: cx + w * 0.5, y: cy + h * 0.8))
            shieldPath.addQuadCurve(to: CGPoint(x: cx - w, y: cy + h * 0.2), controlPoint: CGPoint(x: cx - w * 0.5, y: cy + h * 0.8))
            shieldPath.addLine(to: CGPoint(x: cx - w, y: cy - h * 0.6))
            shieldPath.close()
            
            UIColor.white.withAlphaComponent(0.9).setFill()
            shieldPath.fill()
            
            // テキスト
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            
            let title = "VeraSnap Demo"
            let titleRect = CGRect(x: 0, y: size.height/2 + 80, width: size.width, height: 60)
            title.draw(in: titleRect, withAttributes: titleAttrs)
            
            // タイムスタンプ
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let timestamp = formatter.string(from: Date())
            
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8),
                .paragraphStyle: paragraphStyle
            ]
            
            let timeRect = CGRect(x: 0, y: size.height/2 + 150, width: size.width, height: 40)
            timestamp.draw(in: timeRect, withAttributes: timeAttrs)
            
            // Simulator表示
            let simAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.6),
                .paragraphStyle: paragraphStyle
            ]
            let simRect = CGRect(x: 0, y: size.height - 60, width: size.width, height: 30)
            "📱 Simulator Mode".draw(in: simRect, withAttributes: simAttrs)
        }
        
        let imageData = image.jpegData(compressionQuality: 0.9) ?? Data()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "IMG_\(formatter.string(from: Date())).jpg"
        
        // シミュレータ用のテスト座標（東京・渋谷）
        let testLatitude = 35.6584
        let testLongitude = 139.7015
        
        return CaptureResult(
            imageData: imageData,
            image: image,
            filename: filename,
            mimeType: "image/jpeg",
            captureTimestamp: Date(),
            sensorData: SensorData(
                gps: GPSData(
                    latitudeHash: "sha256:\("\(testLatitude)".sha256Hash)",
                    longitudeHash: "sha256:\("\(testLongitude)".sha256Hash)",
                    altitude: 35.0,
                    accuracy: 5.0
                ),
                accelerometer: [0.0, 0.0, 9.81],
                compass: 0.0,
                ambientLight: 500.0
            ),
            cameraSettings: CameraSettings(
                focalLength: 4.25,
                aperture: 1.8,
                iso: 100,
                exposureTime: 0.01,
                flashMode: flashMode.rawValue
            ),
            flashMode: flashMode.rawValue,
            rawLatitude: testLatitude,
            rawLongitude: testLongitude
        )
    }
    #endif
    
    // MARK: - Sensor Data
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // 許可状態をチェック - 許可がない場合は位置情報を使用しない
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            // 許可がない場合は何もしない（currentLocationはnil）
            print("[CameraService] Location not authorized, skipping location updates")
        @unknown default:
            break
        }
    }
    
    private func setupMotionManager() {
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.1
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                if let acceleration = data?.acceleration {
                    self?.currentAccelerometer = [acceleration.x, acceleration.y, acceleration.z]
                }
            }
        }
    }
    
    private func captureSensorData() -> SensorData {
        var gps: GPSData? = nil
        
        if let location = currentLocation {
            let latHash = "\(location.coordinate.latitude)".sha256Hash
            let lonHash = "\(location.coordinate.longitude)".sha256Hash
            
            gps = GPSData(
                latitudeHash: "sha256:\(latHash)",
                longitudeHash: "sha256:\(lonHash)",
                altitude: location.altitude,
                accuracy: location.horizontalAccuracy
            )
        }
        
        return SensorData(
            gps: gps,
            accelerometer: currentAccelerometer,
            compass: currentHeading,
            ambientLight: nil
        )
    }
    
    private func captureCameraSettings() -> CameraSettings? {
        guard let device = currentDevice else { return nil }
        
        return CameraSettings(
            focalLength: Double(device.activeFormat.videoFieldOfView),
            aperture: Double(device.lensAperture),
            iso: Int(device.iso),
            exposureTime: Double(device.exposureDuration.seconds),
            flashMode: flashMode.rawValue
        )
    }
    
    // MARK: - Camera Switch
    
    func switchCamera() {
        guard let currentInput = captureSession.inputs.first as? AVCaptureDeviceInput else { return }
        
        let newPosition: AVCaptureDevice.Position = currentInput.device.position == .back ? .front : .back
        
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else { return }
        
        do {
            let newInput = try AVCaptureDeviceInput(device: newDevice)
            
            captureSession.beginConfiguration()
            captureSession.removeInput(currentInput)
            
            if captureSession.canAddInput(newInput) {
                captureSession.addInput(newInput)
                currentDevice = newDevice
            } else {
                captureSession.addInput(currentInput)
            }
            
            captureSession.commitConfiguration()
        } catch {
            print("Error switching camera: \(error)")
        }
    }
    
    // MARK: - Session Control for Authentication
    
    /// FaceID/TouchID認証前にカメラセッションを一時停止
    /// 注意: 現在は使用していない（認証中もセッションを維持する方針）
    /// 将来的に必要になる可能性があるため残している
    func pauseSessionForAuth() async {
        #if targetEnvironment(simulator)
        return
        #else
        guard captureSession.isRunning else { return }
        
        print("[CameraService] Pausing session for authentication...")
        let session = captureSession
        await Task.detached {
            session.stopRunning()
        }.value
        
        // 停止完了を待機
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        print("[CameraService] Session paused for auth")
        #endif
    }
    
    /// FaceID/TouchID認証後にカメラセッションを再開
    func resumeSessionAfterAuth() async {
        #if targetEnvironment(simulator)
        isCameraReady = true
        return
        #else
        print("[CameraService] Resuming session after authentication...")
        
        // 【重要】いきなり reconfigureSession() を呼ばない！
        // まずは単純な startRunning (低コスト) を試みる
        await ensureSessionRunning()
        
        // それでもダメだった場合のみ、最終手段として再構成する
        if !captureSession.isRunning {
            print("[CameraService] Simple restart failed, performing full reconfiguration...")
            await reconfigureSession()
        }
        
        // センサーと位置情報の更新を再開
        restartSensorsAndLocation()
        
        isCameraReady = captureSession.isRunning
        print("[CameraService] Session resumed, isRunning: \(captureSession.isRunning)")
        #endif
    }
    
    /// センサーと位置情報の更新を再開
    private func restartSensorsAndLocation() {
        // モーションセンサーを再開
        if motionManager.isAccelerometerAvailable {
            motionManager.startAccelerometerUpdates()
        }
        
        // 位置情報の更新を再開（許可されている場合のみ）
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
            print("[CameraService] Location updates restarted")
        default:
            print("[CameraService] Location not authorized, skipping location restart")
        }
    }
    
    /// カメラセッションが実行中であることを確認し、停止している場合は再開
    func ensureSessionRunning() async {
        #if targetEnvironment(simulator)
        return
        #else
        // 既に動いているなら何もしない（ここが重要）
        guard !captureSession.isRunning else {
            print("[CameraService] Session is already running. Skipping restart.")
            return
        }
        
        guard isSetupComplete else { return }
        
        print("[CameraService] Session was stopped, attempting restart...")
        
        // バックグラウンドスレッドでセッションを再開（完了を待つ、最大3回リトライ）
        for attempt in 1...3 {
            let session = captureSession
            
            // startRunningの完了を待つ
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                    DispatchQueue.main.async {
                        continuation.resume()
                    }
                }
            }
            
            // 【重要】ハードウェア切り替え待ち時間を十分に取る
            // 初回FaceID後は特にここが重要
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            if captureSession.isRunning {
                print("[CameraService] Session restarted successfully on attempt \(attempt)")
                return
            }
            
            print("[CameraService] Restart attempt \(attempt) failed (err=-17281 likely). Retrying...")
            
            // リトライ前にさらに待機
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: 700_000_000) // 700ms
            }
        }
        
        // ここまで来たら reconfigureSession は呼び出し元（resumeSessionAfterAuth）に任せる
        print("[CameraService] All simple restart attempts failed.")
        #endif
    }
    
    /// カメラセッションを完全に再構成
    private func reconfigureSession() async {
        #if targetEnvironment(simulator)
        return
        #else
        // 既存のセッションを停止（完了を待つ）
        if captureSession.isRunning {
            let session = captureSession
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    session.stopRunning()
                    DispatchQueue.main.async {
                        continuation.resume()
                    }
                }
            }
        }
        
        // 入力と出力をクリア
        captureSession.beginConfiguration()
        
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        
        // 出力は保持（photoOutputは再利用）
        
        // デバイスを再取得
        guard let device = currentDevice ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("[CameraService] Failed to get camera device for reconfiguration")
            captureSession.commitConfiguration()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            captureSession.commitConfiguration()
            
            // バックグラウンドでセッション開始（完了を待つ、リトライ付き）
            for attempt in 1...3 {
                let session = captureSession
                
                // startRunningの完了を待つ
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global(qos: .userInitiated).async {
                        session.startRunning()
                        DispatchQueue.main.async {
                            continuation.resume()
                        }
                    }
                }
                
                // セッションが安定するまで待機
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                
                if captureSession.isRunning {
                    isCameraReady = true
                    print("[CameraService] Session reconfigured successfully on attempt \(attempt), isRunning: true")
                    return
                }
                
                print("[CameraService] Reconfigure attempt \(attempt) failed, isRunning: false")
                
                // リトライ前に追加待機
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            }
            
            // 全リトライ失敗
            isCameraReady = captureSession.isRunning
            print("[CameraService] Session reconfigured after all attempts, isRunning: \(captureSession.isRunning)")
            
        } catch {
            print("[CameraService] Reconfiguration failed: \(error)")
            captureSession.commitConfiguration()
        }
        #endif
    }
    
    /// カメラセッションを停止（完了を確実に待つ）
    func stopSession() async {
        print("[CameraService] Stopping session...")
        
        // センサーを先に停止
        motionManager.stopAccelerometerUpdates()
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        
        // カメラが動いている場合のみ停止
        guard captureSession.isRunning else {
            print("[CameraService] Session already stopped")
            return
        }
        
        // withCheckedContinuationで完了を確実に待つ
        let session = captureSession
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                session.stopRunning()
                // 停止が完了してからcontinuationを再開
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
        }
        
        // 停止完了を確認
        print("[CameraService] Session stopped, isRunning: \(captureSession.isRunning)")
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // エラーと画像データを先にキャプチャ
        let errorMessage = error?.localizedDescription
        let imageData = photo.fileDataRepresentation()
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            if let errorMessage = errorMessage {
                self.captureCompletion?(.failure(.captureFailed(errorMessage)))
                self.captureCompletion = nil
                return
            }
            
            guard let imageData = imageData else {
                self.captureCompletion?(.failure(.dataConversionFailed))
                self.captureCompletion = nil
                return
            }
            
            guard let image = UIImage(data: imageData) else {
                self.captureCompletion?(.failure(.dataConversionFailed))
                self.captureCompletion = nil
                return
            }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let filename = "IMG_\(formatter.string(from: Date())).jpg"
            
            // センサーデータとカメラ設定を取得
            let sensorData = self.captureSensorData()
            let cameraSettings = self.captureCameraSettings()
            
            // 生の位置情報を取得（Map表示用）
            let rawLat = self.currentLocation?.coordinate.latitude
            let rawLon = self.currentLocation?.coordinate.longitude
            
            let result = CaptureResult(
                imageData: imageData,
                image: image,
                filename: filename,
                mimeType: "image/jpeg",
                captureTimestamp: Date(),
                sensorData: sensorData,
                cameraSettings: cameraSettings,
                flashMode: self.flashMode.rawValue,  // 撮影時のフラッシュモード
                rawLatitude: rawLat,
                rawLongitude: rawLon
            )
            
            self.currentImage = image
            self.captureCompletion?(.success(result))
            self.captureCompletion = nil
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension CameraService: CLLocationManagerDelegate {
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let lastLocation = locations.last
        Task { @MainActor [weak self] in
            self?.currentLocation = lastLocation
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = newHeading.trueHeading
        Task { @MainActor [weak self] in
            self?.currentHeading = heading
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
        // エラー発生時（許可拒否含む）は位置情報をクリア
        Task { @MainActor [weak self] in
            self?.currentLocation = nil
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        // managerをキャプチャしてTask内で使用（selfを避ける）
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            switch status {
            case .denied, .restricted, .notDetermined:
                // 許可がない場合は位置情報をクリア
                self.currentLocation = nil
                print("[CameraService] Location authorization changed: \(status.rawValue), cleared currentLocation")
            case .authorizedWhenInUse, .authorizedAlways:
                // 許可された場合は位置情報の更新を開始
                // Note: managerはnonisolated contextでは使用できないため、
                // 単にログを出力し、実際の更新開始はsetupLocationManagerで行われている
                print("[CameraService] Location authorized")
            @unknown default:
                self.currentLocation = nil
            }
        }
    }
}

// MARK: - Capture Result

struct CaptureResult: Sendable {
    let imageData: Data
    let image: UIImage
    let filename: String
    let mimeType: String
    let captureTimestamp: Date
    var sensorData: SensorData?
    var cameraSettings: CameraSettings?
    var flashMode: String  // OFF, AUTO, ON
    
    // ローカル保存用の生の位置情報（Proof JSONには含まれない）
    var rawLatitude: Double?
    var rawLongitude: Double?
    
    var assetHash: String { imageData.sha256Prefixed }
    var assetSize: Int { imageData.count }
}

// MARK: - Camera Error

enum CameraError: LocalizedError, Sendable {
    case deviceNotAvailable
    case setupFailed(String)
    case cameraNotReady
    case captureFailed(String)
    case dataConversionFailed
    case unauthorized
    case recordingNotStarted
    case recordingFailed(String)
    case hashingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .deviceNotAvailable: return "Camera device not available"
        case .setupFailed(let message): return "Camera setup failed: \(message)"
        case .cameraNotReady: return "Camera not ready"
        case .captureFailed(let message): return "Capture failed: \(message)"
        case .dataConversionFailed: return "Failed to convert image data"
        case .unauthorized: return "Camera access not authorized"
        case .recordingNotStarted: return "Recording not started"
        case .recordingFailed(let message): return "Recording failed: \(message)"
        case .hashingFailed(let message): return "Failed to hash video: \(message)"
        }
    }
}

// MARK: - Video Capture Result

struct VideoCaptureResult: Sendable {
    let videoURL: URL
    let filename: String
    let mimeType: String
    let captureTimestamp: Date
    let duration: Double
    let resolution: VideoResolution
    let frameRate: Double
    let codec: String
    let hasAudio: Bool
    let fileSize: Int
    let assetHash: String
    var sensorData: SensorData?
    var cameraSettings: CameraSettings?
    var rawLatitude: Double?
    var rawLongitude: Double?
    let thumbnail: UIImage?
}

// MARK: - Video Recording Delegate

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("[CameraService] Recording started to: \(fileURL.lastPathComponent)")
    }
    
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // 🔴 重要: 全てのファイル操作を同期的に行う（一時ファイルが消える前に）
        
        // エラーメッセージを先にキャプチャ
        let errorMessage = error?.localizedDescription
        
        if error != nil {
            print("[CameraService] ❌ Recording error: \(errorMessage ?? "unknown")")
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isRecording = false
                self.recordingDuration = 0
                self.recordingProgress = 0
                self.videoCompletion?(.failure(.recordingFailed(errorMessage ?? "Recording failed")))
                self.videoCompletion = nil
            }
            return
        }
        
        // ファイル名を生成
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "VID_\(formatter.string(from: Date())).mp4"
        
        // 最終的な保存先
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mediaDir = documentsDir.appendingPathComponent("media")
        
        // ディレクトリ作成
        do {
            try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        } catch {
            let errMsg = error.localizedDescription
            print("[CameraService] ❌ Failed to create media directory: \(errMsg)")
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isRecording = false
                self.recordingDuration = 0
                self.recordingProgress = 0
                self.videoCompletion?(.failure(.recordingFailed(errMsg)))
                self.videoCompletion = nil
            }
            return
        }
        
        let finalURL = mediaDir.appendingPathComponent(filename)
        
        // 既存ファイルがあれば削除
        try? FileManager.default.removeItem(at: finalURL)
        
        // 一時ファイルの存在確認
        guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
            print("[CameraService] ❌ Output file does not exist: \(outputFileURL.path)")
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isRecording = false
                self.recordingDuration = 0
                self.recordingProgress = 0
                self.videoCompletion?(.failure(.recordingFailed("Video file was not created")))
                self.videoCompletion = nil
            }
            return
        }
        
        // 🔴 同期的にファイルを移動（一時ファイルが消える前に）
        do {
            try FileManager.default.moveItem(at: outputFileURL, to: finalURL)
            print("[CameraService] ✅ Video moved to: \(finalURL.path)")
        } catch {
            print("[CameraService] ❌ Move failed, trying copy: \(error)")
            do {
                try FileManager.default.copyItem(at: outputFileURL, to: finalURL)
                try? FileManager.default.removeItem(at: outputFileURL)
                print("[CameraService] ✅ Video copied to: \(finalURL.path)")
            } catch {
                let errMsg = error.localizedDescription
                print("[CameraService] ❌ Copy also failed: \(errMsg)")
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isRecording = false
                    self.recordingDuration = 0
                    self.recordingProgress = 0
                    self.videoCompletion?(.failure(.recordingFailed("Failed to save video: \(errMsg)")))
                    self.videoCompletion = nil
                }
                return
            }
        }
        
        // ファイルサイズを取得（同期）
        let fileSize: Int
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: finalURL.path)
            fileSize = attributes[.size] as? Int ?? 0
            print("[CameraService] 🎬 File size: \(fileSize) bytes")
        } catch {
            let errMsg = error.localizedDescription
            print("[CameraService] ❌ Failed to get file attributes: \(errMsg)")
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isRecording = false
                self.recordingDuration = 0
                self.recordingProgress = 0
                self.videoCompletion?(.failure(.recordingFailed(errMsg)))
                self.videoCompletion = nil
            }
            return
        }
        
        // 以降の非同期処理はファイルが安全に保存された後
        let videoURL = finalURL
        let capturedFilename = filename
        let capturedFileSize = fileSize
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isRecording = false
            self.recordingDuration = 0
            self.recordingProgress = 0
            
            await self.processRecordedVideo(
                videoURL: videoURL,
                filename: capturedFilename,
                fileSize: capturedFileSize
            )
        }
    }
    
    /// 録画済み動画を処理（非同期）
    private func processRecordedVideo(videoURL: URL, filename: String, fileSize: Int) async {
        do {
            // 動画のメタデータを取得
            let asset = AVURLAsset(url: videoURL)
            let duration = try await asset.load(.duration).seconds
            
            // ビデオトラック情報
            var resolution = VideoResolution(width: 1920, height: 1080)
            var frameRate: Double = 30.0
            var codec = "h264"
            
            if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                let size = try await videoTrack.load(.naturalSize)
                resolution = VideoResolution(width: Int(size.width), height: Int(size.height))
                frameRate = Double(try await videoTrack.load(.nominalFrameRate))
                
                // コーデック情報
                let formatDescriptions = try await videoTrack.load(.formatDescriptions)
                if let formatDesc = formatDescriptions.first {
                    let codecType = CMFormatDescriptionGetMediaSubType(formatDesc)
                    codec = fourCharCodeToString(codecType)
                }
            }
            
            // オーディオトラックの有無
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let hasAudio = !audioTracks.isEmpty
            
            // ストリーミングハッシュ計算
            print("[CameraService] Calculating hash for video (\(fileSize) bytes)...")
            let assetHash: String
            do {
                assetHash = try StreamingHash.sha256(fileAt: videoURL) { progress in
                    print("[CameraService] Hash progress: \(Int(progress * 100))%")
                }
            } catch {
                videoCompletion?(.failure(.hashingFailed(error.localizedDescription)))
                videoCompletion = nil
                return
            }
            
            // サムネイル生成
            let thumbnail = await generateThumbnailAsync(from: videoURL, at: 0.5)
            if let thumbnail = thumbnail {
                print("[CameraService] 🖼️ Thumbnail generated: \(thumbnail.size.width)x\(thumbnail.size.height)")
            } else {
                print("[CameraService] ⚠️ Thumbnail generation failed")
            }
            
            // センサーデータを取得
            let sensorData = captureSensorData()
            let cameraSettings = captureCameraSettings()
            
            let result = VideoCaptureResult(
                videoURL: videoURL,
                filename: filename,
                mimeType: "video/mp4",
                captureTimestamp: Date(),
                duration: duration,
                resolution: resolution,
                frameRate: frameRate,
                codec: codec,
                hasAudio: hasAudio,
                fileSize: fileSize,
                assetHash: assetHash,
                sensorData: sensorData,
                cameraSettings: cameraSettings,
                rawLatitude: currentLocation?.coordinate.latitude,
                rawLongitude: currentLocation?.coordinate.longitude,
                thumbnail: thumbnail
            )
            
            print("[CameraService] ✅ Video recorded: \(filename), duration: \(String(format: "%.1f", duration))s, size: \(fileSize) bytes")
            
            // completionがある場合（手動停止）はそれを呼ぶ
            // completionがない場合（1分自動停止）はPublished変数に設定
            if let completion = videoCompletion {
                completion(.success(result))
                videoCompletion = nil
            } else {
                print("[CameraService] 📢 Auto-stopped recording, publishing result")
                autoStoppedVideoResult = result
            }
            
        } catch {
            print("[CameraService] ❌ Failed to process video: \(error)")
            videoCompletion?(.failure(.recordingFailed(error.localizedDescription)))
            videoCompletion = nil
        }
    }
    
    /// 4文字コードを文字列に変換
    private func fourCharCodeToString(_ code: FourCharCode) -> String {
        let bytes: [CChar] = [
            CChar(truncatingIfNeeded: (code >> 24) & 0xFF),
            CChar(truncatingIfNeeded: (code >> 16) & 0xFF),
            CChar(truncatingIfNeeded: (code >> 8) & 0xFF),
            CChar(truncatingIfNeeded: code & 0xFF),
            0
        ]
        return String(cString: bytes)
    }
    
    /// 動画からサムネイルを生成（async版）
    private func generateThumbnailAsync(from url: URL, at time: Double) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        
        return await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: cmTime)]) { _, cgImage, _, _, error in
                if let cgImage = cgImage {
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                } else {
                    if let error = error {
                        print("[CameraService] Thumbnail generation failed: \(error)")
                    }
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
