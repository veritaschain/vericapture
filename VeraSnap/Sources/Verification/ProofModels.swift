//
//  ProofModels.swift
//  VeraSnap
//
//  CPP v1.0 Proof Data Models for Verification
//  © 2026 VeritasChain Standards Organization
//

import Foundation

// MARK: - Unified Proof Protocol (両形式に対応)

protocol VerifiableProof {
    var proofVersion: String { get }
    var proofType: String { get }
    var eventId: String { get }
    var eventType: String { get }
    var timestamp: String { get }
    var assetHash: String { get }
    var eventHash: String { get }
    var signatureAlgo: String { get }
    var signatureValue: String { get }
    var publicKey: String? { get }
    var hasTimestampProof: Bool { get }
    var timestampProofType: String? { get }
    var timestampProofIssuedAt: String? { get }
}

// MARK: - Shareable Proof JSON (snake_case - 共有用)

struct ShareableProofJSONParsed: Codable, Sendable, VerifiableProof {
    let proofId: String
    let proofType: String
    let proofVersion: String
    let event: ShareableEventInfoParsed
    let rawEvent: String?  // EventHash検証用の元イベントJSON（Base64エンコード）
    let eventHash: String
    let signature: SignatureInfoParsed
    let publicKey: String?  // 署名検証用公開鍵
    let timestampProof: TimestampProofInfoParsed?
    let attested: Bool?  // Attested Capture情報
    
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
    
    // VerifiableProof conformance
    var eventId: String { event.eventId }
    var eventType: String { event.eventType }
    var timestamp: String { event.timestamp }
    var assetHash: String { event.assetHash }
    var signatureAlgo: String { signature.algo }
    var signatureValue: String { signature.value }
    // publicKey is now a stored property, not computed
    var hasTimestampProof: Bool { timestampProof != nil }
    var timestampProofType: String? { timestampProof?.type }
    var timestampProofIssuedAt: String? { timestampProof?.issuedAt }
}

struct ShareableEventInfoParsed: Codable, Sendable {
    let eventId: String
    let eventType: String
    let timestamp: String
    let assetHash: String
    let assetType: String?      // v42: VIDEO or IMAGE (optional for backward compat)
    let assetName: String?      // v42: Original filename (optional for backward compat)
    let cameraSettings: CameraSettingsJSON?  // フラッシュモード等の検証表示用
    
    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case eventType = "event_type"
        case timestamp = "timestamp"
        case assetHash = "asset_hash"
        case assetType = "asset_type"
        case assetName = "asset_name"
        case cameraSettings = "camera_settings"
    }
}

struct SignatureInfoParsed: Codable, Sendable {
    let algo: String
    let value: String
}

struct TimestampProofInfoParsed: Codable, Sendable {
    let type: String
    let issuedAt: String
    let token: String
    let merkleRoot: String?          // v42.1
    let tsaService: String?          // v42.1
    
    // v42.2 (CPP v1.2): TSAアンカリング仕様の明確化
    let treeSize: Int?               // ツリーのリーフ数（単発=1）
    let anchorDigest: String?        // TSAに投げた値 (hex)
    let digestAlgorithm: String?     // "sha-256" 固定
    let messageImprint: String?      // TSAから返されたmessageImprint
    
    enum CodingKeys: String, CodingKey {
        case type
        case issuedAt = "issued_at"
        case token
        case merkleRoot = "merkle_root"
        case tsaService = "tsa_service"
        case treeSize = "tree_size"
        case anchorDigest = "anchor_digest"
        case digestAlgorithm = "digest_algorithm"
        case messageImprint = "message_imprint"
    }
    
    /// 単発Merkle検証用
    var isSingleLeafTree: Bool {
        (treeSize ?? 1) == 1
    }
    
    /// CPP v1.2 検証: AnchorDigest == MerkleRoot
    var isAnchorDigestValid: Bool {
        guard let digest = anchorDigest, let root = merkleRoot else { return false }
        let rootHex = root.replacingOccurrences(of: "sha256:", with: "")
        return digest.lowercased() == rootHex.lowercased()
    }
    
    /// CPP v1.2 検証: messageImprint == AnchorDigest
    var isMessageImprintValid: Bool {
        guard let imprint = messageImprint, let digest = anchorDigest else { return false }
        return imprint.lowercased() == digest.lowercased()
    }
}

// MARK: - Root Proof Structure (PascalCase - Internal用)

struct CPPProofJSON: Codable, Sendable {
    let proofVersion: String
    let proofType: String
    let generatedAt: String
    let generatedBy: String
    let event: CPPEventJSON
    let anchor: AnchorInfoJSON?
    let verification: VerificationInfoJSON
    let metadata: ProofMetadataJSON
    
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

// MARK: - CPPEvent for Verification

struct CPPEventJSON: Codable, Sendable {
    let eventID: String
    let chainID: String
    let prevHash: String
    let timestamp: String
    let eventType: String
    let hashAlgo: String
    let signAlgo: String
    let asset: AssetInfoJSON
    let captureContext: CaptureContextJSON
    let sensorData: SensorDataJSON?
    let cameraSettings: CameraSettingsJSON?
    let signerInfo: SignerInfoEventJSON?  // 署名者情報（イベント内、ハッシュ対象）
    let eventHash: String
    let signature: String
    
    enum CodingKeys: String, CodingKey {
        case eventID = "EventID"
        case chainID = "ChainID"
        case prevHash = "PrevHash"
        case timestamp = "Timestamp"
        case eventType = "EventType"
        case hashAlgo = "HashAlgo"
        case signAlgo = "SignAlgo"
        case asset = "Asset"
        case captureContext = "CaptureContext"
        case sensorData = "SensorData"
        case cameraSettings = "CameraSettings"
        case signerInfo = "SignerInfo"
        case eventHash = "EventHash"
        case signature = "Signature"
    }
}

// MARK: - SignerInfo (Event内、ハッシュ対象)

struct SignerInfoEventJSON: Codable, Sendable {
    let name: String
    let identifier: String
    let attestedAt: String
    
    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case identifier = "Identifier"
        case attestedAt = "AttestedAt"
    }
}

// MARK: - AssetInfo

struct AssetInfoJSON: Codable, Sendable {
    let assetID: String
    let assetType: String
    let assetHash: String
    let assetName: String
    let assetSize: Int
    let mimeType: String
    let videoMetadata: VideoMetadataJSON?  // v42: 動画の場合のみ
    
    enum CodingKeys: String, CodingKey {
        case assetID = "AssetID"
        case assetType = "AssetType"
        case assetHash = "AssetHash"
        case assetName = "AssetName"
        case assetSize = "AssetSize"
        case mimeType = "MimeType"
        case videoMetadata = "VideoMetadata"
    }
}

// MARK: - VideoMetadata (v42)

struct VideoMetadataJSON: Codable, Sendable {
    let duration: Double
    let resolution: VideoResolutionJSON
    let frameRate: Double
    let codec: String
    let hasAudio: Bool
    
    enum CodingKeys: String, CodingKey {
        case duration = "Duration"
        case resolution = "Resolution"
        case frameRate = "FrameRate"
        case codec = "Codec"
        case hasAudio = "HasAudio"
    }
}

struct VideoResolutionJSON: Codable, Sendable {
    let width: Int
    let height: Int
    
    enum CodingKeys: String, CodingKey {
        case width = "Width"
        case height = "Height"
    }
}

// MARK: - CaptureContext

struct CaptureContextJSON: Codable, Sendable {
    let deviceID: String
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let keyAttestation: KeyAttestationJSON?
    let humanAttestation: HumanAttestationJSON?
    
    enum CodingKeys: String, CodingKey {
        case deviceID = "DeviceID"
        case deviceModel = "DeviceModel"
        case osVersion = "OSVersion"
        case appVersion = "AppVersion"
        case keyAttestation = "KeyAttestation"
        case humanAttestation = "HumanAttestation"
    }
}

// MARK: - KeyAttestation

struct KeyAttestationJSON: Codable, Sendable {
    let attestationType: String
    let attestationData: String
    let keyID: String
    
    enum CodingKeys: String, CodingKey {
        case attestationType = "AttestationType"
        case attestationData = "AttestationData"
        case keyID = "KeyID"
    }
}

// MARK: - HumanAttestation (Verified Capture Mode)

struct HumanAttestationJSON: Codable, Sendable {
    let verified: Bool
    let method: String
    let verifiedAt: String
    let captureOffsetMs: Int
    let sessionNonce: String
    
    enum CodingKeys: String, CodingKey {
        case verified = "Verified"
        case method = "Method"
        case verifiedAt = "VerifiedAt"
        case captureOffsetMs = "CaptureOffsetMs"
        case sessionNonce = "SessionNonce"
    }
}

// MARK: - SensorData

struct SensorDataJSON: Codable, Sendable {
    let gps: GPSDataJSON?
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

// MARK: - GPSData

struct GPSDataJSON: Codable, Sendable {
    let latitudeHash: String
    let longitudeHash: String
    let altitude: Double?
    let accuracy: Double?
    
    enum CodingKeys: String, CodingKey {
        case latitudeHash = "LatitudeHash"
        case longitudeHash = "LongitudeHash"
        case altitude = "Altitude"
        case accuracy = "Accuracy"
    }
}

// MARK: - CameraSettings

struct CameraSettingsJSON: Codable, Sendable {
    let focalLength: Double?
    let aperture: Double?
    let iso: Int?
    let exposureTime: Double?
    let flashMode: String?
    
    enum CodingKeys: String, CodingKey {
        case focalLength = "FocalLength"
        case aperture = "Aperture"
        case iso = "ISO"
        case exposureTime = "ExposureTime"
        case flashMode = "FlashMode"
    }
}

// MARK: - AnchorInfo
// CPP v1.2: TSAアンカリング仕様の明確化

struct AnchorInfoJSON: Codable, Sendable {
    let anchorID: String
    let anchorType: String
    
    // --- Merkle Tree ---
    let merkleRoot: String
    let merkleProof: [String]
    let merkleIndex: Int
    let treeSize: Int?               // v42.2: ツリーのリーフ数（単発=1）
    
    // --- TSA Anchor ---
    let anchorDigest: String?        // v42.2: TSAに投げた値 (hex)
    let anchorDigestAlgorithm: String?  // v42.2: "sha-256" 固定
    let tsaResponse: String?
    let tsaMessageImprint: String?   // v42.2: TSAから返されたmessageImprint
    let tsaTimestamp: String?
    let tsaService: String?
    
    enum CodingKeys: String, CodingKey {
        case anchorID = "AnchorID"
        case anchorType = "AnchorType"
        case merkleRoot = "MerkleRoot"
        case merkleProof = "MerkleProof"
        case merkleIndex = "MerkleIndex"
        case treeSize = "TreeSize"
        case anchorDigest = "AnchorDigest"
        case anchorDigestAlgorithm = "AnchorDigestAlgorithm"
        case tsaResponse = "TSAResponse"
        case tsaMessageImprint = "TSAMessageImprint"
        case tsaTimestamp = "TSATimestamp"
        case tsaService = "TSAService"
    }
    
    /// 単発Merkle検証: treeSize=1 の場合、MerkleRoot == LeafHash
    var isSingleLeafTree: Bool {
        (treeSize ?? 1) == 1
    }
    
    /// CPP v1.2 検証: AnchorDigest == MerkleRoot
    var isAnchorDigestValid: Bool {
        guard let digest = anchorDigest else { return false }
        let rootHex = merkleRoot.replacingOccurrences(of: "sha256:", with: "")
        return digest.lowercased() == rootHex.lowercased()
    }
    
    /// CPP v1.2 検証: messageImprint == AnchorDigest
    var isMessageImprintValid: Bool {
        guard let imprint = tsaMessageImprint, let digest = anchorDigest else { return false }
        return imprint.lowercased() == digest.lowercased()
    }
}

// MARK: - VerificationInfo

struct VerificationInfoJSON: Codable, Sendable {
    let publicKey: String
    let keyAttestation: KeyAttestationJSON?
    let verificationEndpoint: String?
    let signer: SignerInfoJSON?
    
    enum CodingKeys: String, CodingKey {
        case publicKey = "PublicKey"
        case keyAttestation = "KeyAttestation"
        case verificationEndpoint = "VerificationEndpoint"
        case signer = "Signer"
    }
}

// MARK: - SignerInfo (フォレンジックエクスポート時のみ含まれる)

struct SignerInfoJSON: Codable, Sendable {
    let name: String
    let identifier: String?
    let attestedAt: String
    
    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case identifier = "Identifier"
        case attestedAt = "AttestedAt"
    }
}

// MARK: - ProofMetadata

struct ProofMetadataJSON: Codable, Sendable {
    let originalFilename: String?
    let originalSize: Int?
    let thumbnailHash: String?
    let location: LocationInfoJSON?
    
    enum CodingKeys: String, CodingKey {
        case originalFilename = "OriginalFilename"
        case originalSize = "OriginalSize"
        case thumbnailHash = "ThumbnailHash"
        case location = "Location"
    }
}

// MARK: - LocationInfo (法務用エクスポート時のみ含まれる)

struct LocationInfoJSON: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double?
    let altitude: Double?
    let capturedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case latitude = "Latitude"
        case longitude = "Longitude"
        case accuracy = "Accuracy"
        case altitude = "Altitude"
        case capturedAt = "CapturedAt"
    }
}
