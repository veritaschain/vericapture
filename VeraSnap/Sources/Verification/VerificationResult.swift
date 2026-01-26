//
//  VerificationResult.swift
//  VeraSnap
//
//  Verification Result Models
//  © 2026 VeritasChain Standards Organization
//

import Foundation
import SwiftUI
import Combine

// MARK: - Verification Status

enum VerificationStatus: String, CaseIterable {
    case verified = "VERIFIED"
    case signatureInvalid = "SIGNATURE_INVALID"
    case hashMismatch = "HASH_MISMATCH"
    case anchorPending = "ANCHOR_PENDING"
    case anchorVerified = "ANCHOR_VERIFIED"
    case assetMismatch = "ASSET_MISMATCH"
    case pending = "PENDING"
    case error = "ERROR"
    
    var displayName: String {
        switch self {
        case .verified: return L10n.Verify.statusVerified
        case .signatureInvalid: return L10n.Verify.statusSignatureInvalid
        case .hashMismatch: return L10n.Verify.statusHashMismatch
        case .anchorPending: return L10n.Verify.statusAnchorPending
        case .anchorVerified: return L10n.Verify.statusAnchorVerified
        case .assetMismatch: return L10n.Verify.statusAssetMismatch
        case .pending: return L10n.Verify.statusPending
        case .error: return L10n.Verify.statusError
        }
    }
    
    var color: Color {
        switch self {
        case .verified, .anchorVerified:
            return .green
        case .signatureInvalid, .hashMismatch, .assetMismatch, .error:
            return .red
        case .anchorPending, .pending:
            return .yellow
        }
    }
    
    var icon: String {
        switch self {
        case .verified, .anchorVerified:
            return "checkmark.shield.fill"
        case .signatureInvalid, .hashMismatch, .assetMismatch:
            return "xmark.shield.fill"
        case .anchorPending, .pending:
            return "clock.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Check Status (OK/NG/Skipped/Warning)

enum CheckStatus {
    case passed
    case failed
    case skipped
    case warning  // v42.2: 警告（検証は通過したが注意事項あり）
    
    var icon: String {
        switch self {
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .passed: return .green
        case .failed: return .red
        case .skipped: return .orange
        case .warning: return .yellow
        }
    }
    
    var badge: String {
        switch self {
        case .passed: return "OK"
        case .failed: return "NG"
        case .skipped: return "-"
        case .warning: return "⚠️"
        }
    }
    
    var badgeColor: Color {
        switch self {
        case .passed: return .green
        case .failed: return .red
        case .skipped: return .orange
        case .warning: return .yellow
        }
    }
}

// MARK: - Individual Check Result

struct CheckResult: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let status: CheckStatus
    let details: String?
    
    // 後方互換性のためのコンビニエンスイニシャライザ
    init(name: String, description: String, passed: Bool, details: String? = nil) {
        self.name = name
        self.description = description
        self.status = passed ? .passed : .failed
        self.details = details
    }
    
    // 新しいイニシャライザ（スキップ対応）
    init(name: String, description: String, status: CheckStatus, details: String? = nil) {
        self.name = name
        self.description = description
        self.status = status
        self.details = details
    }
    
    var icon: String {
        status.icon
    }
    
    var color: Color {
        status.color
    }
    
    // 後方互換性
    var passed: Bool {
        status == .passed
    }
}

// MARK: - Complete Verification Result

struct VerificationResult: Identifiable {
    let id = UUID()
    let timestamp: Date
    let overallStatus: VerificationStatus
    let proof: CPPProofJSON?
    let checks: [CheckResult]
    let errorMessage: String?
    let shareableAttested: Bool?  // Shareable形式用のAttestedフラグ
    let shareableFlashMode: String?  // Shareable形式用のフラッシュモード
    let shareableCaptureTimestamp: String?  // Shareable形式用の撮影時刻
    let shareableEventId: String?  // Shareable形式用のEventID
    let shareableTsaTimestamp: String?  // Shareable形式用のTSAタイムスタンプ
    let shareableTsaService: String?  // Shareable形式用のTSAサービス
    
    // Computed properties for display
    var captureTimestamp: String? {
        proof?.event.timestamp ?? shareableCaptureTimestamp
    }
    
    var deviceModel: String? {
        proof?.event.captureContext.deviceModel
    }
    
    var osVersion: String? {
        proof?.event.captureContext.osVersion
    }
    
    var assetName: String? {
        proof?.event.asset.assetName
    }
    
    /// 表示用の名前（assetNameがない場合はeventIDの短縮形）
    var displayName: String {
        if let name = proof?.event.asset.assetName {
            return name
        }
        if let eventId = eventID {
            // eventIDの先頭8文字を表示
            let prefix = String(eventId.prefix(8))
            return "Proof_\(prefix)..."
        }
        return L10n.Verify.proofFile
    }
    
    var eventID: String? {
        proof?.event.eventID ?? shareableEventId
    }
    
    var generatedBy: String? {
        proof?.generatedBy
    }
    
    var tsaTimestamp: String? {
        proof?.anchor?.tsaTimestamp ?? shareableTsaTimestamp
    }
    
    var tsaService: String? {
        proof?.anchor?.tsaService ?? shareableTsaService
    }
    
    // 署名者情報（イベント内を優先、なければVerification内を参照）
    var signerName: String? {
        // 1. イベント内のSignerInfo（新形式 - ハッシュ対象）
        if let eventSignerName = proof?.event.signerInfo?.name {
            return eventSignerName
        }
        // 2. Verification内のSigner（旧形式 - ハッシュ対象外）
        return proof?.verification.signer?.name
    }
    
    var signerAttestedAt: String? {
        // 1. イベント内のSignerInfo（新形式 - ハッシュ対象）
        if let eventAttestedAt = proof?.event.signerInfo?.attestedAt {
            return eventAttestedAt
        }
        // 2. Verification内のSigner（旧形式 - ハッシュ対象外）
        return proof?.verification.signer?.attestedAt
    }
    
    /// 署名者情報がハッシュ対象（改ざん検出可能）かどうか
    var isSignerHashProtected: Bool {
        proof?.event.signerInfo != nil
    }
    
    // フラッシュモード（OFF, AUTO, ON） - Internal/Shareable両対応
    var flashMode: String? {
        proof?.event.cameraSettings?.flashMode ?? shareableFlashMode
    }
    
    // 位置情報（法務用エクスポートに含まれる場合のみ）
    var location: LocationInfoJSON? {
        proof?.metadata.location
    }
    
    var hasLocation: Bool {
        location != nil
    }
    
    /// 動画かどうか（AssetTypeまたはファイル名で判定）
    var isVideo: Bool {
        // AssetTypeで判定（Internal形式）
        if let assetType = proof?.event.asset.assetType {
            return assetType == "VIDEO"
        }
        // ファイル名で判定（Shareable形式など）
        if let name = assetName {
            return name.hasPrefix("VID_") || name.lowercased().hasSuffix(".mov") || name.lowercased().hasSuffix(".mp4")
        }
        return false
    }
    
    // HumanAttestation（Attested Captureモード）
    var humanAttestation: HumanAttestationJSON? {
        proof?.event.captureContext.humanAttestation
    }
    
    // Attestedかどうか（Internal形式とShareable形式の両方に対応）
    var isAttestedCapture: Bool {
        humanAttestation != nil || (shareableAttested ?? false)
    }
    
    var attestedVerified: Bool {
        humanAttestation?.verified ?? (shareableAttested ?? false)
    }
    
    // Summary
    var passedChecks: Int {
        checks.filter { $0.status == .passed }.count
    }
    
    var skippedChecks: Int {
        checks.filter { $0.status == .skipped }.count
    }
    
    var failedChecks: Int {
        checks.filter { $0.status == .failed }.count
    }
    
    var warningChecks: Int {
        checks.filter { $0.status == .warning }.count
    }
    
    var totalChecks: Int {
        checks.count
    }
}

// MARK: - Verification History

class VerificationHistory: ObservableObject {
    @Published var results: [VerificationResult] = []
    
    func add(_ result: VerificationResult) {
        results.insert(result, at: 0)
        // Keep only last 50 results
        if results.count > 50 {
            results = Array(results.prefix(50))
        }
    }
    
    func clear() {
        results.removeAll()
    }
}

// MARK: - Identifiable Extension

extension VerificationResult: Hashable {
    static func == (lhs: VerificationResult, rhs: VerificationResult) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
