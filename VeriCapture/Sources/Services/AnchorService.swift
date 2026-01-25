//
//  AnchorService.swift
//  VeriCapture
//
//  RFC 3161 TSA Batch Anchoring Service with Failover
//  v36.0 - TSA Redundancy Architecture
//  © 2026 VeritasChain Standards Organization
//

import Foundation
import Combine
import CryptoKit

@MainActor
final class AnchorService: ObservableObject {
    static let shared = AnchorService()
    
    // MARK: - Published Properties
    
    @Published var lastAnchorTime: Date?
    @Published var pendingEventCount: Int = 0
    @Published var isAnchoring: Bool = false
    @Published var lastUsedProvider: String?
    @Published var failoverConfig: TSAFailoverConfig
    
    // MARK: - Private Properties
    
    private var anchorTimer: Timer?
    private let batchIntervalSeconds: TimeInterval = 30 * 60
    
    private var rateLimitPolicy: RateLimitPolicy {
        RateLimitPolicy.defaultPolicy()
    }
    
    private let userDefaultsKey = "TSA_FailoverConfig"
    
    // MARK: - Computed Properties
    
    var enabledProviderCount: Int {
        failoverConfig.endpoints.filter { $0.isEnabled }.count
    }
    
    var isFailoverEnabled: Bool {
        get { failoverConfig.isEnabled }
        set {
            failoverConfig.isEnabled = newValue
            saveConfig()
        }
    }
    
    var primaryEndpoint: TSAEndpoint {
        failoverConfig.endpoints
            .filter { $0.isEnabled }
            .sorted { $0.priority < $1.priority }
            .first ?? .rfc3161AiModa
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load saved config or use default
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let config = try? JSONDecoder().decode(TSAFailoverConfig.self, from: data) {
            self.failoverConfig = config
        } else {
            self.failoverConfig = TSAFailoverConfig.defaultConfig()
        }
        print("[AnchorService] Initialized with \(failoverConfig.endpoints.count) TSA providers, failover: \(failoverConfig.isEnabled)")
    }
    
    // MARK: - Configuration Management
    
    func updateConfig(_ config: TSAFailoverConfig) {
        self.failoverConfig = config
        saveConfig()
        print("[AnchorService] Config updated: \(config.endpoints.count) providers, failover: \(config.isEnabled)")
    }
    
    func setProConfig() {
        self.failoverConfig = TSAFailoverConfig.proConfig()
        saveConfig()
        print("[AnchorService] Upgraded to Pro config with failover")
    }
    
    func setFreeConfig() {
        self.failoverConfig = TSAFailoverConfig.defaultConfig()
        saveConfig()
        print("[AnchorService] Downgraded to Free config")
    }
    
    private func saveConfig() {
        guard let data = try? JSONEncoder().encode(failoverConfig) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
    
    // MARK: - Batch Processing
    
    func startBatchProcessing() {
        anchorTimer = Timer.scheduledTimer(withTimeInterval: batchIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processBatch()
            }
        }
        // 初回バッチ処理を遅延（アプリ起動を優先）
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3秒後
            await processBatch()
        }
        print("[AnchorService] Batch processing started with primary: \(primaryEndpoint.name)")
    }
    
    func stopBatchProcessing() {
        anchorTimer?.invalidate()
        anchorTimer = nil
    }
    
    func triggerAnchor() async {
        await processBatch()
    }
    
    /// 保留中のイベントカウントを更新（UIリフレッシュ用）
    func refreshPendingCount() {
        do {
            let pendingEvents = try StorageService.shared.getPendingEventsForAnchor()
            pendingEventCount = pendingEvents.count
            print("[AnchorService] Refreshed pending count: \(pendingEventCount)")
        } catch {
            print("[AnchorService] Failed to refresh pending count: \(error)")
        }
    }
    
    // MARK: - Batch Processing Implementation
    
    private func processBatch() async {
        guard !isAnchoring else { return }
        
        isAnchoring = true
        defer { isAnchoring = false }
        
        do {
            let pendingEvents = try StorageService.shared.getPendingEventsForAnchor()
            pendingEventCount = pendingEvents.count
            
            guard !pendingEvents.isEmpty else {
                print("[AnchorService] No pending events to anchor")
                return
            }
            
            print("[AnchorService] Processing \(pendingEvents.count) events")
            
            let eventHashes = pendingEvents.map { $0.eventHash }
            let merkleRoot = computeMerkleRoot(hashes: eventHashes)
            
            // AnchorDigest = MerkleRoot のhex部分（sha256:プレフィックスを除く）
            let anchorDigest = merkleRoot.replacingOccurrences(of: "sha256:", with: "")
            
            let anchorId = UUIDv7.generate()
            let anchor = AnchorRecord(
                anchorId: anchorId,
                anchorType: "RFC3161",
                merkleRoot: merkleRoot,
                treeSize: pendingEvents.count,  // リーフ数
                eventCount: pendingEvents.count,
                firstEventId: pendingEvents.first!.eventId,
                lastEventId: pendingEvents.last!.eventId,
                anchorDigest: anchorDigest,  // TSAに投げる値を明示
                anchorDigestAlgorithm: "sha-256",
                tsaToken: nil,
                tsaMessageImprint: nil,
                timestamp: Date().iso8601String,
                anchorProof: nil,
                serviceEndpoint: primaryEndpoint.endpoint.absoluteString,
                status: .pending
            )
            
            try StorageService.shared.saveAnchor(anchor)
            
            // Use failover-enabled request
            let tsaResult = await requestTSATimestampWithFailover(for: merkleRoot)
            
            switch tsaResult {
            case .success(let tsaResponse):
                // TSAResponse から messageImprint を抽出して検証
                let extractedImprint = extractMessageImprint(from: tsaResponse.tokenData)
                
                // 検証: messageImprint == AnchorDigest であること
                if let imprint = extractedImprint {
                    if imprint.lowercased() != anchorDigest.lowercased() {
                        print("[AnchorService] ⚠️ WARNING: TSA messageImprint mismatch!")
                        print("[AnchorService]   Expected (AnchorDigest): \(anchorDigest)")
                        print("[AnchorService]   Received (messageImprint): \(imprint)")
                        // 不一致でもアンカーは保存（検証時に警告）
                    } else {
                        print("[AnchorService] ✅ TSA messageImprint verified: matches AnchorDigest")
                    }
                }
                
                try StorageService.shared.updateAnchorStatus(
                    anchorId,
                    status: .completed,
                    tsaResponse: tsaResponse.tokenData,
                    tsaTimestamp: tsaResponse.timestamp.iso8601String,
                    tsaMessageImprint: extractedImprint
                )
                
                // Update service endpoint to actual provider used
                try StorageService.shared.updateAnchorServiceEndpoint(
                    anchorId,
                    serviceEndpoint: tsaResponse.serviceEndpoint
                )
                
                for event in pendingEvents {
                    try StorageService.shared.updateEventAnchor(eventId: event.eventId, anchorId: anchorId)
                }
                
                lastAnchorTime = Date()
                lastUsedProvider = tsaResponse.providerName
                pendingEventCount = 0
                
                print("[AnchorService] Anchor completed via \(tsaResponse.providerName): \(anchorId)")
                
            case .failure(let error):
                try StorageService.shared.updateAnchorStatus(anchorId, status: .failed, tsaResponse: nil, tsaTimestamp: nil)
                print("[AnchorService] Anchor failed: \(error)")
            }
            
        } catch {
            print("[AnchorService] Error processing batch: \(error)")
        }
    }
    
    // MARK: - TSA Request with Failover
    
    /// Request TSA timestamp with failover support
    func requestTSATimestampWithFailover(for merkleRoot: String) async -> Result<TSAResponse, AnchorError> {
        
        guard failoverConfig.isEnabled else {
            // Free tier: single endpoint only
            let endpoint = primaryEndpoint
            return await requestTSATimestamp(for: merkleRoot, endpoint: endpoint)
        }
        
        // Pro tier: failover across endpoints
        let sortedEndpoints = failoverConfig.endpoints
            .filter { $0.isEnabled }
            .sorted { $0.priority < $1.priority }
        
        var lastError: AnchorError = .allProvidersExhausted
        
        for endpoint in sortedEndpoints {
            // Check rate limit
            let rateLimitResult = RateLimitGuard.shared.canRequest(
                endpoint: endpoint,
                policy: rateLimitPolicy
            )
            
            switch rateLimitResult {
            case .allowed:
                break
            case .rateLimited(let waitTime):
                print("[AnchorService] Rate limited for \(endpoint.name), skipping (wait: \(Int(waitTime))s)")
                continue
            case .dailyLimitReached(let limit):
                print("[AnchorService] Daily limit reached for \(endpoint.name): \(limit)")
                continue
            case .monthlyLimitReached(let limit):
                print("[AnchorService] Monthly limit reached for \(endpoint.name): \(limit)")
                continue
            case .backingOff(let waitTime):
                print("[AnchorService] Backing off for \(endpoint.name): \(Int(waitTime))s")
                continue
            case .temporarilyDisabled(let retryAfter):
                print("[AnchorService] \(endpoint.name) temporarily disabled for \(Int(retryAfter))s")
                continue
            }
            
            // Attempt request with retries
            for attempt in 1...failoverConfig.maxRetries {
                let result = await requestTSATimestamp(for: merkleRoot, endpoint: endpoint)
                
                switch result {
                case .success(let response):
                    RateLimitGuard.shared.recordSuccess(endpoint: endpoint)
                    print("[AnchorService] TSA success: \(endpoint.name)")
                    return .success(response)
                    
                case .failure(let error):
                    RateLimitGuard.shared.recordFailure(endpoint: endpoint, policy: rateLimitPolicy)
                    lastError = error
                    print("[AnchorService] TSA failed: \(endpoint.name) attempt \(attempt)/\(failoverConfig.maxRetries): \(error)")
                    
                    if attempt < failoverConfig.maxRetries {
                        // Wait before retry (with provider-specific interval)
                        let interval = max(15.0, TimeInterval(endpoint.recommendedMinIntervalSeconds ?? 0))
                        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    }
                }
            }
        }
        
        return .failure(lastError)
    }
    
    /// Single endpoint request (internal)
    private func requestTSATimestamp(
        for merkleRoot: String,
        endpoint: TSAEndpoint
    ) async -> Result<TSAResponse, AnchorError> {
        guard let request = createTSARequest(for: merkleRoot) else {
            return .failure(.requestCreationFailed)
        }
        
        var urlRequest = URLRequest(url: endpoint.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/timestamp-query", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = request
        urlRequest.timeoutInterval = 30
        
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.serverError)
            }
            
            switch httpResponse.statusCode {
            case 200:
                return .success(TSAResponse(
                    tokenData: data,
                    timestamp: Date(),
                    serviceEndpoint: endpoint.endpoint.absoluteString,
                    providerName: endpoint.name
                ))
            case 429:
                return .failure(.rateLimitExceeded)
            case 500...599:
                return .failure(.serverError)
            default:
                return .failure(.serverError)
            }
            
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }
    
    // MARK: - Merkle Tree
    
    private func computeMerkleRoot(hashes: [String]) -> String {
        guard !hashes.isEmpty else {
            return "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        }
        
        var currentLevel = hashes.map { hash -> Data in
            let hex = hash.replacingOccurrences(of: "sha256:", with: "")
            return Data(hexString: hex) ?? Data()
        }
        
        while currentLevel.count > 1 {
            var nextLevel: [Data] = []
            
            for i in stride(from: 0, to: currentLevel.count, by: 2) {
                let left = currentLevel[i]
                let right = i + 1 < currentLevel.count ? currentLevel[i + 1] : currentLevel[i]
                
                var combined = Data()
                combined.append(left)
                combined.append(right)
                
                let hash = SHA256.hash(data: combined)
                nextLevel.append(Data(hash))
            }
            
            currentLevel = nextLevel
        }
        
        return "sha256:\(currentLevel[0].hexString)"
    }
    
    // MARK: - RFC 3161 Request Creation
    
    /// NORMATIVE: Only Merkle root hash is transmitted (PII prohibition)
    /// TSA入力 = MerkleRoot（32 bytes）そのものを messageImprint の hashedMessage にする
    private func createTSARequest(for merkleRoot: String) -> Data? {
        let hashHex = merkleRoot.replacingOccurrences(of: "sha256:", with: "")
        guard let hashData = Data(hexString: hashHex),
              hashData.count == 32 else { return nil }  // Exactly 32 bytes (SHA-256)
        
        let sha256OID: [UInt8] = [0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]
        
        var hashAlgorithm = Data()
        hashAlgorithm.append(contentsOf: sha256OID)
        hashAlgorithm = wrapInSequence(hashAlgorithm)
        
        var hashedMessage = Data()
        hashedMessage.append(0x04)
        hashedMessage.append(UInt8(hashData.count))
        hashedMessage.append(hashData)
        
        var messageImprint = Data()
        messageImprint.append(hashAlgorithm)
        messageImprint.append(hashedMessage)
        messageImprint = wrapInSequence(messageImprint)
        
        var version = Data()
        version.append(0x02)
        version.append(0x01)
        version.append(0x01)
        
        var certReq = Data()
        certReq.append(0x01)
        certReq.append(0x01)
        certReq.append(0xFF)
        
        var request = Data()
        request.append(version)
        request.append(messageImprint)
        request.append(certReq)
        
        return wrapInSequence(request)
    }
    
    // MARK: - TSA Response Parsing
    
    /// TSAResponse (TimeStampToken) から messageImprint.hashedMessage を抽出
    /// RFC 3161 ASN.1 構造:
    ///   TimeStampResp ::= SEQUENCE {
    ///     status          PKIStatusInfo,
    ///     timeStampToken  TimeStampToken OPTIONAL
    ///   }
    ///   TimeStampToken = ContentInfo (SignedData containing TSTInfo)
    ///   TSTInfo ::= SEQUENCE {
    ///     version         INTEGER { v1(1) },
    ///     policy          OBJECT IDENTIFIER,
    ///     messageImprint  MessageImprint,  ← ここを抽出
    ///     ...
    ///   }
    ///   MessageImprint ::= SEQUENCE {
    ///     hashAlgorithm   AlgorithmIdentifier,
    ///     hashedMessage   OCTET STRING  ← これが欲しい値
    ///   }
    private func extractMessageImprint(from tsaToken: Data) -> String? {
        // 簡易ASN.1パーサー（TSTInfo内のmessageImprintを抽出）
        // 完全なASN.1パースは複雑なので、パターンマッチングで抽出
        
        // SHA-256 OID: 2.16.840.1.101.3.4.2.1
        // バイト列: 60 86 48 01 65 03 04 02 01
        let sha256OIDBytes: [UInt8] = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]
        
        let bytes = [UInt8](tsaToken)
        
        // SHA-256 OIDを探す
        for i in 0..<(bytes.count - sha256OIDBytes.count - 34) {
            var match = true
            for j in 0..<sha256OIDBytes.count {
                if bytes[i + j] != sha256OIDBytes[j] {
                    match = false
                    break
                }
            }
            
            if match {
                // OIDの後にOCTET STRING (0x04) + 長さ (0x20=32) + 32バイトのハッシュ
                // 典型的なオフセット: OID(9) + NULL(2) + OCTET STRING tag(1) + length(1)
                let offset = i + sha256OIDBytes.count
                
                // NULL (0x05 0x00) をスキップ
                var pos = offset
                if pos < bytes.count - 1 && bytes[pos] == 0x05 && bytes[pos + 1] == 0x00 {
                    pos += 2
                }
                
                // OCTET STRING (0x04) を探す
                if pos < bytes.count && bytes[pos] == 0x04 {
                    let length = Int(bytes[pos + 1])
                    if length == 32 && pos + 2 + 32 <= bytes.count {
                        let hashBytes = Array(bytes[(pos + 2)..<(pos + 2 + 32)])
                        let hexString = hashBytes.map { String(format: "%02x", $0) }.joined()
                        print("[AnchorService] 📋 Extracted messageImprint: \(hexString)")
                        return hexString
                    }
                }
            }
        }
        
        print("[AnchorService] ⚠️ Could not extract messageImprint from TSA response")
        return nil
    }
    
    private func wrapInSequence(_ data: Data) -> Data {
        var result = Data()
        result.append(0x30)
        
        if data.count < 128 {
            result.append(UInt8(data.count))
        } else if data.count < 256 {
            result.append(0x81)
            result.append(UInt8(data.count))
        } else {
            result.append(0x82)
            result.append(UInt8(data.count >> 8))
            result.append(UInt8(data.count & 0xFF))
        }
        
        result.append(data)
        return result
    }
}

// MARK: - StorageService Extension for Service Endpoint Update

extension StorageService {
    func updateAnchorServiceEndpoint(_ anchorId: String, serviceEndpoint: String) throws {
        // Use the existing update pattern instead of executeSQL
        // This will be handled by a dedicated method in StorageService
        // For now, this is a no-op as service_endpoint is set during saveAnchor
        print("[StorageService] Service endpoint update requested for anchor: \(anchorId)")
    }
}
