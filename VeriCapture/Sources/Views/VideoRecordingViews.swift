//
//  VideoRecordingViews.swift
//  VeriCapture
//
//  Video Recording UI Components
//  © 2026 VeritasChain Standards Organization
//

import SwiftUI
import AVFoundation
import AVKit

// MARK: - Video Player View

/// Proof詳細で動画を再生するビュー
struct VideoPlayerView: View {
    let videoURL: URL
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    
    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .cornerRadius(12)
                    .onAppear {
                        // 動画終了時に最初に戻る
                        NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: player.currentItem,
                            queue: .main
                        ) { _ in
                            player.seek(to: .zero)
                            isPlaying = false
                        }
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else {
                // プレーヤー読み込み中
                ProgressView()
                    .frame(height: 200)
            }
        }
        .onAppear {
            setupPlayer()
        }
    }
    
    private func setupPlayer() {
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("[VideoPlayerView] Video file not found: \(videoURL.path)")
            return
        }
        player = AVPlayer(url: videoURL)
    }
}

/// シンプルな動画サムネイルと再生ボタン
struct VideoThumbnailPlayer: View {
    let videoURL: URL
    let thumbnail: UIImage?
    @State private var showFullPlayer = false
    
    var body: some View {
        ZStack {
            // サムネイル or プレースホルダー
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 250)
                    .cornerRadius(12)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: .infinity, maxHeight: 200)
                    .overlay(
                        Image(systemName: "video.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                    )
            }
            
            // 再生ボタンオーバーレイ
            Button {
                showFullPlayer = true
            } label: {
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .offset(x: 2)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullScreenVideoPlayer(videoURL: videoURL)
        }
    }
}

/// フルスクリーン動画プレーヤー
struct FullScreenVideoPlayer: View {
    let videoURL: URL
    @Environment(\.dismiss) var dismiss
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            }
            
            // 閉じるボタン
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            player = AVPlayer(url: videoURL)
        }
    }
}

// MARK: - Capture Mode Selector

/// 写真/動画モード切り替えセグメント
struct CaptureModeSelector: View {
    @Binding var mode: CaptureViewModel.CaptureMode
    let isDisabled: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(CaptureViewModel.CaptureMode.allCases, id: \.self) { captureMode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mode = captureMode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: captureMode.icon)
                            .font(.system(size: 14, weight: .semibold))
                        Text(captureMode == .photo ? L10n.Video.modePhoto : L10n.Video.modeVideo)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(mode == captureMode ? .white : .white.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(mode == captureMode ? Color.white.opacity(0.25) : Color.clear)
                    )
                }
                .disabled(isDisabled)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.3))
        )
    }
}

// MARK: - Recording Button

/// 録画ボタン（タップで開始/停止）
struct RecordingButton: View {
    let isRecording: Bool
    let isProcessing: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // 外枠
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 72, height: 72)
                
                // 内側（録画中は赤い四角、それ以外は赤い円）
                if isRecording {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red)
                        .frame(width: 32, height: 32)
                } else if isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 58, height: 58)
                        
                        // シールドアイコン（写真と同じ）
                        Image(systemName: "shield.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .disabled(isProcessing)
    }
}

// MARK: - Recording Progress Indicator

/// 録画進捗インジケーター
struct RecordingProgressIndicator: View {
    let duration: TimeInterval
    let progress: Double
    let maxDuration: TimeInterval
    
    var body: some View {
        VStack(spacing: 8) {
            // 録画中バッジ
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .modifier(PulsingAnimation())
                
                Text(L10n.Video.recording)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.6))
            )
            
            // 時間表示
            Text(formatDuration(duration))
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundColor(.white)
            
            // プログレスバー
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progress > 0.8 ? Color.orange : Color.red)
                        .frame(width: geometry.size.width * CGFloat(progress), height: 6)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 40)
            
            // 残り時間
            if maxDuration - duration < 10 && maxDuration - duration > 0 {
                Text(String(format: L10n.Video.maxDuration, Int(maxDuration - duration)))
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            }
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let fraction = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, secs, fraction)
    }
}

// MARK: - Pulsing Animation Modifier

struct PulsingAnimation: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(
                Animation.easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Video Result View

/// 録画結果表示ビュー
struct VideoResultView: View {
    let result: VideoCaptureResultData
    let onDismiss: () -> Void
    let onShare: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text(L10n.Result.title)
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 16) {
                    // サムネイル
                    if let thumbnail = result.thumbnail {
                        ZStack {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .cornerRadius(12)
                            
                            // 再生アイコン
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.9))
                                .shadow(radius: 4)
                        }
                    }
                    
                    // 動画情報
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(label: L10n.Result.proofId, value: String(result.eventId.prefix(8)) + "...")
                            InfoRow(label: L10n.Video.duration, value: String(format: "%.1f秒", result.duration))
                            InfoRow(label: L10n.Video.resolution, value: result.resolution)
                            InfoRow(label: L10n.Result.filesize, value: formatFileSize(result.fileSize))
                            InfoRow(label: L10n.Result.anchorStatus, value: result.anchorStatus)
                        }
                    }
                    .padding(.horizontal)
                    
                    // CPP証明
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                        Text(L10n.Result.thirdPartyVerifiable)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    
                    // 共有ボタン
                    Button(action: onShare) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text(L10n.Result.share)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 10)
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Video Gallery Cell

/// ギャラリー用動画セル
struct VideoGalleryCell: View {
    let event: CPPEvent
    let thumbnail: UIImage?
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // サムネイル
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "video.fill")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                    )
            }
            
            // 動画バッジ
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                    .font(.system(size: 10))
                if let metadata = event.asset.videoMetadata {
                    Text(formatDuration(metadata.duration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.6))
            .cornerRadius(4)
            .padding(6)
        }
        .clipped()
        .cornerRadius(8)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Microphone Permission View

/// マイク許可要求ビュー
struct MicrophonePermissionView: View {
    let onRequestPermission: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Microphone Access Required")
                .font(.headline)
            
            Text("VeriCapture needs microphone access to record video with audio.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: onRequestPermission) {
                Text("Grant Access")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 10)
    }
}

// MARK: - Preview

#Preview("Recording Button") {
    ZStack {
        Color.black
        VStack(spacing: 40) {
            RecordingButton(isRecording: false, isProcessing: false) {}
            RecordingButton(isRecording: true, isProcessing: false) {}
            RecordingButton(isRecording: false, isProcessing: true) {}
        }
    }
}

#Preview("Mode Selector") {
    ZStack {
        Color.black
        CaptureModeSelector(
            mode: .constant(.photo),
            isDisabled: false
        )
    }
}

#Preview("Recording Progress") {
    ZStack {
        Color.black
        RecordingProgressIndicator(
            duration: 15.5,
            progress: 0.26,
            maxDuration: 60
        )
    }
}
