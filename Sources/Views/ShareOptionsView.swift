//
//  ShareOptionsView.swift
//  VeriCapture
//
//  Share Options with QR Proof Entry Point
//  © 2026 VeritasChain Standards Organization
//

import SwiftUI

/// 共有方法の選択肢
enum ShareOption: Identifiable {
    case imageOnly
    case withProof
    case withQR
    case internalProof  // C案: 内部用完全証跡
    case rawDataExport  // 生データエクスポート（検証用）
    
    var id: String {
        switch self {
        case .imageOnly: return "image"
        case .withProof: return "proof"
        case .withQR: return "qr"
        case .internalProof: return "internal"
        case .rawDataExport: return "raw"
        }
    }
    
    var title: String {
        switch self {
        case .imageOnly: return L10n.Share.imageOnly
        case .withProof: return L10n.Share.withProof
        case .withQR: return L10n.Share.withQR
        case .internalProof: return L10n.Export.forensicTitle
        case .rawDataExport: return L10n.Share.rawDataExport
        }
    }
    
    var subtitle: String {
        switch self {
        case .imageOnly: return L10n.Share.imageOnlyDesc
        case .withProof: return L10n.Share.withProofDesc
        case .withQR: return L10n.Share.withQRDesc
        case .internalProof: return L10n.Export.forensicSubtitle
        case .rawDataExport: return L10n.Share.rawDataExportDesc
        }
    }
    
    var icon: String {
        switch self {
        case .imageOnly: return "photo"
        case .withProof: return "doc.badge.plus"
        case .withQR: return "qrcode"
        case .internalProof: return "doc.badge.gearshape"
        case .rawDataExport: return "doc.zipper"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .imageOnly: return .blue
        case .withProof: return .purple
        case .withQR: return .green
        case .internalProof: return .orange
        case .rawDataExport: return .cyan
        }
    }
}

/// 共有オプション選択シート
struct ShareOptionsSheet: View {
    let image: UIImage
    let proofId: String
    let hasLocation: Bool  // この証跡に位置情報があるか
    let onSelect: (ShareOption) -> Void
    let onInternalExport: (Bool) -> Void  // 法務用エクスポート（includeLocation）
    let onRawDataExport: (() -> Void)?    // 生データエクスポート
    
    @Environment(\.dismiss) var dismiss
    @State private var showAuthError = false
    @State private var authErrorMessage = ""
    @State private var includeLocation = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    // 推奨：検証QR付き（最上位に配置）
                    ShareOptionButton(option: .withQR, action: {
                        onSelect(.withQR)
                    }, isRecommended: true)
                    
                    ShareOptionButton(option: .withProof) {
                        onSelect(.withProof)
                    }
                    
                    // 生データエクスポート（検証用）
                    if let onRawExport = onRawDataExport {
                        RawDataExportCard(action: onRawExport)
                    }
                    
                    // 非推奨：画像のみ（警告を統合したカード）
                    ImageOnlyWarningCard {
                        onSelect(.imageOnly)
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    // C案: 完全証跡エクスポート（内部用）- 認証必須
                    VStack(spacing: 8) {
                        ShareOptionButton(option: .internalProof) {
                            authenticateAndExport()
                        }
                        
                        // 位置情報オプション
                        if hasLocation {
                            // 位置情報あり：トグル有効
                            HStack(spacing: 12) {
                                Toggle(isOn: $includeLocation) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L10n.Share.includeLocation)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Text(L10n.Share.includeLocationNote)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .toggleStyle(SwitchToggleStyle(tint: .orange))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.orange.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                            )
                        } else {
                            // 位置情報なし：グレーアウト
                            HStack(spacing: 12) {
                                Toggle(isOn: .constant(false)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L10n.Share.includeLocation)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Text(L10n.Share.locationNoData)
                                            .font(.caption2)
                                            .foregroundColor(.secondary.opacity(0.7))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .toggleStyle(SwitchToggleStyle(tint: .gray))
                                .disabled(true)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.gray.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    
                    // 内部用の警告（アンバー色・用途限定）
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.person.crop")
                            .foregroundColor(.orange)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.Share.internalAboutTitle)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text(L10n.Share.internalAboutDesc)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    // プライバシー保護設計の説明（緑色）
                    HStack(spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.Share.privacyDesignTitle)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text(L10n.Share.privacyDesignDesc)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
                }
                .padding(.horizontal)
                .padding(.top, 8)
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
        }
    }
    
    private func authenticateAndExport() {
        Task {
            let result = await BiometricAuthService.shared.authenticate(for: .exportFullProof)
            
            switch result {
            case .success:
                onInternalExport(includeLocation)
            case .cancelled:
                // ユーザーがキャンセル - 何もしない
                break
            case .failed(let error):
                authErrorMessage = L10n.Export.authFailedMessage(error)
                showAuthError = true
            case .notAvailable:
                // 認証が利用不可の場合は直接エクスポート（セキュリティ設定されていないデバイス）
                onInternalExport(includeLocation)
            }
        }
    }
}

/// 共有オプションボタン
struct ShareOptionButton: View {
    let option: ShareOption
    let action: () -> Void
    var isDeprecated: Bool = false
    var isRecommended: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // アイコン
                ZStack {
                    Circle()
                        .fill(isDeprecated ? Color.gray.opacity(0.15) : option.iconColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: option.icon)
                        .font(.title2)
                        .foregroundColor(isDeprecated ? .gray : option.iconColor)
                    
                    // 警告マーク（非推奨の場合）
                    if isDeprecated {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .offset(x: 18, y: 18)
                    }
                }
                
                // テキスト
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(option.title)
                            .font(.headline)
                            .foregroundColor(isDeprecated ? .secondary : .primary)
                        
                        // 推奨バッジ
                        if isRecommended {
                            Text(L10n.Share.recommendedBadge)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                    }
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(isRecommended ? Color.green.opacity(0.08) : Color(.systemGray6))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isRecommended ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// 画像のみ共有 + 警告を統合したカード
struct ImageOnlyWarningCard: View {
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 画像のみ共有ボタン部分
            Button(action: action) {
                HStack(spacing: 16) {
                    // アイコン
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    
                    // テキスト
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Share.imageOnly)
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(L10n.Share.imageOnlyDesc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(PlainButtonStyle())
            
            // 警告セクション（シンプルなテキストスタイル）
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.Share.ecosystemWarningTitle)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                
                Text(L10n.Share.ecosystemWarningDesc)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(L10n.Share.ecosystemRecommendation)
                    .font(.caption2)
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.05))
        }
        .background(Color(.systemGray6))
        .cornerRadius(14)
    }
}

/// QR付き共有プレビューシート
struct QRPreviewSheet: View {
    let originalImage: UIImage
    let proofId: String
    let onShare: (UIImage) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var qrPosition: QRPosition = .bottomRight
    @State private var qrStyle: QRStyle = .standard  // デフォルトをスタンダードに
    @State private var qrOpacity: Double = 0.9
    @State private var previewImage: UIImage?
    @State private var isGeneratingFull = false
    
    private let qrService = QRCodeService.shared
    
    // プレビュー用に縮小した画像（高速化のため）
    private var thumbnailImage: UIImage {
        let maxDimension: CGFloat = 800 // プレビュー用の最大サイズ
        let scale = min(maxDimension / originalImage.size.width, maxDimension / originalImage.size.height, 1.0)
        if scale >= 1.0 { return originalImage }
        
        let newSize = CGSize(width: originalImage.size.width * scale, height: originalImage.size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        originalImage.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? originalImage
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // プレビュー
                    if let preview = previewImage {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                    } else {
                        ProgressView()
                            .frame(height: 300)
                    }
                    
                    // 設定
                    VStack(spacing: 16) {
                        // スタイル選択
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.QR.styleTitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 12) {
                                ForEach(QRStyle.allCases, id: \.self) { style in
                                    QRStyleButton(
                                        style: style,
                                        isSelected: qrStyle == style,
                                        proofId: proofId
                                    ) {
                                        qrStyle = style
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        // 位置選択（左下、右下の順で表示）
                        HStack {
                            Text(L10n.QR.position)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker(L10n.QR.position, selection: $qrPosition) {
                                Text(L10n.QR.positionBottomLeft).tag(QRPosition.bottomLeft)
                                Text(L10n.QR.positionBottomRight).tag(QRPosition.bottomRight)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 150)
                        }
                        
                        // 透明度（brandedスタイル以外で表示）
                        if qrStyle != .branded {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(L10n.QR.opacity)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(qrOpacity * 100))%")
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }
                                Slider(value: $qrOpacity, in: 0.5...1.0)
                                    .tint(.blue)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    
                    // 説明文（思想厳守）
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "qrcode")
                                .foregroundColor(.green)
                            Text(L10n.QR.verifyNote)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        Text(L10n.QR.verifyDesc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(12)
                    
                    // 共有ボタン
                    Button {
                        shareWithFullResolution()
                    } label: {
                        HStack {
                            if isGeneratingFull {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Text(L10n.QR.shareThis)
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [.green, .blue], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(14)
                    }
                    .disabled(previewImage == nil || isGeneratingFull)
                }
                .padding()
            }
            .navigationTitle(L10n.QR.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Share.cancel) { dismiss() }
                }
            }
            .overlay {
                // 処理中のローディングオーバーレイ
                if isGeneratingFull {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            Text(L10n.QR.preparingImage)
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            ShareProgressBar()
                                .frame(width: 200, height: 6)
                        }
                        .padding(32)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                    }
                }
            }
            .onAppear {
                generatePreview()
            }
            .onChange(of: qrPosition) { _, _ in
                generatePreview()
            }
            .onChange(of: qrStyle) { _, _ in
                generatePreview()
            }
            .onChange(of: qrOpacity) { _, _ in
                generatePreview()
            }
        }
    }
    
    /// プレビュー生成（縮小画像使用で高速化）
    private func generatePreview() {
        let config = QROverlayConfig(
            position: qrPosition,
            style: qrStyle,
            opacity: qrStyle == .branded ? 1.0 : qrOpacity
        )
        
        // 縮小画像でプレビュー生成（高速）
        let result = qrService.embedQRCode(
            originalImage: thumbnailImage,
            proofId: proofId,
            config: config
        )
        previewImage = result
    }
    
    /// フル解像度で生成して共有
    private func shareWithFullResolution() {
        isGeneratingFull = true
        
        // バックグラウンドスレッドで画像生成（UIをブロックしない）
        DispatchQueue.global(qos: .userInitiated).async {
            let config = QROverlayConfig(
                position: qrPosition,
                style: qrStyle,
                opacity: qrStyle == .branded ? 1.0 : qrOpacity
            )
            
            let fullImage = qrService.embedQRCode(
                originalImage: originalImage,
                proofId: proofId,
                config: config
            )
            
            // メインスレッドでUI更新と共有
            DispatchQueue.main.async {
                isGeneratingFull = false
                if let image = fullImage {
                    onShare(image)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - QR Style Button

struct QRStyleButton: View {
    let style: QRStyle
    let isSelected: Bool
    let proofId: String
    let action: () -> Void
    
    @State private var qrImage: UIImage?
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // QRプレビュー
                if let image = qrImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .overlay(ProgressView().scaleEffect(0.7))
                }
                
                Text(style.displayName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            // 表示サイズに合わせて80pxで生成（高速化）
            let qrService = QRCodeService.shared
            qrImage = qrService.generateQRCode(proofId: proofId, size: 80, style: style)
        }
    }
}

// MARK: - Raw Data Export Card (検証用生データエクスポート)

struct RawDataExportCard: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    // アイコン
                    ZStack {
                        Circle()
                            .fill(Color.cyan.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "doc.zipper")
                            .font(.system(size: 20))
                            .foregroundColor(.cyan)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(L10n.Share.rawDataExport)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            // 検証対応バッジ
                            Text(L10n.Share.forVerification)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.cyan.opacity(0.15))
                                )
                        }
                        
                        Text(L10n.Share.rawDataExportDesc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                
                // 説明テキスト
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text(L10n.Share.rawDataExportNote)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 56)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Loading Progress Bar for Share

/// 横棒アニメーションのプログレスバー（ShareOptionsView用）
private struct ShareProgressBar: View {
    @State private var isAnimating = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.3))
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * 0.35)
                    .offset(x: isAnimating ? geometry.size.width * 0.65 : 0)
            }
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.0)
                .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
    }
}

#Preview {
    ShareOptionsSheet(
        image: UIImage(systemName: "photo")!,
        proofId: "019abc12-3def-7890-abcd-ef1234567890",
        hasLocation: true,
        onSelect: { _ in },
        onInternalExport: { _ in },
        onRawDataExport: { }
    )
}
