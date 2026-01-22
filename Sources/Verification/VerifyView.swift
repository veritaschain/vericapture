//
//  VerifyView.swift
//  VeriCapture
//
//  Verification Tab View - Integrated VeriCheck
//  © 2026 VeritasChain Standards Organization
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Verify Tab View

struct VerifyView: View {
    @StateObject private var verificationService = ProofVerificationService()
    @StateObject private var history = VerificationHistory()
    
    @State private var showQRScanner = false
    @State private var showFilePicker = false
    @State private var showJSONInput = false
    @State private var showImageVerification = false  // 画像検証モード
    @State private var currentResult: VerificationResult?
    @State private var isVerifying = false
    @State private var jsonInput = ""
    @State private var scannedQRCode: String? // スキャンしたQRコードを保持
    @State private var scannedQRImage: UIImage? // スキャン時のキャプチャ画像を保持
    
    // 画像検証用State
    @State private var pendingProofJSON: String? = nil
    @State private var selectedImageData: Data? = nil
    @State private var selectedImagePreview: UIImage? = nil
    @State private var pendingFileData: Data? = nil  // ファイルピッカーからのデータを保持
    @State private var pendingJSONInput: String? = nil  // JSON入力からのデータを保持
    @State private var pendingImageVerification: (json: String, imageData: Data?)? = nil  // 画像検証からのデータを保持
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Hero Section
                    heroSection
                    
                    // Action Buttons
                    actionButtonsSection
                    
                    // Recent Verifications
                    if !history.results.isEmpty {
                        recentVerificationsSection
                    }
                    
                    // Info Section
                    infoSection
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemGroupedBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationTitle("")
            .sheet(isPresented: $showQRScanner, onDismiss: {
                // シートが閉じた後にQRコードを処理
                if let code = scannedQRCode {
                    let image = scannedQRImage
                    scannedQRCode = nil
                    scannedQRImage = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        handleQRCode(code, capturedImage: image)
                    }
                }
            }) {
                VerifyQRScannerView(onCodeScanned: { code, image in
                    scannedQRCode = code
                    scannedQRImage = image
                }, isPresented: $showQRScanner)
            }
            .sheet(isPresented: $showFilePicker, onDismiss: {
                // シートが閉じた後にデータを処理
                if let data = pendingFileData {
                    pendingFileData = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        handleFileSelection(data)
                    }
                }
            }) {
                VerifyDocumentPicker(onPick: { data in
                    // データを保存してシートを閉じる
                    pendingFileData = data
                    showFilePicker = false
                })
            }
            .sheet(isPresented: $showJSONInput, onDismiss: {
                // シートが閉じた後にデータを処理
                if let json = pendingJSONInput {
                    pendingJSONInput = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        pendingProofJSON = json
                        // State更新が反映されてから画像選択モードへ遷移
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            showImageVerification = true
                        }
                    }
                }
            }) {
                VerifyJSONInputView(
                    jsonText: $jsonInput,
                    onVerify: { json in
                        // JSONを保存してシートを閉じる
                        pendingJSONInput = json
                        showJSONInput = false
                    }
                )
            }
            .sheet(isPresented: $showImageVerification, onDismiss: {
                // シートが閉じた後に検証を実行
                if let pending = pendingImageVerification {
                    pendingImageVerification = nil
                    // jsonが空の場合はpendingProofJSONを使用
                    let jsonToVerify = pending.json.isEmpty ? (pendingProofJSON ?? "") : pending.json
                    guard !jsonToVerify.isEmpty else {
                        print("[VerifyView] ERROR: No JSON to verify")
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        Task {
                            await verifyWithImage(json: jsonToVerify, imageData: pending.imageData)
                        }
                    }
                }
            }) {
                ImageVerificationView(
                    proofJSON: pendingProofJSON ?? "",
                    onVerify: { json, imageData in
                        // データを保存してシートを閉じる（検証はonDismissで実行）
                        pendingImageVerification = (json: json, imageData: imageData)
                        showImageVerification = false
                    },
                    onSkip: {
                        // 画像なしで検証（スキップもonDismissパターンに）
                        let json = pendingProofJSON ?? ""
                        pendingImageVerification = (json: json, imageData: nil)
                        showImageVerification = false
                    }
                )
            }
            .sheet(item: $currentResult) { result in
                VerifyResultView(result: result)
            }
            .overlay {
                if isVerifying {
                    verifyingOverlay
                }
            }
        }
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.3), .green.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            VStack(spacing: 4) {
                Text(L10n.Verify.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text(L10n.Verify.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text(L10n.Verify.slogan)
                .font(.caption)
                .italic()
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.top, 4)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            // QR Scan Button (Primary)
            Button {
                showQRScanner = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 24, weight: .medium))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Verify.scanQR)
                            .font(.headline)
                        Text(L10n.Verify.scanQRDesc)
                            .font(.caption)
                            .opacity(0.8)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .opacity(0.5)
                }
                .padding()
                .foregroundColor(.white)
                .background(
                    LinearGradient(
                        colors: [.green, .green.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
            }
            
            // 1行ヘルプ
            Text(L10n.Verify.instructionText)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.bottom, 4)
            
            HStack(spacing: 12) {
                // File Import Button
                Button {
                    showFilePicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 20))
                        Text(L10n.Verify.selectFile)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.primary)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
                
                // JSON Input Button
                Button {
                    showJSONInput = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 20))
                        Text(L10n.Verify.inputJSON)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.primary)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
            }
        }
    }
    
    // MARK: - Recent Verifications Section
    
    private var recentVerificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.Verify.recentVerifications)
                    .font(.headline)
                
                Spacer()
                
                Button(L10n.Verify.clear) {
                    withAnimation {
                        history.clear()
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            ForEach(history.results.prefix(5)) { result in
                Button {
                    currentResult = result
                } label: {
                    historyRow(result)
                }
            }
        }
    }
    
    private func historyRow(_ result: VerificationResult) -> some View {
        HStack(spacing: 12) {
            // ステータスアイコン
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: result.overallStatus.icon)
                    .font(.system(size: 24))
                    .foregroundColor(result.overallStatus.color)
                
                // Attestedバッジ（小さいアイコン）
                if result.isAttestedCapture {
                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.purple)
                        .background(
                            Circle()
                                .fill(Color(.systemBackground))
                                .frame(width: 14, height: 14)
                        )
                        .offset(x: 4, y: 4)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // assetNameがない場合はeventIDの短縮形を表示
                    Text(result.assetName ?? result.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    // Attestedテキストバッジ
                    if result.isAttestedCapture {
                        Text(L10n.Verify.attestedBadge)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                
                Text(formatDate(result.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(result.overallStatus.displayName)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(result.overallStatus.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(result.overallStatus.color.opacity(0.15))
                .cornerRadius(6)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Info Section
    
    private var infoSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.Verify.checkItems)
                    .font(.headline)
                
                VStack(spacing: 8) {
                    featureRow(icon: "number.circle.fill", text: L10n.Verify.checkEventHash)
                    featureRow(icon: "signature", text: L10n.Verify.checkSignature)
                    featureRow(icon: "photo.fill", text: L10n.Verify.checkImageHash)
                    featureRow(icon: "clock.badge.checkmark.fill", text: L10n.Verify.checkTimestamp)
                    featureRow(icon: "point.3.filled.connected.trianglepath.dotted", text: L10n.Verify.checkMerkle)
                }
            }
            
            Divider()
            
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption)
                    Text("veritaschain.org")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                
                Text("© 2026 VeritasChain Standards Organization")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.green)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
    
    // MARK: - Verifying Overlay
    
    private var verifyingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                
                Text(verificationService.currentStep)
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                ProgressView(value: verificationService.progress)
                    .frame(width: 200)
                    .tint(.green)
            }
            .padding(30)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
    }
    
    // MARK: - Actions
    
    private func handleQRCode(_ code: String, capturedImage: UIImage?) {
        if code.contains("verify.veritaschain.org") {
            // VeriCapture QRコードを検出
            if let shortId = extractProofId(from: code) {
                // まずローカルを検索
                Task { @MainActor in
                    if let proofJSON = findLocalProof(shortId: shortId) {
                        // ローカルに見つかった場合は即検証
                        await verifyJSON(proofJSON)
                    } else {
                        // ローカルにない場合はガイダンスを表示
                        showProofRequestAlert(shortId: shortId, capturedImage: capturedImage)
                    }
                }
            } else {
                showInvalidQRAlert(url: code)
            }
        } else if code.hasPrefix("{") && code.contains("ProofVersion") {
            // JSONが直接エンコードされている場合（将来の拡張用）
            Task {
                await verifyJSON(code)
            }
        } else {
            // 不明なQRコード
            showUnknownQRAlert(code: code)
        }
    }
    
    private func extractProofId(from url: String) -> String? {
        if let range = url.range(of: "/p/") {
            let shortId = String(url[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "/").first ?? ""
            if !shortId.isEmpty {
                return shortId
            }
        }
        return nil
    }
    
    @MainActor
    private func findLocalProof(shortId: String) -> String? {
        guard let chainId = try? StorageService.shared.getOrCreateChainId(),
              let events = try? StorageService.shared.getAllEvents(chainId: chainId) else {
            return nil
        }
        
        for event in events {
            if event.eventId.hasPrefix(shortId) {
                let anchor = try? StorageService.shared.getAnchor(forEventId: event.eventId)
                let eventBuilder = CPPEventBuilder()
                let proof = eventBuilder.generateProofJSON(event: event, anchor: anchor)
                
                if let proofData = try? JSONEncoder().encode(proof),
                   let proofJSON = String(data: proofData, encoding: .utf8) {
                    return proofJSON
                }
            }
        }
        return nil
    }
    
    private func showProofRequestAlert(shortId: String, capturedImage: UIImage?) {
        let alert = UIAlertController(
            title: L10n.Verify.proofNeededTitle,
            message: L10n.Verify.proofNeededMessage,
            preferredStyle: .alert
        )
        
        // Primary: データを依頼する
        alert.addAction(UIAlertAction(title: L10n.Verify.requestData, style: .default) { _ in
            self.shareProofRequest(shortId: shortId, capturedImage: capturedImage)
        })
        
        // Secondary: ファイルを選択
        alert.addAction(UIAlertAction(title: L10n.Verify.selectFile, style: .default) { _ in
            DispatchQueue.main.async {
                self.showFilePicker = true
            }
        })
        
        // Tertiary: 閉じる
        alert.addAction(UIAlertAction(title: L10n.Result.close, style: .cancel))
        presentAlert(alert)
    }
    
    /// 証跡データを依頼するテキストを共有（キャプチャ画像も添付）
    private func shareProofRequest(shortId: String, capturedImage: UIImage?) {
        let requestText = """
\(L10n.Verify.requestProofLine1)
\(L10n.Verify.requestProofLine2)

Proof ID: \(shortId)

📱 \(AppConstants.appName) - \(AppConstants.tagline)

\(L10n.Verify.requestProofFooter)
\(L10n.Verify.requestProofDisclaimer)
"""
        
        // アラートが完全に閉じるまで待機してから共有シートを表示
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                var topVC = rootVC
                while let presented = topVC.presentedViewController {
                    topVC = presented
                }
                
                // 共有アイテム：キャプチャ画像（あれば）+ テキスト
                var items: [Any] = []
                if let image = capturedImage {
                    items.append(image)
                }
                items.append(requestText)
                
                let activityVC = UIActivityViewController(
                    activityItems: items,
                    applicationActivities: nil
                )
                
                // iPadのポップオーバー対応
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = topVC.view
                    popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                
                topVC.present(activityVC, animated: true)
            }
        }
    }
    
    private func showInvalidQRAlert(url: String) {
        let alert = UIAlertController(
            title: "無効なQRコード",
            message: "VeriCapture形式のQRコードではありません。\n\nURL: \(url)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presentAlert(alert)
    }
    
    private func showUnknownQRAlert(code: String) {
        let alert = UIAlertController(
            title: "認識できないQRコード",
            message: "VeriCapture形式ではありません。\n「証跡付き共有」のProof JSONを選択してください。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "ファイルを選択", style: .default) { _ in
            DispatchQueue.main.async {
                self.showFilePicker = true
            }
        })
        alert.addAction(UIAlertAction(title: "閉じる", style: .cancel))
        presentAlert(alert)
    }
    
    private func presentAlert(_ alert: UIAlertController) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(alert, animated: true)
        }
    }
    
    private func handleFileSelection(_ data: Data) {
        guard let json = String(data: data, encoding: .utf8), !json.isEmpty else {
            return
        }
        
        // Proof JSONを保存
        pendingProofJSON = json
        
        // State更新が反映されてから画像選択モードへ遷移
        // 複数回のランループを待つことで確実に反映させる
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
            // pendingProofJSONが確実に設定されていることを確認
            guard pendingProofJSON != nil && !pendingProofJSON!.isEmpty else {
                print("[VerifyView] ERROR: pendingProofJSON not set")
                return
            }
            showImageVerification = true
        }
    }
    
    @MainActor
    private func verifyJSON(_ json: String) async {
        isVerifying = true
        showJSONInput = false
        showImageVerification = false
        
        let result = await verificationService.verify(proofJSON: json)
        
        isVerifying = false
        pendingProofJSON = nil
        history.add(result)
        currentResult = result
    }
    
    @MainActor
    private func verifyWithImage(json: String, imageData: Data?) async {
        isVerifying = true
        showImageVerification = false
        
        let result = await verificationService.verify(proofJSON: json, assetData: imageData)
        
        isVerifying = false
        pendingProofJSON = nil
        history.add(result)
        currentResult = result
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Document Picker

struct VerifyDocumentPicker: UIViewControllerRepresentable {
    let onPick: (Data) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.json, UTType.plainText],
            asCopy: true
        )
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: VerifyDocumentPicker
        
        init(_ parent: VerifyDocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first,
                  let data = try? Data(contentsOf: url) else {
                return
            }
            parent.onPick(data)
        }
    }
}

// MARK: - JSON Input View

struct VerifyJSONInputView: View {
    @Binding var jsonText: String
    let onVerify: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // ヘッダー説明
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(
                                LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                        Text(L10n.Verify.jsonInputTitle)
                            .font(.headline)
                    }
                    
                    Text(L10n.Verify.jsonInputDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)
                
                // JSON入力エリア
                ZStack(alignment: .topLeading) {
                    // TextEditor
                    TextEditor(text: $jsonText)
                        .font(.system(.caption, design: .monospaced))
                        .focused($isFocused)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                    
                    // プレースホルダー
                    if jsonText.isEmpty {
                        Text("{\n  \"proof_version\": \"1.0\",\n  \"event\": { ... },\n  \"signature\": \"es256:...\",\n  ...\n}")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.gray.opacity(0.5))
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isFocused ? Color.blue.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: isFocused ? 2 : 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
                .padding(.horizontal)
                
                Spacer()
                
                // ボタンエリア
                HStack(spacing: 12) {
                    // クリアボタン
                    Button {
                        jsonText = ""
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.caption)
                            Text(L10n.Verify.clear)
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                    .disabled(jsonText.isEmpty)
                    .opacity(jsonText.isEmpty ? 0.5 : 1)
                    
                    // ペーストボタン
                    Button {
                        if let clipboard = UIPasteboard.general.string {
                            jsonText = clipboard
                            // 触覚フィードバック
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.caption)
                            Text(L10n.Verify.paste)
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                    
                    Spacer()
                    
                    // 検証ボタン
                    Button {
                        onVerify(jsonText)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.shield")
                                .font(.caption)
                            Text(L10n.Verify.verify)
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    LinearGradient(
                                        colors: jsonText.isEmpty ? [.gray, .gray] : [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                    .disabled(jsonText.isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.Verify.inputJSONTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.Verify.cancel) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Image Verification View (AssetHash検証用)

struct ImageVerificationView: View {
    let proofJSON: String
    let onVerify: (String, Data?) -> Void
    let onSkip: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedImageData: Data? = nil
    @State private var selectedImagePreview: UIImage? = nil
    @State private var selectedFileName: String? = nil
    @State private var showFilePicker = false
    @State private var assetHashFromProof: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 説明ヘッダー
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "photo.badge.checkmark")
                            .font(.title2)
                            .foregroundStyle(
                                LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                        Text(L10n.Verify.imageVerificationTitle)
                            .font(.headline)
                    }
                    
                    Text(L10n.Verify.imageVerificationDesc)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // AssetHash表示
                    if !assetHashFromProof.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.Verify.expectedAssetHash)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(assetHashFromProof)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                
                Spacer()
                
                // 画像プレビュー / 選択エリア
                if let preview = selectedImagePreview {
                    VStack(spacing: 12) {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 250)
                            .cornerRadius(12)
                            .shadow(radius: 5)
                        
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text(L10n.Verify.imageSelected)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                if let fileName = selectedFileName {
                                    Text(fileName)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Button {
                            selectedImageData = nil
                            selectedImagePreview = nil
                            selectedFileName = nil
                        } label: {
                            Text(L10n.Verify.changeImage)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    // ファイル選択ボタン
                    Button {
                        showFilePicker = true
                    } label: {
                        VStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [10]))
                                    .foregroundColor(.gray.opacity(0.5))
                                    .frame(height: 200)
                                
                                VStack(spacing: 12) {
                                    Image(systemName: "doc.badge.plus")
                                        .font(.system(size: 50))
                                        .foregroundColor(.gray)
                                    
                                    Text(L10n.Verify.selectImageToVerify)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text(L10n.Verify.selectImageFromFiles)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // ボタンエリア
                VStack(spacing: 12) {
                    // 検証ボタン
                    Button {
                        onVerify(proofJSON, selectedImageData)
                        // dismiss()は親のonVerifyコールバック内で処理される
                    } label: {
                        HStack {
                            Image(systemName: selectedImageData != nil ? "checkmark.shield.fill" : "checkmark.shield")
                            Text(selectedImageData != nil ? L10n.Verify.verifyWithImage : L10n.Verify.verifyProofOnly)
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: selectedImageData != nil ? [.green, .green.opacity(0.8)] : [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                    
                    // 注意事項
                    Text(L10n.Verify.imageVerificationNote)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle(L10n.Verify.assetHashVerification)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.Verify.cancel) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                extractAssetHash()
            }
            .sheet(isPresented: $showFilePicker) {
                ImageFilePickerView { data, fileName in
                    selectedImageData = data
                    selectedFileName = fileName
                    if let data = data {
                        selectedImagePreview = UIImage(data: data)
                    }
                }
            }
        }
    }
    
    private func extractAssetHash() {
        // Proof JSONからAssetHashを抽出
        guard let data = proofJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        // Shareable形式 (snake_case)
        if let event = json["event"] as? [String: Any],
           let hash = event["asset_hash"] as? String {
            assetHashFromProof = hash
            return
        }
        
        // Internal形式 (PascalCase)
        if let event = json["Event"] as? [String: Any],
           let asset = event["Asset"] as? [String: Any],
           let hash = asset["AssetHash"] as? String {
            assetHashFromProof = hash
        }
    }
}

// MARK: - Image File Picker (ファイルアプリから画像を選択)

struct ImageFilePickerView: UIViewControllerRepresentable {
    let onPick: (Data?, String?) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // 画像ファイルタイプを指定
        let supportedTypes: [UTType] = [
            .jpeg,
            .png,
            .heic,
            .heif,
            .image
        ]
        
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: supportedTypes,
            asCopy: true  // コピーとして読み込み（元ファイルを変更しない）
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: ImageFilePickerView
        
        init(_ parent: ImageFilePickerView) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                parent.onPick(nil, nil)
                return
            }
            
            // ファイルをそのまま読み込み（変換なし）
            do {
                let data = try Data(contentsOf: url)
                let fileName = url.lastPathComponent
                parent.onPick(data, fileName)
            } catch {
                print("Failed to read image file: \(error)")
                parent.onPick(nil, nil)
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // キャンセル時は何もしない
        }
    }
}

// MARK: - Preview

#Preview {
    VerifyView()
}
