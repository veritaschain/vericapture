//
//  TSASettingsView.swift
//  VeriCapture
//
//  TSA Provider Settings UI Components
//  v36.0 - TSA Redundancy Architecture
//  © 2026 VeritasChain Standards Organization
//

import SwiftUI

// MARK: - TSA Settings Section

/// TSA Settings Section for Settings Tab
struct TSASettingsSection: View {
    @ObservedObject var anchorService: AnchorService
    @ObservedObject var subscriptionService: SubscriptionService
    
    var body: some View {
        Section {
            // Current TSA Status
            TSAStatusRow(anchorService: anchorService)
            
            if subscriptionService.effectiveIsPro {
                // Pro: Multiple TSA configuration
                NavigationLink {
                    TSAProviderListView(anchorService: anchorService)
                } label: {
                    HStack {
                        Label(L10n.TSA.providersTitle, systemImage: "server.rack")
                        Spacer()
                        Text("\(anchorService.enabledProviderCount)")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Redundancy toggle
                Toggle(isOn: Binding(
                    get: { anchorService.isFailoverEnabled },
                    set: { anchorService.isFailoverEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.TSA.enableRedundancy)
                        Text(L10n.TSA.enableRedundancyDesc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
            } else {
                // Free: Single TSA, upgrade prompt
                HStack {
                    Label(L10n.TSA.primaryProvider, systemImage: "server.rack")
                    Spacer()
                    Text(anchorService.primaryEndpoint.name)
                        .foregroundColor(.secondary)
                }
                
                // Pro upgrade prompt
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                    Text(L10n.TSA.redundancyProOnly)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Last used provider (if available)
            if let lastProvider = anchorService.lastUsedProvider {
                HStack {
                    Text(String(format: L10n.TSA.lastUsedProvider, lastProvider))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
        } header: {
            Text(L10n.TSA.sectionHeader)
        } footer: {
            Text(L10n.TSA.sectionFooter)
        }
    }
}

// MARK: - TSA Status Row

struct TSAStatusRow: View {
    @ObservedObject var anchorService: AnchorService
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(anchorService.primaryEndpoint.name)
                    .font(.headline)
                Text(anchorService.primaryEndpoint.endpoint.absoluteString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Status indicator
            if anchorService.isAnchoring {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }
}

// MARK: - TSA Provider List View

struct TSAProviderListView: View {
    @ObservedObject var anchorService: AnchorService
    @State private var showingAddProvider = false
    
    var body: some View {
        List {
            Section {
                ForEach(sortedProviders) { provider in
                    TSAProviderRow(
                        provider: provider,
                        isEnabled: binding(for: provider)
                    )
                }
                .onMove(perform: movePriority)
            } header: {
                Text("Configured Providers")
            } footer: {
                Text("Drag to reorder priority. Higher items are tried first.")
            }
            
            Section {
                Button {
                    showingAddProvider = true
                } label: {
                    Label(L10n.TSA.addCustomProvider, systemImage: "plus")
                }
            }
        }
        .navigationTitle(L10n.TSA.providersTitle)
        .toolbar {
            EditButton()
        }
        .sheet(isPresented: $showingAddProvider) {
            AddTSAProviderView { newProvider in
                addProvider(newProvider)
            }
        }
    }
    
    private var sortedProviders: [TSAEndpoint] {
        anchorService.failoverConfig.endpoints.sorted { $0.priority < $1.priority }
    }
    
    private func binding(for provider: TSAEndpoint) -> Binding<Bool> {
        Binding(
            get: { provider.isEnabled },
            set: { newValue in
                if let index = anchorService.failoverConfig.endpoints.firstIndex(where: { $0.id == provider.id }) {
                    anchorService.failoverConfig.endpoints[index].isEnabled = newValue
                    anchorService.updateConfig(anchorService.failoverConfig)
                }
            }
        )
    }
    
    private func movePriority(from source: IndexSet, to destination: Int) {
        var providers = sortedProviders
        providers.move(fromOffsets: source, toOffset: destination)
        
        // Update priorities
        for (index, var provider) in providers.enumerated() {
            provider.priority = index + 1
            if let configIndex = anchorService.failoverConfig.endpoints.firstIndex(where: { $0.id == provider.id }) {
                anchorService.failoverConfig.endpoints[configIndex].priority = index + 1
            }
        }
        
        anchorService.updateConfig(anchorService.failoverConfig)
    }
    
    private func addProvider(_ provider: TSAEndpoint) {
        var config = anchorService.failoverConfig
        config.endpoints.append(provider)
        anchorService.updateConfig(config)
    }
}

// MARK: - TSA Provider Row

struct TSAProviderRow: View {
    let provider: TSAEndpoint
    @Binding var isEnabled: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with toggle
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.headline)
                        
                        if provider.isEidasQualified {
                            Text("eIDAS")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(provider.endpoint.absoluteString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
            }
            
            // Warning badges
            HStack(spacing: 6) {
                // Service level badge
                ServiceLevelBadge(level: provider.serviceLevel)
                
                // Rate limit warnings
                if let interval = provider.recommendedMinIntervalSeconds {
                    WarningBadge(
                        icon: "clock",
                        text: L10n.TSA.intervalWarning(interval),
                        color: .orange
                    )
                }
                
                if let dailyLimit = provider.recommendedMaxRequestsPerDay {
                    WarningBadge(
                        icon: "calendar",
                        text: L10n.TSA.dailyLimitWarning(dailyLimit),
                        color: .orange
                    )
                }
                
                if let monthlyLimit = provider.recommendedMaxRequestsPerMonth {
                    WarningBadge(
                        icon: "calendar.badge.exclamationmark",
                        text: L10n.TSA.monthlyLimitWarning(monthlyLimit),
                        color: .red
                    )
                }
                
                // Commercial use warning
                if provider.commercialAllowed == .prohibited {
                    WarningBadge(
                        icon: "exclamationmark.triangle",
                        text: L10n.TSA.commercialProhibited,
                        color: .red
                    )
                }
            }
            .font(.caption2)
            
            // Documentation links
            if provider.tosUrl != nil || provider.cpsUrl != nil {
                HStack(spacing: 16) {
                    if let tosUrl = provider.tosUrl {
                        Link(destination: tosUrl) {
                            Label(L10n.TSA.termsOfService, systemImage: "doc.text")
                        }
                    }
                    if let cpsUrl = provider.cpsUrl {
                        Link(destination: cpsUrl) {
                            Label(L10n.TSA.cps, systemImage: "doc.badge.gearshape")
                        }
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Service Level Badge

struct ServiceLevelBadge: View {
    let level: ServiceLevel
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
            Text(text)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(backgroundColor.opacity(0.2))
        .foregroundColor(backgroundColor)
        .cornerRadius(4)
    }
    
    private var iconName: String {
        switch level {
        case .production: return "checkmark.circle.fill"
        case .bestEffort: return "exclamationmark.circle"
        case .demo: return "testtube.2"
        }
    }
    
    private var text: String {
        switch level {
        case .production: return L10n.TSA.production
        case .bestEffort: return L10n.TSA.bestEffort
        case .demo: return L10n.TSA.demo
        }
    }
    
    private var backgroundColor: Color {
        switch level {
        case .production: return .green
        case .bestEffort: return .orange
        case .demo: return .gray
        }
    }
}

// MARK: - Warning Badge

struct WarningBadge: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.2))
        .foregroundColor(color)
        .cornerRadius(4)
    }
}

// MARK: - Add TSA Provider View

struct AddTSAProviderView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var endpoint: String = ""
    @State private var selectedRegion: TSARegion = .global
    @State private var isEidasQualified: Bool = false
    
    let onAdd: (TSAEndpoint) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Provider Name", text: $name)
                    TextField("Endpoint URL", text: $endpoint)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
                
                Section {
                    Picker("Region", selection: $selectedRegion) {
                        Text(L10n.TSA.regionGlobal).tag(TSARegion.global)
                        Text(L10n.TSA.regionEU).tag(TSARegion.eu)
                        Text(L10n.TSA.regionUS).tag(TSARegion.us)
                        Text(L10n.TSA.regionAPAC).tag(TSARegion.asiaPacific)
                    }
                    
                    Toggle("eIDAS Qualified", isOn: $isEidasQualified)
                }
                
                Section {
                    Text("Custom TSA providers should be RFC 3161 compliant. Test connectivity before relying on them in production.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add TSA Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addProvider()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private var isValid: Bool {
        !name.isEmpty && URL(string: endpoint) != nil
    }
    
    private func addProvider() {
        guard let url = URL(string: endpoint) else { return }
        
        let provider = TSAEndpoint(
            id: UUID().uuidString,
            name: name,
            endpoint: url,
            priority: 50,
            isEnabled: true,
            commercialAllowed: .unknown,
            recommendedMinIntervalSeconds: nil,
            recommendedMaxRequestsPerDay: nil,
            recommendedMaxRequestsPerMonth: nil,
            isEidasQualified: isEidasQualified,
            region: selectedRegion,
            serviceLevel: .production,
            tosUrl: nil,
            cpsUrl: nil
        )
        
        onAdd(provider)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        List {
            TSASettingsSection(
                anchorService: AnchorService.shared,
                subscriptionService: SubscriptionService.shared
            )
        }
    }
}
