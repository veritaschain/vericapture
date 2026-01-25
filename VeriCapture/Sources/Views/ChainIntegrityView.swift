//
//  ChainIntegrityView.swift
//  VeriCapture
//
//  Chain Integrity Verification UI
//  © 2026 VeritasChain Standards Organization
//

import SwiftUI

struct ChainIntegrityView: View {
    @State private var statistics: ChainStatistics?
    @State private var verificationResult: ChainVerificationResult?
    @State private var isLoading = false
    @State private var isVerifying = false
    @State private var showErrorDetails = false
    @State private var showResetConfirmation = false
    @State private var isResetting = false
    @State private var showAuthError = false
    @State private var authErrorMessage = ""
    
    var body: some View {
        List {
            // ステータスセクション
            Section {
                if let stats = statistics {
                    StatisticsCard(statistics: stats)
                } else if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                }
            } header: {
                Text(L10n.Chain.statisticsTitle)
            }
            
            // 検証結果セクション
            Section {
                if let result = verificationResult {
                    VerificationResultCard(result: result, showDetails: $showErrorDetails)
                } else {
                    Button {
                        runVerification()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.shield")
                                .foregroundColor(.green)
                            Text(L10n.Chain.runVerification)
                            Spacer()
                            if isVerifying {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(isVerifying)
                }
            } header: {
                Text(L10n.Chain.verificationTitle)
            } footer: {
                Text(L10n.Chain.verificationFooter)
            }
            
            // エラー詳細セクション（エラーがある場合のみ）
            if let result = verificationResult, !result.errors.isEmpty, showErrorDetails {
                Section {
                    ForEach(result.errors) { error in
                        ErrorDetailRow(error: error)
                    }
                } header: {
                    Text(L10n.Chain.errorDetailsTitle)
                }
            }
            
            // チェーンリセットセクション（常に表示）
            Section {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text(L10n.Chain.resetChain)
                        Spacer()
                        if isResetting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isResetting)
            } header: {
                Text(L10n.Chain.dangerZone)
            } footer: {
                Text(L10n.Chain.resetChainFooter)
            }
            
            // 説明セクション
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    ExplanationRow(
                        icon: "link",
                        title: L10n.Chain.explainPrevHash,
                        description: L10n.Chain.explainPrevHashDesc
                    )
                    
                    Divider()
                    
                    ExplanationRow(
                        icon: "number",
                        title: L10n.Chain.explainEventHash,
                        description: L10n.Chain.explainEventHashDesc
                    )
                    
                    Divider()
                    
                    ExplanationRow(
                        icon: "xmark.seal",
                        title: L10n.Chain.explainTombstone,
                        description: L10n.Chain.explainTombstoneDesc
                    )
                }
                .padding(.vertical, 4)
            } header: {
                Text(L10n.Chain.howItWorks)
            }
        }
        .navigationTitle(L10n.Chain.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadStatistics()
        }
        .refreshable {
            loadStatistics()
            verificationResult = nil
        }
        .confirmationDialog(
            L10n.Chain.resetConfirmTitle,
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.Chain.resetConfirmButton, role: .destructive) {
                resetChain()
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Chain.resetConfirmMessage)
        }
        .alert(L10n.Chain.authError, isPresented: $showAuthError) {
            Button(L10n.Common.ok, role: .cancel) {}
        } message: {
            Text(authErrorMessage)
        }
    }
    
    private func loadStatistics() {
        isLoading = true
        Task {
            do {
                // v40: 現在のケースのchainIdでフィルタリング
                let chainId = CaseService.shared.currentChainId
                let stats = try StorageService.shared.getChainStatistics(chainId: chainId)
                await MainActor.run {
                    self.statistics = stats
                    self.isLoading = false
                }
            } catch {
                print("[ChainIntegrityView] Error loading statistics: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func runVerification() {
        isVerifying = true
        Task {
            do {
                // v40: 現在のケースのchainIdでフィルタリング
                let chainId = CaseService.shared.currentChainId
                let result = try StorageService.shared.verifyChainIntegrity(chainId: chainId)
                await MainActor.run {
                    self.verificationResult = result
                    self.isVerifying = false
                    if !result.errors.isEmpty {
                        self.showErrorDetails = true
                    }
                }
            } catch {
                print("[ChainIntegrityView] Verification error: \(error)")
                await MainActor.run {
                    self.isVerifying = false
                }
            }
        }
    }
    
    private func resetChain() {
        isResetting = true
        Task {
            // 生体認証を要求
            let authResult = await BiometricAuthService.shared.authenticate(for: .resetChain)
            
            await MainActor.run {
                switch authResult {
                case .success, .notAvailable:
                    // 認証成功：リセット実行
                    performResetChain()
                case .cancelled:
                    isResetting = false
                case .failed(let error):
                    isResetting = false
                    authErrorMessage = L10n.Chain.authFailed(error)
                    showAuthError = true
                }
            }
        }
    }
    
    private func performResetChain() {
        Task {
            do {
                try StorageService.shared.resetChain()
                await MainActor.run {
                    self.isResetting = false
                    self.verificationResult = nil
                    self.statistics = nil
                    loadStatistics()
                }
            } catch {
                print("[ChainIntegrityView] Reset error: \(error)")
                await MainActor.run {
                    self.isResetting = false
                }
            }
        }
    }
}

// MARK: - Statistics Card

struct StatisticsCard: View {
    let statistics: ChainStatistics
    @State private var showStatsInfo = false
    
    var body: some View {
        VStack(spacing: 16) {
            // メイン統計
            HStack(spacing: 20) {
                StatItem(
                    value: "\(statistics.totalEvents)",
                    label: L10n.Chain.totalEvents,
                    color: .primary
                )
                
                Divider()
                    .frame(height: 40)
                
                StatItem(
                    value: "\(statistics.activeEvents)",
                    label: L10n.Chain.activeEvents,
                    color: .green
                )
                
                Divider()
                    .frame(height: 40)
                
                StatItem(
                    value: "\(statistics.invalidatedEvents)",
                    label: L10n.Chain.invalidatedEvents,
                    color: .orange
                )
            }
            
            Divider()
            
            // 詳細統計
            HStack {
                DetailStatItem(
                    icon: "xmark.seal.fill",
                    label: L10n.Chain.tombstones,
                    value: "\(statistics.tombstoneCount)"
                )
                
                Spacer()
                
                DetailStatItem(
                    icon: "checkmark.shield.fill",
                    label: L10n.Chain.anchored,
                    value: "\(statistics.anchoredEvents)"
                )
                
                Spacer()
                
                DetailStatItem(
                    icon: "clock.fill",
                    label: L10n.Chain.pendingAnchor,
                    value: "\(statistics.pendingAnchorEvents)"
                )
            }
            
            // 日付範囲
            if let oldest = statistics.oldestEventDate, let newest = statistics.newestEventDate {
                Divider()
                
                HStack {
                    VStack(alignment: .leading) {
                        Text(L10n.Chain.dateRange)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(formatDate(oldest)) → \(formatDate(newest))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    // 統計説明ボタン
                    Button {
                        showStatsInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 統計説明（展開時）
            if showStatsInfo {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    Text(L10n.Chain.statsNote)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text(L10n.Chain.activeEvents)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            Text(L10n.Chain.activeNote)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(L10n.Chain.invalidatedEvents)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            Text(L10n.Chain.invalidatedNote)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: isoString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            return displayFormatter.string(from: date)
        }
        
        // フォールバック
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: isoString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            return displayFormatter.string(from: date)
        }
        
        return isoString.prefix(10).description
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DetailStatItem: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Verification Result Card

struct VerificationResultCard: View {
    let result: ChainVerificationResult
    @Binding var showDetails: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            // ステータスアイコン
            HStack {
                if result.hasRealErrors {
                    // 実際のエラーあり
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundColor(.red)
                } else if result.warningCount > 0 {
                    // 警告のみ
                    Image(systemName: "checkmark.circle.badge.questionmark")
                        .font(.title)
                        .foregroundColor(.orange)
                } else {
                    // 完全にOK
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading) {
                    if result.hasRealErrors {
                        Text(L10n.Chain.verificationFailed)
                            .font(.headline)
                            .foregroundColor(.red)
                    } else if result.warningCount > 0 {
                        Text(L10n.Chain.verificationPassedWithWarnings)
                            .font(.headline)
                            .foregroundColor(.orange)
                    } else {
                        Text(L10n.Chain.verificationPassed)
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    
                    Text(L10n.Chain.checkedFormat(result.checkedEvents, result.checkedTombstones))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // 検証時刻
            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(L10n.Chain.verifiedAt(formatTime(result.verifiedAt)))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            // エラー・警告がある場合
            if !result.errors.isEmpty {
                Divider()
                
                Button {
                    withAnimation {
                        showDetails.toggle()
                    }
                } label: {
                    HStack {
                        if result.hasRealErrors {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.red)
                            Text(L10n.Chain.errorsFound(result.errorCount))
                                .foregroundColor(.red)
                        } else {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                            Text(L10n.Chain.warningsFound(result.warningCount))
                                .foregroundColor(.orange)
                        }
                        Spacer()
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Error Detail Row

struct ErrorDetailRow: View {
    let error: ChainVerificationError
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconForErrorType(error.errorType))
                    .foregroundColor(error.isWarning ? .orange : .red)
                Text(titleForErrorType(error.errorType))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(error.isWarning ? .orange : .primary)
                Spacer()
                if error.isWarning {
                    Text(L10n.Chain.warningBadge)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
                Text("#\(error.index + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(L10n.Chain.eventLabel(String(error.eventId.prefix(20)) + "..."))
                .font(.caption)
                .foregroundColor(.secondary)
            
            if error.errorType == .prevHashMismatch || error.errorType == .eventHashMismatch || error.errorType == .deletedEventGap {
                VStack(alignment: .leading, spacing: 2) {
                    if error.errorType == .deletedEventGap {
                        Text(L10n.Chain.deletedEventGapMessage)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    } else {
                        Text(L10n.Chain.expectedLabel(String(error.expectedValue.prefix(30)) + "..."))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(L10n.Chain.actualLabel(String(error.actualValue.prefix(30)) + "..."))
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func iconForErrorType(_ type: ChainErrorType) -> String {
        switch type {
        case .prevHashMismatch: return "link.badge.xmark"
        case .eventHashMismatch: return "number.square"
        case .signatureInvalid: return "signature"
        case .tombstoneTargetMismatch: return "xmark.seal"
        case .orphanedTombstone: return "questionmark.circle"
        case .timestampAnomaly: return "clock.badge.exclamationmark"
        case .deletedEventGap: return "trash.circle"
        }
    }
    
    private func titleForErrorType(_ type: ChainErrorType) -> String {
        switch type {
        case .prevHashMismatch: return L10n.Chain.errorPrevHash
        case .eventHashMismatch: return L10n.Chain.errorEventHash
        case .signatureInvalid: return L10n.Chain.errorSignature
        case .tombstoneTargetMismatch: return L10n.Chain.errorTombstoneTarget
        case .orphanedTombstone: return L10n.Chain.errorOrphanedTombstone
        case .timestampAnomaly: return L10n.Chain.errorTimestamp
        case .deletedEventGap: return L10n.Chain.errorDeletedGap
        }
    }
}

// MARK: - Explanation Row

struct ExplanationRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.green)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ChainIntegrityView()
    }
}
