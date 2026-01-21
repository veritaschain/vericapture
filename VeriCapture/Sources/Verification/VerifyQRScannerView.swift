//
//  VerifyQRScannerView.swift
//  VeriCapture
//
//  QR Code Scanner for Verification
//  © 2026 VeritasChain Standards Organization
//

import SwiftUI
import AVFoundation

// MARK: - QR Scanner View

struct VerifyQRScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String, UIImage?) -> Void  // QRコードとキャプチャ画像
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> VerifyQRScannerViewController {
        let controller = VerifyQRScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: VerifyQRScannerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, VerifyQRScannerDelegate {
        let parent: VerifyQRScannerView
        
        init(_ parent: VerifyQRScannerView) {
            self.parent = parent
        }
        
        func didScanCode(_ code: String, capturedImage: UIImage?) {
            parent.onCodeScanned(code, capturedImage)
            parent.isPresented = false
        }
        
        func didFailWithError(_ error: Error) {
            print("QR Scanner Error: \(error)")
            parent.isPresented = false
        }
    }
}

// MARK: - QR Scanner Delegate Protocol

protocol VerifyQRScannerDelegate: AnyObject {
    func didScanCode(_ code: String, capturedImage: UIImage?)
    func didFailWithError(_ error: Error)
}

// MARK: - QR Scanner View Controller

class VerifyQRScannerViewController: UIViewController {
    weak var delegate: VerifyQRScannerDelegate?
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false
    private var latestFrame: UIImage?  // 最新のフレームを保持
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataQueue = DispatchQueue(label: "VideoDataQueue", qos: .userInitiated)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupOverlay()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startScanning()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }
    
    private func setupCamera() {
        let session = AVCaptureSession()
        
        guard let device = AVCaptureDevice.default(for: .video) else {
            delegate?.didFailWithError(VerifyQRScannerError.cameraUnavailable)
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            // QRコード検出用のメタデータ出力
            let metadataOutput = AVCaptureMetadataOutput()
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
                metadataOutput.metadataObjectTypes = [.qr]
            }
            
            // フレームキャプチャ用のビデオデータ出力
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
            }
            
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.frame = view.layer.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            
            self.captureSession = session
            self.previewLayer = previewLayer
            
        } catch {
            delegate?.didFailWithError(error)
        }
    }
    
    private func setupOverlay() {
        // Semi-transparent overlay
        let overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.addSubview(overlayView)
        
        // Scanning area (center square)
        let scanSize: CGFloat = 250
        let scanRect = CGRect(
            x: (view.bounds.width - scanSize) / 2,
            y: (view.bounds.height - scanSize) / 2,
            width: scanSize,
            height: scanSize
        )
        
        // Cut out the scanning area
        let maskLayer = CAShapeLayer()
        let path = UIBezierPath(rect: overlayView.bounds)
        path.append(UIBezierPath(roundedRect: scanRect, cornerRadius: 12))
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        overlayView.layer.mask = maskLayer
        
        // Scanning frame
        let frameView = UIView(frame: scanRect)
        frameView.layer.borderColor = UIColor.white.cgColor
        frameView.layer.borderWidth = 3
        frameView.layer.cornerRadius = 12
        frameView.clipsToBounds = true
        view.addSubview(frameView)
        
        // Scan line animation (横棒アニメーション)
        let scanLine = UIView()
        scanLine.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.8)
        scanLine.frame = CGRect(x: 8, y: 0, width: scanSize - 16, height: 3)
        scanLine.layer.shadowColor = UIColor.systemGreen.cgColor
        scanLine.layer.shadowOffset = .zero
        scanLine.layer.shadowRadius = 4
        scanLine.layer.shadowOpacity = 0.8
        frameView.addSubview(scanLine)
        
        // スキャンラインを上下にアニメーション
        startScanLineAnimation(scanLine, in: frameView, scanSize: scanSize)
        
        // Corner accents
        addCornerAccents(to: frameView, size: scanSize)
        
        // Instructions label
        let label = UILabel()
        label.text = L10n.Verify.qrInstruction
        label.textColor = .white
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.frame = CGRect(x: 20, y: scanRect.maxY + 30, width: view.bounds.width - 40, height: 30)
        view.addSubview(label)
        
        // Title label
        let titleLabel = UILabel()
        titleLabel.text = L10n.Verify.title
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.frame = CGRect(x: 20, y: 60, width: view.bounds.width - 40, height: 40)
        view.addSubview(titleLabel)
        
        // Close button - Large tappable button
        let closeButton = UIButton(type: .system)
        closeButton.setTitle(L10n.Result.close, for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        closeButton.layer.cornerRadius = 25
        closeButton.layer.borderWidth = 2
        closeButton.layer.borderColor = UIColor.white.cgColor
        closeButton.frame = CGRect(x: (view.bounds.width - 140) / 2, y: view.bounds.height - 120, width: 140, height: 50)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
    }
    
    private func addCornerAccents(to frameView: UIView, size: CGFloat) {
        let cornerLength: CGFloat = 30
        let cornerWidth: CGFloat = 4
        let accentColor = UIColor.systemGreen.cgColor
        
        // Top-left
        let topLeft1 = CALayer()
        topLeft1.backgroundColor = accentColor
        topLeft1.frame = CGRect(x: -cornerWidth/2, y: -cornerWidth/2, width: cornerLength, height: cornerWidth)
        frameView.layer.addSublayer(topLeft1)
        
        let topLeft2 = CALayer()
        topLeft2.backgroundColor = accentColor
        topLeft2.frame = CGRect(x: -cornerWidth/2, y: -cornerWidth/2, width: cornerWidth, height: cornerLength)
        frameView.layer.addSublayer(topLeft2)
        
        // Top-right
        let topRight1 = CALayer()
        topRight1.backgroundColor = accentColor
        topRight1.frame = CGRect(x: size - cornerLength + cornerWidth/2, y: -cornerWidth/2, width: cornerLength, height: cornerWidth)
        frameView.layer.addSublayer(topRight1)
        
        let topRight2 = CALayer()
        topRight2.backgroundColor = accentColor
        topRight2.frame = CGRect(x: size - cornerWidth/2, y: -cornerWidth/2, width: cornerWidth, height: cornerLength)
        frameView.layer.addSublayer(topRight2)
        
        // Bottom-left
        let bottomLeft1 = CALayer()
        bottomLeft1.backgroundColor = accentColor
        bottomLeft1.frame = CGRect(x: -cornerWidth/2, y: size - cornerWidth/2, width: cornerLength, height: cornerWidth)
        frameView.layer.addSublayer(bottomLeft1)
        
        let bottomLeft2 = CALayer()
        bottomLeft2.backgroundColor = accentColor
        bottomLeft2.frame = CGRect(x: -cornerWidth/2, y: size - cornerLength + cornerWidth/2, width: cornerWidth, height: cornerLength)
        frameView.layer.addSublayer(bottomLeft2)
        
        // Bottom-right
        let bottomRight1 = CALayer()
        bottomRight1.backgroundColor = accentColor
        bottomRight1.frame = CGRect(x: size - cornerLength + cornerWidth/2, y: size - cornerWidth/2, width: cornerLength, height: cornerWidth)
        frameView.layer.addSublayer(bottomRight1)
        
        let bottomRight2 = CALayer()
        bottomRight2.backgroundColor = accentColor
        bottomRight2.frame = CGRect(x: size - cornerWidth/2, y: size - cornerLength + cornerWidth/2, width: cornerWidth, height: cornerLength)
        frameView.layer.addSublayer(bottomRight2)
    }
    
    private func startScanLineAnimation(_ scanLine: UIView, in frameView: UIView, scanSize: CGFloat) {
        // 初期位置
        scanLine.frame.origin.y = 8
        
        // 上下にアニメーション
        UIView.animate(
            withDuration: 2.0,
            delay: 0,
            options: [.curveEaseInOut, .repeat, .autoreverse],
            animations: {
                scanLine.frame.origin.y = scanSize - 11
            }
        )
    }
    
    @objc private func closeTapped() {
        stopScanning()
        dismiss(animated: true) { [weak self] in
            // delegateに閉じたことを通知（エラーなしで閉じる）
            self?.delegate?.didFailWithError(VerifyQRScannerError.userCancelled)
        }
    }
    
    func startScanning() {
        hasScanned = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }
    
    func stopScanning() {
        captureSession?.stopRunning()
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

extension VerifyQRScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasScanned,
              let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = metadataObject.stringValue else {
            return
        }
        
        hasScanned = true
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // キャプチャ画像を取得（スレッドセーフに）
        let capturedImage = latestFrame
        
        delegate?.didScanCode(code, capturedImage: capturedImage)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension VerifyQRScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // フレームをUIImageに変換して保持
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // 正しい向きで画像を作成
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        
        // メインスレッドで最新フレームを更新
        DispatchQueue.main.async { [weak self] in
            self?.latestFrame = image
        }
    }
}

// MARK: - QR Scanner Error

enum VerifyQRScannerError: Error, LocalizedError {
    case cameraUnavailable
    case permissionDenied
    case userCancelled
    
    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return L10n.Verify.qrErrorCameraUnavailable
        case .permissionDenied: return L10n.Verify.qrErrorPermissionDenied
        case .userCancelled: return nil // ユーザーがキャンセルした場合はメッセージ不要
        }
    }
}
