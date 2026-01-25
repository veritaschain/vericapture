//
//  ShareOptionsView.swift
//  VeriCapture
//
//  Share Options - Simplified (v42)
//  画像: 3オプション / 動画: 2オプション
//  © 2026 VeritasChain Standards Organization
//

import SwiftUI

/// 共有方法の選択肢
enum ShareOption: Identifiable {
    case mediaOnly      // 画像/動画のみ（証跡なし）
    case withQR         // 検証QR付き（画像のみ対応）
    case exportZip      // 検証用エクスポート（ZIP）
    case c2paExport     // C2PA互換エクスポート
    
    // Legacy aliases (互換性維持用)
    case imageOnly
    case videoOnly
    case withProof
    case internalProof
    case rawDataExport
    
    var id: String {
        switch self {
        case .mediaOnly, .imageOnly, .videoOnly: return "media"
        case .withQR: return "qr"
        case .exportZip, .internalProof, .rawDataExport, .withProof: return "export"
        case .c2paExport: return "c2pa"
        }
    }
}

/// 共有オプション選択シート
/// - 画像: QR付き / 画像のみ / エクスポート（3オプション）
/// - 動画: 動画のみ / エクスポート（2オプション）
struct ShareOptionsSheet: View {
    let image: UIImage?
    let videoURL: URL?
    let proofId: String
    let hasLocation: Bool
    let onSelect: (ShareOption) -> Void
    let onInternalExport: (Bool, Bool) -> Void  // (includeLocation, includeC2PA)
    let onRawDataExport: (() -> Void)?
    let onC2PAExport: (() -> Void)?  // 互換性のため残す
    
    var isVideo: Bool { videoURL != nil }
    
    @Environment(\.dismiss) var dismiss
    @State private var showAuthError = false
    @State private var authErrorMessage = ""
    @State private var includeLocation = false
    @State private var includeC2PA = false
    @State private var showC2PAInfo = false
    
    init(
        image: UIImage?,
        videoURL: URL?,
        proofId: String,
        hasLocation: Bool,
        onSelect: @escaping (ShareOption) -> Void,
        onInternalExport: @escaping (Bool, Bool) -> Void,
        onRawDataExport: (() -> Void)? = nil,
        onC2PAExport: (() -> Void)? = nil
    ) {
        self.image = image
        self.videoURL = videoURL
        self.proofId = proofId
        self.hasLocation = hasLocation
        self.onSelect = onSelect
        self.onInternalExport = onInternalExport
        self.onRawDataExport = onRawDataExport
        self.onC2PAExport = onC2PAExport
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    
                    // ===== オプション1: 検証QR付き（画像のみ・推奨） =====
                    if !isVideo {
                        OptionCard(
                            icon: "qrcode",
                            iconColor: .green,
                            title: L10n.Share.withQR,
                            subtitle: L10n.Share.withQRDesc,
                            badge: L10n.Share.recommendedBadge,
                            badgeColor: .green,
                            isHighlighted: true
                        ) {
                            onSelect(.withQR)
                        }
                    }
                    
                    // ===== オプション2: 画像/動画のみ =====
                    MediaOnlySection(isVideo: isVideo) {
                        onSelect(isVideo ? .videoOnly : .imageOnly)
                    }
                    
                    // ===== オプション3: 検証用エクスポート（ZIP）+ C2PAオプション =====
                    ExportSection(
                        hasLocation: hasLocation,
                        includeLocation: $includeLocation,
                        includeC2PA: $includeC2PA,
                        showC2PAInfo: $showC2PAInfo
                    ) {
                        authenticateAndExport()
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    // ===== 説明 =====
                    PrivacyExplanation()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .navigationTitle(L10n.Share.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Share.cancel) { dismiss() }
                }
            }
            .alert(L10n.Export.authErrorTitle, isPresented: $showAuthError) {
                Button(L10n.Common.ok) {}
            } message: {
                Text(authErrorMessage)
            }
            .sheet(isPresented: $showC2PAInfo) {
                C2PAInfoSheet()
            }
        }
    }
    
    private func authenticateAndExport() {
        Task {
            let result = await BiometricAuthService.shared.authenticate(for: .exportFullProof)
            
            switch result {
            case .success:
                onInternalExport(includeLocation, includeC2PA)
            case .cancelled:
                break
            case .failed(let error):
                authErrorMessage = L10n.Export.authFailedMessage(error)
                showAuthError = true
            case .notAvailable:
                onInternalExport(includeLocation, includeC2PA)
            }
        }
    }
}

// MARK: - Components

/// オプションカード（共通コンポーネント）
private struct OptionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var badge: String? = nil
    var badgeColor: Color = .blue
    var isHighlighted: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // アイコン
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(iconColor)
                }
                
                // テキスト
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if let badge = badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(badgeColor)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isHighlighted ? iconColor.opacity(0.5) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// 画像/動画のみセクション（警告付き）
private struct MediaOnlySection: View {
    let isVideo: Bool
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 16) {
                    // アイコン
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: isVideo ? "video" : "photo")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isVideo ? L10n.Share.videoOnly : L10n.Share.imageOnly)
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(isVideo ? L10n.Share.videoOnlyDesc : L10n.Share.imageOnlyDesc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .buttonStyle(PlainButtonStyle())
            
            // 警告メッセージ
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                
                Text(L10n.Share.proofLostWarning)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color(.systemGray6))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

/// 検証用エクスポートセクション
private struct ExportSection: View {
    let hasLocation: Bool
    @Binding var includeLocation: Bool
    @Binding var includeC2PA: Bool
    @Binding var showC2PAInfo: Bool
    let action: () -> Void
    
    var body: some View {
        // 検証用エクスポート + オプションを1つのカードに結合
        VStack(spacing: 0) {
            // エクスポートボタン部分
            Button(action: action) {
                HStack(spacing: 14) {
                    // アイコン
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "doc.zipper")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    
                    // テキスト
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(L10n.Share.exportZip)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            // バッジ
                            Text(L10n.Share.verificationBadge)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color.blue)
                                )
                        }
                        
                        Text(L10n.Share.exportZipDesc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(PlainButtonStyle())
            
            // 区切り線
            Divider()
                .padding(.leading, 16)
            
            // 位置情報トグル
            HStack(spacing: 12) {
                Toggle(isOn: hasLocation ? $includeLocation : .constant(false)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Share.includeLocation)
                            .font(.subheadline)
                            .foregroundColor(hasLocation ? .primary : .secondary)
                        Text(hasLocation ? L10n.Share.includeLocationNote : L10n.Share.locationNoData)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .orange))
                .disabled(!hasLocation)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            // 区切り線
            Divider()
                .padding(.leading, 16)
            
            // C2PAマニフェストトグル
            HStack(spacing: 12) {
                Toggle(isOn: $includeC2PA) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(L10n.Share.includeC2PA)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            
                            // C2PAバッジ
                            Text("C2PA")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.purple)
                                .cornerRadius(4)
                            
                            // ⓘボタン
                            Button {
                                showC2PAInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.purple)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Text(L10n.Share.includeC2PADesc)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .purple))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1.5)
        )
    }
}

/// プライバシー説明セクション（ボタンではない情報表示）
private struct PrivacyExplanation: View {
    var body: some View {
        VStack(spacing: 8) {
            // プライバシー保護設計（中央寄せ・シンプル表示）
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
                
                Text(L10n.Share.privacyDesignTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - QR Preview Sheet

/// QR付き画像プレビューシート
struct QRPreviewSheet: View {
    let originalImage: UIImage
    let proofId: String
    let onShare: (UIImage) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var qrImage: UIImage?
    @State private var isGenerating = true
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let qrImage = qrImage {
                    // プレビュー
                    GeometryReader { geometry in
                        Image(uiImage: qrImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: geometry.size.width - 40)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // 説明
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "qrcode")
                                .foregroundColor(.green)
                            Text(L10n.Share.qrAddedExplanation)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(L10n.Share.qrScanInstruction)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                    
                    // 共有ボタン
                    Button {
                        onShare(qrImage)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text(L10n.Share.shareWithQR)
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                } else if isGenerating {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text(L10n.Share.generatingQR)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top)
                    Spacer()
                }
            }
            .padding()
            .navigationTitle(L10n.Share.qrPreviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.Share.cancel) { dismiss() }
                }
            }
            .onAppear {
                generateQRImage()
            }
        }
    }
    
    @MainActor
    private func generateQRImage() {
        // 値をキャプチャ
        let image = originalImage
        let id = proofId
        
        Task {
            // embedQRCodeは同期関数、バックグラウンドで実行
            let result = QRCodeService.shared.embedQRCode(
                originalImage: image,
                proofId: id
            )
            
            // UI更新
            qrImage = result
            isGenerating = false
        }
    }
}

// MARK: - Legacy Components (互換性維持)

/// ShareOptionCard (Legacy alias)
struct ShareOptionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var badge: String? = nil
    var badgeColor: Color = .blue
    var isHighlighted: Bool = false
    let action: () -> Void
    
    var body: some View {
        OptionCard(
            icon: icon,
            iconColor: iconColor,
            title: title,
            subtitle: subtitle,
            badge: badge,
            badgeColor: badgeColor,
            isHighlighted: isHighlighted,
            action: action
        )
    }
}

/// MediaOnlyCard (Legacy alias)
struct MediaOnlyCard: View {
    let isVideo: Bool
    let action: () -> Void
    
    var body: some View {
        MediaOnlySection(isVideo: isVideo, action: action)
    }
}

/// LocationToggle (Legacy alias)
struct LocationToggle: View {
    let hasLocation: Bool
    @Binding var includeLocation: Bool
    
    var body: some View {
        EmptyView()
    }
}

/// ExplanationSection (Legacy alias)
struct ExplanationSection: View {
    var body: some View {
        PrivacyExplanation()
    }
}
