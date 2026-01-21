//
//  PaywallView.swift
//  VeriCapture
//
//  Subscription Paywall UI
//  © 2026 VeritasChain株式会社
//

import SwiftUI
import StoreKit

// MARK: - Paywall View

struct PaywallView: View {
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @Environment(\.dismiss) private var dismiss
    
    let reason: PaywallReason
    
    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var purchaseSuccess = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Limit reached banner (when applicable)
                    if case .limitReached(let count) = reason {
                        limitReachedBanner(count: count)
                    }
                    
                    // Pro features list
                    proFeaturesSection
                    
                    // Pricing plans
                    pricingSection
                    
                    // Purchase button
                    purchaseButton
                    
                    // Restore button
                    restoreButton
                    
                    // Disclaimer
                    disclaimerSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("VeriCapture Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Paywall.close) { dismiss() }
                }
            }
            .alert(L10n.Paywall.error, isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onChange(of: purchaseSuccess) { _, success in
                if success {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Pro icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "shield.checkered")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 8) {
                Text("VeriCapture Pro")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(L10n.Paywall.tagline)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 20)
    }
    
    // MARK: - Limit Reached Banner
    
    private func limitReachedBanner(count: Int) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(L10n.Paywall.limitReachedTitle)
                    .fontWeight(.semibold)
            }
            
            Text(L10n.Paywall.limitReachedMessage(count))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Pro Features
    
    private var proFeaturesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.Paywall.proBenefitsTitle)
                .font(.headline)
            
            VStack(spacing: 12) {
                // Unlimited storage (main feature)
                HStack(spacing: 14) {
                    Image(systemName: "infinity")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 40)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Paywall.unlimitedStorage)
                            .font(.headline)
                        
                        Text(L10n.Paywall.freeLimit)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                
                // TSA Redundancy (Pro feature)
                HStack(spacing: 14) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 40)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Paywall.tsaRedundancy)
                            .font(.headline)
                        
                        Text(L10n.Paywall.tsaRedundancyDesc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                
                // Free features (for explanation)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Paywall.freeFeaturesTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 20) {
                        freeFeatureItem(icon: "camera.fill", text: L10n.Paywall.featureCapture)
                        freeFeatureItem(icon: "shield.checkered", text: L10n.Paywall.featureProof)
                        freeFeatureItem(icon: "qrcode", text: L10n.Paywall.featureQr)
                        freeFeatureItem(icon: "doc.badge.plus", text: L10n.Paywall.featureJson)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.08))
                .cornerRadius(12)
            }
        }
    }
    
    private func freeFeatureItem(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.green)
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Pricing
    
    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.Paywall.selectPlan)
                .font(.headline)
            
            if subscriptionService.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else if subscriptionService.products.isEmpty {
                // Failed to load product info
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(L10n.Paywall.loadFailed)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        Task {
                            await subscriptionService.loadProducts()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text(L10n.Paywall.reload)
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                    
                    // Reference prices (non-selectable)
                    VStack(spacing: 8) {
                        Text(L10n.Paywall.referencePriceNote)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text(L10n.Paywall.monthlyPlan)
                                    .font(.subheadline)
                                Text("$4.99" + L10n.Paywall.perMonth)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(L10n.Paywall.yearlyPlan)
                                        .font(.subheadline)
                                    Text(L10n.Paywall.savePercent)
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange)
                                        .cornerRadius(4)
                                }
                                Text("$37.99" + L10n.Paywall.perYear)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
            } else {
                VStack(spacing: 12) {
                    ForEach(subscriptionService.products.sorted { $0.id < $1.id }, id: \.id) { product in
                        let isYearly = product.id.contains("yearly")
                        
                        PricingCard(
                            title: isYearly ? L10n.Paywall.yearlyPlan : L10n.Paywall.monthlyPlan,
                            price: product.displayPrice,
                            period: isYearly ? L10n.Paywall.perYear : L10n.Paywall.perMonth,
                            isSelected: selectedProduct?.id == product.id,
                            badge: isYearly ? L10n.Paywall.savePercent : nil
                        ) {
                            selectedProduct = product
                        }
                    }
                }
                .onAppear {
                    // Default to yearly plan
                    if selectedProduct == nil {
                        selectedProduct = subscriptionService.products.first { $0.id.contains("yearly") }
                            ?? subscriptionService.products.first
                    }
                }
            }
        }
    }
    
    // MARK: - Purchase Button
    
    private var purchaseButton: some View {
        Button {
            Task { await purchase() }
        } label: {
            HStack {
                if isPurchasing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(L10n.Paywall.upgradeButton)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .disabled(selectedProduct == nil || isPurchasing)
    }
    
    // MARK: - Restore Button
    
    private var restoreButton: some View {
        Button {
            Task { await restore() }
        } label: {
            Text(L10n.Paywall.restorePurchases)
                .font(.subheadline)
                .foregroundColor(.blue)
        }
        .disabled(isPurchasing)
    }
    
    // MARK: - Disclaimer
    
    private var disclaimerSection: some View {
        VStack(spacing: 8) {
            Text(L10n.Paywall.subscriptionInfoTitle)
                .font(.caption)
                .fontWeight(.medium)
            
            Text(L10n.Paywall.subscriptionInfoBody)
            .font(.caption2)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)
            
            HStack(spacing: 16) {
                Link(L10n.Paywall.terms, destination: URL(string: "https://veritaschain.org/terms")!)
                Link(L10n.Paywall.privacy, destination: URL(string: "https://veritaschain.org/privacy")!)
            }
            .font(.caption2)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func purchase() async {
        guard let product = selectedProduct else { return }
        
        isPurchasing = true
        let success = await subscriptionService.purchase(product)
        isPurchasing = false
        
        if success {
            purchaseSuccess = true
        } else if let error = subscriptionService.errorMessage {
            errorMessage = error
            showError = true
        }
    }
    
    private func restore() async {
        isPurchasing = true
        let success = await subscriptionService.restorePurchases()
        isPurchasing = false
        
        if success {
            purchaseSuccess = true
        } else if let error = subscriptionService.errorMessage {
            errorMessage = error
            showError = true
        }
    }
}

// MARK: - Pricing Card

struct PricingCard: View {
    let title: String
    let price: String
    let period: String
    let isSelected: Bool
    let badge: String?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if let badge = badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .cornerRadius(4)
                        }
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(price)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(period)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Paywall Reason

enum PaywallReason {
    case limitReached(count: Int)
    case featureRequired(ProFeature)
    case manual
}

// MARK: - Limit Reached Sheet

struct LimitReachedSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentCount: Int
    let onMakeSpace: () -> Void
    let onUpgrade: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.orange)
            }
            
            // Message
            VStack(spacing: 12) {
                Text(L10n.Paywall.limitReachedTitle)
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text(L10n.Paywall.limitReachedCaptureMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text(L10n.Paywall.currentCount(currentCount, 50))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            
            // Actions
            VStack(spacing: 12) {
                Button {
                    onUpgrade()
                } label: {
                    HStack {
                        Image(systemName: "crown.fill")
                        Text(L10n.Paywall.proUnlimited)
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                }
                
                Button {
                    onMakeSpace()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text(L10n.Paywall.makeSpace)
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
            
            // Cancel
            Button(L10n.Paywall.later) {
                dismiss()
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Pro Badge

struct ProBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.caption2)
            Text("PRO")
                .font(.caption2)
                .fontWeight(.bold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [.blue, .purple],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(6)
    }
}

#Preview {
    PaywallView(reason: .limitReached(count: 50))
}
