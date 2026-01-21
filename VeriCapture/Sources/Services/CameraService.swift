//
//  CameraService.swift
//  VeriCapture
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
    
    let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var currentDevice: AVCaptureDevice?
    
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var currentAccelerometer: [Double]?
    private var currentHeading: Double?
    
    private var captureCompletion: ((Result<CaptureResult, CameraError>) -> Void)?
    private var isSetupComplete = false  // 重複セットアップ防止
    private var isSensorInitialized = false  // センサー初期化状態
    
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
    
    // MARK: - Camera Setup
    
    private func setupCamera() async {
        // 重複セットアップ防止
        guard !isSetupComplete else { return }
        isSetupComplete = true
        
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo
        
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
            
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
                photoOutput.maxPhotoQualityPrioritization = .quality
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
            print("[CameraService] Session started, isRunning: \(captureSession.isRunning)")
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
            
            // VeriCaptureロゴ（中央）
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
            
            let title = "VeriCapture Demo"
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
        Task { @MainActor in
            if let error = error {
                captureCompletion?(.failure(.captureFailed(error.localizedDescription)))
                captureCompletion = nil
                return
            }
            
            guard let imageData = photo.fileDataRepresentation() else {
                captureCompletion?(.failure(.dataConversionFailed))
                captureCompletion = nil
                return
            }
            
            guard let image = UIImage(data: imageData) else {
                captureCompletion?(.failure(.dataConversionFailed))
                captureCompletion = nil
                return
            }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let filename = "IMG_\(formatter.string(from: Date())).jpg"
            
            // センサーデータとカメラ設定を取得
            let sensorData = captureSensorData()
            let cameraSettings = captureCameraSettings()
            
            // 生の位置情報を取得（Map表示用）
            let rawLat = currentLocation?.coordinate.latitude
            let rawLon = currentLocation?.coordinate.longitude
            
            let result = CaptureResult(
                imageData: imageData,
                image: image,
                filename: filename,
                mimeType: "image/jpeg",
                captureTimestamp: Date(),
                sensorData: sensorData,
                cameraSettings: cameraSettings,
                flashMode: flashMode.rawValue,  // 撮影時のフラッシュモード
                rawLatitude: rawLat,
                rawLongitude: rawLon
            )
            
            currentImage = image
            captureCompletion?(.success(result))
            captureCompletion = nil
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension CameraService: CLLocationManagerDelegate {
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            currentLocation = locations.last
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            currentHeading = newHeading.trueHeading
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
        // エラー発生時（許可拒否含む）は位置情報をクリア
        Task { @MainActor in
            currentLocation = nil
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .denied, .restricted, .notDetermined:
                // 許可がない場合は位置情報をクリア
                currentLocation = nil
                print("[CameraService] Location authorization changed: \(manager.authorizationStatus.rawValue), cleared currentLocation")
            case .authorizedWhenInUse, .authorizedAlways:
                // 許可された場合は位置情報の更新を開始
                manager.startUpdatingLocation()
                manager.startUpdatingHeading()
                print("[CameraService] Location authorized, started updates")
            @unknown default:
                currentLocation = nil
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
    
    var errorDescription: String? {
        switch self {
        case .deviceNotAvailable: return "Camera device not available"
        case .setupFailed(let message): return "Camera setup failed: \(message)"
        case .cameraNotReady: return "Camera not ready"
        case .captureFailed(let message): return "Capture failed: \(message)"
        case .dataConversionFailed: return "Failed to convert image data"
        case .unauthorized: return "Camera access not authorized"
        }
    }
}
