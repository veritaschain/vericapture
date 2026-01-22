//
//  ProofVerificationService.swift
//  VeriCapture
//
//  Main Proof Verification Service
//  © 2026 VeritasChain Standards Organization
//

import Foundation
import Combine

// MARK: - Proof Verification Service

@MainActor
class ProofVerificationService: ObservableObject {
    
    @Published var isVerifying = false
    @Published var currentStep = ""
    @Published var progress: Double = 0.0
    
    private let supportedVersions = ["1.0"]
    
    // MARK: - Main Verification Entry Point
    
    func verify(proofJSON: String, assetData: Data? = nil) async -> VerificationResult {
        isVerifying = true
        progress = 0.0
        
        defer {
            isVerifying = false
            progress = 1.0
        }
        
        var checks: [CheckResult] = []
        
        // Step 1: Parse JSON (両形式を試行)
        currentStep = L10n.Verify.checkStep1
        
        // まずShareable形式（snake_case）を試す
        if let shareableProof = parseShareableProof(proofJSON) {
            return await verifyShareableProof(shareableProof, assetData: assetData)
        }
        
        // 次にInternal形式（PascalCase）を試す
        let proof: CPPProofJSON
        do {
            proof = try parseInternalProof(proofJSON)
            checks.append(CheckResult(
                name: L10n.Verify.checkJsonParse,
                description: L10n.Verify.checkJsonParseDesc,
                passed: true,
                details: "ProofVersion: \(proof.proofVersion)"
            ))
        } catch {
            checks.append(CheckResult(
                name: L10n.Verify.checkJsonParse,
                description: L10n.Verify.checkJsonParseDesc,
                passed: false,
                details: error.localizedDescription
            ))
            return VerificationResult(
                timestamp: Date(),
                overallStatus: .error,
                proof: nil,
                checks: checks,
                errorMessage: error.localizedDescription,
                shareableAttested: nil,
                shareableFlashMode: nil,
                shareableCaptureTimestamp: nil,
                shareableEventId: nil,
                shareableTsaTimestamp: nil,
                shareableTsaService: nil
            )
        }
        
        progress = 0.2
        
        // Step 2: Version Check
        currentStep = L10n.Verify.checkStep2
        
        let versionValid = supportedVersions.contains(proof.proofVersion)
        checks.append(CheckResult(
            name: L10n.Verify.checkVersion,
            description: L10n.Verify.checkVersionDesc,
            passed: versionValid,
            details: versionValid ? "v\(proof.proofVersion) - " + L10n.Verify.checkVersionSupported : "v\(proof.proofVersion) - " + L10n.Verify.checkVersionUnsupported
        ))
        
        progress = 0.3
        
        // Step 3: EventHash Verification
        currentStep = L10n.Verify.checkStep3
        
        let eventHashValid: Bool
        var eventHashDetails: String
        do {
            eventHashValid = try CryptoVerificationService.verifyEventHash(event: proof.event)
            eventHashDetails = eventHashValid ? L10n.Verify.checkHashMatch : L10n.Verify.checkHashMismatch
        } catch {
            eventHashValid = false
            eventHashDetails = L10n.Verify.checkVerificationError(error.localizedDescription)
        }
        
        checks.append(CheckResult(
            name: L10n.Verify.checkEventHashName,
            description: L10n.Verify.checkEventHashDesc,
            passed: eventHashValid,
            details: eventHashDetails
        ))
        
        progress = 0.5
        
        // Step 4: Signature Verification
        currentStep = L10n.Verify.checkStep4
        
        let signatureValid: Bool
        var signatureDetails: String
        do {
            signatureValid = try CryptoVerificationService.verifySignature(
                event: proof.event,
                publicKeyBase64: proof.verification.publicKey
            )
            signatureDetails = signatureValid ? L10n.Verify.checkSignatureValid : L10n.Verify.checkSignatureInvalid
        } catch {
            signatureValid = false
            signatureDetails = L10n.Verify.checkVerificationError(error.localizedDescription)
        }
        
        checks.append(CheckResult(
            name: L10n.Verify.checkSignatureName,
            description: L10n.Verify.checkSignatureDesc,
            passed: signatureValid,
            details: signatureDetails
        ))
        
        progress = 0.7
        
        // Step 5: Asset Hash Verification (if asset provided)
        if let assetData = assetData {
            currentStep = L10n.Verify.checkStepImage
            
            let assetHashValid = CryptoVerificationService.verifyAssetHash(
                assetData: assetData,
                expectedHash: proof.event.asset.assetHash
            )
            
            checks.append(CheckResult(
                name: L10n.Verify.checkImageHashName,
                description: L10n.Verify.checkImageHashDesc,
                passed: assetHashValid,
                details: assetHashValid ? L10n.Verify.checkImageMatch : L10n.Verify.checkImageMismatch
            ))
        } else {
            // 画像未提供 - スキップ（黄色）
            checks.append(CheckResult(
                name: L10n.Verify.checkImageHashName,
                description: L10n.Verify.checkImageHashDesc,
                status: .skipped,
                details: L10n.Verify.checkImageNotProvided
            ))
        }
        
        // Step 6: Anchor Verification (if present)
        if let anchor = proof.anchor {
            currentStep = L10n.Verify.checkStepTsa
            
            let merkleValid = CryptoVerificationService.verifyMerkleProof(
                eventHash: proof.event.eventHash,
                merkleProof: anchor.merkleProof,
                merkleIndex: anchor.merkleIndex,
                expectedRoot: anchor.merkleRoot
            )
            
            checks.append(CheckResult(
                name: L10n.Verify.checkMerkle,
                description: L10n.Verify.checkMerkleDesc,
                passed: merkleValid,
                details: merkleValid ? L10n.Verify.checkMerkleMatch : L10n.Verify.checkMerkleMismatch
            ))
            
            if anchor.tsaResponse != nil {
                checks.append(CheckResult(
                    name: L10n.Verify.checkTsa,
                    description: L10n.Verify.checkTsaDesc,
                    passed: true,
                    details: "TSA: \(anchor.tsaService ?? L10n.Verify.checkUnknown) @ \(anchor.tsaTimestamp ?? L10n.Verify.checkUnknown)"
                ))
            }
        }
        
        progress = 1.0
        
        // Determine overall status
        // スキップは失敗ではない（passedまたはskippedで通過）
        let noFailures = checks.allSatisfy { $0.status != .failed }
        let hasHashMismatch = checks.contains { $0.status == .failed && ($0.name == L10n.Verify.checkImageHashName || $0.name == L10n.Verify.checkEventHashName) }
        let hasSignatureIssue = checks.contains { $0.status == .failed && $0.name == L10n.Verify.checkSignatureName }
        
        let overallStatus: VerificationStatus
        if noFailures {
            overallStatus = proof.anchor != nil ? .anchorVerified : .verified
        } else if hasSignatureIssue {
            overallStatus = .signatureInvalid
        } else if hasHashMismatch {
            overallStatus = .hashMismatch
        } else {
            overallStatus = .error
        }
        
        return VerificationResult(
            timestamp: Date(),
            overallStatus: overallStatus,
            proof: proof,
            checks: checks,
            errorMessage: nil,
            shareableAttested: nil,  // Internal形式ではproof.humanAttestationから取得
            shareableFlashMode: nil,  // Internal形式ではproof.cameraSettingsから取得
            shareableCaptureTimestamp: nil,  // Internal形式ではproofから取得
            shareableEventId: nil,  // Internal形式ではproofから取得
            shareableTsaTimestamp: nil,  // Internal形式ではproof.anchorから取得
            shareableTsaService: nil  // Internal形式ではproof.anchorから取得
        )
    }
    
    // MARK: - Shareable Proof Verification (snake_case形式)
    
    private func verifyShareableProof(_ proof: ShareableProofJSONParsed, assetData: Data?) async -> VerificationResult {
        var checks: [CheckResult] = []
        
        // JSONパース成功
        checks.append(CheckResult(
            name: L10n.Verify.checkJsonParse,
            description: L10n.Verify.checkJsonParseDesc,
            passed: true,
            details: L10n.Verify.checkShareableFormat(proof.proofVersion)
        ))
        
        progress = 0.2
        
        // Version Check
        currentStep = L10n.Verify.checkStep2
        let versionValid = supportedVersions.contains(proof.proofVersion)
        checks.append(CheckResult(
            name: L10n.Verify.checkVersion,
            description: L10n.Verify.checkVersionDesc,
            passed: versionValid,
            details: versionValid ? "v\(proof.proofVersion) - " + L10n.Verify.checkVersionSupported : "v\(proof.proofVersion) - " + L10n.Verify.checkVersionUnsupported
        ))
        
        progress = 0.4
        
        // EventHash検証（rawEventから再計算して検証）
        currentStep = L10n.Verify.checkStep3
        var eventHashValid = false
        var eventHashDetails = ""
        
        if let rawEventBase64 = proof.rawEvent {
            // Base64デコード（改行・空白を無視）
            let cleanedBase64 = rawEventBase64.trimmingCharacters(in: .whitespacesAndNewlines)
            if let rawEventData = Data(base64Encoded: cleanedBase64, options: .ignoreUnknownCharacters) {
                // rawEventからEventHashを再計算
                let computedHash = rawEventData.sha256Prefixed
                eventHashValid = (computedHash == proof.eventHash)
                
                // 追加検証：rawEvent内のフィールドとeventセクションの整合性チェック
                if eventHashValid {
                    // rawEventをデコードしてevent情報と照合
                    if let rawJson = try? JSONSerialization.jsonObject(with: rawEventData) as? [String: Any],
                       let rawAsset = rawJson["Asset"] as? [String: Any],
                       let rawAssetHash = rawAsset["AssetHash"] as? String,
                       let rawEventId = rawJson["EventID"] as? String,
                       let rawTimestamp = rawJson["Timestamp"] as? String {
                        
                        // eventセクションとの整合性検証
                        let assetHashMatch = (rawAssetHash == proof.assetHash)
                        let eventIdMatch = (rawEventId == proof.eventId)
                        let timestampMatch = (rawTimestamp == proof.timestamp)
                        
                        if assetHashMatch && eventIdMatch && timestampMatch {
                            eventHashDetails = L10n.Verify.checkHashMatch
                        } else {
                            eventHashValid = false
                            eventHashDetails = L10n.Verify.checkHashMismatch + " (データ不整合)"
                        }
                    } else {
                        eventHashDetails = L10n.Verify.checkHashMatch
                    }
                } else {
                    eventHashDetails = L10n.Verify.checkHashMismatch
                }
            } else {
                // Base64デコード失敗
                eventHashValid = false
                eventHashDetails = "Base64デコード失敗"
            }
        } else {
            // rawEventがない古い形式：形式チェックのみ（警告付き）
            eventHashValid = !proof.eventHash.isEmpty && proof.eventHash.hasPrefix("sha256:")
            eventHashDetails = eventHashValid ? L10n.Verify.checkHashFormatOk + " (v1.0 - 限定検証)" : L10n.Verify.checkHashFormatInvalid
        }
        
        checks.append(CheckResult(
            name: L10n.Verify.checkEventHashName,
            description: L10n.Verify.checkEventHashDesc,
            passed: eventHashValid,
            details: eventHashDetails
        ))
        
        progress = 0.6
        
        // 署名検証（Shareable形式）
        currentStep = L10n.Verify.checkStep4
        var signatureValid = false
        var signatureDetails = ""
        
        if let pubKey = proof.publicKey, !pubKey.isEmpty {
            // publicKeyがある場合：実際に暗号学的署名検証を実行
            do {
                signatureValid = try CryptoVerificationService.verifyShareableSignature(
                    eventHash: proof.eventHash,
                    signatureValue: proof.signatureValue,
                    publicKeyBase64: pubKey
                )
                signatureDetails = signatureValid ? L10n.Verify.checkSignatureValid : L10n.Verify.checkSignatureInvalid
            } catch {
                signatureValid = false
                signatureDetails = L10n.Verify.checkVerificationError(error.localizedDescription)
            }
        } else {
            // publicKeyがない場合：署名検証不可（警告を表示）
            signatureValid = false
            signatureDetails = L10n.Verify.checkSignatureNoPublicKey
        }
        
        checks.append(CheckResult(
            name: L10n.Verify.checkSignatureName,
            description: L10n.Verify.checkSignatureDesc,
            passed: signatureValid,
            details: signatureDetails
        ))
        
        progress = 0.8
        
        // AssetHash検証
        if let assetData = assetData {
            let assetHashValid = CryptoVerificationService.verifyAssetHash(
                assetData: assetData,
                expectedHash: proof.assetHash
            )
            checks.append(CheckResult(
                name: L10n.Verify.checkImageHashName,
                description: L10n.Verify.checkImageHashDesc,
                passed: assetHashValid,
                details: assetHashValid ? L10n.Verify.checkImageMatch : L10n.Verify.checkImageMismatch
            ))
        } else {
            // 画像未提供 - スキップ（黄色）
            checks.append(CheckResult(
                name: L10n.Verify.checkImageHashName,
                description: L10n.Verify.checkImageHashDesc,
                status: .skipped,
                details: L10n.Verify.checkImageNotProvided
            ))
        }
        
        // TSA検証
        if proof.hasTimestampProof {
            checks.append(CheckResult(
                name: L10n.Verify.checkTsa,
                description: L10n.Verify.checkTsaDesc,
                passed: true,
                details: "\(proof.timestampProofType ?? "RFC3161") @ \(proof.timestampProofIssuedAt ?? L10n.Verify.checkUnknown)"
            ))
        }
        
        progress = 1.0
        
        // Determine overall status (same logic as Internal format)
        // スキップは失敗ではない（passedまたはskippedで通過）
        let noFailures = checks.allSatisfy { $0.status != .failed }
        let hasHashMismatch = checks.contains { $0.status == .failed && ($0.name == L10n.Verify.checkImageHashName || $0.name == L10n.Verify.checkEventHashName) }
        let hasSignatureIssue = checks.contains { $0.status == .failed && $0.name == L10n.Verify.checkSignatureName }
        
        let overallStatus: VerificationStatus
        if noFailures {
            overallStatus = proof.hasTimestampProof ? .anchorVerified : .verified
        } else if hasSignatureIssue {
            overallStatus = .signatureInvalid
        } else if hasHashMismatch {
            overallStatus = .hashMismatch
        } else {
            overallStatus = .error
        }
        
        return VerificationResult(
            timestamp: Date(),
            overallStatus: overallStatus,
            proof: nil, // Shareable形式はCPPProofJSONに変換しない
            checks: checks,
            errorMessage: nil,
            shareableAttested: proof.attested,  // Attestedフラグを渡す
            shareableFlashMode: proof.event.cameraSettings?.flashMode,  // フラッシュモードを渡す
            shareableCaptureTimestamp: proof.event.timestamp,  // 撮影時刻を渡す
            shareableEventId: proof.event.eventId,  // EventIDを渡す
            shareableTsaTimestamp: proof.timestampProofIssuedAt,  // TSAタイムスタンプを渡す
            shareableTsaService: proof.timestampProofType  // TSAサービスタイプを渡す（RFC3161等）
        )
    }
    
    // MARK: - Parse Proof JSON
    
    private func parseShareableProof(_ json: String) -> ShareableProofJSONParsed? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(ShareableProofJSONParsed.self, from: data)
    }
    
    private func parseInternalProof(_ json: String) throws -> CPPProofJSON {
        guard let data = json.data(using: .utf8) else {
            throw ProofParseError.invalidEncoding
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(CPPProofJSON.self, from: data)
    }
}

// MARK: - Proof Parse Errors

enum ProofParseError: Error, LocalizedError {
    case invalidEncoding
    case invalidFormat
    case missingField(String)
    case unsupportedVersion(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidEncoding: return "JSONエンコーディングが不正です"
        case .invalidFormat: return L10n.Verify.errorInvalidFormat
        case .missingField(let field): return "必須フィールドがありません: \(field)"
        case .unsupportedVersion(let version): return "未対応のバージョンです: \(version)"
        }
    }
}
