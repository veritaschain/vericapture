//
//  TSAEndpoint.swift
//  VeriCapture
//
//  TSA Provider Configuration with Usage Restrictions
//  v36.0 - TSA Redundancy Architecture
//  © 2026 VeritasChain Standards Organization
//

import Foundation

// MARK: - TSA Endpoint Model

/// TSA Provider Configuration with Usage Restrictions
struct TSAEndpoint: Codable, Identifiable, Sendable, Equatable {
    let id: String                          // UUID
    let name: String                        // "DigiCert", "Sectigo", etc.
    let endpoint: URL                       // RFC 3161 endpoint URL
    var priority: Int                       // Lower = Higher priority (1, 2, 3...)
    var isEnabled: Bool                     // User toggle
    
    // --- Provider Metadata ---
    let commercialAllowed: CommercialStatus // .allowed, .prohibited, .unknown
    let recommendedMinIntervalSeconds: Int? // e.g., Sectigo: 15
    let recommendedMaxRequestsPerDay: Int?  // e.g., SwissSign: 10
    let recommendedMaxRequestsPerMonth: Int?// e.g., GlobalSign AATL: 50
    let isEidasQualified: Bool              // eIDAS QTSP status
    let region: TSARegion                   // .eu, .us, .global
    let serviceLevel: ServiceLevel          // .production, .bestEffort, .demo
    
    // --- Documentation URLs ---
    let tosUrl: URL?                        // Terms of Service
    let cpsUrl: URL?                        // Certificate Practice Statement
    
    static func == (lhs: TSAEndpoint, rhs: TSAEndpoint) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Supporting Enums

enum CommercialStatus: String, Codable, Sendable {
    case allowed = "ALLOWED"
    case prohibited = "PROHIBITED"
    case unknown = "UNKNOWN"
}

enum TSARegion: String, Codable, Sendable {
    case eu = "EU"
    case us = "US"
    case global = "GLOBAL"
    case asiaPacific = "APAC"
}

enum ServiceLevel: String, Codable, Sendable {
    case production = "PRODUCTION"      // SLA guaranteed
    case bestEffort = "BEST_EFFORT"     // No SLA, community/free
    case demo = "DEMO"                  // For testing only
}

// MARK: - TSA Failover Configuration

/// TSA Failover Configuration (Pro Feature)
struct TSAFailoverConfig: Codable, Sendable {
    var isEnabled: Bool                     // Pro subscription required
    var endpoints: [TSAEndpoint]            // Priority-ordered list
    let failoverMode: FailoverMode
    let maxRetries: Int                     // Per-endpoint retry limit
    
    enum FailoverMode: String, Codable, Sendable {
        case sequential = "SEQUENTIAL"      // Try in priority order
        case roundRobin = "ROUND_ROBIN"     // Distribute load
        case latencyBased = "LATENCY"       // Prefer fastest response
    }
    
    static func defaultConfig() -> TSAFailoverConfig {
        TSAFailoverConfig(
            isEnabled: false,
            endpoints: TSAEndpoint.freeDefaults,
            failoverMode: .sequential,
            maxRetries: 2
        )
    }
    
    static func proConfig() -> TSAFailoverConfig {
        TSAFailoverConfig(
            isEnabled: true,
            endpoints: TSAEndpoint.proDefaults,
            failoverMode: .sequential,
            maxRetries: 2
        )
    }
}

// MARK: - Default TSA Endpoints

extension TSAEndpoint {
    
    /// Primary: rfc3161.ai.moda (Load Balancer with internal failover)
    static let rfc3161AiModa = TSAEndpoint(
        id: "rfc3161-ai-moda",
        name: "RFC3161.ai.moda",
        endpoint: URL(string: "https://rfc3161.ai.moda")!,
        priority: 1,
        isEnabled: true,
        commercialAllowed: .allowed,
        recommendedMinIntervalSeconds: nil,
        recommendedMaxRequestsPerDay: nil,
        recommendedMaxRequestsPerMonth: nil,
        isEidasQualified: false,
        region: .global,
        serviceLevel: .production,
        tosUrl: URL(string: "https://rfc3161.ai.moda"),
        cpsUrl: nil
    )
    
    /// Secondary: DigiCert
    static let digicert = TSAEndpoint(
        id: "digicert",
        name: "DigiCert",
        endpoint: URL(string: "http://timestamp.digicert.com")!,
        priority: 2,
        isEnabled: true,
        commercialAllowed: .allowed,
        recommendedMinIntervalSeconds: nil,
        recommendedMaxRequestsPerDay: nil,
        recommendedMaxRequestsPerMonth: nil,
        isEidasQualified: false,
        region: .us,
        serviceLevel: .production,
        tosUrl: URL(string: "https://www.digicert.com/legal-repository"),
        cpsUrl: URL(string: "https://www.digicert.com/legal-repository")
    )
    
    /// Tertiary: Sectigo (15-second interval recommended)
    static let sectigo = TSAEndpoint(
        id: "sectigo",
        name: "Sectigo",
        endpoint: URL(string: "https://timestamp.sectigo.com")!,
        priority: 3,
        isEnabled: true,
        commercialAllowed: .allowed,
        recommendedMinIntervalSeconds: 15,     // ⚠️ Important
        recommendedMaxRequestsPerDay: nil,
        recommendedMaxRequestsPerMonth: nil,
        isEidasQualified: false,
        region: .global,
        serviceLevel: .production,
        tosUrl: URL(string: "https://www.sectigo.com/legal"),
        cpsUrl: URL(string: "https://www.sectigo.com/uploads/legal/Sectigo-eIDAS-TSPPS-v1.0.6.pdf")
    )
    
    /// Emergency Fallback: FreeTSA (Best-effort, no SLA)
    static let freetsa = TSAEndpoint(
        id: "freetsa",
        name: "FreeTSA",
        endpoint: URL(string: "https://freetsa.org/tsr")!,
        priority: 99,
        isEnabled: true,
        commercialAllowed: .unknown,
        recommendedMinIntervalSeconds: nil,
        recommendedMaxRequestsPerDay: nil,
        recommendedMaxRequestsPerMonth: nil,
        isEidasQualified: false,
        region: .global,
        serviceLevel: .bestEffort,            // ⚠️ No SLA
        tosUrl: URL(string: "https://www.freetsa.org"),
        cpsUrl: URL(string: "https://www.freetsa.org/freetsa_cps.html")
    )
    
    // ⚠️ EXCLUDED FROM DEFAULTS: GlobalSign AATL (月50回推奨制限)
    // VeriCapture月1440回（30分×48回/日×30日）で大幅超過のため
    
    /// Default endpoint list for Free tier (single provider)
    static let freeDefaults: [TSAEndpoint] = [
        .rfc3161AiModa
    ]
    
    /// Default endpoint list for Pro tier (failover enabled)
    static let proDefaults: [TSAEndpoint] = [
        .rfc3161AiModa,  // Primary
        .digicert,       // Secondary
        .sectigo,        // Tertiary
        .freetsa         // Emergency (best-effort)
    ]
    
    /// All available built-in providers
    static let allBuiltIn: [TSAEndpoint] = [
        .rfc3161AiModa,
        .digicert,
        .sectigo,
        .freetsa
    ]
}

// MARK: - Extended TSA Response

struct TSAResponse: Sendable {
    let tokenData: Data
    let timestamp: Date
    let serviceEndpoint: String
    let providerName: String
    
    init(tokenData: Data, timestamp: Date, serviceEndpoint: String = "", providerName: String = "") {
        self.tokenData = tokenData
        self.timestamp = timestamp
        self.serviceEndpoint = serviceEndpoint
        self.providerName = providerName
    }
}

// MARK: - Extended Anchor Errors

enum AnchorError: LocalizedError, Sendable {
    case requestCreationFailed
    case serverError
    case networkError(String)
    case parseError
    case rateLimitExceeded
    case allProvidersExhausted
    case providerTemporarilyDisabled
    
    var errorDescription: String? {
        switch self {
        case .requestCreationFailed: return "Failed to create TSA request"
        case .serverError: return "TSA server error"
        case .networkError(let message): return "Network error: \(message)"
        case .parseError: return "Failed to parse TSA response"
        case .rateLimitExceeded: return "TSA rate limit exceeded"
        case .allProvidersExhausted: return "All TSA providers failed"
        case .providerTemporarilyDisabled: return "TSA provider temporarily disabled"
        }
    }
}
