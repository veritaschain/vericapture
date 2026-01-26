//
//  ContentView.swift
//  VeraSnap
//
//  Main Application View - Enhanced UX
//  © 2026 VeritasChain Standards Organization
//

import SwiftUI
import AVFoundation
import Combine
import CoreLocation
import MapKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var captureViewModel = CaptureViewModel()
    @State private var selectedTab = 0
    
    var body: some View {
        Group {
            if !appState.isInitialized {
                InitializationView(error: appState.initializationError)
            } else {
                ZStack {
                    TabView(selection: $selectedTab) {
                        CameraView(viewModel: captureViewModel)
                            .tabItem { Label(L10n.Tab.capture, systemImage: "camera.fill") }
                            .tag(0)
                        
                        GalleryView(viewModel: captureViewModel)
                            .tabItem { Label(L10n.Tab.gallery, systemImage: "shield.checkered") }
                            .tag(1)
                        
                        VerifyView()
                            .tabItem { Label(L10n.Tab.verify, systemImage: "checkmark.shield") }
                            .tag(2)
                        
                        SettingsView(viewModel: captureViewModel)
                            .tabItem { Label(L10n.Tab.settings, systemImage: "gearshape.fill") }
                            .tag(3)
                    }
                    .environmentObject(appState)
                    .onChange(of: captureViewModel.navigateToGalleryForDeletion) { _, shouldNavigate in
                        if shouldNavigate {
                            // 証跡タブに移動して選択モードを有効化
                            selectedTab = 1
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                captureViewModel.startSelectionMode()
                                captureViewModel.navigateToGalleryForDeletion = false
                            }
                        }
                    }
                    
                    // グローバルローディングオーバーレイ（タブ移動しても表示される）
                    if captureViewModel.isCapturing {
                        GlobalLoadingOverlay(mode: .capturing(isFirst: captureViewModel.isFirstCapture))
                    } else if captureViewModel.isSharing {
                        GlobalLoadingOverlay(mode: .sharing)
                    }
                }
            }
        }
    }
}

// MARK: - Global Loading Overlay

enum LoadingMode {
    case capturing(isFirst: Bool)
    case sharing
    case exporting
    
    var message: String {
        switch self {
        case .capturing(let isFirst):
            return isFirst ? L10n.Camera.firstCaptureLoading : L10n.Detail.preparingProof
        case .sharing:
            return L10n.Detail.preparingProof
        case .exporting:
            return L10n.Settings.exportingAll
        }
    }
}

struct GlobalLoadingOverlay: View {
    let mode: LoadingMode
    @State private var animationOffset: CGFloat = 0
    
    // 後方互換のため
    init(isFirstCapture: Bool) {
        self.mode = .capturing(isFirst: isFirstCapture)
    }
    
    init(mode: LoadingMode) {
        self.mode = mode
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // アニメーション付きプログレスバー
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.3))
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * 0.35)
                            .offset(x: animationOffset * geometry.size.width * 0.65)
                    }
                }
                .frame(width: 220, height: 8)
                
                Text(mode.message)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
        .onAppear {
            // 即座にアニメーション開始
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                animationOffset = 1.0
            }
        }
    }
}

// MARK: - Initialization View

struct InitializationView: View {
    let error: String?
    
    var body: some View {
        VStack(spacing: 24) {
            if let error = error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                Text(L10n.Init.error)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(error)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 60))
                    .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text(L10n.Init.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(L10n.Init.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                ProgressView()
                    .scaleEffect(1.2)
                    .padding(.top, 8)
            }
        }
        .padding()
    }
}

// MARK: - Camera View (Enhanced)

struct CameraView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCaptureResult = false
    @State private var showVideoResult = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastIcon = "checkmark.circle.fill"
    @State private var showCPPInfo = false
    @State private var showAttestedBadgeInfo = false
    
    var body: some View {
        ZStack {
            // カメラプレビュー or 権限要求画面
            if viewModel.cameraService.isAuthorized {
                #if targetEnvironment(simulator)
                // シミュレーター用デモプレビュー
                SimulatorPreviewView()
                    .ignoresSafeArea()
                #else
                CameraPreviewView(cameraService: viewModel.cameraService)
                    .ignoresSafeArea()
                #endif
                
                // カメラUI オーバーレイ
                cameraOverlay
            } else {
                PermissionRequestView(viewModel: viewModel)
            }
            
            // トースト通知
            if showToast {
                VStack {
                    Spacer()
                    ToastView(message: toastMessage, icon: toastIcon)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 160)
                }
                .animation(.spring(response: 0.3), value: showToast)
            }
            
            // ローディング表示はグローバルオーバーレイ（ContentView）で行うため、ここでは削除
        }
        .sheet(isPresented: $showCaptureResult, onDismiss: {
            // 【重要】シートが閉じたらカメラを再開
            Task {
                await viewModel.resumeCameraAfterReview()
            }
        }) {
            if let result = viewModel.lastCaptureResult {
                CaptureResultView(result: result, viewModel: viewModel)
                    .onAppear {
                        // 【念のため】シートが表示されたら確実にカメラを止めておく
                        Task {
                            await viewModel.pauseCameraForReview()
                        }
                    }
            }
        }
        .sheet(isPresented: $showVideoResult, onDismiss: {
            Task {
                await viewModel.resumeCameraAfterReview()
            }
        }) {
            if let result = viewModel.lastVideoResult {
                VideoResultView(
                    result: result,
                    onDismiss: { showVideoResult = false },
                    onShare: {
                        // 動画共有処理（将来実装）
                        showVideoResult = false
                    }
                )
                .onAppear {
                    Task {
                        await viewModel.pauseCameraForReview()
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showLimitReached) {
            LimitReachedSheet(
                currentCount: viewModel.currentProofCount,
                onMakeSpace: {
                    viewModel.showLimitReached = false
                    // 証跡一覧タブに移動して選択モードを有効化
                    viewModel.navigateToGalleryForDeletion = true
                },
                onUpgrade: {
                    viewModel.showLimitReached = false
                    viewModel.showPaywall = true
                }
            )
        }
        .sheet(isPresented: $viewModel.showPaywall) {
            PaywallView(reason: .limitReached(count: viewModel.currentProofCount))
        }
        .alert(L10n.Common.error, isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? L10n.Error.unknown)
        }
        .onAppear {
            Task { await viewModel.checkAuthorization() }
        }
        .onChange(of: viewModel.lastCaptureResult?.eventId) { _, newValue in
            if newValue != nil {
                showCaptureToast()
            }
        }
        .onChange(of: viewModel.lastVideoResult?.eventId) { _, newValue in
            if newValue != nil {
                showVideoToast()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // アプリのライフサイクルに応じてカメラを制御
            switch newPhase {
            case .active:
                // フォアグラウンドに戻った時：カメラを再開
                if oldPhase == .inactive || oldPhase == .background {
                    print("[CameraView] App became active, resuming camera")
                    Task {
                        // 撮影中でなければカメラを再開
                        if !viewModel.isCapturing && !viewModel.isAuthenticating {
                            await viewModel.cameraService.resumeSessionAfterAuth()
                        }
                    }
                }
            case .inactive, .background:
                // バックグラウンドに行く時：カメラを停止
                print("[CameraView] App going to background, stopping camera")
                Task {
                    await viewModel.cameraService.stopSession()
                }
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - Camera Overlay
    
    private var cameraOverlay: some View {
        ZStack {
            VStack(spacing: 0) {
                // 上部ステータスバー
                topStatusBar
                
                Spacer()
                
                // 下部コントロール
                bottomControls
            }
            
            // 認証中オーバーレイ
            if viewModel.isAuthenticating {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text(L10n.Camera.authInProgress)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(L10n.Camera.keepDeviceStill)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(30)
                .background(Color.black.opacity(0.7))
                .cornerRadius(20)
            }
        }
    }
    
    private var topStatusBar: some View {
        VStack(spacing: 8) {
            // ケース選択ボタン (v40)
            CaseSelectorButton()
            
            HStack {
                // CPP証跡ステータス
                Button {
                    showCPPInfo = true
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(L10n.Camera.cppOn)
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .opacity(0.8)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(20)
                }
                .popover(isPresented: $showCPPInfo, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "shield.checkered")
                                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                            Text(L10n.Camera.cppProofGeneration)
                                .font(.headline)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Label(L10n.CameraInfo.feature1, systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Label(L10n.CameraInfo.feature2, systemImage: "lock.shield.fill")
                                .foregroundColor(.blue)
                            Label(L10n.CameraInfo.feature3, systemImage: "person.badge.shield.checkmark.fill")
                                .foregroundColor(.purple)
                        }
                        .font(.subheadline)
                        
                        // 注意書き
                        Text(L10n.CameraInfo.disclaimer)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding()
                    .frame(width: 280)
                    .presentationCompactAdaptation(.popover)
                }
                
                // Attested Capture Modeインジケーター
                if viewModel.isAttestedCaptureMode {
                    Button {
                        showAttestedBadgeInfo = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .font(.caption)
                            Text(L10n.AttestedCapture.badge)
                                .font(.caption2)
                                .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                            .opacity(0.8)
                    )
                    .cornerRadius(16)
                }
                .alert(L10n.AttestedCapture.disclaimer, isPresented: $showAttestedBadgeInfo) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(L10n.AttestedCapture.badgeTooltip)
                }
            }
            
            Spacer()
            
            // フラッシュ切り替え
            Button {
                viewModel.cameraService.flashMode = viewModel.cameraService.flashMode.next
            } label: {
                Image(systemName: viewModel.cameraService.flashMode.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            
            // カメラ切り替え
            Button {
                viewModel.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 60)
    }
    
    private var bottomControls: some View {
        VStack(spacing: 16) {
            // 撮影モードセレクター（写真/動画）
            CaptureModeSelector(
                mode: $viewModel.captureMode,
                isDisabled: viewModel.isCapturing || viewModel.isRecording
            )
            
            // 録画中の進捗表示
            if viewModel.isRecording {
                RecordingProgressIndicator(
                    duration: viewModel.recordingDuration,
                    progress: viewModel.recordingProgress,
                    maxDuration: 60
                )
                .transition(.opacity)
            }
            
            // シャッターボタンエリア
            HStack {
                // 左のプレースホルダー
                Color.clear.frame(width: 60, height: 60)
                
                Spacer()
                
                // メインキャプチャボタン（写真/動画に応じて変化）
                if viewModel.captureMode == .photo {
                    // 写真用シャッターボタン - 盾マーク付き
                    Button {
                        Task { await viewModel.capturePhoto() }
                    } label: {
                        ZStack {
                            // 外側のリング
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 80, height: 80)
                            
                            // 内側の塗り（グラデーション）
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white, Color.white.opacity(0.95)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 66, height: 66)
                            
                            // 盾マーク（VeraSnapのシンボル）
                            if viewModel.isCapturing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            } else {
                                Image(systemName: "shield.checkered")
                                    .font(.system(size: 28, weight: .medium))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                        }
                    }
                    .disabled(!viewModel.isReady || viewModel.isCapturing)
                    .scaleEffect(viewModel.isCapturing ? 0.95 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: viewModel.isCapturing)
                } else {
                    // 動画用録画ボタン
                    RecordingButton(
                        isRecording: viewModel.isRecording,
                        isProcessing: viewModel.isCapturing
                    ) {
                        Task {
                            if viewModel.isRecording {
                                await viewModel.stopVideoRecording()
                            } else {
                                await viewModel.startVideoRecording()
                            }
                        }
                    }
                    .disabled(!viewModel.isReady)
                }
                
                Spacer()
                
                // 直近の撮影サムネイル（右下）
                thumbnailButton
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
    }
    
    // サムネイルボタン（写真/動画共通）
    @ViewBuilder
    private var thumbnailButton: some View {
        if let lastImage = viewModel.lastCapturedImage {
            Button {
                showCaptureResult = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: lastImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        )
                    
                    // 証跡完了バッジ
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                        .background(Circle().fill(.white).frame(width: 14, height: 14))
                        .offset(x: 4, y: -4)
                }
            }
        } else if let videoResult = viewModel.lastVideoResult, let thumbnail = videoResult.thumbnail {
            Button {
                showVideoResult = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        )
                    
                    // 動画バッジ
                    HStack(spacing: 2) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 8))
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.green)
                    .padding(3)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(4)
                    .offset(x: 4, y: -4)
                }
            }
        } else {
            Color.clear.frame(width: 60, height: 60)
        }
    }
    
    // MARK: - Toast
    
    private func showCaptureToast() {
        toastMessage = L10n.Camera.toastCaptured
        toastIcon = "checkmark.seal.fill"
        
        withAnimation {
            showToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showToast = false
            }
        }
    }
    
    private func showVideoToast() {
        toastMessage = L10n.Video.saved
        toastIcon = "video.fill"
        
        withAnimation {
            showToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showToast = false
            }
        }
    }
}

// MARK: - Permission Request View

struct PermissionRequestView: View {
    @ObservedObject var viewModel: CaptureViewModel
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // アイコン
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.2), .purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "camera.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            
            // タイトルと説明
            VStack(spacing: 12) {
                Text(L10n.Permission.cameraAccess)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(L10n.Permission.cameraMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            
            // 許可ボタン (Apple Guideline 5.1.1: Use "Continue" instead of "Allow Camera")
            Button {
                Task { await viewModel.checkAuthorization() }
            } label: {
                Text(L10n.Permission.continueButton)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(14)
            }
            .padding(.horizontal, 40)
            
            // 設定アプリへの導線
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(L10n.Permission.openSettings)
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            
            Spacer()
            
            // 説明テキスト
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.green)
                    Text(L10n.Camera.privacyNote)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: "signature")
                        .foregroundColor(.blue)
                    Text(L10n.CameraInfo.secureEnclave)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 40)
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.green)
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
        )
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let cameraService: CameraService
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.session = cameraService.captureSession
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.updateLayout()
    }
}

class CameraPreviewUIView: UIView {
    var session: AVCaptureSession? {
        didSet {
            // サイズが確定している場合のみセットアップ
            if bounds.width > 0 && bounds.height > 0 {
                setupPreviewLayer()
            }
        }
    }
    
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isSetup = false
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // サイズが確定したらプレビューレイヤーをセットアップ
        if !isSetup && bounds.width > 0 && bounds.height > 0 && session != nil {
            setupPreviewLayer()
        }
        
        previewLayer?.frame = bounds
    }
    
    private func setupPreviewLayer() {
        guard !isSetup else { return }
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        previewLayer?.removeFromSuperlayer()
        
        guard let session = session else { return }
        
        isSetup = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.addSublayer(layer)
        previewLayer = layer
    }
    
    func updateLayout() {
        previewLayer?.frame = bounds
    }
}

// MARK: - Simulator Preview View

#if targetEnvironment(simulator)
struct SimulatorPreviewView: View {
    @State private var animationPhase: Double = 0
    
    var body: some View {
        ZStack {
            // アニメーション背景
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.2, blue: 0.4),
                    Color(red: 0.2, green: 0.3, blue: 0.6)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // グリッドパターン
            GeometryReader { geo in
                Path { path in
                    let spacing: CGFloat = 40
                    for x in stride(from: 0, to: geo.size.width, by: spacing) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    for y in stride(from: 0, to: geo.size.height, by: spacing) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
            
            VStack(spacing: 20) {
                // カメラアイコン
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(0.8 + sin(animationPhase) * 0.2)
                
                Text(L10n.Capture.simulatorTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(L10n.Capture.simulatorMessage)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                animationPhase = .pi * 2
            }
        }
    }
}
#endif

// MARK: - Capture Result View (Enhanced)

struct CaptureResultView: View {
    let result: CaptureResultData
    @ObservedObject var viewModel: CaptureViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showShareOptions = false
    @State private var showQRPreview = false
    @State private var copiedToClipboard = false
    @State private var isProcessing = false
    @State private var showAttestedBadgeInfo = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // プレビュー画像
                    if let image = result.image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 280)
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                    }
                    
                    // ステータスバッジ
                    HStack(spacing: 12) {
                        StatusBadge(status: .generated)
                        
                        // Attested Captureバッジ（タップでツールチップ表示）
                        if result.isAttestedCapture {
                            Button {
                                showAttestedBadgeInfo = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.badge.shield.checkmark.fill")
                                        .font(.caption)
                                    Text(L10n.AttestedCapture.badge)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(12)
                            }
                            .alert(L10n.AttestedCapture.disclaimer, isPresented: $showAttestedBadgeInfo) {
                                Button("OK", role: .cancel) { }
                            } message: {
                                Text(L10n.AttestedCapture.badgeTooltip)
                            }
                        }
                    }
                    
                    // 証跡情報カード
                    VStack(alignment: .leading, spacing: 16) {
                        // Proof ID（コピー可能）
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text(L10n.Result.proofId)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(L10n.Detail.proofIdNote)
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                                Text(String(result.eventId.prefix(16)) + "...")
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                            }
                            
                            Spacer()
                            
                            Button {
                                UIPasteboard.general.string = result.eventId
                                copiedToClipboard = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedToClipboard = false
                                }
                            } label: {
                                Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(copiedToClipboard ? .green : .blue)
                                    .frame(width: 44, height: 44)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(10)
                            }
                        }
                        
                        Divider()
                        
                        DetailRow(label: L10n.Result.timestamp, value: formatDate(result.timestamp))
                        DetailRow(label: L10n.Result.filename, value: result.filename)
                        DetailRow(label: L10n.Result.filesize, value: formatBytes(result.fileSize))
                        
                        Divider()
                        
                        DetailRow(label: L10n.Result.hashAlgo, value: "SHA-256")
                        DetailRow(label: L10n.Result.signAlgo, value: result.signAlgorithm)
                        DetailRow(label: L10n.Result.anchorStatus, value: L10n.Result.anchorPending)
                    }
                    .padding(20)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // 説明
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text(L10n.Result.thirdPartyVerifiable)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(12)
                    
                    // アクションボタン（共有オプション選択へ）
                    Button {
                        if result.image != nil {
                            showShareOptions = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text(L10n.Result.share)
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: result.image != nil ? [.blue, .purple] : [.gray, .gray.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                    }
                    .disabled(result.image == nil)
                }
                .padding(20)
            }
            .navigationTitle(L10n.Result.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Result.close) { dismiss() }
                }
            }
            .sheet(isPresented: $showShareOptions) {
                ShareOptionsSheet(
                    image: result.image,  // UIImage? を直接渡す
                    videoURL: nil,  // CaptureResultViewは写真専用
                    proofId: result.eventId,
                    hasLocation: result.hasLocation,
                    onSelect: { option in
                        handleShareOption(option)
                    },
                    onInternalExport: { includeLocation, includeC2PA in
                        handleInternalExport(includeLocation: includeLocation, includeC2PA: includeC2PA)
                    },
                    onRawDataExport: {
                        handleRawDataExport()
                    },
                    onC2PAExport: {
                        handleC2PAExport()
                    }
                )
            }
            .sheet(isPresented: $showQRPreview) {
                if let image = result.image {
                    QRPreviewSheet(
                        originalImage: image,
                        proofId: result.eventId
                    ) { qrImage in
                        // UIKitで直接共有シートを表示
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            presentShareSheet(items: [qrImage])
                        }
                    }
                }
            }
            .overlay {
                // 処理中のローディングオーバーレイ（横棒プログレスバー）
                if isProcessing || viewModel.isSharing {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            Text(L10n.Detail.preparingProof)
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            // 横棒プログレスバー（アニメーション）
                            IndeterminateProgressBar()
                                .frame(width: 200, height: 6)
                        }
                        .padding(32)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                    }
                }
            }
        }
    }
    
    private func handleShareOption(_ option: ShareOption) {
        // すべての共有オプションでグローバルローディングを表示（フリーズ防止）
        // QRプレビューは別シートなので除外
        if option != .withQR {
            viewModel.isSharing = true
        }
        
        // シートを閉じてから処理を開始
        showShareOptions = false
        
        // シートが完全に閉じるまで待機してから処理
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            switch option {
            case .imageOnly, .mediaOnly:
                if let image = result.image {
                    viewModel.isSharing = false
                    presentShareSheet(items: [image])
                } else {
                    viewModel.isSharing = false
                }
                
            case .videoOnly:
                // CaptureResultViewは写真専用のため、このケースは発生しない
                viewModel.isSharing = false
                
            case .withProof:
                Task {
                    if let url = await viewModel.exportProof(eventId: result.eventId) {
                        var items: [Any] = [url]
                        if let image = result.image {
                            // 参照用プレビューの透かしを追加
                            let watermarkedImage = ReferenceWatermark.addWatermark(to: image)
                            items.insert(watermarkedImage, at: 0)
                        }
                        await MainActor.run {
                            viewModel.isSharing = false
                            presentShareSheet(items: items)
                        }
                    } else {
                        await MainActor.run {
                            viewModel.isSharing = false
                        }
                    }
                }
                
            case .withQR:
                showQRPreview = true
                
            case .internalProof, .exportZip:
                // 内部用完全証跡エクスポート（このViewではサポートしない）
                viewModel.isSharing = false
                
            case .rawDataExport:
                // 生データエクスポート（handleRawDataExportで処理）
                viewModel.isSharing = false
                
            case .c2paExport:
                // C2PAエクスポート（handleC2PAExportで処理）
                viewModel.isSharing = false
            }
        }
    }
    
    private func handleInternalExport(includeLocation: Bool, includeC2PA: Bool) {
        viewModel.isSharing = true
        showShareOptions = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task {
                // 法務用エクスポート（メディア + Proof JSON + C2PA(オプション) をZIPにまとめて）
                if let zipURL = await viewModel.exportInternalProof(eventId: result.eventId, includeLocation: includeLocation, includeC2PA: includeC2PA) {
                    await MainActor.run {
                        viewModel.isSharing = false
                        // ZIPファイルを共有
                        presentShareSheet(items: [zipURL])
                    }
                } else {
                    await MainActor.run {
                        viewModel.isSharing = false
                    }
                }
            }
        }
    }
    
    private func handleRawDataExport() {
        viewModel.isSharing = true
        showShareOptions = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Task {
                // 生データ（元画像/動画 + Proof JSON）をZIPにまとめてエクスポート
                if let zipURL = await viewModel.exportRawData(eventId: result.eventId) {
                    await MainActor.run {
                        viewModel.isSharing = false
                        // ZIPファイルを共有
                        presentShareSheet(items: [zipURL])
                    }
                } else {
                    await MainActor.run {
                        viewModel.isSharing = false
                    }
                }
            }
        }
    }
    
    private func handleC2PAExport() {
        viewModel.isSharing = true
        showShareOptions = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Task {
                do {
                    let zipURL = try await C2PAExportService.shared.exportC2PAPackage(eventId: result.eventId)
                    await MainActor.run {
                        viewModel.isSharing = false
                        presentShareSheet(items: [zipURL])
                    }
                } catch {
                    await MainActor.run {
                        viewModel.isSharing = false
                        print("[C2PAExport] Failed: \(error)")
                    }
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return formatter.string(from: date) + " JST"
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Status Badge

enum ProofStatus {
    case generated   // 証跡生成完了（一次生成）
    case anchored    // 外部確定済み（第三者タイムスタンプ取得）
    case pending     // 確定準備中
    case failed      // 生成失敗
    
    var label: String {
        switch self {
        case .generated: return L10n.Gallery.statusGenerated
        case .anchored: return L10n.Gallery.statusAnchored
        case .pending: return L10n.Gallery.statusPending
        case .failed: return L10n.Gallery.statusFailed
        }
    }
    
    var icon: String {
        switch self {
        case .generated: return "checkmark.circle.fill"
        case .anchored: return "checkmark.seal.fill"
        case .pending: return "clock.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .generated: return .blue
        case .anchored: return .green
        case .pending: return .orange
        case .failed: return .red
        }
    }
}

struct StatusBadge: View {
    let status: ProofStatus
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.icon)
            Text(status.label)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .foregroundColor(status.color)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(status.color.opacity(0.12))
        .cornerRadius(20)
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - UIKit Share Helper

/// UIKitで直接共有シートを表示（SwiftUIのsheet問題を回避）
func presentShareSheet(items: [Any]) {
    guard !items.isEmpty else { return }
    
    func tryPresent(attempts: Int = 0) {
        guard attempts < 10 else {
            print("[Share] Failed to present after 10 attempts")
            return
        }
        
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController else {
                return
            }
            
            // 最前面のViewControllerを取得
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            
            // まだdismiss中のVCがある場合は待機
            if topVC.isBeingDismissed || topVC.isBeingPresented {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    tryPresent(attempts: attempts + 1)
                }
                return
            }
            
            let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
            
            // iPad対応
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            topVC.present(activityVC, animated: true)
        }
    }
    
    tryPresent()
}

// MARK: - Gallery View (Enhanced)

struct GalleryView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @ObservedObject private var caseService = CaseService.shared
    @State private var eventToDelete: CPPEvent?
    @State private var showDeleteAuthError = false
    @State private var deleteAuthErrorMessage = ""
    @State private var showBatchDeleteConfirm = false
    @State private var showBatchDeleteReasonPicker = false
    @State private var selectedBatchDeleteReason: InvalidationReason = .userPrivacyRequest
    @State private var showCaseSelector = false
    
    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // v40: ケース情報バー
                if let currentCase = caseService.currentCase {
                    Button {
                        showCaseSelector = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: currentCase.icon)
                                .font(.caption)
                                .foregroundColor(Color(hex: currentCase.colorHex) ?? .blue)
                            
                            Text(currentCase.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text(L10n.Case.photoCount(viewModel.currentCaseEventCount))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                    }
                }
                
                // 検索バー
                if viewModel.currentCaseEventCount > 0 {
                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField(L10n.GallerySearch.placeholder, text: $viewModel.searchText)
                                .textFieldStyle(.plain)
                            if !viewModel.searchText.isEmpty {
                                Button {
                                    viewModel.searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        
                        // フィルタメニュー
                        Menu {
                            ForEach(GalleryFilterMode.allCases, id: \.self) { mode in
                                Button {
                                    viewModel.filterMode = mode
                                } label: {
                                    HStack {
                                        Text(filterModeLabel(mode))
                                        if viewModel.filterMode == mode {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: viewModel.filterMode == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                                .font(.title3)
                                .foregroundColor(viewModel.filterMode == .all ? .primary : .blue)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                
                // メインコンテンツ
                Group {
                    if viewModel.capturedEvents.isEmpty {
                        VStack {
                            Spacer()
                            EmptyGalleryView()
                            Spacer()
                        }
                    } else if viewModel.sortedEvents.isEmpty {
                        // フィルタ結果が空
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text(L10n.GallerySearch.noResults)
                                .foregroundColor(.secondary)
                            Button(L10n.GallerySearch.clearFilter) {
                                viewModel.searchText = ""
                                viewModel.filterMode = .all
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        if viewModel.galleryDisplayMode == .grid {
                            // グリッド表示
                            ScrollView {
                                LazyVGrid(columns: gridColumns, spacing: 8) {
                                    ForEach(viewModel.sortedEvents, id: \.eventId) { event in
                                        gridCardView(for: event)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .refreshable {
                                viewModel.refreshEvents()
                            }
                        } else {
                            // リスト表示（日付グループ化）
                            List {
                                ForEach(viewModel.groupedEvents, id: \.0) { group in
                                    Section(header: Text(group.0).font(.headline).foregroundColor(.secondary)) {
                                        ForEach(group.1, id: \.eventId) { event in
                                            listCardView(for: event)
                                        }
                                    }
                                }
                            }
                            .listStyle(.plain)
                            .refreshable {
                                viewModel.refreshEvents()
                            }
                        }
                    }
                }
            }
            .navigationTitle(viewModel.isSelectionMode ? L10n.GallerySelect.title(viewModel.selectedEventIds.count) : L10n.Gallery.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.isSelectionMode {
                        Button(L10n.Common.cancel) {
                            viewModel.endSelectionMode()
                        }
                    } else {
                        // 表示モード切り替えボタン
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.galleryDisplayMode = viewModel.galleryDisplayMode == .list ? .grid : .list
                            }
                        } label: {
                            Image(systemName: viewModel.galleryDisplayMode == .list ? "square.grid.3x3" : "list.bullet")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isSelectionMode {
                        HStack(spacing: 12) {
                            Button {
                                if viewModel.selectedEventIds.count == viewModel.sortedEvents.count {
                                    viewModel.deselectAll()
                                } else {
                                    viewModel.selectAll()
                                }
                            } label: {
                                Text(viewModel.selectedEventIds.count == viewModel.sortedEvents.count ? L10n.GallerySelect.deselectAll : L10n.GallerySelect.selectAll)
                                    .font(.subheadline)
                            }
                            
                            Button(role: .destructive) {
                                showBatchDeleteReasonPicker = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(viewModel.selectedEventIds.isEmpty)
                        }
                    } else {
                        HStack(spacing: 12) {
                            // 無料プランの残り枚数
                            if !viewModel.isPro {
                                Text(L10n.GalleryContext.remaining(50 - viewModel.currentProofCount))
                                    .font(.caption2)
                                    .foregroundColor(viewModel.currentProofCount >= 90 ? .orange : .secondary)
                            }
                            
                            // 選択モードボタン
                            if !viewModel.capturedEvents.isEmpty {
                                Button {
                                    viewModel.startSelectionMode()
                                } label: {
                                    Image(systemName: "checkmark.circle")
                                }
                            }
                        }
                    }
                }
            }
            // 単体削除シート
            .sheet(item: $eventToDelete) { event in
                DeleteOptionsSheet(event: event, viewModel: viewModel)
            }
            // 一括削除理由選択
            .confirmationDialog(
                L10n.Delete.invalidateSelectReason,
                isPresented: $showBatchDeleteReasonPicker,
                titleVisibility: .visible
            ) {
                Button(L10n.InvalidationReason.privacy) {
                    selectedBatchDeleteReason = .userPrivacyRequest
                    showBatchDeleteConfirm = true
                }
                Button(L10n.InvalidationReason.accidental) {
                    selectedBatchDeleteReason = .userAccidentalCapture
                    showBatchDeleteConfirm = true
                }
                Button(L10n.InvalidationReason.inappropriate) {
                    selectedBatchDeleteReason = .userContentInappropriate
                    showBatchDeleteConfirm = true
                }
                Button(L10n.Common.cancel, role: .cancel) {}
            }
            // 一括削除確認alert
            .alert(L10n.GallerySelect.deleteTitle(viewModel.selectedEventIds.count), isPresented: $showBatchDeleteConfirm) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.GalleryContext.delete, role: .destructive) {
                    performBatchDelete()
                }
            } message: {
                Text(L10n.GallerySelect.deleteMessage)
            }
            // 認証エラーalert
            .alert(L10n.GalleryDelete.authError, isPresented: $showDeleteAuthError) {
                Button(L10n.Error.ok) {}
            } message: {
                Text(deleteAuthErrorMessage)
            }
            // v40: ケース選択シート
            .sheet(isPresented: $showCaseSelector) {
                CaseSelectorSheet()
            }
        }
        .onAppear {
            viewModel.refreshEvents()
        }
        // v40: ケース変更時にイベントをリフレッシュ
        .onChange(of: caseService.currentCase?.caseId) { _, _ in
            viewModel.refreshEvents()
        }
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func gridCardView(for event: CPPEvent) -> some View {
        if viewModel.isSelectionMode {
            Button {
                viewModel.toggleSelection(event.eventId)
            } label: {
                ZStack(alignment: .topLeading) {
                    GridEventCard(event: event, viewModel: viewModel)
                        .allowsHitTesting(false)  // 選択モード中はカード内部のタップを無効化
                    
                    // 選択チェックマーク
                    Image(systemName: viewModel.isSelected(event.eventId) ? "checkmark.circle.fill" : "circle")
                        .font(.title)
                        .foregroundColor(viewModel.isSelected(event.eventId) ? .blue : .white)
                        .shadow(radius: 2)
                        .padding(8)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())  // 全体をタップ領域に
        } else {
            GridEventCard(event: event, viewModel: viewModel)
                .contextMenu {
                    eventContextMenu(for: event)
                }
        }
    }
    
    @ViewBuilder
    private func listCardView(for event: CPPEvent) -> some View {
        if viewModel.isSelectionMode {
            Button {
                viewModel.toggleSelection(event.eventId)
            } label: {
                HStack(spacing: 12) {
                    // チェックボックス部分（広いタップ領域）
                    Image(systemName: viewModel.isSelected(event.eventId) ? "checkmark.circle.fill" : "circle")
                        .font(.title)
                        .foregroundColor(viewModel.isSelected(event.eventId) ? .blue : .secondary)
                        .frame(width: 32, height: 32)
                    
                    // カード部分
                    EventCard(event: event, viewModel: viewModel)
                        .allowsHitTesting(false)  // 選択モード中はカード内部のタップを無効化
                }
                .padding(.leading, 8)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())  // 全体をタップ領域に
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
        } else {
            EventCard(event: event, viewModel: viewModel)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .contextMenu {
                    eventContextMenu(for: event)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        viewModel.togglePin(event.eventId)
                    } label: {
                        Label(
                            viewModel.isPinned(event.eventId) ? L10n.GalleryPin.unpin : L10n.GalleryPin.pin,
                            systemImage: viewModel.isPinned(event.eventId) ? "pin.slash" : "pin"
                        )
                    }
                    .tint(.orange)
                }
                // スワイプ削除は無効化（クラッシュ防止）
                // 削除はコンテキストメニューまたは選択モードから
        }
    }
    
    private func filterModeLabel(_ mode: GalleryFilterMode) -> String {
        switch mode {
        case .all: return L10n.GalleryFilter.all
        case .attested: return L10n.GalleryFilter.attested
        case .anchored: return L10n.GalleryFilter.anchored
        case .pending: return L10n.GalleryFilter.pending
        }
    }
    
    /// イベントのコンテキストメニュー
    @ViewBuilder
    private func eventContextMenu(for event: CPPEvent) -> some View {
        Button {
            viewModel.togglePin(event.eventId)
        } label: {
            Label(
                viewModel.isPinned(event.eventId) ? L10n.GalleryPin.unpin : L10n.GalleryPin.pin,
                systemImage: viewModel.isPinned(event.eventId) ? "pin.slash" : "pin"
            )
        }
        
        Divider()
        
        Button(role: .destructive) {
            eventToDelete = event
        } label: {
            Label(L10n.GalleryContext.delete, systemImage: "trash")
        }
    }
    
    /// 一括削除
    private func performBatchDelete() {
        let reason = selectedBatchDeleteReason
        Task {
            let result = await BiometricAuthService.shared.authenticate(for: .deleteProof)
            
            await MainActor.run {
                switch result {
                case .success, .notAvailable:
                    viewModel.deleteSelectedEvents(reason: reason)
                case .cancelled:
                    break
                case .failed(let error):
                    deleteAuthErrorMessage = L10n.Subscription.authFailed(error)
                    showDeleteAuthError = true
                }
            }
        }
    }
}

// MARK: - Grid Event Card

struct GridEventCard: View {
    let event: CPPEvent
    @ObservedObject var viewModel: CaptureViewModel
    @State private var showDetail = false
    @State private var thumbnail: UIImage?
    
    private var isPinned: Bool {
        viewModel.isPinned(event.eventId)
    }
    
    // CPP Additional Spec: Extended status
    private var mediaStatus: MediaStatus {
        StorageService.shared.getMediaStatus(eventId: event.eventId)
    }
    
    private var eventStatus: EventStatus {
        StorageService.shared.getEventStatus(eventId: event.eventId)
    }
    
    private var anchorStatus: ProofAnchorStatus {
        StorageService.shared.getAnchorStatus(eventId: event.eventId)
    }
    
    // v42.2: Conformance Level
    private var conformanceLevel: ConformanceLevel {
        let hasTimestamp = anchorStatus == .anchored
        let hasHumanAttestation = event.captureContext.humanAttestation != nil
        return ConformanceLevel.determine(hasTimestamp: hasTimestamp, hasHumanAttestation: hasHumanAttestation)
    }
    
    var body: some View {
        Button {
            showDetail = true
        } label: {
            ZStack(alignment: .topLeading) {
                // サムネイル - mediaStatusとeventStatusを毎回評価
                let currentMediaStatus = StorageService.shared.getMediaStatus(eventId: event.eventId)
                let currentEventStatus = StorageService.shared.getEventStatus(eventId: event.eventId)
                
                if currentEventStatus == .invalidated {
                    // 失効した証跡
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .aspectRatio(1, contentMode: .fill)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: "xmark.seal.fill")
                                    .font(.title2)
                                    .foregroundColor(.red.opacity(0.7))
                                Text(L10n.GalleryStatus.invalidated)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                } else if currentMediaStatus == .purged {
                    // メディア削除済み
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .aspectRatio(1, contentMode: .fill)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: "photo.badge.minus")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text(L10n.GalleryStatus.mediaPurged)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                } else if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .aspectRatio(1, contentMode: .fill)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                }
                
                // ステータスバッジとピンアイコンのオーバーレイ
                VStack {
                    HStack {
                        // ピンアイコン
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.orange)
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                        
                        Spacer()
                        
                        // CPP追加仕様: アンカーステータスバッジ
                        AnchorStatusBadge(status: anchorStatus, eventStatus: eventStatus)
                    }
                    .padding(6)
                    
                    Spacer()
                    
                    // 下部オーバーレイ
                    HStack(alignment: .bottom) {
                        // v42.2: Conformance Level Indicator（左下）
                        ConformanceLevelIndicator(level: conformanceLevel)
                        
                        Spacer()
                        
                        // 動画の場合は長さを表示（右下）
                        if event.asset.assetType == .video, let videoMetadata = event.asset.videoMetadata {
                            HStack(spacing: 4) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 10))
                                Text(formatDuration(videoMetadata.duration))
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                        }
                    }
                    .padding(6)
                }
            }
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            EventDetailView(event: event, viewModel: viewModel)
        }
        .task {
            await loadThumbnail()
        }
        .onChange(of: viewModel.capturedEvents.count) { _, _ in
            // イベント一覧が更新されたらサムネイルを再チェック
            let currentStatus = StorageService.shared.getMediaStatus(eventId: event.eventId)
            if currentStatus != .present {
                thumbnail = nil
            }
        }
    }
    
    private func loadThumbnail() async {
        // メディアが削除されている場合はロードしない
        guard mediaStatus == .present else {
            await MainActor.run { thumbnail = nil }
            return
        }
        
        if let image = StorageService.shared.loadThumbnail(eventId: event.eventId) {
            await MainActor.run {
                self.thumbnail = image
            }
        }
    }
    
    /// 動画の長さをフォーマット (mm:ss)
    private func formatDuration(_ duration: Double) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Empty Gallery View

struct EmptyGalleryView: View {
    var body: some View {
        VStack(spacing: 24) {
            // プレビューカード（ダミー）
            VStack(spacing: 0) {
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 12)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 80, height: 10)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green.opacity(0.5))
                            .frame(width: 8, height: 8)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(0.3))
                            .frame(width: 40, height: 10)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(16)
            }
            .frame(width: 280)
            .opacity(0.6)
            
            // テキスト
            VStack(spacing: 12) {
                Text(L10n.Gallery.emptyTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(L10n.Gallery.emptyMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // 説明
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "checkmark.seal.fill", color: .green, text: L10n.Gallery.statusLegendAnchored)
                FeatureRow(icon: "clock.fill", color: .orange, text: L10n.Gallery.statusLegendPending)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Event Card

struct EventCard: View {
    let event: CPPEvent
    @ObservedObject var viewModel: CaptureViewModel
    @State private var showDetail = false
    @State private var thumbnail: UIImage?
    
    private var status: ProofStatus {
        // アンカリング状態に基づいてステータスを判定
        if event.isAnchored {
            return .anchored
        } else {
            return .generated  // 証跡生成は完了しているが、外部タイムスタンプは未取得
        }
    }
    
    private var isPinned: Bool {
        viewModel.isPinned(event.eventId)
    }
    
    private var mediaStatus: MediaStatus {
        StorageService.shared.getMediaStatus(eventId: event.eventId)
    }
    
    private var eventStatus: EventStatus {
        StorageService.shared.getEventStatus(eventId: event.eventId)
    }
    
    private var anchorStatus: ProofAnchorStatus {
        StorageService.shared.getAnchorStatus(eventId: event.eventId)
    }
    
    // v42.2: Conformance Level
    private var conformanceLevel: ConformanceLevel {
        let hasTimestamp = anchorStatus == .anchored
        let hasHumanAttestation = event.captureContext.humanAttestation != nil
        return ConformanceLevel.determine(hasTimestamp: hasTimestamp, hasHumanAttestation: hasHumanAttestation)
    }
    
    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 14) {
                // サムネイル（メディア状態を考慮）
                ZStack(alignment: .topLeading) {
                    let currentMediaStatus = StorageService.shared.getMediaStatus(eventId: event.eventId)
                    let currentEventStatus = StorageService.shared.getEventStatus(eventId: event.eventId)
                    
                    if currentEventStatus == .invalidated {
                        // 失効した証跡
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray5))
                            .frame(width: 56, height: 56)
                            .overlay {
                                Image(systemName: "xmark.seal.fill")
                                    .font(.title3)
                                    .foregroundColor(.red.opacity(0.7))
                            }
                    } else if currentMediaStatus == .purged {
                        // メディア削除済み
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray5))
                            .frame(width: 56, height: 56)
                            .overlay {
                                Image(systemName: event.asset.assetType == .video ? "video.badge.minus" : "photo.badge.minus")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                    } else if let thumbnail = thumbnail {
                        ZStack(alignment: .bottomTrailing) {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            
                            // 動画バッジ
                            if event.asset.assetType == .video {
                                HStack(spacing: 2) {
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 8))
                                    if let metadata = event.asset.videoMetadata {
                                        Text(formatDuration(metadata.duration))
                                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    }
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(4)
                                .padding(2)
                            }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: event.asset.assetType == .video ? "video.fill" : "photo.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .frame(width: 56, height: 56)
                    }
                    
                    // ピン留めインジケータ
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Color.orange)
                            .clipShape(Circle())
                            .offset(x: -4, y: -4)
                    }
                }
                .frame(width: 56, height: 56)
                
                // 情報
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.asset.assetName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(formatDate(event.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("ProofID: " + String(event.eventId.prefix(12)) + "...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fontDesign(.monospaced)
                }
                
                Spacer()
                
                // ステータスバッジ
                VStack(spacing: 4) {
                    // v42.2: Conformance Level Badge
                    ConformanceBadge(level: conformanceLevel, size: .small)
                    
                    // Attested Captureバッジ（HumanAttestationがある場合）
                    if event.captureContext.humanAttestation != nil {
                        HStack(spacing: 2) {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .font(.caption2)
                            Text(L10n.AttestedCapture.badge)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(8)
                    }
                    
                    Image(systemName: status.icon)
                        .foregroundColor(status.color)
                    Text(status.label)
                        .font(.caption2)
                        .foregroundColor(status.color)
                }
            }
            .padding(14)
            .background(Color(.systemBackground))
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            EventDetailView(event: event, viewModel: viewModel)
        }
        .onAppear {
            loadThumbnail()
        }
        .onChange(of: viewModel.capturedEvents.count) { _, _ in
            // イベント一覧が更新されたらサムネイルを再チェック
            let currentStatus = StorageService.shared.getMediaStatus(eventId: event.eventId)
            if currentStatus != .present {
                thumbnail = nil
            }
        }
    }
    
    private func loadThumbnail() {
        // メディアが削除されている場合はロードしない
        guard mediaStatus == .present else {
            thumbnail = nil
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let img = StorageService.shared.loadThumbnail(eventId: event.eventId)
            DispatchQueue.main.async {
                thumbnail = img
            }
        }
    }
    
    private func formatDate(_ timestamp: String) -> String {
        guard let date = Date.fromISO8601(timestamp) else { return timestamp }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        formatter.timeZone = .current
        
        let dateString = formatter.string(from: date)
        
        // タイムゾーン略称を取得
        let tzFormatter = DateFormatter()
        tzFormatter.dateFormat = "zzz"
        tzFormatter.timeZone = .current
        let tzAbbrev = tzFormatter.string(from: date)
        
        return "\(dateString) \(tzAbbrev)"
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Event Detail View

struct EventDetailView: View {
    let event: CPPEvent
    @ObservedObject var viewModel: CaptureViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showShareOptions = false
    @State private var showQRPreview = false
    @State private var copiedToClipboard = false
    @State private var loadedImage: UIImage?
    @State private var isProcessing = false
    @State private var showDeleteOptions = false  // CPP追加仕様: 削除オプションシート
    @State private var locationCoordinate: CLLocationCoordinate2D?
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var showInternalExportConfirm = false
    @State private var showInternalExportResult = false
    @State private var internalExportMessage = ""
    @State private var showAuthError = false
    @State private var authErrorMessage = ""
    @State private var showAttestedBadgeInfo = false
    @AppStorage("signerName") private var signerNameSetting: String = ""  // 署名者名設定
    
    // CPP追加仕様: 拡張ステータス
    private var mediaStatus: MediaStatus {
        StorageService.shared.getMediaStatus(eventId: event.eventId)
    }
    
    private var eventStatus: EventStatus {
        StorageService.shared.getEventStatus(eventId: event.eventId)
    }
    
    private var anchorStatus: ProofAnchorStatus {
        StorageService.shared.getAnchorStatus(eventId: event.eventId)
    }
    
    // v42.2: Conformance Level（証明力レベル）
    private var conformanceLevel: ConformanceLevel {
        let hasTimestamp = anchorStatus == .anchored
        let hasHumanAttestation = event.captureContext.humanAttestation != nil
        return ConformanceLevel.determine(hasTimestamp: hasTimestamp, hasHumanAttestation: hasHumanAttestation)
    }
    
    // 動画かどうか
    private var isVideo: Bool {
        event.asset.assetType == .video
    }
    
    // 動画URLを取得
    private var videoURL: URL? {
        guard isVideo else { return nil }
        return StorageService.shared.getVideoURL(eventId: event.eventId)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // CPP追加仕様: 画像プレビュー（メディア状態を考慮）
                    if eventStatus == .invalidated {
                        // 失効した証跡
                        VStack(spacing: 8) {
                            Image(systemName: "xmark.seal.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.red.opacity(0.7))
                            Text(L10n.GalleryStatus.invalidated)
                                .font(.headline)
                                .foregroundColor(.secondary)
                            if let tombstone = StorageService.shared.getTombstone(forEventId: event.eventId) {
                                Text(L10n.Detail.invalidatedAt(formatTimestampWithTimezone(tombstone.timestamp)))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    } else if mediaStatus == .purged {
                        // メディア削除済み
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.minus")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            Text(L10n.GalleryStatus.mediaPurged)
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(L10n.Delete.recordRemains)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    } else if isVideo, let url = videoURL {
                        // 🎬 動画プレーヤー
                        VideoThumbnailPlayer(videoURL: url, thumbnail: loadedImage)
                    } else if let image = loadedImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                    } else if isVideo {
                        // 動画だがサムネイルがない場合
                        VStack(spacing: 8) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            Text(L10n.Video.modeVideo)
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    // CPP追加仕様: 拡張ステータスバッジ
                    HStack(spacing: 12) {
                        ExtendedStatusBadge(
                            anchorStatus: anchorStatus,
                            eventStatus: eventStatus,
                            mediaStatus: mediaStatus
                        )
                        
                        // Attested Captureバッジ（タップでツールチップ表示）
                        if event.captureContext.humanAttestation != nil {
                            Button {
                                showAttestedBadgeInfo = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.badge.shield.checkmark.fill")
                                        .font(.caption)
                                    Text(L10n.AttestedCapture.badge)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(12)
                            }
                            .alert(L10n.AttestedCapture.disclaimer, isPresented: $showAttestedBadgeInfo) {
                                Button("OK", role: .cancel) { }
                            } message: {
                                Text(L10n.AttestedCapture.badgeTooltip)
                            }
                        }
                    }
                    
                    // v42.2: Conformance Level Card（証明力レベル）
                    ConformanceLevelCard(level: conformanceLevel)
                    
                    // Human Attestation 詳細（Attested Captureの場合のみ）
                    if let attestation = event.captureContext.humanAttestation {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "person.badge.shield.checkmark.fill")
                                    .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                                Text(L10n.Detail.humanAttestation)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                DetailRow(label: L10n.Attestation.authMethod, value: attestation.method)
                                DetailRow(label: L10n.Attestation.authTime, value: formatAttestationTime(attestation.verifiedAt))
                                DetailRow(label: L10n.Attestation.timeOffset, value: "\(attestation.captureOffsetMs) ms")
                            }
                            
                            // 注意書き
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(L10n.Attestation.disclaimer)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                        .padding()
                        .background(Color.purple.opacity(0.08))
                        .cornerRadius(16)
                    }
                    
                    // 位置情報マップ（位置情報がある場合のみ表示）
                    if let coordinate = locationCoordinate {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.blue)
                                Text(L10n.Detail.captureLocation)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            
                            Map(position: $mapCameraPosition) {
                                Marker(L10n.Detail.captureLocationMarker, coordinate: coordinate)
                                    .tint(.blue)
                            }
                            .frame(height: 150)
                            .cornerRadius(12)
                            .onAppear {
                                mapCameraPosition = .region(MKCoordinateRegion(
                                    center: coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                ))
                            }
                            
                            Text(L10n.Detail.locationPrivacyNote)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text(L10n.Detail.proofId)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(L10n.Detail.proofIdNote)
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                                Text(event.eventId)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Button {
                                UIPasteboard.general.string = event.eventId
                                copiedToClipboard = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedToClipboard = false
                                }
                            } label: {
                                Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(copiedToClipboard ? .green : .blue)
                            }
                        }
                        
                        Divider()
                        
                        DetailRow(label: L10n.Result.filename, value: event.asset.assetName)
                        DetailRow(label: L10n.Result.filesize, value: "\(event.asset.assetSize) bytes")
                        DetailRow(label: L10n.Result.timestamp, value: formatTimestampWithTimezone(event.timestamp))
                        
                        // フラッシュモード（撮影設定として表示）
                        if let flashMode = event.cameraSettings?.flashMode {
                            DetailRow(label: L10n.Verify.flashMode, value: flashMode)
                        }
                        
                        Divider()
                        
                        DetailRow(label: L10n.Result.hashAlgo, value: event.hashAlgo)
                        DetailRow(label: L10n.Result.signAlgo, value: event.signAlgo)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.Detail.assetHash)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(event.asset.assetHash)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.Detail.eventHash)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(event.eventHash)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        // 署名者情報（設定されている場合のみ）
                        if !signerNameSetting.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "person.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(L10n.Verify.signerName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(signerNameSetting)
                                    .font(.subheadline)
                                Text(L10n.Detail.signerNote)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // アンカー情報セクション
                        AnchorInfoSection(eventId: event.eventId)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    Button {
                        if loadedImage != nil && mediaStatus == .present {
                            showShareOptions = true
                        }
                    } label: {
                        HStack {
                            if mediaStatus == .purged {
                                Image(systemName: "photo.badge.minus")
                                Text(L10n.GalleryStatus.mediaPurged)
                            } else if loadedImage == nil {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            if mediaStatus != .purged {
                                Text(L10n.Detail.share)
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: (loadedImage != nil && mediaStatus == .present) ? [.blue, .purple] : [.gray, .gray.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                    }
                    .disabled(loadedImage == nil || mediaStatus != .present)
                    
                    // CPP追加仕様: 削除オプションボタン
                    Button {
                        showDeleteOptions = true
                    } label: {
                        HStack {
                            Image(systemName: "ellipsis.circle")
                            Text(L10n.Delete.sheetTitle)
                            if eventStatus == .active {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(eventStatus == .active ? .red : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(eventStatus == .active ? Color.red.opacity(0.1) : Color(.systemGray5))
                        .cornerRadius(10)
                    }
                    .disabled(eventStatus != .active)
                }
                .padding()
            }
            .navigationTitle(L10n.Detail.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Result.close) { dismiss() }
                }
            }
            .onAppear {
                loadImage()
                loadLocationMetadata()
            }
            .sheet(isPresented: $showShareOptions) {
                ShareOptionsSheet(
                    image: loadedImage,
                    videoURL: videoURL,
                    proofId: event.eventId,
                    hasLocation: locationCoordinate != nil,
                    onSelect: { option in
                        handleShareOption(option)
                    },
                    onInternalExport: { includeLocation, includeC2PA in
                        handleInternalExport(includeLocation: includeLocation, includeC2PA: includeC2PA)
                    },
                    onRawDataExport: {
                        handleRawDataExport()
                    },
                    onC2PAExport: {
                        handleC2PAExport()
                    }
                )
            }
            .sheet(isPresented: $showDeleteOptions) {
                DeleteOptionsSheet(event: event, viewModel: viewModel)
            }
            .sheet(isPresented: $showQRPreview) {
                if let image = loadedImage {
                    QRPreviewSheet(
                        originalImage: image,
                        proofId: event.eventId
                    ) { qrImage in
                        // UIKitで直接共有シートを表示
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            presentShareSheet(items: [qrImage])
                        }
                    }
                }
            }
            .overlay {
                // 処理中のローディングオーバーレイ（横棒プログレスバー）
                if isProcessing || viewModel.isSharing {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            Text(L10n.Detail.preparingProof)
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            IndeterminateProgressBar()
                                .frame(width: 200, height: 6)
                        }
                        .padding(32)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                    }
                }
            }
            .alert(L10n.Export.forensicConfirmTitle, isPresented: $showInternalExportConfirm) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Export.forensicButton) {
                    exportInternalProof()
                }
            } message: {
                Text(L10n.Export.forensicConfirmMessage)
            }
            .alert(L10n.Export.completeTitle, isPresented: $showInternalExportResult) {
                Button(L10n.Common.ok) {}
            } message: {
                Text(internalExportMessage)
            }
            .alert(L10n.Export.authErrorTitle, isPresented: $showAuthError) {
                Button(L10n.Common.ok) {}
            } message: {
                Text(authErrorMessage)
            }
        }
    }
    
    /// Face ID認証後に法務用エクスポート確認を表示
    private func authenticateAndExportInternal() async {
        let result = await BiometricAuthService.shared.authenticate(for: .exportFullProof)
        
        switch result {
        case .success:
            showInternalExportConfirm = true
        case .cancelled:
            break
        case .failed(let error):
            authErrorMessage = L10n.Subscription.authFailed(error)
            showAuthError = true
        case .notAvailable:
            // 認証が利用不可の場合は直接確認を表示
            showInternalExportConfirm = true
        }
    }
    
    private func exportInternalProof() {
        Task {
            if let url = await viewModel.exportInternalProof(eventId: event.eventId) {
                await MainActor.run {
                    internalExportMessage = L10n.ExportMessage.shareSheet
                    // 直接共有シートを表示
                    presentShareSheet(items: [url])
                }
            } else {
                await MainActor.run {
                    internalExportMessage = L10n.ExportMessage.failed
                    showInternalExportResult = true
                }
            }
        }
    }
    
    private func loadImage() {
        // メディアが削除済みの場合はロードしない
        guard mediaStatus == .present else {
            loadedImage = nil
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let img: UIImage?
            if isVideo {
                // 動画の場合はサムネイルを読み込む
                img = StorageService.shared.loadThumbnail(eventId: event.eventId, size: CGSize(width: 640, height: 360))
            } else {
                // 画像の場合は画像を読み込む
                img = StorageService.shared.loadImage(eventId: event.eventId)
            }
            DispatchQueue.main.async {
                loadedImage = img
            }
        }
    }
    
    /// タイムスタンプをローカル時刻＋タイムゾーン明示で表示
    private func formatTimestampWithTimezone(_ timestamp: String) -> String {
        guard let date = Date.fromISO8601(timestamp) else { return timestamp }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        formatter.timeZone = .current
        
        let dateString = formatter.string(from: date)
        
        // タイムゾーン略称（JST, PST等）を取得
        let tzFormatter = DateFormatter()
        tzFormatter.dateFormat = "zzz"
        tzFormatter.timeZone = .current
        let tzAbbrev = tzFormatter.string(from: date)
        
        return "\(dateString) \(tzAbbrev)"
    }
    
    private func formatAttestationTime(_ timestamp: String) -> String {
        formatTimestampWithTimezone(timestamp)
    }
    
    private func loadLocationMetadata() {
        if let location = StorageService.shared.getLocationMetadata(eventId: event.eventId) {
            locationCoordinate = CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            )
        }
    }
    
    private func handleShareOption(_ option: ShareOption) {
        // すべての共有オプションでグローバルローディングを表示（フリーズ防止）
        // QRプレビューは別シートなので除外
        if option != .withQR {
            viewModel.isSharing = true
        }
        
        // シートを閉じてから処理を開始
        showShareOptions = false
        
        // シートが完全に閉じるまで待機してから処理
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            switch option {
            case .imageOnly, .mediaOnly:
                if let image = loadedImage {
                    viewModel.isSharing = false
                    presentShareSheet(items: [image])
                } else {
                    viewModel.isSharing = false
                }
                
            case .videoOnly:
                // 動画のみ共有
                if let url = videoURL {
                    viewModel.isSharing = false
                    presentShareSheet(items: [url])
                } else {
                    viewModel.isSharing = false
                }
                
            case .withProof:
                Task {
                    if let url = await viewModel.exportProof(eventId: event.eventId) {
                        var items: [Any] = [url]
                        if let image = loadedImage {
                            // 参照用プレビューの透かしを追加
                            let watermarkedImage = ReferenceWatermark.addWatermark(to: image)
                            items.insert(watermarkedImage, at: 0)
                        }
                        await MainActor.run {
                            viewModel.isSharing = false
                            presentShareSheet(items: items)
                        }
                    } else {
                        await MainActor.run {
                            viewModel.isSharing = false
                        }
                    }
                }
                
            case .withQR:
                showQRPreview = true
                
            case .internalProof, .exportZip:
                // 新しいonInternalExportコールバックで処理
                viewModel.isSharing = false
                
            case .rawDataExport:
                // 生データエクスポート（handleRawDataExportで処理）
                viewModel.isSharing = false
                
            case .c2paExport:
                // C2PAエクスポート（handleC2PAExportで処理）
                viewModel.isSharing = false
            }
        }
    }
    
    private func handleInternalExport(includeLocation: Bool, includeC2PA: Bool) {
        viewModel.isSharing = true
        showShareOptions = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task {
                // 法務用エクスポート（メディア + Proof JSON + C2PA(オプション) をZIPにまとめて）
                if let zipURL = await viewModel.exportInternalProof(eventId: event.eventId, includeLocation: includeLocation, includeC2PA: includeC2PA) {
                    await MainActor.run {
                        viewModel.isSharing = false
                        // ZIPファイルを共有
                        presentShareSheet(items: [zipURL])
                    }
                } else {
                    await MainActor.run {
                        viewModel.isSharing = false
                    }
                }
            }
        }
    }
    
    private func handleRawDataExport() {
        viewModel.isSharing = true
        showShareOptions = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Task {
                // 生データ（元画像/動画 + Proof JSON）をZIPにまとめてエクスポート
                if let zipURL = await viewModel.exportRawData(eventId: event.eventId) {
                    await MainActor.run {
                        viewModel.isSharing = false
                        // ZIPファイルを共有
                        presentShareSheet(items: [zipURL])
                    }
                } else {
                    await MainActor.run {
                        viewModel.isSharing = false
                    }
                }
            }
        }
    }
    
    private func handleC2PAExport() {
        viewModel.isSharing = true
        showShareOptions = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Task {
                do {
                    let zipURL = try await C2PAExportService.shared.exportC2PAPackage(eventId: event.eventId)
                    await MainActor.run {
                        viewModel.isSharing = false
                        presentShareSheet(items: [zipURL])
                    }
                } catch {
                    await MainActor.run {
                        viewModel.isSharing = false
                        print("[C2PAExport] Failed: \(error)")
                    }
                }
            }
        }
    }
}

// MARK: - Settings View (Enhanced)

struct SettingsView: View {
    @ObservedObject var viewModel: CaptureViewModel
    @ObservedObject private var anchorService = AnchorService.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var showPaywall = false
    @State private var showUseCases = false
    @State private var isRestoring = false
    @State private var showRestoreAlert = false
    @State private var restoreMessage = ""
    @State private var isExportingAllInternal = false
    @State private var showExportAlert = false
    @State private var exportAlertMessage = ""
    @State private var showExportOptions = false
    @State private var exportIncludeMedia = false
    @State private var exportIncludeC2PA = false
    @State private var showC2PAInfo = false
    @State private var showAuthError = false
    @State private var authErrorMessage = ""
    @AppStorage("signerName") private var signerName: String = ""  // 署名者名（フォレンジック用）
    
    /// 現在の証跡数（viewModelから取得）
    private var currentProofCount: Int {
        viewModel.currentProofCount
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "shield.checkered")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("VeraSnap")
                                    .font(.headline)
                                
                                if subscriptionService.effectiveIsPro {
                                    ProBadge()
                                }
                            }
                            Text("\(L10n.Settings.version) 1.0.0")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 8)
                }
                
                // Pro / サブスクリプションセクション
                Section {
                    if subscriptionService.effectiveIsPro {
                        // Pro状態
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.orange)
                            Text(L10n.Settings.proActive)
                                .fontWeight(.medium)
                            Spacer()
                            if case .pro(let expiration) = subscriptionService.status,
                               let date = expiration {
                                Text(L10n.ProDisplay.until(formatDate(date)))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // サブスク管理リンク
                        Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                            HStack {
                                Text(L10n.Settings.manageSubscription)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        // 無料ユーザー
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(L10n.Settings.freePlan)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(L10n.ProDisplay.remaining(50 - currentProofCount))
                                    .font(.caption)
                                    .foregroundColor(currentProofCount >= 90 ? .orange : .secondary)
                            }
                            
                            // プログレスバー（使用率）
                            ProgressView(value: min(Double(currentProofCount) / 50.0, 1.0))
                                .tint(currentProofCount >= 90 ? .orange : .blue)
                            
                            if currentProofCount >= 90 {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                    Text(L10n.Settings.approachingLimit)
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Image(systemName: "crown.fill")
                                    .foregroundColor(.orange)
                                Text(L10n.Settings.upgradeToProButton)
                                    .fontWeight(.medium)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Button {
                            Task { await restorePurchases() }
                        } label: {
                            HStack {
                                Text(L10n.Settings.restorePurchases)
                                Spacer()
                                if isRestoring {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isRestoring)
                    }
                } header: {
                    Text(L10n.Settings.planSection)
                }
                
                // アプリ説明セクション
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n.Settings.aboutDescription)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineSpacing(4)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text(L10n.Settings.aboutTitle)
                }
                
                // MARK: - Case Management (v40)
                Section {
                    NavigationLink {
                        CaseListView()
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.Case.title)
                                    .font(.body)
                                if let currentCase = CaseService.shared.currentCase {
                                    Text(currentCase.name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Text("\(CaseService.shared.cases.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text(L10n.Case.title)
                } footer: {
                    Text(L10n.Settings.casesFooter)
                }
                
                Section {
                    // TSAプロバイダー
                    SettingsTSARow()
                    
                    HStack {
                        Text(L10n.Settings.timestampPending)
                        Spacer()
                        Text("\(anchorService.pendingEventCount)")
                            .foregroundColor(.secondary)
                    }
                    
                    if let lastAnchor = anchorService.lastAnchorTime {
                        HStack {
                            Text(L10n.Settings.timestampLast)
                            Spacer()
                            Text(formatDate(lastAnchor))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button {
                        Task { await anchorService.triggerAnchor() }
                    } label: {
                        HStack {
                            Text(L10n.Settings.timestampTrigger)
                            Spacer()
                            if anchorService.isAnchoring {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.up.circle")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .disabled(anchorService.isAnchoring || anchorService.pendingEventCount == 0)
                } header: {
                    Text(L10n.Settings.timestampTitle)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        // Pro版の場合、フェイルオーバー先を表示
                        if subscriptionService.effectiveIsPro {
                            Text(L10n.Settings.timestampFooterPro)
                        } else {
                            Text(L10n.Settings.timestampFooter)
                        }
                    }
                }
                
                // MARK: - Attested Capture Mode
                Section {
                    // トグル
                    Toggle(isOn: $viewModel.isAttestedCaptureMode) {
                        HStack {
                            Image(systemName: "person.badge.shield.checkmark.fill")
                                .foregroundColor(.purple)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.AttestedCapture.toggleTitle)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(viewModel.isAttestedCaptureMode ? L10n.AttestedCapture.enabled : L10n.AttestedCapture.disabled)
                                    .font(.caption)
                                    .foregroundColor(viewModel.isAttestedCaptureMode ? .green : .secondary)
                            }
                        }
                    }
                    .disabled(!viewModel.isAttestedCaptureModeAvailable)
                    
                    // 認証方式の表示
                    if viewModel.isAttestedCaptureModeAvailable {
                        HStack {
                            Text(L10n.AttestedCapture.authMethod)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(BiometricAuthService.shared.biometryTypeName)
                                .foregroundColor(.primary)
                        }
                        .font(.caption)
                    }
                } header: {
                    Text(L10n.AttestedCapture.sectionTitle)
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        // 説明文
                        Text(L10n.AttestedCapture.description(BiometricAuthService.shared.biometryTypeName))
                        
                        // 免責事項（シンプルなテキスト）
                        Text(L10n.AttestedCapture.disclaimer)
                            .foregroundColor(.orange)
                        Text(L10n.AttestedCapture.disclaimerFull)
                            .foregroundColor(.secondary)
                        
                        // 利用不可の場合
                        if !viewModel.isAttestedCaptureModeAvailable {
                            Text(L10n.AttestedCapture.notAvailable)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // 位置情報セクション
                Section {
                    // 現在の状態表示
                    HStack {
                        Image(systemName: "location.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.Settings.locationStatusTitle)
                                .font(.subheadline)
                            Text(locationStatusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    // 設定を開くボタン
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Text(L10n.Settings.locationOpenSettings)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text(L10n.Settings.locationTitle)
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Settings.locationOnDesc)
                        Text(L10n.Settings.locationOffDesc)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 言語設定セクション
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.Settings.languageCurrent)
                                Text(currentLanguageName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text(L10n.Settings.languageTitle)
                } footer: {
                    Text(L10n.Settings.languageNote)
                }
                
                // ユースケースセクション
                Section {
                    Button {
                        showUseCases = true
                    } label: {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                            Text(L10n.Settings.useCasesBrowse)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text(L10n.Settings.useCasesTitle)
                } footer: {
                    Text(L10n.Settings.useCasesFooter)
                }
                
                // フォレンジック設定セクション
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "signature")
                                .foregroundColor(.purple)
                            Text(L10n.Settings.signerNameLabel)
                        }
                        
                        TextField(L10n.Settings.signerNamePlaceholder, text: $signerName)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.words)
                        
                        Text(L10n.Settings.signerNameHint)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(L10n.Settings.forensicTitle)
                } footer: {
                    Text(L10n.Settings.forensicFooter)
                }
                
                // チェーン整合性検証セクション
                Section {
                    NavigationLink {
                        ChainIntegrityView()
                    } label: {
                        HStack {
                            Image(systemName: "link.badge.checkmark")
                                .foregroundColor(.green)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.Chain.title)
                                    .font(.subheadline)
                                Text(L10n.Chain.verificationFooter)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            
                            Spacer()
                        }
                    }
                } header: {
                    Text(L10n.Chain.statisticsTitle)
                }
                
                // データ管理セクション - 認証必須
                Section {
                    // 画像を含めるトグル
                    Toggle(isOn: $exportIncludeMedia) {
                        HStack {
                            Image(systemName: "photo")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.Settings.exportIncludeMedia)
                                Text(L10n.Settings.exportIncludeMediaDesc)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // C2PAエクスポートトグル
                    Toggle(isOn: $exportIncludeC2PA) {
                        HStack {
                            Image(systemName: "shield.lefthalf.filled")
                                .foregroundColor(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(L10n.Settings.exportIncludeC2PA)
                                    Text("C2PA")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.purple)
                                        .cornerRadius(4)
                                    
                                    // iボタン
                                    Button {
                                        showC2PAInfo = true
                                    } label: {
                                        Image(systemName: "info.circle")
                                            .foregroundColor(.purple)
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Text(L10n.Settings.exportIncludeC2PADesc)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // エクスポートボタン
                    Button {
                        Task { await authenticateAndExportAll() }
                    } label: {
                        HStack {
                            Image(systemName: "doc.zipper")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(L10n.Settings.exportAllForensic)
                                    Image(systemName: "faceid")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(exportIncludeMedia ? L10n.Settings.exportAllForensicDescWithMedia : L10n.Settings.exportAllForensicDesc)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if isExportingAllInternal {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isExportingAllInternal)
                } header: {
                    Text(L10n.Settings.dataManagement)
                } footer: {
                    Text(L10n.Settings.exportAllForensicFooter)
                }
                
                Section(L10n.Settings.specTitle) {
                    Link(destination: URL(string: "https://veritaschain.org/vap/cpp/verasnap/")!) {
                        HStack {
                            Text(L10n.Settings.specAbout)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Link(destination: URL(string: "https://github.com/veritaschain/cpp-spec")!) {
                        HStack {
                            Text(L10n.Settings.specCpp)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Link(destination: URL(string: "https://github.com/veritaschain/cpp-spec/blob/main/docs/VeraSnap/VeraSnap_WorldFirst_Report_Final_EN.md")!) {
                        HStack {
                            Text(L10n.Settings.specWorldFirst)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        // Verify, Don't Trust.
                        Text(L10n.Settings.philosophy)
                            .font(.headline)
                            .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                        
                        Text(L10n.Settings.philosophyDesc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                        
                        Divider()
                        
                        // 開発者情報
                        HStack {
                            Text(L10n.Settings.developer)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(L10n.Settings.developerName)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        
                        // 開発責任者
                        HStack {
                            Text(L10n.SettingsDeveloper.lead)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Link(destination: URL(string: "https://www.linkedin.com/in/tokachi/")!) {
                                HStack(spacing: 4) {
                                    Text("Tokachi Kamimura")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        
                        Divider()
                        
                        // サポート連絡先
                        Text(L10n.Settings.supportMessage)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                        
                        Divider()
                        
                        // オープンソース参加案内
                        Text(L10n.Settings.openSourceMessage)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                        
                        // GitHub CPP-spec リンク
                        Link(destination: URL(string: "https://github.com/veritaschain/cpp-spec")!) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.caption2)
                                Text(L10n.Settings.viewOnGitHub)
                                    .font(.caption2)
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption2)
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle(L10n.Settings.title)
            .sheet(isPresented: $showPaywall) {
                PaywallView(reason: .manual)
            }
            .sheet(isPresented: $showUseCases) {
                UseCasesView()
            }
            .alert(L10n.Subscription.restoreTitle, isPresented: $showRestoreAlert) {
                Button(L10n.Error.ok) {}
            } message: {
                Text(restoreMessage)
            }
            .alert(L10n.Settings.export, isPresented: $showExportAlert) {
                Button(L10n.Error.ok) {}
            } message: {
                Text(exportAlertMessage)
            }
            .alert(L10n.GalleryDelete.authError, isPresented: $showAuthError) {
                Button(L10n.Error.ok) {}
            } message: {
                Text(authErrorMessage)
            }
            .sheet(isPresented: $showC2PAInfo) {
                C2PAInfoSheet()
            }
            .overlay {
                // エクスポート中のローディングオーバーレイ
                if isExportingAllInternal {
                    ZStack {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            
                            Text(L10n.Settings.exportingAll)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 28)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                    }
                }
            }
        }
        .onAppear {
            // 設定画面表示時に確定待ちカウントを更新
            anchorService.refreshPendingCount()
        }
    }
    
    private func authenticateAndExportAll() async {
        // 認証前からローディング表示
        isExportingAllInternal = true
        
        let result = await BiometricAuthService.shared.authenticate(for: .exportFullProof)
        
        switch result {
        case .success:
            await exportAllInternalProofsCore()
        case .cancelled:
            // ユーザーがキャンセル - 何もしない
            isExportingAllInternal = false
        case .failed(let error):
            isExportingAllInternal = false
            authErrorMessage = L10n.Subscription.authFailed(error)
            showAuthError = true
        case .notAvailable:
            // 認証が利用不可の場合は直接エクスポート（セキュリティ設定されていないデバイス）
            await exportAllInternalProofsCore()
        }
    }
    
    private func exportAllInternalProofs() async {
        isExportingAllInternal = true
        await exportAllInternalProofsCore()
    }
    
    private func exportAllInternalProofsCore() async {
        defer { isExportingAllInternal = false }
        
        // MainActorでトグルの値を取得
        let includeMedia = await MainActor.run { exportIncludeMedia }
        let includeC2PA = await MainActor.run { exportIncludeC2PA }
        
        do {
            let events = try StorageService.shared.getEvents()
            guard !events.isEmpty else {
                await MainActor.run {
                    exportAlertMessage = L10n.ExportMessage.noProofs
                    showExportAlert = true
                }
                return
            }
            
            let eventBuilder = CPPEventBuilder()
            var proofs: [InternalProofJSON] = []
            
            // 署名者名を取得（フォレンジック設定から）
            let signerName = UserDefaults.standard.string(forKey: "signerName")
            
            for event in events {
                let anchor = try StorageService.shared.getAnchor(forEventId: event.eventId)
                let proof = eventBuilder.generateProofJSON(event: event, anchor: anchor, signerName: signerName)
                proofs.append(proof)
            }
            
            // 統合フォレンジックパッケージ（Proof + Tombstone + Media）を作成
            let zipURL = try StorageService.shared.exportForensicPackageAsZip(
                proofs: proofs,
                signerName: signerName,
                includeMedia: includeMedia,
                includeC2PA: includeC2PA
            )
            
            // 共有シートを表示
            await MainActor.run {
                presentShareSheet(items: [zipURL])
            }
            
        } catch {
            await MainActor.run {
                exportAlertMessage = L10n.ExportMessage.error(error.localizedDescription)
                showExportAlert = true
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return formatter.string(from: date)
    }
    
    private var currentLanguageName: String {
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        let languageNames: [String: String] = [
            "ja": "日本語",
            "en": "English",
            "zh": "中文",
            "ko": "한국어",
            "fr": "Français",
            "de": "Deutsch",
            "es": "Español",
            "pt": "Português",
            "ar": "العربية"
        ]
        return languageNames[languageCode] ?? languageCode
    }
    
    private var locationStatusText: String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return L10n.Settings.locationStatusOn
        case .denied, .restricted:
            return L10n.Settings.locationStatusOff
        case .notDetermined:
            return L10n.Settings.locationStatusNotDetermined
        @unknown default:
            return L10n.Settings.locationStatusOff
        }
    }
    
    private func restorePurchases() async {
        isRestoring = true
        let success = await subscriptionService.restorePurchases()
        isRestoring = false
        
        if success {
            restoreMessage = L10n.Subscription.restoreSuccess
        } else {
            restoreMessage = subscriptionService.errorMessage ?? L10n.Subscription.restoreFailed
        }
        showRestoreAlert = true
    }
}

// MARK: - Progress Bar Components

/// 撮影中のプログレスバー
struct CaptureProgressBar: View {
    @State private var progress: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 8)
                
                // プログレス
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progress, height: 8)
            }
        }
        .frame(height: 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                progress = 1.0
            }
        }
    }
}

// MARK: - CPP Additional Spec UI Components

/// C2PA情報シート
struct C2PAInfoSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // C2PAとは
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "shield.lefthalf.filled")
                                .foregroundColor(.purple)
                            Text(L10n.C2PAInfo.whatIsC2PA)
                                .font(.headline)
                        }
                        
                        Text(L10n.C2PAInfo.whatIsC2PADesc)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // マッピングテーブル
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left.arrow.right")
                                .foregroundColor(.purple)
                            Text(L10n.Settings.c2paMappingTitle)
                                .font(.headline)
                        }
                        
                        VStack(spacing: 10) {
                            C2PAMappingRow(cpp: "EventId", c2pa: "instanceID")
                            C2PAMappingRow(cpp: "EventHash", c2pa: "vso.cpp.event_hash")
                            C2PAMappingRow(cpp: "AssetHash", c2pa: "c2pa.hash.data")
                            C2PAMappingRow(cpp: "Signature", c2pa: "signature_info")
                            C2PAMappingRow(cpp: "TSA Timestamp", c2pa: "time_source: rfc3161")
                            C2PAMappingRow(cpp: "HumanAttestation", c2pa: "vso.cpp.human_attested")
                            C2PAMappingRow(cpp: "CameraSettings", c2pa: "stds.exif")
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    Divider()
                    
                    // 使用方法
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                            Text(L10n.C2PAInfo.howToUse)
                                .font(.headline)
                        }
                        
                        Text(L10n.C2PAInfo.howToUseDesc)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // C2PAリンク
                    Link(destination: URL(string: "https://c2pa.org")!) {
                        HStack {
                            Image(systemName: "globe")
                            Text(L10n.C2PAInfo.learnMore)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle(L10n.C2PAInfo.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Common.close) { dismiss() }
                }
            }
        }
    }
}

/// C2PA マッピング行（設定画面用）
struct C2PAMappingRow: View {
    let cpp: String
    let c2pa: String
    
    var body: some View {
        HStack(spacing: 8) {
            // CPP
            Text(cpp)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.orange)
                .frame(width: 100, alignment: .leading)
            
            // 矢印
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // C2PA
            Text(c2pa)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.purple)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

/// アンカーステータスバッジ
struct AnchorStatusBadge: View {
    let status: ProofAnchorStatus
    let eventStatus: EventStatus
    
    var body: some View {
        if eventStatus == .invalidated {
            // 失効バッジ
            Image(systemName: "xmark.seal.fill")
                .font(.caption)
                .foregroundColor(.white)
                .padding(4)
                .background(Color.red)
                .clipShape(Circle())
                .shadow(radius: 2)
        } else {
            // アンカーステータスバッジ
            Image(systemName: statusIcon)
                .font(.caption)
                .foregroundColor(.white)
                .padding(4)
                .background(statusColor)
                .clipShape(Circle())
                .shadow(radius: 2)
        }
    }
    
    private var statusIcon: String {
        switch status {
        case .anchored: return "checkmark.shield.fill"
        case .pending: return "clock.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .skipped: return "minus.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .anchored: return .green
        case .pending: return .blue  // 固定前は青色
        case .failed: return .red
        case .skipped: return .gray
        }
    }
}

/// 拡張ステータスバッジ（詳細画面用）
struct ExtendedStatusBadge: View {
    let anchorStatus: ProofAnchorStatus
    let eventStatus: EventStatus
    let mediaStatus: MediaStatus
    
    var body: some View {
        HStack(spacing: 8) {
            // イベントステータス
            if eventStatus == .invalidated {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.seal.fill")
                        .font(.caption)
                    Text(L10n.GalleryStatus.invalidated)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.red)
                .cornerRadius(12)
            } else {
                // アンカーステータス
                HStack(spacing: 4) {
                    Image(systemName: anchorStatusIcon)
                        .font(.caption)
                    Text(anchorStatus.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(anchorStatusColor)
                .cornerRadius(12)
            }
            
            // メディアステータス（削除済みの場合のみ表示）
            if mediaStatus == .purged {
                HStack(spacing: 4) {
                    Image(systemName: "photo.badge.minus")
                        .font(.caption)
                    Text(L10n.GalleryStatus.mediaPurged)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.gray)
                .cornerRadius(12)
            }
        }
    }
    
    private var anchorStatusIcon: String {
        switch anchorStatus {
        case .anchored: return "checkmark.shield.fill"
        case .pending: return "clock.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .skipped: return "minus.circle.fill"
        }
    }
    
    private var anchorStatusColor: Color {
        switch anchorStatus {
        case .anchored: return .green
        case .pending: return .blue  // 固定前は青色
        case .failed: return .red
        case .skipped: return .gray
        }
    }
}

/// 削除オプションシート
struct DeleteOptionsSheet: View {
    let event: CPPEvent
    @ObservedObject var viewModel: CaptureViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedReason: InvalidationReason = .userPrivacyRequest
    @State private var isProcessing = false
    @State private var showAuthError = false
    @State private var authErrorMessage = ""
    
    private var eventStatus: EventStatus {
        StorageService.shared.getEventStatus(eventId: event.eventId)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 警告アイコン
                Image(systemName: "trash.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.red)
                    .padding(.top, 20)
                
                // 説明
                VStack(spacing: 12) {
                    Text(L10n.Delete.confirmTitle)
                        .font(.headline)
                    
                    Text(L10n.Delete.confirmMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // 理由選択
                VStack(spacing: 8) {
                    Text(L10n.Delete.invalidateSelectReason)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    Picker("理由", selection: $selectedReason) {
                        Text(L10n.InvalidationReason.privacy).tag(InvalidationReason.userPrivacyRequest)
                        Text(L10n.InvalidationReason.accidental).tag(InvalidationReason.userAccidentalCapture)
                        Text(L10n.InvalidationReason.inappropriate).tag(InvalidationReason.userContentInappropriate)
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // ボタン
                VStack(spacing: 12) {
                    Button {
                        Task { await deleteEvent() }
                    } label: {
                        HStack {
                            if isProcessing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "faceid")
                                Text(L10n.Delete.confirmButton)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isProcessing || eventStatus != .active)
                    
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle(L10n.Delete.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }
            }
            .alert(L10n.Common.error, isPresented: $showAuthError) {
                Button(L10n.Common.ok) { }
            } message: {
                Text(authErrorMessage)
            }
        }
    }
    
    @MainActor
    private func deleteEvent() async {
        isProcessing = true
        let currentViewModel = viewModel  // ローカルにキャプチャ
        
        // 生体認証
        let authResult = await BiometricAuthService.shared.authenticate(for: .deleteProof)
        
        switch authResult {
        case .success, .notAvailable:
            do {
                // 1. Tombstone発行（証跡失効の記録）
                _ = try await TombstoneService.shared.invalidateEvent(
                    eventId: event.eventId,
                    reason: selectedReason,
                    isUserInitiated: true
                )
                
                // 2. メディア削除
                try StorageService.shared.purgeMedia(eventId: event.eventId)
                
                // 3. イベント自体を削除
                try StorageService.shared.deleteEvent(eventId: event.eventId)
                
                // 4. 削除したイベントが最後に撮影したものならサムネイルをクリア
                if currentViewModel.lastCaptureResult?.eventId == event.eventId {
                    currentViewModel.lastCapturedImage = nil
                    currentViewModel.lastCaptureResult = nil
                }
                // 動画の場合もクリア
                if currentViewModel.lastVideoResult?.eventId == event.eventId {
                    currentViewModel.lastVideoResult = nil
                }
                
                // 5. 処理完了、シートを閉じる
                isProcessing = false
                dismiss()
                
                // 6. UIを更新
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    currentViewModel.refreshEvents()
                }
            } catch let error as TombstoneError {
                // Tombstone固有のエラー
                isProcessing = false
                switch error {
                case .targetEventNotFound:
                    authErrorMessage = L10n.Delete.errorTargetNotFound
                case .alreadyInvalidated:
                    authErrorMessage = L10n.Delete.errorAlreadyInvalidated
                case .eventNotActive:
                    authErrorMessage = L10n.Delete.errorEventNotActive
                case .signatureFailed:
                    authErrorMessage = L10n.Delete.errorSignatureFailed
                case .storageFailed:
                    authErrorMessage = L10n.Delete.errorStorageFailed
                }
                showAuthError = true
            } catch {
                isProcessing = false
                authErrorMessage = L10n.Delete.errorGeneric(error.localizedDescription)
                showAuthError = true
            }
            
        case .cancelled:
            isProcessing = false
            
        case .failed(let error):
            isProcessing = false
            authErrorMessage = L10n.Delete.errorAuthFailed(error)
            showAuthError = true
        }
    }
}

/// 不確定プログレスバー（左右に移動）
struct IndeterminateProgressBar: View {
    @State private var offset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.3))
                
                // 移動するバー
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * 0.35)
                    .offset(x: offset * geometry.size.width * 0.65)
            }
        }
        .onAppear {
            // 即座にアニメーション開始
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                offset = 1.0
            }
        }
    }
}

// MARK: - Anchor Info Section (証跡詳細用)

struct AnchorInfoSection: View {
    let eventId: String
    
    private var anchor: AnchorRecord? {
        try? StorageService.shared.getAnchor(forEventId: eventId)
    }
    
    private var statusIcon: String {
        guard let anchor = anchor else {
            return "minus.circle"  // アンカーなし
        }
        switch anchor.status {
        case .completed:
            return "checkmark.seal.fill"
        case .pending:
            return "clock.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var statusColor: Color {
        guard let anchor = anchor else {
            return .secondary  // アンカーなし
        }
        switch anchor.status {
        case .completed:
            return .green
        case .pending:
            return .orange
        case .failed:
            return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Image(systemName: statusIcon)
                    .font(.caption)
                    .foregroundColor(statusColor)
                Text(L10n.Detail.anchorInfo)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            
            if let anchor = anchor, anchor.status == .completed {
                // タイムスタンプ確定済み
                AnchorDetailRow(label: L10n.Detail.anchorProvider, value: anchor.serviceEndpoint)
                AnchorDetailRow(label: L10n.Detail.anchorTime, value: anchor.timestamp)
            } else {
                // タイムスタンプ未確定 - "none" と表示
                AnchorDetailRow(label: L10n.Detail.anchorProvider, value: L10n.Timestamp.none)
                AnchorDetailRow(label: L10n.Detail.anchorTime, value: L10n.Timestamp.none)
            }
        }
    }
}

struct AnchorDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }
}

// MARK: - TSA Provider Row (設定画面用)

struct SettingsTSARow: View {
    @ObservedObject var anchorService = AnchorService.shared
    
    var body: some View {
        HStack {
            Text(L10n.Settings.tsaProvider)
            Spacer()
            Text(anchorService.primaryEndpoint.name)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
