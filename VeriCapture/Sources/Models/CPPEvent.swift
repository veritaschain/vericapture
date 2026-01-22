//
//  CPPEvent.swift
//  VeriCapture
//
//  CPP v1.0 Event Data Model
//  © 2026 VeritasChain Standards Organization
//

import Foundation

// MARK: - CPP Event Types

enum CPPEventType: String, Codable, Sendable {
    case ingest = "INGEST"
    case export = "EXPORT"
}

enum AssetType: String, Codable, Sendable {
    case image = "IMAGE"
    case video = "VIDEO"
}

// MARK: - CPP INGEST Event

struct CPPEvent: Codable, Sendable, Identifiable {
    let eventId: String
    let chainId: String
    let prevHash: String
    let timestamp: String
    let eventType: CPPEventType
    let hashAlgo: String
    let signAlgo: String
    let asset: Asset
    let captureContext: CaptureContext
    let sensorData: SensorData?
    let cameraSettings: CameraSettings?
    var eventHash: String
    var signature: String
    
    /// Identifiable準拠
    var id: String { eventId }
    
    /// アンカリング状態（StorageServiceから取得）
    var isAnchored: Bool {
        // StorageServiceからアンカリング状態を確認
        StorageService.shared.isEventAnchored(eventId: eventId)
    }
    
    enum CodingKeys: String, CodingKey {
        case eventId = "EventID"
        case chainId = "ChainID"
        case prevHash = "PrevHash"
        case timestamp = "Timestamp"
        case eventType = "EventType"
        case hashAlgo = "HashAlgo"
        case signAlgo = "SignAlgo"
        case asset = "Asset"
        case captureContext = "CaptureContext"
        case sensorData = "SensorData"
        case cameraSettings = "CameraSettings"
        case eventHash = "EventHash"
        case signature = "Signature"
    }
}

// MARK: - Asset

struct Asset: Codable, Sendable {
    let assetId: String
    let assetType: AssetType
    let assetHash: String
    let assetName: String
    let assetSize: Int
    let mimeType: String
    
    enum CodingKeys: String, CodingKey {
        case assetId = "AssetID"
        case assetType = "AssetType"
        case assetHash = "AssetHash"
        case assetName = "AssetName"
        case assetSize = "AssetSize"
        case mimeType = "MimeType"
    }
}

// MARK: - Capture Context

struct CaptureContext: Codable, Sendable {
    let deviceId: String
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let keyAttestation: KeyAttestation
    let humanAttestation: HumanAttestation?
    
    enum CodingKeys: String, CodingKey {
        case deviceId = "DeviceID"
        case deviceModel = "DeviceModel"
        case osVersion = "OSVersion"
        case appVersion = "AppVersion"
        case keyAttestation = "KeyAttestation"
        case humanAttestation = "HumanAttestation"
    }
}

/// Human Attestation - 撮影操作における生体認証の試行結果を記録（フェーズA設計）
/// NOTE: 本人確認や身元証明ではない。生体情報は一切保存しない。
/// NOTE: Verified Capture Mode使用時のみ付与される（通常撮影ではnull）
/// NOTE: フェーズA設計では認証失敗時も撮影を許可し、verified=falseとして記録
struct HumanAttestation: Codable, Sendable {
    /// 認証結果（成功=true, 失敗/キャンセル=false）
    let verified: Bool
    /// 認証方式 (FaceID, TouchID, OpticID, Passcode, None)
    let method: String
    /// 認証試行時刻 (ISO8601)
    let verifiedAt: String
    /// 撮影イベントとの時間差（ミリ秒）
    let captureOffsetMs: Int
    /// 認証と撮影の結合を証明するナンス
    let sessionNonce: String
    
    enum CodingKeys: String, CodingKey {
        case verified = "Verified"
        case method = "Method"
        case verifiedAt = "VerifiedAt"
        case captureOffsetMs = "CaptureOffsetMs"
        case sessionNonce = "SessionNonce"
    }
}

struct KeyAttestation: Codable, Sendable {
    let attestationType: String
    let attestationData: String
    let keyId: String
    
    enum CodingKeys: String, CodingKey {
        case attestationType = "AttestationType"
        case attestationData = "AttestationData"
        case keyId = "KeyID"
    }
}

// MARK: - Sensor Data

struct SensorData: Codable, Sendable {
    let gps: GPSData?
    let accelerometer: [Double]?
    let compass: Double?
    let ambientLight: Double?
    
    enum CodingKeys: String, CodingKey {
        case gps = "GPS"
        case accelerometer = "Accelerometer"
        case compass = "Compass"
        case ambientLight = "AmbientLight"
    }
}

struct GPSData: Codable, Sendable {
    let latitudeHash: String?
    let longitudeHash: String?
    let altitude: Double?
    let accuracy: Double?
    
    enum CodingKeys: String, CodingKey {
        case latitudeHash = "LatitudeHash"
        case longitudeHash = "LongitudeHash"
        case altitude = "Altitude"
        case accuracy = "Accuracy"
    }
}

// MARK: - Camera Settings

struct CameraSettings: Codable, Sendable {
    let focalLength: Double?
    let aperture: Double?
    let iso: Int?
    let exposureTime: Double?
    let flashMode: String?  // OFF, AUTO, ON
    
    enum CodingKeys: String, CodingKey {
        case focalLength = "FocalLength"
        case aperture = "Aperture"
        case iso = "ISO"
        case exposureTime = "ExposureTime"
        case flashMode = "FlashMode"
    }
}

// MARK: - Anchor Record

struct AnchorRecord: Codable, Sendable {
    let anchorId: String
    let anchorType: String
    let merkleRoot: String
    let eventCount: Int
    let firstEventId: String
    let lastEventId: String
    let timestamp: String
    let anchorProof: String?
    let serviceEndpoint: String
    let status: AnchorStatus
    
    enum CodingKeys: String, CodingKey {
        case anchorId = "AnchorID"
        case anchorType = "AnchorType"
        case merkleRoot = "MerkleRoot"
        case eventCount = "EventCount"
        case firstEventId = "FirstEventID"
        case lastEventId = "LastEventID"
        case timestamp = "Timestamp"
        case anchorProof = "AnchorProof"
        case serviceEndpoint = "ServiceEndpoint"
        case status = "Status"
    }
}

enum AnchorStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case completed = "COMPLETED"
    case failed = "FAILED"
}

// MARK: - Proof JSON

// MARK: - Internal Proof JSON (Forensic - Full Data)
// 端末内に暗号化保存、共有不可、デバッグ・法務提出用

struct InternalProofJSON: Codable, Sendable {
    let proofVersion: String
    let proofType: String
    let generatedAt: String
    let generatedBy: String
    let event: CPPEvent
    let anchor: AnchorInfo?
    let verification: VerificationInfo
    let metadata: ProofMetadata
    
    enum CodingKeys: String, CodingKey {
        case proofVersion = "ProofVersion"
        case proofType = "ProofType"
        case generatedAt = "GeneratedAt"
        case generatedBy = "GeneratedBy"
        case event = "Event"
        case anchor = "Anchor"
        case verification = "Verification"
        case metadata = "Metadata"
    }
}

// MARK: - Shareable Proof JSON (Minimal - Privacy-First)
// 第三者検証に必要な最小限のみ、個人特定・追跡要素は除外

struct ShareableProofJSON: Codable, Sendable {
    let proofId: String
    let proofType: String
    let proofVersion: String
    let event: ShareableEventInfo
    let rawEvent: String?  // EventHash検証用の元イベントJSON（Base64エンコード）
    let eventHash: String
    let signature: SignatureInfo
    let publicKey: String  // 署名検証用公開鍵（Base64）
    let timestampProof: TimestampProofInfo?
    let attested: Bool?  // Attested Capture情報（プライバシー保護：詳細は含めずフラグのみ）
    
    enum CodingKeys: String, CodingKey {
        case proofId = "proof_id"
        case proofType = "proof_type"
        case proofVersion = "proof_version"
        case event = "event"
        case rawEvent = "raw_event"
        case eventHash = "event_hash"
        case signature = "signature"
        case publicKey = "public_key"
        case timestampProof = "timestamp_proof"
        case attested = "attested"
    }
}

struct ShareableEventInfo: Codable, Sendable {
    let eventId: String
    let eventType: String
    let timestamp: String
    let assetHash: String
    let cameraSettings: CameraSettings?  // フラッシュモード等の検証表示用
    
    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case eventType = "event_type"
        case timestamp = "timestamp"
        case assetHash = "asset_hash"
        case cameraSettings = "camera_settings"
    }
}

struct SignatureInfo: Codable, Sendable {
    let algo: String
    let value: String
    
    enum CodingKeys: String, CodingKey {
        case algo
        case value
    }
}

struct TimestampProofInfo: Codable, Sendable {
    let type: String
    let issuedAt: String
    let token: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case issuedAt = "issued_at"
        case token
    }
}

// MARK: - Legacy Alias (後方互換性)
typealias ProofJSON = InternalProofJSON

struct AnchorInfo: Codable, Sendable {
    let anchorId: String
    let anchorType: String
    let merkleRoot: String
    let merkleProof: [String]
    let merkleIndex: Int
    let tsaResponse: String?
    let tsaTimestamp: String?
    let tsaService: String
    
    enum CodingKeys: String, CodingKey {
        case anchorId = "AnchorID"
        case anchorType = "AnchorType"
        case merkleRoot = "MerkleRoot"
        case merkleProof = "MerkleProof"
        case merkleIndex = "MerkleIndex"
        case tsaResponse = "TSAResponse"
        case tsaTimestamp = "TSATimestamp"
        case tsaService = "TSAService"
    }
}

struct VerificationInfo: Codable, Sendable {
    let publicKey: String
    let keyAttestation: KeyAttestation
    let verificationEndpoint: String?
    let signer: SignerInfo?  // 署名者情報（フォレンジック用）
    
    enum CodingKeys: String, CodingKey {
        case publicKey = "PublicKey"
        case keyAttestation = "KeyAttestation"
        case verificationEndpoint = "VerificationEndpoint"
        case signer = "Signer"
    }
}

/// 署名者情報（フォレンジックモード用）
struct SignerInfo: Codable, Sendable {
    let name: String           // 署名者名
    let identifier: String?    // 識別子（オプション、Apple IDハッシュ等）
    let attestedAt: String     // 署名時刻
    
    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case identifier = "Identifier"
        case attestedAt = "AttestedAt"
    }
}

struct ProofMetadata: Codable, Sendable {
    let originalFilename: String
    let originalSize: Int
    let thumbnailHash: String?
    let location: LocationInfo?
    
    enum CodingKeys: String, CodingKey {
        case originalFilename = "OriginalFilename"
        case originalSize = "OriginalSize"
        case thumbnailHash = "ThumbnailHash"
        case location = "Location"
    }
}

/// 位置情報（法務用エクスポート時のみ、オプション）
struct LocationInfo: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double?
    let altitude: Double?
    let capturedAt: String
    
    enum CodingKeys: String, CodingKey {
        case latitude = "Latitude"
        case longitude = "Longitude"
        case accuracy = "Accuracy"
        case altitude = "Altitude"
        case capturedAt = "CapturedAt"
    }
}

// MARK: - Media Status (CPP Additional Spec)

/// メディア（画像/動画）の状態
/// 証跡（Event）とは独立して管理される
enum MediaStatus: String, Codable, Sendable {
    case present = "PRESENT"       // メディアが存在する（通常状態）
    case purged = "PURGED"         // ユーザーにより削除された
    case corrupted = "CORRUPTED"   // 破損が検出された
    case migrated = "MIGRATED"     // 外部ストレージに移動された（将来拡張）
    
    var displayName: String {
        switch self {
        case .present: return L10n.MediaStatus.present
        case .purged: return L10n.MediaStatus.purged
        case .corrupted: return L10n.MediaStatus.corrupted
        case .migrated: return L10n.MediaStatus.migrated
        }
    }
    
    var icon: String {
        switch self {
        case .present: return "photo.fill"
        case .purged: return "photo.badge.minus"
        case .corrupted: return "exclamationmark.triangle.fill"
        case .migrated: return "externaldrive.fill"
        }
    }
}

// MARK: - Event Status (CPP Additional Spec)

/// イベント（証跡）の状態
/// Tombstoneにより失効した場合も、イベント自体は削除されない
enum EventStatus: String, Codable, Sendable {
    case active = "ACTIVE"           // 通常の有効状態
    case invalidated = "INVALIDATED" // Tombstoneにより失効
    case superseded = "SUPERSEDED"   // 後続イベントにより置換（将来拡張）
    
    var displayName: String {
        switch self {
        case .active: return L10n.EventStatus.active
        case .invalidated: return L10n.EventStatus.invalidated
        case .superseded: return L10n.EventStatus.superseded
        }
    }
    
    var isValid: Bool {
        self == .active
    }
}

// MARK: - Proof Anchor Status (CPP Additional Spec)

/// TSA外部アンカリングの状態（UI表示用）
enum ProofAnchorStatus: String, Codable, Sendable {
    case pending = "PENDING"     // 外部固定待ち
    case anchored = "ANCHORED"   // 外部固定完了
    case failed = "FAILED"       // 外部固定失敗
    case skipped = "SKIPPED"     // 意図的にスキップ
    
    var displayName: String {
        switch self {
        case .pending: return L10n.AnchorStatusDisplay.pending
        case .anchored: return L10n.AnchorStatusDisplay.anchored
        case .failed: return L10n.AnchorStatusDisplay.failed
        case .skipped: return L10n.AnchorStatusDisplay.skipped
        }
    }
    
    var icon: String {
        switch self {
        case .pending: return "clock.fill"
        case .anchored: return "checkmark.shield.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .skipped: return "minus.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .pending: return "orange"
        case .anchored: return "green"
        case .failed: return "red"
        case .skipped: return "gray"
        }
    }
}

// MARK: - Tombstone Event (CPP Additional Spec)

/// 失効理由コード
enum InvalidationReason: String, Codable, Sendable {
    case userPrivacyRequest = "USER_PRIVACY_REQUEST"
    case userAccidentalCapture = "USER_ACCIDENTAL_CAPTURE"
    case userContentInappropriate = "USER_CONTENT_INAPPROPRIATE"
    case legalCourtOrder = "LEGAL_COURT_ORDER"
    case legalGdprErasure = "LEGAL_GDPR_ERASURE"
    case systemDuplicateDetected = "SYSTEM_DUPLICATE_DETECTED"
    case systemIntegrityCompromised = "SYSTEM_INTEGRITY_COMPROMISED"
    
    var displayName: String {
        switch self {
        case .userPrivacyRequest: return L10n.InvalidationReason.privacy
        case .userAccidentalCapture: return L10n.InvalidationReason.accidental
        case .userContentInappropriate: return L10n.InvalidationReason.inappropriate
        case .legalCourtOrder: return L10n.InvalidationReason.courtOrder
        case .legalGdprErasure: return L10n.InvalidationReason.gdpr
        case .systemDuplicateDetected: return L10n.InvalidationReason.duplicate
        case .systemIntegrityCompromised: return L10n.InvalidationReason.integrity
        }
    }
    
    var isUserInitiated: Bool {
        switch self {
        case .userPrivacyRequest, .userAccidentalCapture, .userContentInappropriate:
            return true
        default:
            return false
        }
    }
}

/// Tombstone（墓石）イベント
/// 証跡の「失効」を記録する特殊イベント
struct TombstoneEvent: Codable, Sendable {
    let tombstoneId: String
    let eventType: String  // Always "TOMBSTONE"
    let timestamp: String
    let target: TombstoneTarget
    let reason: TombstoneReason
    let executor: TombstoneExecutor
    let prevHash: String
    let tombstoneHash: String
    let signature: SignatureInfo
    
    enum CodingKeys: String, CodingKey {
        case tombstoneId = "TombstoneID"
        case eventType = "EventType"
        case timestamp = "Timestamp"
        case target = "Target"
        case reason = "Reason"
        case executor = "Executor"
        case prevHash = "PrevHash"
        case tombstoneHash = "TombstoneHash"
        case signature = "Signature"
    }
}

/// Tombstoneの対象イベント情報
struct TombstoneTarget: Codable, Sendable {
    let eventId: String
    let eventHash: String
    
    enum CodingKeys: String, CodingKey {
        case eventId = "EventID"
        case eventHash = "EventHash"
    }
}

/// Tombstoneの失効理由
struct TombstoneReason: Codable, Sendable {
    let code: String
    let description: String?
    
    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case description = "Description"
    }
}

/// Tombstoneの実行主体
struct TombstoneExecutor: Codable, Sendable {
    let type: String  // "USER" or "SYSTEM"
    let attestation: String?
    
    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case attestation = "Attestation"
    }
}

// MARK: - Extended Event Info (for UI)

/// UI表示用の拡張イベント情報
struct ExtendedEventInfo: Sendable {
    let event: CPPEvent
    let mediaStatus: MediaStatus
    let eventStatus: EventStatus
    let anchorStatus: ProofAnchorStatus
    let tombstone: TombstoneEvent?
    
    var canPurgeMedia: Bool {
        mediaStatus == .present && eventStatus == .active
    }
    
    var canInvalidate: Bool {
        eventStatus == .active
    }
    
    var isFullyVerifiable: Bool {
        mediaStatus == .present && eventStatus == .active && anchorStatus == .anchored
    }
}

// MARK: - Export Models with Tombstone Support

/// Shareable Export Package (第三者検証用 - 最小限)
/// - Tombstone: 存在のみ記録、詳細なし
struct ShareableExportPackage: Codable, Sendable {
    let packageVersion: String
    let packageType: String
    let generatedAt: String
    let events: [ShareableProofJSON]
    let tombstones: [ShareableTombstoneInfo]?
    let chainStatistics: ExportChainStatistics
    
    enum CodingKeys: String, CodingKey {
        case packageVersion = "package_version"
        case packageType = "package_type"
        case generatedAt = "generated_at"
        case events = "events"
        case tombstones = "tombstones"
        case chainStatistics = "chain_statistics"
    }
}

/// Shareable Tombstone Info (第三者検証用 - 最小限)
/// - 削除が改ざんでないことを示すため、存在と理由コード、署名のみ公開
struct ShareableTombstoneInfo: Codable, Sendable {
    let tombstoneId: String
    let targetEventId: String
    let reasonCode: String           // プライバシー保護：詳細テキストは含めない
    let timestamp: String
    let tombstoneHash: String
    let signature: SignatureInfo
    
    enum CodingKeys: String, CodingKey {
        case tombstoneId = "tombstone_id"
        case targetEventId = "target_event_id"
        case reasonCode = "reason_code"
        case timestamp = "timestamp"
        case tombstoneHash = "tombstone_hash"
        case signature = "signature"
    }
    
    /// TombstoneEventからShareableTombstoneInfoを生成
    init(from tombstone: TombstoneEvent) {
        self.tombstoneId = tombstone.tombstoneId
        self.targetEventId = tombstone.target.eventId
        self.reasonCode = tombstone.reason.code
        self.timestamp = tombstone.timestamp
        self.tombstoneHash = tombstone.tombstoneHash
        self.signature = tombstone.signature
    }
}

/// Internal Export Package (法務・監査用 - 完全)
/// - Tombstone: 全情報を含む
struct InternalExportPackage: Codable, Sendable {
    let packageVersion: String
    let packageType: String
    let generatedAt: String
    let generatedBy: String
    let conformanceLevel: String
    let events: [InternalProofJSON]
    let tombstones: [InternalTombstoneInfo]?
    let chainStatistics: ExportChainStatistics
    let chainIntegrity: ChainIntegrityInfo?
    
    enum CodingKeys: String, CodingKey {
        case packageVersion = "PackageVersion"
        case packageType = "PackageType"
        case generatedAt = "GeneratedAt"
        case generatedBy = "GeneratedBy"
        case conformanceLevel = "ConformanceLevel"
        case events = "Events"
        case tombstones = "Tombstones"
        case chainStatistics = "ChainStatistics"
        case chainIntegrity = "ChainIntegrity"
    }
}

/// Internal Tombstone Info (法務・監査用 - 完全)
/// - 全情報を含む：理由テキスト、実行者、承認フロー等
struct InternalTombstoneInfo: Codable, Sendable {
    let tombstoneId: String
    let eventType: String
    let timestamp: String
    let target: TombstoneTarget
    let reason: TombstoneReason
    let executor: TombstoneExecutor
    let prevHash: String
    let tombstoneHash: String
    let signature: SignatureInfo
    
    enum CodingKeys: String, CodingKey {
        case tombstoneId = "TombstoneID"
        case eventType = "EventType"
        case timestamp = "Timestamp"
        case target = "Target"
        case reason = "Reason"
        case executor = "Executor"
        case prevHash = "PrevHash"
        case tombstoneHash = "TombstoneHash"
        case signature = "Signature"
    }
    
    /// TombstoneEventからInternalTombstoneInfoを生成
    init(from tombstone: TombstoneEvent) {
        self.tombstoneId = tombstone.tombstoneId
        self.eventType = tombstone.eventType
        self.timestamp = tombstone.timestamp
        self.target = tombstone.target
        self.reason = tombstone.reason
        self.executor = tombstone.executor
        self.prevHash = tombstone.prevHash
        self.tombstoneHash = tombstone.tombstoneHash
        self.signature = tombstone.signature
    }
}

/// エクスポート用チェーン統計
struct ExportChainStatistics: Codable, Sendable {
    let totalEvents: Int            // イベント総数
    let activeEvents: Int           // 有効イベント数
    let invalidatedEvents: Int      // 失効イベント数
    let tombstoneCount: Int         // Tombstone数
    let anchoredEvents: Int         // 外部固定済み
    let pendingAnchorEvents: Int    // 固定待ち
    let dateRangeStart: String?     // 最古イベント日時
    let dateRangeEnd: String?       // 最新イベント日時
    
    enum CodingKeys: String, CodingKey {
        case totalEvents = "total_events"
        case activeEvents = "active_events"
        case invalidatedEvents = "invalidated_events"
        case tombstoneCount = "tombstone_count"
        case anchoredEvents = "anchored_events"
        case pendingAnchorEvents = "pending_anchor_events"
        case dateRangeStart = "date_range_start"
        case dateRangeEnd = "date_range_end"
    }
}

/// チェーン整合性情報（エクスポート用）
struct ChainIntegrityInfo: Codable, Sendable {
    let isValid: Bool
    let verifiedAt: String
    let checkedEvents: Int
    let checkedTombstones: Int
    let warningCount: Int
    let errorCount: Int
    
    enum CodingKeys: String, CodingKey {
        case isValid = "IsValid"
        case verifiedAt = "VerifiedAt"
        case checkedEvents = "CheckedEvents"
        case checkedTombstones = "CheckedTombstones"
        case warningCount = "WarningCount"
        case errorCount = "ErrorCount"
    }
}

