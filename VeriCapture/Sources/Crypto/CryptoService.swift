//
//  CryptoService.swift
//  VeriCapture
//
//  Secure Enclave Key Management and Signing
//  © 2026 VeritasChain Standards Organization
//

import Foundation
import CryptoKit
import Security

// MARK: - Crypto Service

final class CryptoService: @unchecked Sendable {
    static let shared = CryptoService()
    
    private let keyTag = "org.veritaschain.vericapture.signing.key"
    
    private let lock = NSLock()
    private var _privateKey: SecKey?
    private var _publicKeyData: Data?
    private var _attestationData: String?
    
    private init() {}
    
    // MARK: - Key Initialization
    
    func initializeKey() throws {
        if let existingKey = try? retrieveKey() {
            lock.lock()
            defer { lock.unlock() }
            _privateKey = existingKey
            _publicKeyData = try extractPublicKeyData(from: existingKey)
            _attestationData = getAttestationType()
            print("[CryptoService] Existing key loaded")
            return
        }
        
        let newKey = try generateKey()
        lock.lock()
        defer { lock.unlock() }
        _privateKey = newKey
        _publicKeyData = try extractPublicKeyData(from: newKey)
        _attestationData = getAttestationType()
        print("[CryptoService] New key generated")
    }
    
    // MARK: - Key Generation
    
    private func generateKey() throws -> SecKey {
        var error: Unmanaged<CFError>?
        
        #if targetEnvironment(simulator)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!
            ]
        ]
        #else
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            &error
        ) else {
            throw CryptoError.accessControlCreationFailed(error?.takeRetainedValue())
        }
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
                kSecAttrAccessControl as String: access
            ]
        ]
        #endif
        
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw CryptoError.keyGenerationFailed(error?.takeRetainedValue())
        }
        
        return key
    }
    
    // MARK: - Key Retrieval
    
    private func retrieveKey() throws -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { return nil }
            throw CryptoError.keyRetrievalFailed(status)
        }
        
        return (item as! SecKey)
    }
    
    // MARK: - Public Key Extraction
    
    private func extractPublicKeyData(from privateKey: SecKey) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw CryptoError.publicKeyExtractionFailed
        }
        
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw CryptoError.publicKeyExtractionFailed
        }
        
        return publicKeyData
    }
    
    // MARK: - Signing
    
    func sign(data: Data) throws -> Data {
        lock.lock()
        let key = _privateKey
        lock.unlock()
        
        guard let privateKey = key else {
            throw CryptoError.keyNotInitialized
        }
        
        var error: Unmanaged<CFError>?
        // 注意: .ecdsaSignatureDigestX962SHA256 を使用
        // データは既にSHA-256ハッシュ済みなので、二重ハッシュを避ける
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureDigestX962SHA256,
            data as CFData,
            &error
        ) as Data? else {
            throw CryptoError.signingFailed(error?.takeRetainedValue())
        }
        
        return signature
    }
    
    func signEventHash(_ eventHash: String) throws -> String {
        let hashHex = eventHash.replacingOccurrences(of: "sha256:", with: "")
        guard let hashData = Data(hexString: hashHex) else {
            throw CryptoError.invalidHashFormat
        }
        
        let signature = try sign(data: hashData)
        return "es256:\(signature.base64EncodedString())"
    }
    
    // MARK: - Attestation
    
    private func getAttestationType() -> String {
        #if targetEnvironment(simulator)
        return "SIMULATOR_ATTESTATION"
        #else
        return "APPLE_APP_ATTEST_PLACEHOLDER"
        #endif
    }
    
    // MARK: - Public Accessors
    
    func getPublicKeyBase64() -> String {
        lock.lock()
        defer { lock.unlock() }
        return _publicKeyData?.base64EncodedString() ?? ""
    }
    
    func getKeyId() -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let pubData = _publicKeyData else { return "" }
        return "sha256:\(pubData.sha256Hash)"
    }
    
    func getKeyAttestation() -> KeyAttestation {
        #if targetEnvironment(simulator)
        let attestationType = "SIMULATOR"
        #else
        let attestationType = "APPLE_APP_ATTEST"
        #endif
        
        lock.lock()
        let attestation = _attestationData ?? ""
        lock.unlock()
        
        return KeyAttestation(
            attestationType: attestationType,
            attestationData: attestation,
            keyId: getKeyId()
        )
    }
    
    func getSignAlgorithm() -> String { "ES256" }
}

// MARK: - Crypto Errors

enum CryptoError: LocalizedError, Sendable {
    case accessControlCreationFailed(CFError?)
    case keyGenerationFailed(CFError?)
    case keyRetrievalFailed(OSStatus)
    case keyNotInitialized
    case publicKeyExtractionFailed
    case signingFailed(CFError?)
    case invalidHashFormat
    
    var errorDescription: String? {
        switch self {
        case .accessControlCreationFailed: return "Failed to create access control"
        case .keyGenerationFailed: return "Failed to generate key"
        case .keyRetrievalFailed(let status): return "Failed to retrieve key: \(status)"
        case .keyNotInitialized: return "Key not initialized"
        case .publicKeyExtractionFailed: return "Failed to extract public key"
        case .signingFailed: return "Failed to sign"
        case .invalidHashFormat: return "Invalid hash format"
        }
    }
}
