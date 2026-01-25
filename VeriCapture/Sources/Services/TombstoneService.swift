//
//  TombstoneService.swift
//  VeriCapture
//
//  CPP Additional Spec: Tombstone (Event Invalidation) Service
//  © 2026 VeritasChain Standards Organization
//

import Foundation

/// Tombstone（墓石）サービス
/// 証跡の「失効」を記録する特殊イベントを生成・管理
final class TombstoneService: @unchecked Sendable {
    static let shared = TombstoneService()
    
    private let cryptoService = CryptoService.shared
    private let storageService = StorageService.shared
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// 証跡を失効させる（Tombstoneを生成）
    /// - Parameters:
    ///   - eventId: 失効対象のイベントID
    ///   - reason: 失効理由
    ///   - description: 追加説明（オプション）
    ///   - isUserInitiated: ユーザー操作かシステム操作か
    /// - Returns: 生成されたTombstoneイベント
    func invalidateEvent(
        eventId: String,
        reason: InvalidationReason,
        description: String? = nil,
        isUserInitiated: Bool = true
    ) async throws -> TombstoneEvent {
        
        print("[TombstoneService] Starting invalidation for event: \(eventId)")
        
        // 1. 対象イベントを取得
        guard let targetEvent = try storageService.getEvent(eventId: eventId) else {
            print("[TombstoneService] ERROR: Target event not found: \(eventId)")
            throw TombstoneError.targetEventNotFound
        }
        print("[TombstoneService] Step 1: Target event found")
        
        // 2. 既にTombstoneが存在するか確認
        if storageService.hasTombstone(forEventId: eventId) {
            print("[TombstoneService] ERROR: Tombstone already exists for: \(eventId)")
            throw TombstoneError.alreadyInvalidated
        }
        print("[TombstoneService] Step 2: No existing tombstone")
        
        // 3. イベントが既に失効していないか確認
        let currentStatus = storageService.getEventStatus(eventId: eventId)
        if currentStatus != .active {
            print("[TombstoneService] ERROR: Event not active, status: \(currentStatus)")
            throw TombstoneError.eventNotActive
        }
        print("[TombstoneService] Step 3: Event is active")
        
        // 4. 最新のハッシュを取得（チェーン連結用）
        let latestHash = try storageService.getLatestEventHash()
        
        // 5. Tombstoneイベントを構築
        let tombstoneId = generateTombstoneId()
        let timestamp = Date().iso8601String
        
        let target = TombstoneTarget(
            eventId: targetEvent.eventId,
            eventHash: targetEvent.eventHash
        )
        
        let tombstoneReason = TombstoneReason(
            code: reason.rawValue,
            description: description
        )
        
        let executor = TombstoneExecutor(
            type: isUserInitiated ? "USER" : "SYSTEM",
            attestation: isUserInitiated ? "biometric_verified" : nil
        )
        
        // 6. TombstoneHashを計算
        let tombstoneData = TombstoneHashData(
            tombstoneId: tombstoneId,
            eventType: "TOMBSTONE",
            timestamp: timestamp,
            targetEventId: target.eventId,
            targetEventHash: target.eventHash,
            reasonCode: tombstoneReason.code,
            reasonDescription: tombstoneReason.description,
            executorType: executor.type,
            prevHash: latestHash
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let canonicalJson = try encoder.encode(tombstoneData)
        let tombstoneHash = "sha256:" + canonicalJson.sha256Hash
        
        // 7. 署名 (tombstoneHashを署名)
        let signatureValue: String
        do {
            signatureValue = try cryptoService.signEventHash(tombstoneHash)
        } catch {
            print("[TombstoneService] Signature failed: \(error)")
            throw TombstoneError.signatureFailed
        }
        
        // es256:プレフィックスを除去してbase64部分のみ取得
        let signatureBase64 = signatureValue.replacingOccurrences(of: "es256:", with: "")
        
        // 8. Tombstoneイベントを構築
        let tombstone = TombstoneEvent(
            tombstoneId: tombstoneId,
            eventType: "TOMBSTONE",
            timestamp: timestamp,
            target: target,
            reason: tombstoneReason,
            executor: executor,
            prevHash: latestHash,
            tombstoneHash: tombstoneHash,
            signature: SignatureInfo(algo: "ES256", value: signatureBase64)
        )
        
        // 9. 保存（chain_idを含める）
        try storageService.saveTombstone(tombstone, chainId: targetEvent.chainId)
        
        // 10. 対象イベントのステータスを更新
        try storageService.updateEventStatus(eventId: eventId, status: .invalidated)
        
        print("[TombstoneService] Event invalidated: \(eventId)")
        print("[TombstoneService] Tombstone created: \(tombstoneId)")
        
        return tombstone
    }
    
    /// イベントが失効可能かチェック
    func canInvalidate(eventId: String) -> Bool {
        // Tombstoneが既に存在しないこと
        guard !storageService.hasTombstone(forEventId: eventId) else {
            return false
        }
        
        // イベントがアクティブ状態であること
        let status = storageService.getEventStatus(eventId: eventId)
        return status == .active
    }
    
    /// Tombstoneを取得
    func getTombstone(forEventId eventId: String) -> TombstoneEvent? {
        return storageService.getTombstone(forEventId: eventId)
    }
    
    // MARK: - Private Methods
    
    private func generateTombstoneId() -> String {
        // UUIDv7形式のID生成
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        let random = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
        return String(format: "TOMB-%016llX-%@", timestamp, String(random))
    }
}

// MARK: - Hash Data Structure

/// Tombstoneハッシュ計算用の構造体
private struct TombstoneHashData: Codable {
    let tombstoneId: String
    let eventType: String
    let timestamp: String
    let targetEventId: String
    let targetEventHash: String
    let reasonCode: String
    let reasonDescription: String?
    let executorType: String
    let prevHash: String
}

// MARK: - Errors

enum TombstoneError: LocalizedError, Sendable {
    case targetEventNotFound
    case alreadyInvalidated
    case eventNotActive
    case signatureFailed
    case storageFailed
    
    var errorDescription: String? {
        switch self {
        case .targetEventNotFound:
            return "Target event not found"
        case .alreadyInvalidated:
            return "Event has already been invalidated"
        case .eventNotActive:
            return "Event is not in active state"
        case .signatureFailed:
            return "Failed to sign tombstone"
        case .storageFailed:
            return "Failed to store tombstone"
        }
    }
}
