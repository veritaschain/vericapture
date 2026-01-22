//
//  CaptureViewModel.swift
//  VeriCapture
//
//  Capture Coordination ViewModel
//  © 2026 VeritasChain Standards Organization
//
//  Phase A Design: 認証失敗時も撮影を許可し、verified=falseとして記録

import SwiftUI
import Combine
import UIKit

// MARK: - Gallery Display Mode

enum GalleryDisplayMode: String {
    case list = "list"
    case grid = "grid"
}

enum GalleryFilterMode: String, CaseIterable {
    case all = "all"
    case attested = "attested"
    case anchored = "anchored"
    case pending = "pending"
}

struct CaptureResultData: Sendable {
    let eventId: String
    let timestamp: Date
    let filename: String
    let fileSize: Int
    let assetHash: String
    let signAlgorithm: String
    let anchorStatus: String
    let image: UIImage?
    let savedSuccessfully: Bool
    let isAttestedCapture: Bool
    let isVerifiedSuccess: Bool  // 認証成功したか（フェーズA）
    let hasLocation: Bool  // 位置情報が記録されているか
}

@MainActor
final class CaptureViewModel: ObservableObject {
    
    @Published var isCapturing = false
    @Published var isSharing = false  // 共有処理中フラグ（グローバルローディング用）
    @Published var lastCapturedImage: UIImage?
    @Published var lastCaptureResult: CaptureResultData?
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var capturedEvents: [CPPEvent] = []
    
    // ギャラリー表示設定
    @Published var pinnedEventIds: Set<String> {
        didSet {
            savePinnedEventIds()
        }
    }
    @Published var galleryDisplayMode: GalleryDisplayMode {
        didSet {
            UserDefaults.standard.set(galleryDisplayMode.rawValue, forKey: "galleryDisplayMode")
        }
    }
    
    // 検索・フィルタ・選択モード
    @Published var searchText: String = ""
    @Published var filterMode: GalleryFilterMode = .all
    @Published var isSelectionMode: Bool = false
    @Published var selectedEventIds: Set<String> = []
    
    // Pro/課金関連
    @Published var showLimitReached = false
    @Published var showPaywall = false
    @Published var navigateToGalleryForDeletion = false  // 「空きを作る」で証跡タブへ遷移
    
    // Verified Capture Mode
    @Published var isAttestedCaptureMode: Bool {
        didSet {
            UserDefaults.standard.set(isAttestedCaptureMode, forKey: "attestedCaptureModeEnabled")
        }
    }
    @Published var lastAuthResult: BiometricAuthService.VerifiedCaptureAuthResult?
    @Published var isAuthenticating = false  // FaceID認証中フラグ
    
    let cameraService = CameraService()
    private let eventBuilder = CPPEventBuilder()
    
    private var chainId: String?
    private var cancellables = Set<AnyCancellable>()
    private var captureCount = 0
    
    // FaceID後のカメラ再開用
    private var didBecomeActiveContinuation: CheckedContinuation<Void, Never>?
    
    /// 初回撮影かどうか（初回は時間がかかるため）
    var isFirstCapture: Bool {
        captureCount == 0
    }
    
    /// カメラが撮影可能かどうか（カメラ状態を監視）
    var isReady: Bool {
        cameraService.isAuthorized && cameraService.isCameraReady
    }
    
    /// 現在の保存済み証跡数（全ケース合計 - 無料プラン制限用）
    var currentProofCount: Int {
        StorageService.shared.getTotalEventCount()
    }
    
    /// 現在のケースの証跡数
    var currentCaseEventCount: Int {
        capturedEvents.count
    }
    
    /// 残り保存可能数
    var remainingSlots: Int {
        SubscriptionService.shared.remainingFreeSlots(currentCount: currentProofCount)
    }
    
    /// Pro状態
    var isPro: Bool {
        SubscriptionService.shared.effectiveIsPro
    }
    
    /// Verified Capture Modeが利用可能か
    var isAttestedCaptureModeAvailable: Bool {
        BiometricAuthService.shared.isDeviceAuthAvailable
    }
    
    init() {
        // ギャラリー表示設定を読み込み
        self.pinnedEventIds = Self.loadPinnedEventIds()
        self.galleryDisplayMode = GalleryDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: "galleryDisplayMode") ?? "list"
        ) ?? .list
        
        // Verified Capture Mode の設定を読み込み
        self.isAttestedCaptureMode = UserDefaults.standard.bool(forKey: "attestedCaptureModeEnabled")
        
        if let id = try? StorageService.shared.getOrCreateChainId() {
            chainId = id
        }
        
        // 保存済みイベントを読み込み（証跡一覧表示用）
        refreshEvents()
        
        // カメラの状態変化を監視してUIを更新
        cameraService.$isCameraReady
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        cameraService.$isAuthorized
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // フラッシュモードの変化を監視してUIを更新
        cameraService.$flashMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // アプリがアクティブになった通知を監視（FaceID後のカメラ再開用）
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleDidBecomeActive()
            }
            .store(in: &cancellables)
    }
    
    /// アプリがアクティブになった時の処理
    private func handleDidBecomeActive() {
        // FaceID後のカメラ再開を待っている場合、continuationを再開
        if let continuation = didBecomeActiveContinuation {
            print("[CaptureViewModel] App became active, resuming camera restart...")
            didBecomeActiveContinuation = nil
            continuation.resume()
        }
    }
    
    /// アプリがアクティブになるまで待機
    private func waitForAppToBeActive() async {
        print("[CaptureViewModel] Waiting for app to become active...")
        await withCheckedContinuation { continuation in
            self.didBecomeActiveContinuation = continuation
        }
    }
    
    func checkAuthorization() async {
        await cameraService.checkAuthorization()
        // isReadyはcomputed propertyなので自動更新される
    }
    
    func switchCamera() {
        cameraService.switchCamera()
    }
    
    func capturePhoto() async {
        guard !isCapturing else { return }
        
        isCapturing = true
        lastAuthResult = nil
        
        // 撮影開始時のHaptic feedback
        let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
        impactGenerator.impactOccurred()
        
        // UI更新を待つ（ローディング表示が確実に表示されるようにする）
        await Task.yield()
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Verified Capture Mode: 撮影前に認証を試行
        var humanAttestation: HumanAttestation? = nil
        var authResult: BiometricAuthService.VerifiedCaptureAuthResult? = nil
        
        if isAttestedCaptureMode {
            // 重要: FaceID認証前にカメラセッションを【完全に】停止
            // FaceIDはフロントカメラを使用し、バックカメラと競合するため、
            // 停止が完了するまで待ってからFaceIDを開始する
            print("[CaptureViewModel] Stopping camera before FaceID authentication...")
            
            // 認証中フラグをON（UI表示用）
            isAuthenticating = true
            
            // 【重要】awaitで停止完了を待つ（これがないと競合が発生する）
            await cameraService.stopSession()
            
            // 停止完了後、システムが安定するまで少し待機
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            
            // カメラが完全に停止した状態でFaceIDを実行
            print("[CaptureViewModel] Camera stopped, starting FaceID...")
            authResult = await BiometricAuthService.shared.authenticateForVerifiedCapture()
            lastAuthResult = authResult
            
            // 認証中フラグをOFF
            isAuthenticating = false
            
            // キャンセルされた場合は撮影を中止
            if authResult?.failureReason == "UserCancelled" {
                print("[CaptureViewModel] Authentication cancelled by user, aborting capture")
                await cameraService.resumeSessionAfterAuth()
                isCapturing = false
                return
            }
            
            // 【核心的修正】FaceIDのUIが完全に閉じるまで待機
            // 時間ベースの待機ではなく、アプリがアクティブになるのを待つことで
            // GPUリソースの競合（fence tx observer timed out）を完全に回避
            print("[CaptureViewModel] FaceID complete, waiting for app to become active...")
            
            // アプリがまだアクティブでない場合は待機
            if UIApplication.shared.applicationState != .active {
                await waitForAppToBeActive()
            }
            
            // アプリがアクティブになった後、UIアニメーション完了を待つ（短い安定化待機）
            print("[CaptureViewModel] App is active, stabilizing before camera restart...")
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms (安定化のため)
            
            // カメラセッションを再構成
            print("[CaptureViewModel] Restarting camera...")
            await cameraService.resumeSessionAfterAuth()
            
            // 認証失敗時も撮影は続行（verified=falseとして記録）
        }
        
        do {
            let captureResult = try await cameraService.capturePhoto()
            
            // 即座にプレビューを表示（ユーザー体験向上）
            lastCapturedImage = captureResult.image
            
            // v40: CaseServiceから現在のケースのchainIdを取得
            guard let chainId = CaseService.shared.currentChainId ?? self.chainId ?? (try? StorageService.shared.getOrCreateChainId()) else {
                throw CaptureError.chainIdNotAvailable
            }
            self.chainId = chainId
            
            // Verified Capture Mode: HumanAttestationを生成（フェーズA）
            // 認証成功/失敗どちらの場合も生成される
            if let authResult = authResult {
                humanAttestation = eventBuilder.buildHumanAttestation(
                    from: authResult,
                    captureTimestamp: captureResult.captureTimestamp
                )
            }
            
            // 署名者名を取得（監査用設定から）
            let signerName = UserDefaults.standard.string(forKey: "signerName")
            
            // 証跡生成（MainActorで実行）
            let event = try eventBuilder.buildIngestEvent(
                from: captureResult,
                chainId: chainId,
                humanAttestation: humanAttestation,
                signerName: signerName
            )
            
            // 上限チェック
            let canSave = SubscriptionService.shared.canSaveProof(currentCount: currentProofCount)
            
            // Verified Capture Modeの状態判定
            let isAttestedCapture = humanAttestation != nil
            let isVerifiedSuccess = humanAttestation?.verified ?? false
            
            if canSave {
                // 保存
                try StorageService.shared.saveEvent(event, imageData: captureResult.imageData)
                
                // 位置情報をローカルに保存（Map表示用、Proof JSONには含まれない）
                let hasLocation = captureResult.rawLatitude != nil && captureResult.rawLongitude != nil
                if let lat = captureResult.rawLatitude, let lon = captureResult.rawLongitude {
                    StorageService.shared.saveLocationMetadata(
                        eventId: event.eventId,
                        latitude: lat,
                        longitude: lon
                    )
                }
                
                lastCaptureResult = CaptureResultData(
                    eventId: event.eventId,
                    timestamp: captureResult.captureTimestamp,
                    filename: event.asset.assetName,
                    fileSize: event.asset.assetSize,
                    assetHash: event.asset.assetHash,
                    signAlgorithm: event.signAlgo,
                    anchorStatus: L10n.Result.anchorPending,
                    image: captureResult.image,
                    savedSuccessfully: true,
                    isAttestedCapture: isAttestedCapture,
                    isVerifiedSuccess: isVerifiedSuccess,
                    hasLocation: hasLocation
                )
                
                refreshEvents()
                
                // v40: ケースの統計を更新
                CaseService.shared.onCaptureCompleted(eventId: event.eventId)
                
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
                print("[CaptureViewModel] Photo captured and saved: \(event.eventId), AttestedCapture: \(isAttestedCapture), Verified: \(isVerifiedSuccess)")
            } else {
                // 上限到達：証跡は生成したが保存しない
                let hasLocation = captureResult.rawLatitude != nil && captureResult.rawLongitude != nil
                lastCaptureResult = CaptureResultData(
                    eventId: event.eventId,
                    timestamp: captureResult.captureTimestamp,
                    filename: event.asset.assetName,
                    fileSize: event.asset.assetSize,
                    assetHash: event.asset.assetHash,
                    signAlgorithm: event.signAlgo,
                    anchorStatus: "保存制限",
                    image: captureResult.image,
                    savedSuccessfully: false,
                    isAttestedCapture: isAttestedCapture,
                    isVerifiedSuccess: isVerifiedSuccess,
                    hasLocation: hasLocation
                )
                
                // 上限到達シートを表示
                showLimitReached = true
                
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
                
                print("[CaptureViewModel] Limit reached. Event generated but not saved: \(event.eventId)")
            }
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            print("[CaptureViewModel] Capture failed: \(error)")
        }
        
        captureCount += 1
        isCapturing = false
    }
    
    func refreshEvents() {
        // v40: CaseServiceのcurrentChainIdを優先
        guard let chainId = CaseService.shared.currentChainId ?? chainId else { return }
        
        do {
            capturedEvents = try StorageService.shared.getAllEvents(chainId: chainId).reversed()
        } catch {
            print("[CaptureViewModel] Failed to refresh events: \(error)")
        }
    }
    
    /// 証跡を削除して空きを作る（Tombstone発行付き）
    func deleteEvent(_ event: CPPEvent, reason: InvalidationReason = .userPrivacyRequest) {
        Task {
            do {
                // 削除対象が最後に撮影したものならサムネイルもクリア
                if lastCaptureResult?.eventId == event.eventId {
                    await MainActor.run {
                        lastCapturedImage = nil
                        lastCaptureResult = nil
                    }
                }
                
                // 1. Tombstone発行（証跡失効の記録）
                _ = try await TombstoneService.shared.invalidateEvent(
                    eventId: event.eventId,
                    reason: reason,
                    isUserInitiated: true
                )
                
                // 2. メディア削除
                try StorageService.shared.purgeMedia(eventId: event.eventId)
                
                // 3. イベント自体を削除
                try StorageService.shared.deleteEvent(eventId: event.eventId)
                
                // 4. v40: ケース統計を更新
                CaseService.shared.onEventDeleted(eventId: event.eventId, chainId: event.chainId)
                
                // UIから削除（アニメーション付き）
                await MainActor.run {
                    withAnimation {
                        capturedEvents.removeAll { $0.eventId == event.eventId }
                    }
                }
                print("[CaptureViewModel] Event deleted with tombstone: \(event.eventId)")
            } catch {
                print("[CaptureViewModel] Failed to delete event: \(error)")
                // エラー時はリフレッシュ
                await MainActor.run {
                    refreshEvents()
                }
            }
        }
    }
    
    /// 共有用Proof JSONをエクスポート（最小限の情報のみ、プライバシー保護）
    func exportProof(eventId: String) async -> URL? {
        do {
            return try StorageService.shared.exportShareableProof(eventId: eventId)
        } catch {
            print("[CaptureViewModel] Shareable export failed: \(error)")
            return nil
        }
    }
    
    /// 内部用Proof JSONをエクスポート（完全な情報、法務提出用）
    /// - Parameters:
    ///   - eventId: エクスポート対象のイベントID
    ///   - includeLocation: 位置情報（緯度・経度）を含めるか
    func exportInternalProof(eventId: String, includeLocation: Bool = false) async -> URL? {
        do {
            guard let event = try StorageService.shared.getEvent(eventId: eventId) else { return nil }
            let anchor = try StorageService.shared.getAnchor(forEventId: eventId)
            
            // 位置情報を取得（オプション）
            var locationInfo: LocationInfo? = nil
            if includeLocation {
                if let location = StorageService.shared.getLocationMetadata(eventId: eventId) {
                    locationInfo = LocationInfo(
                        latitude: location.latitude,
                        longitude: location.longitude,
                        accuracy: nil,
                        altitude: nil,
                        capturedAt: event.timestamp
                    )
                }
            }
            
            // 署名者名を取得（フォレンジック設定から）
            let signerName = UserDefaults.standard.string(forKey: "signerName")
            
            let proof = eventBuilder.generateProofJSON(event: event, anchor: anchor, locationInfo: locationInfo, signerName: signerName)
            return try StorageService.shared.exportInternalProof(proof)
        } catch {
            print("[CaptureViewModel] Internal export failed: \(error)")
            return nil
        }
    }
    
    /// 生データエクスポート（元画像 + Proof JSON をそのままファイルに保存）
    /// AssetHash検証に使用可能な形式でエクスポートする
    /// - Parameter eventId: エクスポート対象のイベントID
    /// - Returns: [画像ファイルURL, ProofファイルURL] の配列
    func exportRawData(eventId: String) async -> [URL]? {
        do {
            guard let event = try StorageService.shared.getEvent(eventId: eventId) else { return nil }
            
            // 元画像データを取得（生バイト）
            guard let imageData = StorageService.shared.loadMediaData(eventId: eventId) else {
                print("[CaptureViewModel] Raw image data not found for eventId: \(eventId)")
                return nil
            }
            
            // Shareable Proof JSONを取得（第三者検証用）
            let proofURL = try StorageService.shared.exportShareableProof(eventId: eventId)
            
            // 一時ファイルに画像を保存
            let tempDir = FileManager.default.temporaryDirectory
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            
            // 画像ファイル（元の拡張子を維持）
            let imageExtension = event.asset.mimeType.contains("heic") ? "heic" : 
                                 event.asset.mimeType.contains("heif") ? "heif" : 
                                 event.asset.mimeType.contains("png") ? "png" : "jpg"
            let imageFileName = "VeriCapture_\(timestamp).\(imageExtension)"
            let imageURL = tempDir.appendingPathComponent(imageFileName)
            try imageData.write(to: imageURL)
            
            print("[CaptureViewModel] Raw data export: \(imageFileName), proof.json")
            return [imageURL, proofURL]
            
        } catch {
            print("[CaptureViewModel] Raw data export failed: \(error)")
            return nil
        }
    }
    
    // MARK: - Camera Control for UI State
    
    /// 結果確認画面・共有画面を表示する際にカメラを休止する
    /// これにより、共有シート表示時のメモリ不足やフリーズを防ぐ
    func pauseCameraForReview() async {
        print("[CaptureViewModel] Pausing camera for review/sharing...")
        await cameraService.stopSession()
    }
    
    /// 結果確認画面を閉じた後にカメラを再開する
    func resumeCameraAfterReview() async {
        print("[CaptureViewModel] Resuming camera after review...")
        // アプリがアクティブな場合のみ再開
        if UIApplication.shared.applicationState == .active {
            await cameraService.resumeSessionAfterAuth()
        }
    }
    
    // MARK: - Gallery Pinning
    
    /// イベントがピン留めされているか確認
    func isPinned(_ eventId: String) -> Bool {
        pinnedEventIds.contains(eventId)
    }
    
    /// ピン留め状態をトグル
    func togglePin(_ eventId: String) {
        if pinnedEventIds.contains(eventId) {
            pinnedEventIds.remove(eventId)
        } else {
            pinnedEventIds.insert(eventId)
        }
    }
    
    /// フィルタ・検索適用済みでピン留め優先ソートされたイベント
    var sortedEvents: [CPPEvent] {
        var filtered = capturedEvents
        
        // フィルタ適用
        switch filterMode {
        case .all:
            break
        case .attested:
            filtered = filtered.filter { $0.captureContext.humanAttestation != nil }
        case .anchored:
            filtered = filtered.filter { $0.isAnchored }
        case .pending:
            filtered = filtered.filter { !$0.isAnchored }
        }
        
        // 検索適用
        if !searchText.isEmpty {
            let lowercased = searchText.lowercased()
            filtered = filtered.filter { event in
                event.asset.assetName.lowercased().contains(lowercased) ||
                event.eventId.lowercased().contains(lowercased)
            }
        }
        
        // ピン留め優先でソート
        return filtered.sorted { event1, event2 in
            let pinned1 = pinnedEventIds.contains(event1.eventId)
            let pinned2 = pinnedEventIds.contains(event2.eventId)
            
            if pinned1 && !pinned2 {
                return true
            } else if !pinned1 && pinned2 {
                return false
            } else {
                return event1.timestamp > event2.timestamp
            }
        }
    }
    
    /// 日付でグループ化されたイベント
    var groupedEvents: [(String, [CPPEvent])] {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: today)!
        let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: today)!
        
        var groups: [String: [CPPEvent]] = [:]
        var groupOrder: [String] = []
        
        // ピン留めイベントは最初に分離
        let pinnedEvents = sortedEvents.filter { pinnedEventIds.contains($0.eventId) }
        let unpinnedEvents = sortedEvents.filter { !pinnedEventIds.contains($0.eventId) }
        
        if !pinnedEvents.isEmpty {
            groups[L10n.Gallery.groupPinned] = pinnedEvents
            groupOrder.append(L10n.Gallery.groupPinned)
        }
        
        // ISO8601フォーマッターを再利用可能にする
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // フラクショナルセカンドなしのフォールバック用
        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]
        
        for event in unpinnedEvents {
            // フラクショナルセカンド付きでパース、失敗したらなしでパース
            guard let eventDate = isoFormatter.date(from: event.timestamp) ?? isoFormatterNoFrac.date(from: event.timestamp) else {
                continue
            }
            
            let groupName: String
            if calendar.isDate(eventDate, inSameDayAs: now) {
                groupName = L10n.Gallery.groupToday
            } else if calendar.isDate(eventDate, inSameDayAs: yesterday) {
                groupName = L10n.Gallery.groupYesterday
            } else if eventDate >= lastWeekStart {
                groupName = L10n.Gallery.groupThisWeek
            } else if eventDate >= lastMonthStart {
                groupName = L10n.Gallery.groupThisMonth
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy/MM"
                groupName = formatter.string(from: eventDate)
            }
            
            if groups[groupName] == nil {
                groups[groupName] = []
                groupOrder.append(groupName)
            }
            groups[groupName]?.append(event)
        }
        
        return groupOrder.compactMap { key in
            guard let events = groups[key] else { return nil }
            return (key, events)
        }
    }
    
    // MARK: - Selection Mode
    
    /// 選択モードを開始
    func startSelectionMode() {
        isSelectionMode = true
        selectedEventIds.removeAll()
    }
    
    /// 選択モードを終了
    func endSelectionMode() {
        isSelectionMode = false
        selectedEventIds.removeAll()
    }
    
    /// イベントの選択をトグル
    func toggleSelection(_ eventId: String) {
        if selectedEventIds.contains(eventId) {
            selectedEventIds.remove(eventId)
        } else {
            selectedEventIds.insert(eventId)
        }
    }
    
    /// イベントが選択されているか確認
    func isSelected(_ eventId: String) -> Bool {
        selectedEventIds.contains(eventId)
    }
    
    /// 全選択
    func selectAll() {
        selectedEventIds = Set(sortedEvents.map { $0.eventId })
    }
    
    /// 全選択解除
    func deselectAll() {
        selectedEventIds.removeAll()
    }
    
    /// 選択されたイベントを削除
    func deleteSelectedEvents(reason: InvalidationReason = .userPrivacyRequest) {
        for eventId in selectedEventIds {
            if let event = capturedEvents.first(where: { $0.eventId == eventId }) {
                deleteEvent(event, reason: reason)
            }
        }
        endSelectionMode()
    }
    
    /// ピン留めIDをUserDefaultsに保存
    private func savePinnedEventIds() {
        let array = Array(pinnedEventIds)
        UserDefaults.standard.set(array, forKey: "pinnedEventIds")
    }
    
    /// ピン留めIDをUserDefaultsから読み込み
    private static func loadPinnedEventIds() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: "pinnedEventIds") ?? []
        return Set(array)
    }
}

enum CaptureError: LocalizedError, Sendable {
    case chainIdNotAvailable
    case eventCreationFailed
    case storageFailed
    case limitReached
    case authenticationFailed
    case authenticationCancelled
    
    var errorDescription: String? {
        switch self {
        case .chainIdNotAvailable: return "Chain ID not available"
        case .eventCreationFailed: return "Failed to create event"
        case .storageFailed: return "Failed to save capture"
        case .limitReached: return "Free storage limit reached"
        case .authenticationFailed: return "Authentication failed"
        case .authenticationCancelled: return "Authentication cancelled"
        }
    }
}
