//
//  QRCodeService.swift
//  VeriCapture
//
//  QR Proof Entry Point Generator - Stylish Edition
//  © 2026 VeritasChain株式会社
//

import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// QRコードの配置位置
enum QRPosition: String, CaseIterable, Sendable {
    case bottomRight = "bottom_right"
    case bottomLeft = "bottom_left"
    
    var displayName: String {
        switch self {
        case .bottomRight: return "右下"
        case .bottomLeft: return "左下"
        }
    }
    
    var localizedName: String {
        switch self {
        case .bottomRight: return L10n.QR.positionBottomRight
        case .bottomLeft: return L10n.QR.positionBottomLeft
        }
    }
}

/// QRコードのスタイル
enum QRStyle: String, CaseIterable, Sendable {
    case standard = "standard"      // 標準（白黒四角）
    case rounded = "rounded"        // 角丸ドット
    case branded = "branded"        // ブランド（角丸+グラデ+ロゴ）
    
    var displayName: String {
        switch self {
        case .standard: return L10n.QR.styleStandard
        case .rounded: return L10n.QR.styleRounded
        case .branded: return L10n.QR.styleBranded
        }
    }
}

/// QR Proof Entry Point の設定
struct QROverlayConfig: Sendable {
    var position: QRPosition = .bottomRight
    var style: QRStyle = .branded
    var opacity: CGFloat = 0.9
    var sizeRatio: CGFloat = 0.12 // 画像短辺の12%
    var minSize: CGFloat = 100
    var maxSize: CGFloat = 180
    var marginRatio: CGFloat = 0.04 // 画像端から4%
    
    static let `default` = QROverlayConfig()
}

/// QRコード生成・合成サービス
final class QRCodeService: @unchecked Sendable {
    
    static let shared = QRCodeService()
    
    /// 検証URLのベースドメイン
    private let verifyBaseURL = "https://verify.veritaschain.org/p/"
    
    /// ブランドカラー
    private let brandColorStart = UIColor(red: 59/255, green: 130/255, blue: 246/255, alpha: 1) // Blue
    private let brandColorEnd = UIColor(red: 147/255, green: 51/255, blue: 234/255, alpha: 1)   // Purple
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Proof IDからQRコードを生成（スタイル指定可）
    func generateQRCode(proofId: String, size: CGFloat = 200, style: QRStyle = .branded) -> UIImage? {
        // 完全なProof IDを使用（短縮しない）
        let verifyURL = verifyBaseURL + proofId
        
        switch style {
        case .standard:
            return generateStandardQR(from: verifyURL, size: size)
        case .rounded:
            return generateRoundedQR(from: verifyURL, size: size)
        case .branded:
            return generateBrandedQR(from: verifyURL, size: size)
        }
    }
    
    /// 画像にQRコードを焼き込む
    func embedQRCode(
        originalImage: UIImage,
        proofId: String,
        config: QROverlayConfig = .default
    ) -> UIImage? {
        
        // QRサイズを計算
        let shortSide = min(originalImage.size.width, originalImage.size.height)
        var qrSize = shortSide * config.sizeRatio
        qrSize = max(config.minSize, min(config.maxSize, qrSize))
        
        // QRコード生成
        guard let qrImage = generateQRCode(proofId: proofId, size: qrSize, style: config.style) else {
            return nil
        }
        
        // 合成
        return compositeImages(
            base: originalImage,
            overlay: qrImage,
            position: config.position,
            opacity: config.opacity,
            marginRatio: config.marginRatio
        )
    }
    
    /// 検証URLを取得（完全なProof ID使用）
    func getVerifyURL(proofId: String) -> URL? {
        return URL(string: verifyBaseURL + proofId)
    }
    
    /// 表示用の短縮IDを取得（UI表示用、8-4形式）
    func getDisplayProofId(_ proofId: String) -> String {
        // 完全なIDを返す（短縮しない）
        return proofId
    }
    
    /// 互換性のため残す（非推奨）
    @available(*, deprecated, message: "Use getDisplayProofId instead")
    func getShortProofId(_ proofId: String) -> String {
        return proofId
    }
    
    // MARK: - QR Generation Styles
    
    /// 標準QRコード（白黒四角）+ 中央にアプリアイコン
    private func generateStandardQR(from string: String, size: CGFloat) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        guard let data = string.data(using: .utf8) else { return nil }
        filter.message = data
        filter.correctionLevel = "H" // ロゴ埋め込み用に高い誤り訂正レベル
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scaleX = size / outputImage.extent.size.width
        let scaleY = size / outputImage.extent.size.height
        let scale = min(scaleX, scaleY)
        
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        
        let qrImage = UIImage(cgImage: cgImage)
        
        // 中央にアプリアイコンを埋め込む
        return embedAppIcon(on: qrImage, size: size, style: .standard)
    }
    
    /// 角丸ドットQRコード + 中央にアプリアイコン
    private func generateRoundedQR(from string: String, size: CGFloat) -> UIImage? {
        guard let matrix = generateQRMatrix(from: string) else { return nil }
        
        let moduleCount = matrix.count
        let moduleSize = size / CGFloat(moduleCount + 4) // パディング込み
        let padding = moduleSize * 2
        let totalSize = size
        
        // 中央のロゴ領域を計算（ドットを描画しない領域）
        let logoAreaRatio: CGFloat = 0.25
        let logoAreaSize = size * logoAreaRatio
        let logoAreaMin = (size - logoAreaSize) / 2
        let logoAreaMax = logoAreaMin + logoAreaSize
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: totalSize, height: totalSize), false, 0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // 背景（角丸白）
        let bgRect = CGRect(x: 0, y: 0, width: totalSize, height: totalSize)
        let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: totalSize * 0.08)
        UIColor.white.setFill()
        bgPath.fill()
        
        // ドットを描画
        UIColor.black.setFill()
        
        for row in 0..<moduleCount {
            for col in 0..<moduleCount {
                if matrix[row][col] {
                    let x = padding + CGFloat(col) * moduleSize
                    let y = padding + CGFloat(row) * moduleSize
                    
                    // 中央のロゴ領域内はスキップ
                    let dotCenterX = x + moduleSize / 2
                    let dotCenterY = y + moduleSize / 2
                    if dotCenterX >= logoAreaMin && dotCenterX <= logoAreaMax &&
                       dotCenterY >= logoAreaMin && dotCenterY <= logoAreaMax {
                        continue
                    }
                    
                    // ファインダーパターン（角の大きな四角）は特別扱い
                    if isFinderPattern(row: row, col: col, size: moduleCount) {
                        // ファインダーは四角のまま
                        let rect = CGRect(x: x, y: y, width: moduleSize, height: moduleSize)
                        context.fill(rect)
                    } else {
                        // 通常ドットは角丸
                        let dotSize = moduleSize * 0.85
                        let offset = (moduleSize - dotSize) / 2
                        let dotRect = CGRect(x: x + offset, y: y + offset, width: dotSize, height: dotSize)
                        let dotPath = UIBezierPath(roundedRect: dotRect, cornerRadius: dotSize * 0.4)
                        dotPath.fill()
                    }
                }
            }
        }
        
        guard let qrImage = UIGraphicsGetImageFromCurrentImageContext() else { return nil }
        
        // 中央にアプリアイコンを埋め込む
        return embedAppIcon(on: qrImage, size: size, style: .rounded)
    }
    
    /// ブランドQRコード（角丸+グラデ+アプリアイコン）
    private func generateBrandedQR(from string: String, size: CGFloat) -> UIImage? {
        guard let matrix = generateQRMatrix(from: string) else { return nil }
        
        let moduleCount = matrix.count
        let margin: CGFloat = size * 0.08 // 背景の外側マージン
        let innerSize = size - margin * 2
        let moduleSize = innerSize / CGFloat(moduleCount + 4) // QRコード用のモジュールサイズ
        let qrPadding = moduleSize * 2 // QRパターン周囲のパディング
        
        // 中央のロゴ領域を計算（ドットを描画しない領域）
        let logoAreaRatio: CGFloat = 0.25
        let logoAreaSize = innerSize * logoAreaRatio
        let logoAreaCenter = size / 2
        let logoAreaMin = logoAreaCenter - logoAreaSize / 2
        let logoAreaMax = logoAreaCenter + logoAreaSize / 2
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // 背景（角丸白 + シャドウ）
        let bgRect = CGRect(x: margin, y: margin, width: innerSize, height: innerSize)
        
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 6, color: UIColor.black.withAlphaComponent(0.12).cgColor)
        let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: innerSize * 0.1)
        UIColor.white.setFill()
        bgPath.fill()
        context.restoreGState()
        
        // グラデーション用の色空間
        let colors = [brandColorStart.cgColor, brandColorEnd.cgColor] as CFArray
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) else {
            return nil
        }
        
        // マスク用のパスを作成（背景の中にQRを配置）
        let maskPath = CGMutablePath()
        let qrOrigin = margin + qrPadding // QRパターンの開始位置
        
        for row in 0..<moduleCount {
            for col in 0..<moduleCount {
                if matrix[row][col] {
                    let x = qrOrigin + CGFloat(col) * moduleSize
                    let y = qrOrigin + CGFloat(row) * moduleSize
                    
                    // 中央のロゴ領域内はスキップ
                    let dotCenterX = x + moduleSize / 2
                    let dotCenterY = y + moduleSize / 2
                    if dotCenterX >= logoAreaMin && dotCenterX <= logoAreaMax &&
                       dotCenterY >= logoAreaMin && dotCenterY <= logoAreaMax {
                        continue
                    }
                    
                    if isFinderPattern(row: row, col: col, size: moduleCount) {
                        // ファインダーパターン（角丸四角）
                        let rect = CGRect(x: x, y: y, width: moduleSize, height: moduleSize)
                        let cornerRadius = moduleSize * 0.15
                        maskPath.addRoundedRect(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
                    } else {
                        // 通常ドット（丸）
                        let dotSize = moduleSize * 0.75
                        let center = CGPoint(x: x + moduleSize / 2, y: y + moduleSize / 2)
                        maskPath.addEllipse(in: CGRect(x: center.x - dotSize / 2, y: center.y - dotSize / 2, width: dotSize, height: dotSize))
                    }
                }
            }
        }
        
        // グラデーションで塗る
        context.saveGState()
        context.addPath(maskPath)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: margin, y: margin),
            end: CGPoint(x: size - margin, y: size - margin),
            options: []
        )
        context.restoreGState()
        
        // 中央にアプリアイコンを配置
        let logoSize = innerSize * 0.24
        let logoRect = CGRect(
            x: (size - logoSize) / 2,
            y: (size - logoSize) / 2,
            width: logoSize,
            height: logoSize
        )
        
        // ロゴ背景（白丸）
        let logoBgPath = UIBezierPath(ovalIn: logoRect.insetBy(dx: -logoSize * 0.1, dy: -logoSize * 0.1))
        UIColor.white.setFill()
        logoBgPath.fill()
        
        // アプリアイコンを描画
        if let appIcon = getAppIcon() {
            // 角丸でクリップして描画
            let iconRect = logoRect.insetBy(dx: logoSize * 0.05, dy: logoSize * 0.05)
            let iconPath = UIBezierPath(roundedRect: iconRect, cornerRadius: iconRect.width * 0.2)
            context.saveGState()
            iconPath.addClip()
            appIcon.draw(in: iconRect)
            context.restoreGState()
        } else {
            // フォールバック: 盾マークを描画
            drawShieldIcon(in: logoRect, context: context)
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    // MARK: - Helper Methods
    
    /// アプリアイコンを取得
    private func getAppIcon() -> UIImage? {
        // CFBundleIconsからアプリアイコンを取得
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
           let lastIcon = iconFiles.last {
            return UIImage(named: lastIcon)
        }
        // フォールバック: 直接AppIconを試す
        return UIImage(named: "AppIcon")
    }
    
    /// QRコードにアプリアイコンを埋め込む
    private func embedAppIcon(on qrImage: UIImage, size: CGFloat, style: QRStyle) -> UIImage? {
        guard let appIcon = getAppIcon() else {
            // アイコンが取得できない場合はQRコードをそのまま返す
            return qrImage
        }
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return qrImage }
        
        // QRコードを描画
        qrImage.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
        
        // アイコンサイズ（QRの約25%）
        let iconSizeRatio: CGFloat = style == .standard ? 0.22 : 0.24
        let iconSize = size * iconSizeRatio
        let iconRect = CGRect(
            x: (size - iconSize) / 2,
            y: (size - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        
        // 白い背景（角丸四角）
        let bgPadding = iconSize * 0.12
        let bgRect = iconRect.insetBy(dx: -bgPadding, dy: -bgPadding)
        let bgCornerRadius = bgRect.width * 0.2
        let bgPath = UIBezierPath(roundedRect: bgRect, cornerRadius: bgCornerRadius)
        UIColor.white.setFill()
        bgPath.fill()
        
        // アプリアイコンを角丸でクリップして描画
        let iconCornerRadius = iconRect.width * 0.2 // iOSアイコンの角丸に近づける
        let iconPath = UIBezierPath(roundedRect: iconRect, cornerRadius: iconCornerRadius)
        
        context.saveGState()
        iconPath.addClip()
        appIcon.draw(in: iconRect)
        context.restoreGState()
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    /// QRコードのビットマトリクスを生成
    private func generateQRMatrix(from string: String) -> [[Bool]]? {
        let filter = CIFilter.qrCodeGenerator()
        guard let data = string.data(using: .utf8) else { return nil }
        filter.message = data
        filter.correctionLevel = "H"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        
        guard let pixelData = cgImage.dataProvider?.data,
              let data = CFDataGetBytePtr(pixelData) else { return nil }
        
        var matrix: [[Bool]] = Array(repeating: Array(repeating: false, count: width), count: height)
        
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                // グレースケールまたはRGBの最初のチャンネルで判定
                let pixelValue = data[offset]
                matrix[y][x] = pixelValue == 0 // 黒がtrue
            }
        }
        
        return matrix
    }
    
    /// ファインダーパターン（角の目印）かどうか判定
    private func isFinderPattern(row: Int, col: Int, size: Int) -> Bool {
        let finderSize = 7
        
        // 左上
        if row < finderSize && col < finderSize { return true }
        // 右上
        if row < finderSize && col >= size - finderSize { return true }
        // 左下
        if row >= size - finderSize && col < finderSize { return true }
        
        return false
    }
    
    /// 盾アイコンを描画
    private func drawShieldIcon(in rect: CGRect, context: CGContext) {
        let insetRect = rect.insetBy(dx: rect.width * 0.15, dy: rect.height * 0.15)
        
        // グラデーション
        let colors = [brandColorStart.cgColor, brandColorEnd.cgColor] as CFArray
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) else { return }
        
        // 盾の形状を描く
        let path = UIBezierPath()
        let w = insetRect.width
        let h = insetRect.height
        let x = insetRect.origin.x
        let y = insetRect.origin.y
        
        // シンプルな盾形状
        path.move(to: CGPoint(x: x + w * 0.5, y: y))
        path.addLine(to: CGPoint(x: x + w, y: y + h * 0.15))
        path.addLine(to: CGPoint(x: x + w, y: y + h * 0.5))
        path.addQuadCurve(to: CGPoint(x: x + w * 0.5, y: y + h), controlPoint: CGPoint(x: x + w, y: y + h * 0.85))
        path.addQuadCurve(to: CGPoint(x: x, y: y + h * 0.5), controlPoint: CGPoint(x: x, y: y + h * 0.85))
        path.addLine(to: CGPoint(x: x, y: y + h * 0.15))
        path.close()
        
        context.saveGState()
        context.addPath(path.cgPath)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: x, y: y),
            end: CGPoint(x: x + w, y: y + h),
            options: []
        )
        context.restoreGState()
        
        // チェックマーク
        let checkPath = UIBezierPath()
        let cx = x + w * 0.5
        let cy = y + h * 0.5
        let checkSize = w * 0.35
        
        checkPath.move(to: CGPoint(x: cx - checkSize * 0.5, y: cy))
        checkPath.addLine(to: CGPoint(x: cx - checkSize * 0.1, y: cy + checkSize * 0.4))
        checkPath.addLine(to: CGPoint(x: cx + checkSize * 0.5, y: cy - checkSize * 0.3))
        
        checkPath.lineWidth = w * 0.08
        checkPath.lineCapStyle = .round
        checkPath.lineJoinStyle = .round
        UIColor.white.setStroke()
        checkPath.stroke()
    }
    
    /// 画像を合成
    private func compositeImages(
        base: UIImage,
        overlay: UIImage,
        position: QRPosition,
        opacity: CGFloat,
        marginRatio: CGFloat
    ) -> UIImage? {
        
        let baseSize = base.size
        let overlaySize = overlay.size
        let margin = min(baseSize.width, baseSize.height) * marginRatio
        
        // QRの配置位置を計算
        let overlayOrigin: CGPoint
        switch position {
        case .bottomRight:
            overlayOrigin = CGPoint(
                x: baseSize.width - overlaySize.width - margin,
                y: baseSize.height - overlaySize.height - margin
            )
        case .bottomLeft:
            overlayOrigin = CGPoint(
                x: margin,
                y: baseSize.height - overlaySize.height - margin
            )
        }
        
        // 合成
        UIGraphicsBeginImageContextWithOptions(baseSize, false, base.scale)
        defer { UIGraphicsEndImageContext() }
        
        base.draw(at: .zero)
        
        // QRコードを描画
        overlay.draw(
            in: CGRect(origin: overlayOrigin, size: overlaySize),
            blendMode: .normal,
            alpha: opacity
        )
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

// MARK: - Export Event Data

/// QR焼き込みエクスポート時の記録用データ
struct QRExportRecord: Codable, Sendable {
    let sourceEventId: String
    let exportedAt: String
    let qrPosition: String
    let qrOpacity: Double
    let verifyURL: String
    let exportedAssetHash: String
    let exportedAssetSize: Int
    
    enum CodingKeys: String, CodingKey {
        case sourceEventId = "SourceEventID"
        case exportedAt = "ExportedAt"
        case qrPosition = "QRPosition"
        case qrOpacity = "QROpacity"
        case verifyURL = "VerifyURL"
        case exportedAssetHash = "ExportedAssetHash"
        case exportedAssetSize = "ExportedAssetSize"
    }
}
