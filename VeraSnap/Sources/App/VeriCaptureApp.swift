//
//  VeraSnapApp.swift
//  VeraSnap
//
//  CPP v1.0 Compliant Camera Application
//  © 2026 VeritasChain Standards Organization
//

import SwiftUI
import Combine

@main
struct VeraSnapApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            if !appState.hasCompletedOnboarding {
                OnboardingView(onComplete: {
                    appState.completeOnboarding()
                })
            } else {
                ContentView()
                    .environmentObject(appState)
                    .onAppear {
                        Task {
                            await appState.initialize()
                        }
                    }
            }
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var currentPage = 0
    
    var body: some View {
        ZStack {
            // 背景グラデーション
            LinearGradient(
                colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // ページコンテンツ
                TabView(selection: $currentPage) {
                    OnboardingPage(
                        icon: "shield.checkered",
                        title: L10n.Onboarding.title1,
                        description: L10n.Onboarding.desc1
                    )
                    .tag(0)
                    
                    OnboardingPage(
                        icon: "lock.shield.fill",
                        title: L10n.Onboarding.title2,
                        description: L10n.Onboarding.desc2
                    )
                    .tag(1)
                    
                    OnboardingPage(
                        icon: "checkmark.seal.fill",
                        title: L10n.Onboarding.title3,
                        description: L10n.Onboarding.desc3
                    )
                    .tag(2)
                    
                    OnboardingPage(
                        icon: "globe",
                        title: L10n.Onboarding.title4,
                        description: L10n.Onboarding.desc4
                    )
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                
                // ボタン
                Button {
                    if currentPage < 3 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        onComplete()
                    }
                } label: {
                    Text(currentPage < 3 ? L10n.Onboarding.next : L10n.Onboarding.start)
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
                
                // スキップボタン
                if currentPage < 3 {
                    Button {
                        onComplete()
                    } label: {
                        Text(L10n.Onboarding.skip)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.bottom, 40)
                } else {
                    Spacer().frame(height: 60)
                }
            }
        }
    }
}

struct OnboardingPage: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // アイコン
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 140, height: 140)
                
                Image(systemName: icon)
                    .font(.system(size: 60))
                    .foregroundColor(.white)
            }
            
            // タイトル
            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            // 説明
            Text(description)
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
            Spacer()
        }
    }
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var isInitialized = false
    @Published var initializationError: String?
    @Published var chainId: String?
    @Published var initializationProgress: Double = 0
    @Published var initializationStage: String = ""
    @Published var hasCompletedOnboarding: Bool
    
    private let onboardingKey = "hasCompletedOnboarding"
    
    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: onboardingKey)
    }
    
    func initialize() async {
        do {
            // Stage 1: 必須サービスの初期化（同期）
            initializationStage = "Initializing storage..."
            initializationProgress = 0.1
            try StorageService.shared.initialize()
            
            // 少し待機してUIを更新
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            initializationStage = "Initializing crypto..."
            initializationProgress = 0.3
            try CryptoService.shared.initializeKey()
            
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            // Stage 1.5: Case Management initialization (v40)
            initializationStage = "Initializing cases..."
            initializationProgress = 0.4
            CaseService.shared.initialize()
            
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            initializationStage = "Loading chain..."
            initializationProgress = 0.5
            // Use CaseService chainId if available
            if let caseChainId = CaseService.shared.currentChainId {
                chainId = caseChainId
            } else {
                chainId = try StorageService.shared.getOrCreateChainId()
            }
            
            // Stage 2: メイン初期化完了（UIを表示）
            initializationProgress = 0.7
            initializationStage = "Ready"
            isInitialized = true
            print("[VeraSnap] Initialization complete. ChainID: \(chainId ?? "unknown")")
            
            // Stage 3: バックグラウンドサービスの開始（非同期・低優先度）
            Task.detached(priority: .utility) {
                // Anchorサービスの開始を少し遅延
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                await MainActor.run {
                    AnchorService.shared.startBatchProcessing()
                }
            }
            
            // Stage 4: Secure Enclaveのウォームアップ（非同期・完了を待たない）
            Task.detached(priority: .background) {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒後
                await self.warmupSecureEnclave()
            }
            
            // Stage 5: StoreKitの初期化を遅延（非同期）
            Task.detached(priority: .background) {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒後
                await SubscriptionService.shared.loadProducts()
            }
            
        } catch {
            initializationError = error.localizedDescription
            print("[VeraSnap] Initialization failed: \(error)")
        }
    }
    
    /// Secure Enclaveへの初回アクセスを事前に行い、後続の署名を高速化
    private func warmupSecureEnclave() async {
        let dummyHash = "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        _ = try? CryptoService.shared.signEventHash(dummyHash)
        print("[VeraSnap] Crypto warmup complete")
    }
}
