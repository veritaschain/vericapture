//
//  TSAVerificationPolicy.swift
//  VeriCapture
//
//  Certificate Rotation Resilient Verification Policy
//  v36.0 - TSA Redundancy Architecture
//  © 2026 VeritasChain Standards Organization
//

import Foundation

// MARK: - TSA Verification Policy

/// Certificate Rotation Resilient Verification Policy
/// 
/// Implements a 2-layer verification approach:
/// - Layer 1: Cryptographic verification (MANDATORY)
/// - Layer 2: Chain verification (CONFIGURABLE - warning only by default)
struct TSAVerificationPolicy: Codable, Sendable {
    
    // Layer 1: Always required (not configurable)
    // - MessageImprint hash match
    // - TST signature validity
    // - Certificate validity at timestamp time (NOT current time)
    
    /// CA chain verification behavior
    let chainVerificationMode: ChainVerificationMode
    
    /// OCSP/CRL revocation check behavior
    let revocationCheckMode: RevocationCheckMode
    
    enum ChainVerificationMode: String, Codable, Sendable {
        case required = "REQUIRED"      // Fail if chain invalid
        case warnOnly = "WARN_ONLY"     // Log warning, continue
        case skip = "SKIP"              // Don't check
    }
    
    enum RevocationCheckMode: String, Codable, Sendable {
        case required = "REQUIRED"
        case bestEffort = "BEST_EFFORT" // Try, but continue on failure
        case skip = "SKIP"
    }
    
    /// Default policy: Crypto mandatory, chain verification as warning
    static func defaultPolicy() -> TSAVerificationPolicy {
        TSAVerificationPolicy(
            chainVerificationMode: .warnOnly,
            revocationCheckMode: .bestEffort
        )
    }
    
    /// Strict policy: All verifications required
    static func strictPolicy() -> TSAVerificationPolicy {
        TSAVerificationPolicy(
            chainVerificationMode: .required,
            revocationCheckMode: .required
        )
    }
    
    /// Permissive policy: Crypto only (for certificate rotation scenarios)
    static func permissivePolicy() -> TSAVerificationPolicy {
        TSAVerificationPolicy(
            chainVerificationMode: .skip,
            revocationCheckMode: .skip
        )
    }
}

// MARK: - Verification Result

/// TSA Verification Result with Layer Details
struct TSAVerificationResult: Sendable {
    let overallStatus: TSAVerificationStatus
    
    // Layer 1: Mandatory Checks
    let messageImprintValid: Bool
    let signatureValid: Bool
    let certificateValidAtTimestamp: Bool
    
    // Layer 2: Optional Checks
    let chainVerificationResult: ChainResult?
    let revocationCheckResult: RevocationResult?
    
    // Metadata
    let timestampTime: Date?
    let tsaCertificateSubject: String?
    let warnings: [VerificationWarning]
    
    enum ChainResult: Sendable {
        case valid
        case invalid(reason: String)
        case skipped
        case networkError(String)
    }
    
    enum RevocationResult: Sendable {
        case notRevoked
        case revoked(reason: String)
        case unknown
        case skipped
        case networkError(String)
    }
    
    struct VerificationWarning: Sendable {
        let code: String
        let message: String
        let recommendation: String?
    }
    
    /// Convenience initializer for successful verification
    static func success(
        timestampTime: Date,
        tsaCertificateSubject: String,
        warnings: [VerificationWarning] = []
    ) -> TSAVerificationResult {
        TSAVerificationResult(
            overallStatus: warnings.isEmpty ? .verified : .verifiedWithWarnings,
            messageImprintValid: true,
            signatureValid: true,
            certificateValidAtTimestamp: true,
            chainVerificationResult: .valid,
            revocationCheckResult: .notRevoked,
            timestampTime: timestampTime,
            tsaCertificateSubject: tsaCertificateSubject,
            warnings: warnings
        )
    }
    
    /// Convenience initializer for failure
    static func failure(status: TSAVerificationStatus, reason: String) -> TSAVerificationResult {
        TSAVerificationResult(
            overallStatus: status,
            messageImprintValid: status != .tampered,
            signatureValid: status != .signatureInvalid,
            certificateValidAtTimestamp: status != .certificateExpiredAtTimestamp,
            chainVerificationResult: nil,
            revocationCheckResult: nil,
            timestampTime: nil,
            tsaCertificateSubject: nil,
            warnings: [VerificationWarning(code: "FAILURE", message: reason, recommendation: nil)]
        )
    }
}

// MARK: - Verification Status

enum TSAVerificationStatus: String, Codable, Sendable {
    case verified = "VERIFIED"
    case verifiedWithWarnings = "VERIFIED_WITH_WARNINGS"
    case tampered = "TAMPERED"
    case signatureInvalid = "SIGNATURE_INVALID"
    case certificateExpiredAtTimestamp = "CERT_EXPIRED_AT_TIMESTAMP"
    case chainVerificationFailed = "CHAIN_VERIFICATION_FAILED"
    case certificateRevoked = "CERTIFICATE_REVOKED"
    case error = "ERROR"
    
    var isValid: Bool {
        switch self {
        case .verified, .verifiedWithWarnings:
            return true
        default:
            return false
        }
    }
    
    var localizedDescription: String {
        switch self {
        case .verified:
            return "Timestamp verified"
        case .verifiedWithWarnings:
            return "Timestamp verified with warnings"
        case .tampered:
            return "Data tampering detected"
        case .signatureInvalid:
            return "Invalid timestamp signature"
        case .certificateExpiredAtTimestamp:
            return "Certificate was expired when timestamp was issued"
        case .chainVerificationFailed:
            return "Certificate chain verification failed"
        case .certificateRevoked:
            return "TSA certificate has been revoked"
        case .error:
            return "Verification error"
        }
    }
}

// MARK: - TSA Verification Service Extension

extension ProofVerificationService {
    
    /// Verify TSA timestamp with certificate rotation resilience
    /// 
    /// CRITICAL: Certificate validity is checked at TIMESTAMP TIME, not current time.
    /// This ensures that timestamps remain verifiable even after TSA certificates rotate.
    func verifyTSATimestamp(
        token: Data,
        expectedHash: String,
        policy: TSAVerificationPolicy? = nil
    ) -> TSAVerificationResult {
        let policy = policy ?? TSAVerificationPolicy.defaultPolicy()
        var warnings: [TSAVerificationResult.VerificationWarning] = []
        
        // Parse TST (TimeStampToken)
        guard let tstInfo = parseTSTInfo(from: token) else {
            return .failure(status: .error, reason: "Failed to parse TimeStampToken")
        }
        
        // ─────────────────────────────────────────────────────────
        // LAYER 1: MANDATORY CRYPTOGRAPHIC VERIFICATION
        // ─────────────────────────────────────────────────────────
        
        // 1. Verify MessageImprint
        let expectedHashData = Data(hexString: expectedHash.replacingOccurrences(of: "sha256:", with: "")) ?? Data()
        let messageImprintValid = tstInfo.messageImprint == expectedHashData
        
        guard messageImprintValid else {
            return TSAVerificationResult(
                overallStatus: .tampered,
                messageImprintValid: false,
                signatureValid: false,
                certificateValidAtTimestamp: false,
                chainVerificationResult: nil,
                revocationCheckResult: nil,
                timestampTime: tstInfo.genTime,
                tsaCertificateSubject: tstInfo.tsaCertSubject,
                warnings: []
            )
        }
        
        // 2. Verify TST Signature
        let signatureValid = verifyTSTSignature(token: token, tstInfo: tstInfo)
        
        guard signatureValid else {
            return TSAVerificationResult(
                overallStatus: .signatureInvalid,
                messageImprintValid: true,
                signatureValid: false,
                certificateValidAtTimestamp: false,
                chainVerificationResult: nil,
                revocationCheckResult: nil,
                timestampTime: tstInfo.genTime,
                tsaCertificateSubject: tstInfo.tsaCertSubject,
                warnings: []
            )
        }
        
        // 3. Verify Certificate Validity AT TIMESTAMP TIME (not current time!)
        // CRITICAL: This is the key insight for certificate rotation resilience
        let certValidAtTimestamp = verifyCertificateValidityAtTime(
            certificate: tstInfo.tsaCertificate,
            atTime: tstInfo.genTime
        )
        
        guard certValidAtTimestamp else {
            return TSAVerificationResult(
                overallStatus: .certificateExpiredAtTimestamp,
                messageImprintValid: true,
                signatureValid: true,
                certificateValidAtTimestamp: false,
                chainVerificationResult: nil,
                revocationCheckResult: nil,
                timestampTime: tstInfo.genTime,
                tsaCertificateSubject: tstInfo.tsaCertSubject,
                warnings: []
            )
        }
        
        // ─────────────────────────────────────────────────────────
        // LAYER 2: OPTIONAL CHAIN VERIFICATION
        // ─────────────────────────────────────────────────────────
        
        var chainResult: TSAVerificationResult.ChainResult? = nil
        
        switch policy.chainVerificationMode {
        case .required:
            let result = verifyCertificateChain(tstInfo.tsaCertificate)
            chainResult = result
            if case .invalid(let reason) = result {
                return TSAVerificationResult(
                    overallStatus: .chainVerificationFailed,
                    messageImprintValid: true,
                    signatureValid: true,
                    certificateValidAtTimestamp: true,
                    chainVerificationResult: result,
                    revocationCheckResult: nil,
                    timestampTime: tstInfo.genTime,
                    tsaCertificateSubject: tstInfo.tsaCertSubject,
                    warnings: [.init(code: "CHAIN_FAILED", message: reason, recommendation: nil)]
                )
            }
            
        case .warnOnly:
            let result = verifyCertificateChain(tstInfo.tsaCertificate)
            chainResult = result
            if case .invalid(let reason) = result {
                warnings.append(.init(
                    code: "CHAIN_VERIFICATION_WARNING",
                    message: "Certificate chain verification failed: \(reason)",
                    recommendation: "This may occur after TSA certificate rotation. Core cryptographic verification passed."
                ))
            }
            
        case .skip:
            chainResult = .skipped
        }
        
        // Revocation check
        var revocationResult: TSAVerificationResult.RevocationResult? = nil
        
        switch policy.revocationCheckMode {
        case .required:
            revocationResult = checkRevocationStatus(tstInfo.tsaCertificate)
            if case .revoked(let reason) = revocationResult {
                return TSAVerificationResult(
                    overallStatus: .certificateRevoked,
                    messageImprintValid: true,
                    signatureValid: true,
                    certificateValidAtTimestamp: true,
                    chainVerificationResult: chainResult,
                    revocationCheckResult: revocationResult,
                    timestampTime: tstInfo.genTime,
                    tsaCertificateSubject: tstInfo.tsaCertSubject,
                    warnings: [.init(code: "REVOKED", message: reason, recommendation: nil)]
                )
            }
            
        case .bestEffort:
            revocationResult = checkRevocationStatus(tstInfo.tsaCertificate)
            if case .networkError(let error) = revocationResult {
                warnings.append(.init(
                    code: "REVOCATION_CHECK_SKIPPED",
                    message: "Could not check revocation status: \(error)",
                    recommendation: nil
                ))
            }
            
        case .skip:
            revocationResult = .skipped
        }
        
        // ─────────────────────────────────────────────────────────
        // SUCCESS
        // ─────────────────────────────────────────────────────────
        
        return TSAVerificationResult(
            overallStatus: warnings.isEmpty ? .verified : .verifiedWithWarnings,
            messageImprintValid: true,
            signatureValid: true,
            certificateValidAtTimestamp: true,
            chainVerificationResult: chainResult,
            revocationCheckResult: revocationResult,
            timestampTime: tstInfo.genTime,
            tsaCertificateSubject: tstInfo.tsaCertSubject,
            warnings: warnings
        )
    }
    
    // MARK: - Private Helpers
    
    /// Parse TST Info from token
    private func parseTSTInfo(from token: Data) -> TSTInfo? {
        // Simplified parsing - in production, use proper ASN.1 parser
        // For now, return a basic structure for testing
        guard token.count > 50 else { return nil }
        
        return TSTInfo(
            messageImprint: Data(), // Would be extracted from ASN.1
            genTime: Date(),
            tsaCertificate: Data(),
            tsaCertSubject: "Unknown TSA"
        )
    }
    
    /// Verify TST signature
    private func verifyTSTSignature(token: Data, tstInfo: TSTInfo) -> Bool {
        // In production, verify the CMS signature
        // For now, return true if token is present
        return token.count > 0
    }
    
    /// CRITICAL: Certificate validity check must use TIMESTAMP TIME, not current time
    private func verifyCertificateValidityAtTime(
        certificate: Data,
        atTime: Date
    ) -> Bool {
        // In production, parse certificate and check:
        // cert.notBefore <= atTime && atTime <= cert.notAfter
        // For now, assume valid
        return true
    }
    
    /// Verify certificate chain
    private func verifyCertificateChain(_ certificate: Data) -> TSAVerificationResult.ChainResult {
        // In production, verify chain to trusted root
        // For now, return valid
        return .valid
    }
    
    /// Check revocation status
    private func checkRevocationStatus(_ certificate: Data) -> TSAVerificationResult.RevocationResult {
        // In production, check OCSP/CRL
        // For now, return not revoked
        return .notRevoked
    }
}

// MARK: - TST Info Structure

struct TSTInfo {
    let messageImprint: Data
    let genTime: Date
    let tsaCertificate: Data
    let tsaCertSubject: String
}
