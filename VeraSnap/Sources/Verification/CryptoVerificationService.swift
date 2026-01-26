//
//  CryptoVerificationService.swift
//  VeraSnap
//
//  Cryptographic Verification Service using CryptoKit + Security Framework
//  © 2026 VeritasChain Standards Organization
//

import Foundation
import CryptoKit
import Security

// MARK: - Crypto Verification Service

class CryptoVerificationService {

    // MARK: - SHA-256 Hashing

    /// Calculate SHA-256 hash of data
    static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Calculate SHA-256 hash of string (UTF-8 encoded)
    static func sha256(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        return sha256(data)
    }

    private static func digestHex<D: Digest>(_ digest: D) -> String {
        digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - JSON Canonicalization (RFC 8785 - JCS)

    /// Canonicalize JSON according to RFC 8785
    static func jcsCanonize(_ object: Any) throws -> String {
        return try canonize(object)
    }

    private static func canonize(_ value: Any) throws -> String {
        switch value {
        case is NSNull:
            return "null"
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            return formatNumber(number)
        case let string as String:
            return escapeString(string)
        case let array as [Any]:
            let elements = try array.map { try canonize($0) }
            return "[" + elements.joined(separator: ",") + "]"
        case let dict as [String: Any]:
            let sortedKeys = dict.keys.sorted()
            let pairs = try sortedKeys.map { key -> String in
                let canonKey = escapeString(key)
                let canonValue = try canonize(dict[key]!)
                return "\(canonKey):\(canonValue)"
            }
            return "{" + pairs.joined(separator: ",") + "}"
        default:
            throw VerifyCryptoError.invalidJSON
        }
    }

    private static func formatNumber(_ number: NSNumber) -> String {
        let doubleValue = number.doubleValue

        if doubleValue.truncatingRemainder(dividingBy: 1) == 0 &&
           doubleValue >= Double(Int64.min) &&
           doubleValue <= Double(Int64.max) {
            return String(Int64(doubleValue))
        }

        return String(doubleValue)
    }

    private static func escapeString(_ string: String) -> String {
        var result = "\""
        for char in string {
            switch char {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if char.asciiValue ?? 0 < 0x20 {
                    result += String(format: "\\u%04x", char.asciiValue ?? 0)
                } else {
                    result.append(char)
                }
            }
        }
        result += "\""
        return result
    }

    // MARK: - EventHash Calculation (Shared)

    static func computeEventHash(event: CPPEventJSON) throws -> String {
        var eventDict = try eventToDictionary(event)
        eventDict.removeValue(forKey: "EventHash")
        eventDict.removeValue(forKey: "Signature")

        let canonicalString = try jcsCanonize(eventDict)
        let canonicalData = canonicalString.data(using: .utf8) ?? Data()
        return "sha256:" + sha256(canonicalData)
    }

    // MARK: - EventHash Verification

    /// Verify EventHash by recalculating from event data
    /// Uses JSONCanonicalizer for consistency with event generation
    static func verifyEventHash(event: CPPEventJSON) throws -> Bool {
        let calculatedHash = try computeEventHash(event: event)
        
        return calculatedHash.lowercased() == event.eventHash.lowercased()
    }

    private static func eventToDictionary(_ event: CPPEventJSON) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VerifyCryptoError.invalidJSON
        }
        return dict
    }

    // MARK: - Signature Verification (ES256 / ECDSA P-256)

    /// Verify ES256 signature
    /// SECURITY FIX: EventHashを再計算してから署名検証を行う
    /// これにより、JSONに書かれているEventHashを改ざんしても検証が失敗する
    static func verifySignature(event: CPPEventJSON, publicKeyBase64: String) throws -> Bool {
        // 1. Decode public key
        guard let publicKeyData = Data(base64Encoded: publicKeyBase64) else {
            throw VerifyCryptoError.invalidPublicKey
        }

        // 2. Parse public key (raw format: 04 + X + Y = 65 bytes)
        let publicKey: P256.Signing.PublicKey
        do {
            if publicKeyData.count == 65 && publicKeyData[0] == 0x04 {
                publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
            } else if publicKeyData.count == 64 {
                var x963Data = Data([0x04])
                x963Data.append(publicKeyData)
                publicKey = try P256.Signing.PublicKey(x963Representation: x963Data)
            } else {
                publicKey = try P256.Signing.PublicKey(derRepresentation: publicKeyData)
            }
        } catch {
            throw VerifyCryptoError.invalidPublicKey
        }

        // 3. Extract signature
        let signatureString = event.signature.replacingOccurrences(of: "es256:", with: "")
        guard let signatureData = Data(base64Encoded: signatureString) else {
            throw VerifyCryptoError.invalidSignature
        }

        // 4. Parse signature (DER or raw format)
        let signature: P256.Signing.ECDSASignature
        do {
            if signatureData.count == 64 {
                signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
            } else {
                signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
            }
        } catch {
            throw VerifyCryptoError.invalidSignature
        }

        // 5. SECURITY FIX: EventHashを再計算（JSONに書かれている値を信用しない）
        // これにより、Eventの内容を改ざんしてEventHashをそのままにしても検証が失敗する
        let recalculatedHash = try computeEventHash(event: event)
        let recalculatedHashHex = recalculatedHash.replacingOccurrences(of: "sha256:", with: "")

        guard let messageHash = Data(verifyHexString: recalculatedHashHex) else {
            throw VerifyCryptoError.invalidHash
        }

        // 6. Use Security framework for reliable verification with pre-computed hash
        return try verifyECDSAWithSecurityFramework(
            publicKey: publicKey,
            signature: signature,
            messageHash: messageHash
        )
    }

    /// Verify ES256 signature for Shareable Proof format
    /// - Parameters:
    ///   - eventHash: The event hash (sha256:xxx format)
    ///   - signatureValue: The signature value (es256:xxx format)
    ///   - publicKeyBase64: The public key in base64 format
    /// - Returns: true if signature is valid
    static func verifyShareableSignature(
        eventHash: String,
        signatureValue: String,
        publicKeyBase64: String
    ) throws -> Bool {
        // 1. Decode public key
        guard let publicKeyData = Data(base64Encoded: publicKeyBase64) else {
            throw VerifyCryptoError.invalidPublicKey
        }

        // 2. Parse public key (raw format: 04 + X + Y = 65 bytes)
        let publicKey: P256.Signing.PublicKey
        do {
            if publicKeyData.count == 65 && publicKeyData[0] == 0x04 {
                publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
            } else if publicKeyData.count == 64 {
                var x963Data = Data([0x04])
                x963Data.append(publicKeyData)
                publicKey = try P256.Signing.PublicKey(x963Representation: x963Data)
            } else {
                publicKey = try P256.Signing.PublicKey(derRepresentation: publicKeyData)
            }
        } catch {
            throw VerifyCryptoError.invalidPublicKey
        }

        // 3. Extract signature (remove es256: prefix)
        let signatureString = signatureValue.replacingOccurrences(of: "es256:", with: "")
        guard let signatureData = Data(base64Encoded: signatureString) else {
            throw VerifyCryptoError.invalidSignature
        }

        // 4. Parse signature (DER or raw format)
        let signature: P256.Signing.ECDSASignature
        do {
            if signatureData.count == 64 {
                signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
            } else {
                signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
            }
        } catch {
            throw VerifyCryptoError.invalidSignature
        }

        // 5. Get message hash (remove sha256: prefix)
        let hashHex = eventHash.replacingOccurrences(of: "sha256:", with: "")
        guard let messageHash = Data(verifyHexString: hashHex), messageHash.count == 32 else {
            throw VerifyCryptoError.invalidHash
        }

        // 6. Use Security framework for reliable verification with pre-computed hash
        return try verifyECDSAWithSecurityFramework(
            publicKey: publicKey,
            signature: signature,
            messageHash: messageHash
        )
    }

    /// Low-level ECDSA signature verification using Security framework
    /// This properly handles pre-computed SHA-256 hashes
    private static func verifyECDSAWithSecurityFramework(
        publicKey: P256.Signing.PublicKey,
        signature: P256.Signing.ECDSASignature,
        messageHash: Data
    ) throws -> Bool {
        // Convert CryptoKit public key to SecKey
        let x963Data = publicKey.x963Representation

        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(x963Data as CFData, keyAttributes as CFDictionary, &error) else {
            throw VerifyCryptoError.invalidPublicKey
        }

        // Get signature in DER format (Security framework expects DER)
        let derSignature = signature.derRepresentation

        // CRITICAL: Use kSecKeyAlgorithmECDSASignatureDigestX962SHA256
        // This tells Security framework that we're providing a PRE-COMPUTED SHA-256 hash
        // NOT the original message
        let algorithm = SecKeyAlgorithm.ecdsaSignatureDigestX962SHA256

        guard SecKeyIsAlgorithmSupported(secKey, .verify, algorithm) else {
            throw VerifyCryptoError.verificationFailed
        }

        // Verify: messageHash is the SHA-256 digest, signature is DER-encoded
        let isValid = SecKeyVerifySignature(
            secKey,
            algorithm,
            messageHash as CFData,  // Pre-computed SHA-256 hash
            derSignature as CFData,  // DER-encoded signature
            &error
        )

        return isValid
    }

    // MARK: - Asset Hash Verification

    /// Verify asset (image) hash
    static func verifyAssetHash(assetData: Data, expectedHash: String) -> Bool {
        let calculatedHash = "sha256:" + sha256(assetData)
        return calculatedHash.lowercased() == expectedHash.lowercased()
    }

    // MARK: - Merkle Proof Verification

    /// Verify Merkle proof
    /// CPP v1.2: 単発Merkleルールを明確化
    /// - treeSize=1 の場合: MerkleRoot == LeafHash (EventHash) であること
    /// - treeSize>1 の場合: MerkleProofを使用して検証
    static func verifyMerkleProof(
        eventHash: String,
        merkleProof: [String],
        merkleIndex: Int,
        expectedRoot: String,
        treeSize: Int = 1
    ) -> Bool {
        // EventHashからLeafHashを計算
        let eventHashData = Data(verifyHexString: eventHash.replacingOccurrences(of: "sha256:", with: "")) ?? Data()
        let leafHash = "sha256:" + digestHex(SHA256.hash(data: eventHashData))

        // 単発Merkle検証（CPP v1.2）
        if treeSize == 1 && merkleProof.isEmpty && merkleIndex == 0 {
            // 単発の場合: MerkleRoot == LeafHash == SHA256(EventHash)
            let leafHex = leafHash.replacingOccurrences(of: "sha256:", with: "").lowercased()
            let rootHex = expectedRoot.replacingOccurrences(of: "sha256:", with: "").lowercased()
            return leafHex == rootHex
        }

        // バッチMerkle検証（通常のProof検証）
        // 開始点はLeafHash（EventHashではない）
        var currentHash = leafHash.replacingOccurrences(of: "sha256:", with: "")
        var index = merkleIndex

        for siblingHash in merkleProof {
            let sibling = siblingHash.replacingOccurrences(of: "sha256:", with: "")

            // 現在のノードが左(偶数)か右(奇数)かでconcatの順序を決定
            var combined = Data()
            if index % 2 == 0 {
                // 現在は左、兄弟は右
                combined.append(Data(verifyHexString: currentHash) ?? Data())
                combined.append(Data(verifyHexString: sibling) ?? Data())
            } else {
                // 現在は右、兄弟は左
                combined.append(Data(verifyHexString: sibling) ?? Data())
                combined.append(Data(verifyHexString: currentHash) ?? Data())
            }
            currentHash = digestHex(SHA256.hash(data: combined))
            index = index / 2
        }

        let calculatedRoot = "sha256:" + currentHash
        return calculatedRoot.lowercased() == expectedRoot.lowercased()
    }

    // MARK: - TSA Anchor Verification (CPP v1.2)

    /// TSAアンカー検証結果
    enum TSAVerificationResult {
        case valid(genTime: String?)
        case invalid(reason: String)
        case warning(message: String, genTime: String?)
        case notVerifiable(reason: String)
    }

    /// TSAアンカー完全検証
    /// CPP v1.2 必須要件:
    /// 1. TSAに投げる値は AnchorDigest のみ
    /// 2. AnchorDigest は MerkleRoot と一致
    /// 3. TSAResponse の messageImprint.hashedMessage は AnchorDigest と一致
    static func verifyTSAAnchor(
        eventHash: String,
        anchor: AnchorInfoJSON
    ) -> TSAVerificationResult {

        // Step 1: Merkle検証
        let treeSize = anchor.treeSize ?? 1

        // EventHashからLeafHashを計算
        let eventHashData = Data(verifyHexString: eventHash.replacingOccurrences(of: "sha256:", with: "")) ?? Data()
        let leafHash = "sha256:" + digestHex(SHA256.hash(data: eventHashData))

        if treeSize == 1 {
            // 単発: MerkleRoot == LeafHash == SHA256(EventHash)
            let leafHex = leafHash.replacingOccurrences(of: "sha256:", with: "").lowercased()
            let rootHex = anchor.merkleRoot.replacingOccurrences(of: "sha256:", with: "").lowercased()

            if leafHex != rootHex {
                return .invalid(reason: "Single-leaf Merkle: MerkleRoot != SHA256(EventHash)")
            }
        } else {
            // バッチ: MerkleProof検証
            if !verifyMerkleProof(
                eventHash: eventHash,
                merkleProof: anchor.merkleProof,
                merkleIndex: anchor.merkleIndex,
                expectedRoot: anchor.merkleRoot,
                treeSize: treeSize
            ) {
                return .invalid(reason: "Merkle proof verification failed")
            }
        }

        // Step 2: AnchorDigest検証
        if let anchorDigest = anchor.anchorDigest {
            let rootHex = anchor.merkleRoot.replacingOccurrences(of: "sha256:", with: "").lowercased()
            if anchorDigest.lowercased() != rootHex {
                return .invalid(reason: "AnchorDigest != MerkleRoot")
            }
        }

        // Step 3: TSAResponse存在確認
        guard let tsaToken = anchor.tsaResponse, !tsaToken.isEmpty else {
            return .notVerifiable(reason: "TSAResponse missing")
        }

        // Step 4: messageImprint検証（v42.2以降のProofのみ）
        if let messageImprint = anchor.tsaMessageImprint {
            let anchorDigest = anchor.anchorDigest ?? anchor.merkleRoot.replacingOccurrences(of: "sha256:", with: "")

            if messageImprint.lowercased() != anchorDigest.lowercased() {
                return .invalid(reason: "TSA messageImprint != AnchorDigest")
            }

            // 完全検証成功
            return .valid(genTime: anchor.tsaTimestamp)
        }

        // v42.1以前のProof: messageImprint未保存の場合は警告付きで通過
        return .warning(
            message: "TSA timestamp claimed but messageImprint not stored (pre-v42.2 proof)",
            genTime: anchor.tsaTimestamp
        )
    }
}

// MARK: - Custom SHA256 Digest Wrapper (kept for compatibility)

struct VerifySHA256Digest: Digest {
    static var byteCount: Int = 32

    private let bytes: [UInt8]

    init(_ data: Data) {
        self.bytes = Array(data)
    }

    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }

    var description: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bytes)
    }

    static func == (lhs: VerifySHA256Digest, rhs: VerifySHA256Digest) -> Bool {
        lhs.bytes == rhs.bytes
    }
}

// MARK: - Crypto Errors

enum VerifyCryptoError: Error, LocalizedError {
    case invalidJSON
    case invalidPublicKey
    case invalidSignature
    case invalidHash
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "JSONの形式が不正です"
        case .invalidPublicKey: return "公開鍵の形式が不正です"
        case .invalidSignature: return "署名の形式が不正です"
        case .invalidHash: return "ハッシュ値の形式が不正です"
        case .verificationFailed: return "検証に失敗しました"
        }
    }
}

// MARK: - Data Extensions for Verification

extension Data {
    init?(verifyHexString: String) {
        let hex = verifyHexString.dropFirst(verifyHexString.hasPrefix("0x") ? 2 : 0)
        guard hex.count % 2 == 0 else { return nil }

        var data = Data()
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }

    var verifyHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
