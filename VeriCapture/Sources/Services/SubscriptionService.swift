//
//  SubscriptionService.swift
//  VeriCapture
//
//  StoreKit 2 Subscription Management
//  © 2026 VeritasChain株式会社
//

import Foundation
import StoreKit
import Combine

// MARK: - Product Identifiers

enum SubscriptionProductID: String, CaseIterable {
    case monthly = "com.veritaschain.vericapture.pro.monthly"
    case yearly = "com.veritaschain.vericapture.pro.yearly"
    
    var displayName: String {
        switch self {
        case .monthly: return "月額プラン"
        case .yearly: return "年額プラン"
        }
    }
    
    var localizedPrice: String {
        switch self {
        case .monthly: return "¥480/月"
        case .yearly: return "¥3,600/年"
        }
    }
}

// MARK: - Subscription Status

enum SubscriptionStatus: Equatable {
    case free
    case pro(expirationDate: Date?)
    case expired
    
    var isPro: Bool {
        switch self {
        case .pro: return true
        default: return false
        }
    }
}

// MARK: - Subscription Service

@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()
    
    // MARK: - Debug Configuration
    
    /// デバッグ用: Pro状態を強制（TestFlight/開発用）
    /// ⚠️ 本番リリース時は必ず false にすること ⚠️
    static let forceProForTesting = false  // 本番用: false
    
    // MARK: - Published Properties
    
    @Published private(set) var status: SubscriptionStatus = .free
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    
    // MARK: - Computed Properties (with debug override)
    
    /// 実際のPro状態（デバッグオーバーライド対応）
    var effectiveIsPro: Bool {
        if Self.forceProForTesting { return true }
        return status.isPro
    }
    
    // MARK: - Constants
    
    static let freeProofLimit = 50
    
    // MARK: - Private Properties
    
    private var updateListenerTask: Task<Void, Error>?
    
    // MARK: - Initialization
    
    private init() {
        print("[SubscriptionService] 🏗️ Initializing SubscriptionService...")
        // トランザクションリスナーは安全に開始（遅延）
        Task {
            // UIがブロックされないように遅延
            print("[SubscriptionService] ⏳ Waiting 2s before starting transaction listener...")
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒
            print("[SubscriptionService] 🎧 Starting transaction listener...")
            updateListenerTask = listenForTransactions()
            await updateSubscriptionStatus()
            print("[SubscriptionService] ✅ Transaction listener started")
        }
        
        // 製品ロードはさらに遅延（VeriCaptureApp.swiftで明示的に呼ばれる）
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Product Loading
    
    func loadProducts() async {
        // すでにロード済みなら何もしない
        guard products.isEmpty else {
            print("[SubscriptionService] ⚡ Products already loaded, skipping")
            return
        }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        let productIDs = SubscriptionProductID.allCases.map { $0.rawValue }
        print("[SubscriptionService] 🚀 START loadProducts()")
        print("[SubscriptionService] 📦 Requesting product IDs: \(productIDs)")
        
        // 最大3回リトライ
        for attempt in 1...3 {
            print("[SubscriptionService] 🔄 Attempt \(attempt) of 3...")
            do {
                let storeProducts = try await Product.products(for: productIDs)
                
                // 価格順にソート（月額が先）
                products = storeProducts.sorted { $0.price < $1.price }
                
                print("[SubscriptionService] ✅ SUCCESS! Loaded \(products.count) products on attempt \(attempt)")
                for product in products {
                    print("[SubscriptionService] 💰 Product: \(product.id) = \(product.displayPrice)")
                }
                
                if products.isEmpty {
                    // 製品が0件の場合、具体的な原因を表示
                    errorMessage = "Products not available. Please check App Store Connect configuration."
                    print("[SubscriptionService] ⚠️ WARNING: No products returned!")
                    print("[SubscriptionService] ⚠️ Possible causes:")
                    print("[SubscriptionService]    - Products not in 'Ready to Submit' status")
                    print("[SubscriptionService]    - Paid Apps Agreement not signed")
                    print("[SubscriptionService]    - Product IDs don't match")
                    print("[SubscriptionService]    - Sandbox account not properly configured")
                    print("[SubscriptionService]    - Bundle ID mismatch")
                }
                return
            } catch let error as StoreKit.StoreKitError {
                print("[SubscriptionService] ❌ StoreKit error on attempt \(attempt): \(error)")
                print("[SubscriptionService] ❌ Error details: \(error.localizedDescription)")
                switch error {
                case .networkError(let underlying):
                    errorMessage = "Network error. Please check your connection."
                    print("[SubscriptionService] ❌ Network error underlying: \(underlying)")
                case .userCancelled:
                    errorMessage = "Request cancelled."
                case .notAvailableInStorefront:
                    errorMessage = "Products not available in this region."
                case .notEntitled:
                    errorMessage = "Not entitled to these products."
                default:
                    errorMessage = "Store error: \(error.localizedDescription)"
                }
            } catch {
                print("[SubscriptionService] ❌ Load attempt \(attempt) failed: \(error)")
                print("[SubscriptionService] ❌ Error type: \(type(of: error))")
                print("[SubscriptionService] ❌ Error description: \(error.localizedDescription)")
                errorMessage = "Failed to load: \(error.localizedDescription)"
            }
            
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000) // 1秒、2秒
            }
        }
        
        if errorMessage == nil {
            errorMessage = L10n.Paywall.loadFailed
        }
        print("[SubscriptionService] ❌ FAILED to load products after 3 attempts")
        print("[SubscriptionService] ❌ Final error: \(errorMessage ?? "unknown")")
    }
    
    // MARK: - Purchase
    
    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateSubscriptionStatus()
                await transaction.finish()
                print("[SubscriptionService] Purchase successful: \(product.id)")
                return true
                
            case .userCancelled:
                print("[SubscriptionService] User cancelled purchase")
                return false
                
            case .pending:
                print("[SubscriptionService] Purchase pending")
                return false
                
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "購入に失敗しました: \(error.localizedDescription)"
            print("[SubscriptionService] Purchase failed: \(error)")
            return false
        }
    }
    
    // MARK: - Restore Purchases
    
    func restorePurchases() async -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            
            if status.isPro {
                print("[SubscriptionService] Restore successful - Pro activated")
                return true
            } else {
                errorMessage = "復元可能な購入が見つかりませんでした"
                print("[SubscriptionService] No purchases to restore")
                return false
            }
        } catch let error as NSError where error.domain == "ASDErrorDomain" && error.code == 509 {
            // "No active account" エラー - App Storeにサインインしていない
            errorMessage = "App Storeにサインインしてください"
            print("[SubscriptionService] No App Store account signed in")
            return false
        } catch {
            errorMessage = "購入の復元に失敗しました"
            print("[SubscriptionService] Restore failed: \(error)")
            return false
        }
    }
    
    // MARK: - Subscription Status
    
    func updateSubscriptionStatus() async {
        var foundActiveSubscription = false
        var latestExpirationDate: Date?
        
        // Transaction.currentEntitlementsはエラーをスローしない
        // アカウントがない場合は空のシーケンスを返す
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            
            if transaction.productType == .autoRenewable {
                if let expirationDate = transaction.expirationDate {
                    if expirationDate > Date() {
                        foundActiveSubscription = true
                        if latestExpirationDate == nil || expirationDate > latestExpirationDate! {
                            latestExpirationDate = expirationDate
                        }
                    }
                }
            }
        }
        
        if foundActiveSubscription {
            status = .pro(expirationDate: latestExpirationDate)
            print("[SubscriptionService] Status: Pro (expires: \(latestExpirationDate?.description ?? "unknown"))")
        } else {
            status = .free
            print("[SubscriptionService] Status: Free")
        }
    }
    
    // MARK: - Transaction Listener
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { break }
                
                if case .verified(let transaction) = result {
                    await self.updateSubscriptionStatus()
                    await transaction.finish()
                }
            }
        }
    }
    
    // MARK: - Verification
    
    private func checkVerified<T>(_ result: StoreKit.VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: - Feature Checks
    
    /// 証跡保存が可能かチェック
    func canSaveProof(currentCount: Int) -> Bool {
        if effectiveIsPro { return true }  // テストフラグ対応
        return currentCount < Self.freeProofLimit
    }
    
    /// Pro機能が必要かどうか（現在は無制限ストレージのみ）
    func requiresPro(for feature: ProFeature) -> Bool {
        if effectiveIsPro { return false }  // テストフラグ対応
        return true // unlimitedStorage only
    }
    
    /// 残り保存可能数
    func remainingFreeSlots(currentCount: Int) -> Int {
        if effectiveIsPro { return Int.max }  // テストフラグ対応
        return max(0, Self.freeProofLimit - currentCount)
    }
}

// MARK: - Pro Features

enum ProFeature: CaseIterable {
    case unlimitedStorage
    
    var title: String {
        switch self {
        case .unlimitedStorage: return "証跡保存：無制限"
        }
    }
    
    var icon: String {
        switch self {
        case .unlimitedStorage: return "infinity"
        }
    }
    
    var freeDescription: String {
        switch self {
        case .unlimitedStorage: return "50件まで"
        }
    }
}

// MARK: - Errors

enum SubscriptionError: LocalizedError {
    case verificationFailed
    case purchaseFailed
    case restoreFailed
    
    var errorDescription: String? {
        switch self {
        case .verificationFailed: return "購入の検証に失敗しました"
        case .purchaseFailed: return "購入に失敗しました"
        case .restoreFailed: return "購入の復元に失敗しました"
        }
    }
}
