//
//  RateLimitGuard.swift
//  VeraSnap
//
//  Rate Limit Guard - Enforces TSA request policies
//  v36.0 - TSA Redundancy Architecture
//  © 2026 VeritasChain Standards Organization
//

import Foundation
import Combine

// MARK: - Rate Limit Policy

/// Mandatory Rate Limit Policy for TSA Requests
struct RateLimitPolicy: Codable, Sendable {
    /// Minimum interval between requests to the same provider (seconds)
    let perProviderMinIntervalSeconds: TimeInterval
    
    /// Maximum requests per day (0 = unlimited)
    let maxRequestsPerDay: Int
    
    /// Maximum requests per month (0 = unlimited)
    let maxRequestsPerMonth: Int
    
    /// Backoff multiplier on failure (e.g., 2.0 = exponential backoff)
    let backoffMultiplier: Double
    
    /// Maximum backoff time (seconds)
    let maxBackoffSeconds: TimeInterval
    
    /// Initial backoff time after first failure (seconds)
    let initialBackoffSeconds: TimeInterval
    
    /// Number of consecutive failures before temporary disable
    let maxConsecutiveFailures: Int
    
    /// Duration to disable provider after max failures (seconds)
    let disableDurationSeconds: TimeInterval
    
    /// Default policy - accessed via defaultPolicy to avoid @MainActor issues
    static func defaultPolicy() -> RateLimitPolicy {
        RateLimitPolicy(
            perProviderMinIntervalSeconds: 15.0,   // Sectigo recommended
            maxRequestsPerDay: 0,                  // Unlimited by default
            maxRequestsPerMonth: 0,                // Unlimited by default
            backoffMultiplier: 2.0,
            maxBackoffSeconds: 3600,               // 1 hour max
            initialBackoffSeconds: 30,
            maxConsecutiveFailures: 3,
            disableDurationSeconds: 1800           // 30 minutes
        )
    }
    
    static func strictPolicy() -> RateLimitPolicy {
        RateLimitPolicy(
            perProviderMinIntervalSeconds: 30.0,
            maxRequestsPerDay: 100,
            maxRequestsPerMonth: 1500,
            backoffMultiplier: 2.0,
            maxBackoffSeconds: 7200,
            initialBackoffSeconds: 60,
            maxConsecutiveFailures: 2,
            disableDurationSeconds: 3600
        )
    }
}

// MARK: - Rate Limit Result

enum RateLimitResult: Sendable {
    case allowed
    case rateLimited(waitTime: TimeInterval)
    case dailyLimitReached(limit: Int)
    case monthlyLimitReached(limit: Int)
    case backingOff(waitTime: TimeInterval)
    case temporarilyDisabled(retryAfter: TimeInterval)
    
    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
    
    var localizedDescription: String {
        switch self {
        case .allowed:
            return "Request allowed"
        case .rateLimited(let waitTime):
            return String(format: "Rate limited, wait %.0f seconds", waitTime)
        case .dailyLimitReached(let limit):
            return "Daily limit of \(limit) reached"
        case .monthlyLimitReached(let limit):
            return "Monthly limit of \(limit) reached"
        case .backingOff(let waitTime):
            return String(format: "Backing off for %.0f seconds", waitTime)
        case .temporarilyDisabled(let retryAfter):
            return String(format: "Provider disabled for %.0f seconds", retryAfter)
        }
    }
}

// MARK: - Request Counters

struct RequestCounters: Codable, Sendable {
    var todayCount: Int = 0
    var monthCount: Int = 0
    var lastRequestTime: Date?
    var consecutiveFailures: Int = 0
    var currentBackoff: TimeInterval = 0
    var disabledUntil: Date?
    var lastResetDay: Int = 0       // Day of year for daily reset
    var lastResetMonth: Int = 0     // Month for monthly reset
    
    mutating func resetIfNeeded() {
        let calendar = Calendar.current
        let now = Date()
        let currentDay = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
        let currentMonth = calendar.component(.month, from: now)
        
        // Reset daily counter
        if currentDay != lastResetDay {
            todayCount = 0
            lastResetDay = currentDay
        }
        
        // Reset monthly counter
        if currentMonth != lastResetMonth {
            monthCount = 0
            lastResetMonth = currentMonth
        }
    }
}

// MARK: - Rate Limit Guard

/// Rate Limit Guard - Enforces TSA request policies
@MainActor
final class RateLimitGuard: ObservableObject {
    static let shared = RateLimitGuard()
    
    @Published private(set) var requestCounts: [String: RequestCounters] = [:]
    
    private let userDefaultsKey = "TSA_RateLimitCounters"
    
    private init() {
        loadCounters()
    }
    
    // MARK: - Public Methods
    
    /// Check if request is allowed and return wait time if needed
    func canRequest(
        endpoint: TSAEndpoint,
        policy: RateLimitPolicy? = nil
    ) -> RateLimitResult {
        let policy = policy ?? RateLimitPolicy.defaultPolicy()
        var counters = requestCounts[endpoint.id] ?? RequestCounters()
        counters.resetIfNeeded()
        
        // Check if temporarily disabled
        if let disabledUntil = counters.disabledUntil, Date() < disabledUntil {
            let waitTime = disabledUntil.timeIntervalSince(Date())
            return .temporarilyDisabled(retryAfter: waitTime)
        }
        
        // Check provider-specific limits
        let minInterval = max(
            policy.perProviderMinIntervalSeconds,
            TimeInterval(endpoint.recommendedMinIntervalSeconds ?? 0)
        )
        
        if let lastRequest = counters.lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < minInterval {
                return .rateLimited(waitTime: minInterval - elapsed)
            }
        }
        
        // Check daily limit
        let dailyLimit = endpoint.recommendedMaxRequestsPerDay ?? policy.maxRequestsPerDay
        if dailyLimit > 0 && counters.todayCount >= dailyLimit {
            return .dailyLimitReached(limit: dailyLimit)
        }
        
        // Check monthly limit
        let monthlyLimit = endpoint.recommendedMaxRequestsPerMonth ?? policy.maxRequestsPerMonth
        if monthlyLimit > 0 && counters.monthCount >= monthlyLimit {
            return .monthlyLimitReached(limit: monthlyLimit)
        }
        
        // Check backoff after failures
        if counters.currentBackoff > 0 {
            if let lastRequest = counters.lastRequestTime {
                let elapsed = Date().timeIntervalSince(lastRequest)
                if elapsed < counters.currentBackoff {
                    return .backingOff(waitTime: counters.currentBackoff - elapsed)
                }
            }
        }
        
        return .allowed
    }
    
    /// Record successful request
    func recordSuccess(endpoint: TSAEndpoint) {
        var counters = requestCounts[endpoint.id] ?? RequestCounters()
        counters.resetIfNeeded()
        counters.todayCount += 1
        counters.monthCount += 1
        counters.lastRequestTime = Date()
        counters.consecutiveFailures = 0
        counters.currentBackoff = 0
        counters.disabledUntil = nil
        requestCounts[endpoint.id] = counters
        saveCounters()
        
        print("[RateLimitGuard] Success recorded for \(endpoint.name): today=\(counters.todayCount), month=\(counters.monthCount)")
    }
    
    /// Record failed request with backoff calculation
    func recordFailure(endpoint: TSAEndpoint, policy: RateLimitPolicy? = nil) {
        let policy = policy ?? RateLimitPolicy.defaultPolicy()
        var counters = requestCounts[endpoint.id] ?? RequestCounters()
        counters.resetIfNeeded()
        counters.consecutiveFailures += 1
        counters.lastRequestTime = Date()
        
        // Calculate exponential backoff
        let backoff = policy.initialBackoffSeconds *
            pow(policy.backoffMultiplier, Double(counters.consecutiveFailures - 1))
        counters.currentBackoff = min(backoff, policy.maxBackoffSeconds)
        
        // Temporarily disable if too many failures
        if counters.consecutiveFailures >= policy.maxConsecutiveFailures {
            counters.disabledUntil = Date().addingTimeInterval(policy.disableDurationSeconds)
            print("[RateLimitGuard] Provider \(endpoint.name) disabled until \(counters.disabledUntil!)")
        }
        
        requestCounts[endpoint.id] = counters
        saveCounters()
        
        print("[RateLimitGuard] Failure recorded for \(endpoint.name): failures=\(counters.consecutiveFailures), backoff=\(counters.currentBackoff)s")
    }
    
    /// Get statistics for a provider
    func getStats(for endpoint: TSAEndpoint) -> (today: Int, month: Int, failures: Int) {
        var counters = requestCounts[endpoint.id] ?? RequestCounters()
        counters.resetIfNeeded()
        return (counters.todayCount, counters.monthCount, counters.consecutiveFailures)
    }
    
    /// Reset all counters (for testing)
    func resetAllCounters() {
        requestCounts.removeAll()
        saveCounters()
        print("[RateLimitGuard] All counters reset")
    }
    
    /// Reset counters for a specific provider
    func resetCounters(for endpoint: TSAEndpoint) {
        requestCounts.removeValue(forKey: endpoint.id)
        saveCounters()
        print("[RateLimitGuard] Counters reset for \(endpoint.name)")
    }
    
    // MARK: - Persistence
    
    private func loadCounters() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: RequestCounters].self, from: data) else {
            return
        }
        requestCounts = decoded
        print("[RateLimitGuard] Loaded \(requestCounts.count) provider counters")
    }
    
    private func saveCounters() {
        guard let data = try? JSONEncoder().encode(requestCounts) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}

// MARK: - Convenience Extensions

extension RateLimitGuard {
    /// Check if any provider is available
    func hasAvailableProvider(from endpoints: [TSAEndpoint], policy: RateLimitPolicy? = nil) -> Bool {
        for endpoint in endpoints where endpoint.isEnabled {
            if canRequest(endpoint: endpoint, policy: policy).isAllowed {
                return true
            }
        }
        return false
    }
    
    /// Get next available provider
    func getNextAvailableProvider(from endpoints: [TSAEndpoint], policy: RateLimitPolicy? = nil) -> TSAEndpoint? {
        let sorted = endpoints
            .filter { $0.isEnabled }
            .sorted { $0.priority < $1.priority }
        
        for endpoint in sorted {
            if canRequest(endpoint: endpoint, policy: policy).isAllowed {
                return endpoint
            }
        }
        return nil
    }
}
