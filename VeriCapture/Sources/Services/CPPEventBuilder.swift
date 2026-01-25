//
//  CPPEventBuilder.swift
//  VeriCapture
//
//  CPP v1.0 INGEST Event Builder
//  © 2026 VeritasChain Standards Organization
//

import Foundation

// MARK: - CPP Event Builder

@MainActor
final class CPPEventBuilder {
    
    /// 通常の撮影イベントを生成（署名者情報なし）
    func buildIngestEvent(from captureResult: CaptureResult, chainId: String) throws -> CPPEvent {
        return try buildIngestEvent(from: captureResult, chainId: chainId, humanAttestation: nil, signerName: nil)
    }
    
    /// Verified Capture Mode: 認証情報を含む撮影イベントを生成（署名者情報なし）
    func buildIngestEvent(
        from captureResult: CaptureResult,
        chainId: String,
        humanAttestation: HumanAttestation?
    ) throws -> CPPEvent {
        return try buildIngestEvent(from: captureResult, chainId: chainId, humanAttestation: humanAttestation, signerName: nil)
    }
    
    /// フル機能: 認証情報と署名者情報を含む撮影イベントを生成
    /// - Parameters:
    ///   - captureResult: 撮影結果
    ///   - chainId: チェーンID
    ///   - humanAttestation: 人間認証情報（Verified Capture Mode用）
    ///   - signerName: 署名者名（監査用 - EventHashに含まれる）
    func buildIngestEvent(
        from captureResult: CaptureResult,
        chainId: String,
        humanAttestation: HumanAttestation?,
        signerName: String?
    ) throws -> CPPEvent {
        
        let prevHash = try getPreviousHash(chainId: chainId)
        let eventId = UUIDv7.generate()
        let assetId = "urn:cpp:asset:vericapture:\(UUIDv7.generate())"
        
        let asset = Asset(
            assetId: assetId,
            assetType: .image,
            assetHash: captureResult.assetHash,
            assetName: captureResult.filename,
            assetSize: captureResult.assetSize,
            mimeType: captureResult.mimeType,
            videoMetadata: nil
        )
        
        let captureContext = CaptureContext(
            deviceId: DeviceInfo.deviceId,
            deviceModel: DeviceInfo.deviceModel,
            osVersion: DeviceInfo.osVersion,
            appVersion: DeviceInfo.appVersion,
            keyAttestation: CryptoService.shared.getKeyAttestation(),
            humanAttestation: humanAttestation
        )
        
        // 署名者情報を生成（設定されている場合のみ）
        let signerInfo: SignerInfo?
        if let name = signerName, !name.isEmpty {
            signerInfo = SignerInfo(
                name: name,
                identifier: DeviceInfo.deviceId,  // デバイスIDを識別子として使用
                attestedAt: captureResult.captureTimestamp.iso8601String
            )
        } else {
            signerInfo = nil
        }
        
        var event = CPPEvent(
            eventId: eventId,
            chainId: chainId,
            prevHash: prevHash,
            timestamp: captureResult.captureTimestamp.iso8601String,
            eventType: .ingest,
            hashAlgo: "SHA256",
            signAlgo: CryptoService.shared.getSignAlgorithm(),
            asset: asset,
            captureContext: captureContext,
            sensorData: captureResult.sensorData,
            cameraSettings: captureResult.cameraSettings,
            signerInfo: signerInfo,
            eventHash: "",
            signature: ""
        )
        
        let eventHash = try computeEventHash(event: event)
        event.eventHash = eventHash
        
        let signature = try CryptoService.shared.signEventHash(eventHash)
        event.signature = signature
        
        return event
    }
    
    // MARK: - Video Event Builder
    
    /// 動画録画イベントを生成
    func buildVideoIngestEvent(
        from videoResult: VideoCaptureResult,
        chainId: String,
        humanAttestation: HumanAttestation? = nil,
        signerName: String? = nil
    ) throws -> CPPEvent {
        
        let prevHash = try getPreviousHash(chainId: chainId)
        let eventId = UUIDv7.generate()
        let assetId = "urn:cpp:asset:vericapture:\(UUIDv7.generate())"
        
        // 動画メタデータ
        let videoMetadata = VideoMetadata(
            duration: videoResult.duration,
            resolution: videoResult.resolution,
            frameRate: videoResult.frameRate,
            codec: videoResult.codec,
            hasAudio: videoResult.hasAudio
        )
        
        let asset = Asset(
            assetId: assetId,
            assetType: .video,
            assetHash: videoResult.assetHash,
            assetName: videoResult.filename,
            assetSize: videoResult.fileSize,
            mimeType: videoResult.mimeType,
            videoMetadata: videoMetadata
        )
        
        let captureContext = CaptureContext(
            deviceId: DeviceInfo.deviceId,
            deviceModel: DeviceInfo.deviceModel,
            osVersion: DeviceInfo.osVersion,
            appVersion: DeviceInfo.appVersion,
            keyAttestation: CryptoService.shared.getKeyAttestation(),
            humanAttestation: humanAttestation
        )
        
        // 署名者情報を生成（設定されている場合のみ）
        let signerInfo: SignerInfo?
        if let name = signerName, !name.isEmpty {
            signerInfo = SignerInfo(
                name: name,
                identifier: DeviceInfo.deviceId,
                attestedAt: videoResult.captureTimestamp.iso8601String
            )
        } else {
            signerInfo = nil
        }
        
        var event = CPPEvent(
            eventId: eventId,
            chainId: chainId,
            prevHash: prevHash,
            timestamp: videoResult.captureTimestamp.iso8601String,
            eventType: .ingest,
            hashAlgo: "SHA256",
            signAlgo: CryptoService.shared.getSignAlgorithm(),
            asset: asset,
            captureContext: captureContext,
            sensorData: videoResult.sensorData,
            cameraSettings: videoResult.cameraSettings,
            signerInfo: signerInfo,
            eventHash: "",
            signature: ""
        )
        
        let eventHash = try computeEventHash(event: event)
        event.eventHash = eventHash
        
        let signature = try CryptoService.shared.signEventHash(eventHash)
        event.signature = signature
        
        return event
    }
    
    /// HumanAttestationを生成（フェーズA設計）
    /// - 認証を試行した場合は成功/失敗どちらでも生成
    /// - 認証を試行していない場合（非対応デバイス等）はnilを返す
    func buildHumanAttestation(
        from authResult: BiometricAuthService.VerifiedCaptureAuthResult,
        captureTimestamp: Date
    ) -> HumanAttestation? {
        // 認証を試行していない場合はnull
        guard authResult.attempted else { return nil }
        
        // 認証時刻と撮影時刻の差をミリ秒で計算
        let offsetMs = Int((captureTimestamp.timeIntervalSince(authResult.attemptedAt)) * 1000)
        
        // 認証成功/失敗どちらでもHumanAttestationを生成（フェーズA）
        return HumanAttestation(
            verified: authResult.success,  // true または false
            method: authResult.method,
            verifiedAt: authResult.attemptedAt.iso8601String,
            captureOffsetMs: offsetMs,
            sessionNonce: authResult.sessionNonce
        )
    }
    
    private func computeEventHash(event: CPPEvent) throws -> String {
        var dict = try eventToDictionary(event)
        dict.removeValue(forKey: "Signature")
        dict.removeValue(forKey: "EventHash")
        
        let canonicalData = try JSONCanonicalizer.canonicalize(dict)
        return canonicalData.sha256Prefixed
    }
    
    private func eventToDictionary(_ event: CPPEvent) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CPPEventError.serializationFailed
        }
        
        return dict
    }
    
    private func getPreviousHash(chainId: String) throws -> String {
        // chainIdに関係なく、最新のイベントのハッシュを取得
        // （1デバイス = 1チェーンなので、chainIdでのフィルタは不要）
        if let lastEvent = try StorageService.shared.getLastEventAny() {
            return lastEvent.eventHash
        }
        // チェーンの最初のイベント（GENESIS）
        return "GENESIS"
    }
    
    func generateProofJSON(event: CPPEvent, anchor: AnchorRecord?, locationInfo: LocationInfo? = nil, signerName: String? = nil) -> ProofJSON {
        
        var anchorInfo: AnchorInfo? = nil
        
        if let anchor = anchor, anchor.status == .completed {
            // TSAToken (TimeStampToken) をbase64エンコード
            let tsaTokenBase64 = anchor.tsaToken?.base64EncodedString()
            anchorInfo = AnchorInfo(
                anchorId: anchor.anchorId,
                anchorType: anchor.anchorType,
                merkleRoot: anchor.merkleRoot,
                merkleProof: [],
                merkleIndex: 0,
                tsaResponse: tsaTokenBase64,  // RFC3161 TimeStampToken (DER/base64)
                tsaTimestamp: anchor.timestamp,
                tsaService: anchor.serviceEndpoint
            )
        }
        
        // 署名者情報はEvent.SignerInfo内に含まれているため、
        // Verification.signerには設定しない（重複を避ける）
        // Event.SignerInfoはEventHashの計算対象なので改ざん検出可能
        
        let verification = VerificationInfo(
            publicKey: CryptoService.shared.getPublicKeyBase64(),
            keyAttestation: CryptoService.shared.getKeyAttestation(),
            verificationEndpoint: nil,
            signer: nil  // 旧形式は使用しない
        )
        
        let metadata = ProofMetadata(
            originalFilename: event.asset.assetName,
            originalSize: event.asset.assetSize,
            thumbnailHash: nil,
            location: locationInfo
        )
        
        return ProofJSON(
            proofVersion: "1.0",
            proofType: "CPP_INGEST_PROOF",
            generatedAt: Date().iso8601String,
            generatedBy: DeviceInfo.appVersion,
            event: event,
            anchor: anchorInfo,
            verification: verification,
            metadata: metadata
        )
    }
}

enum CPPEventError: LocalizedError, Sendable {
    case serializationFailed
    case hashComputationFailed
    case chainIntegrityError
    
    var errorDescription: String? {
        switch self {
        case .serializationFailed: return "Failed to serialize event"
        case .hashComputationFailed: return "Failed to compute event hash"
        case .chainIntegrityError: return "Chain integrity error"
        }
    }
}
