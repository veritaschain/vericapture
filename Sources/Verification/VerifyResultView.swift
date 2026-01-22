//
//  VerifyResultView.swift
//  VeriCapture
//
//  Verification Result Display View
//  © 2026 VeritasChain Standards Organization
//

import SwiftUI

// MARK: - Verification Result View

struct VerifyResultView: View {
    let result: VerificationResult
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Status Header
                    statusHeader
                    
                    // Proof Details（Internal形式またはflashModeがある場合）
                    if result.proof != nil || result.flashMode != nil {
                        proofDetailsSection
                    }
                    
                    // Attested Capture Section（生体認証が試行された場合）
                    if result.isAttestedCapture {
                        attestedSection
                    }
                    
                    // Location Section (法務用エクスポートに含まれる場合のみ)
                    if result.hasLocation {
                        locationSection
                    }
                    
                    // Check Results
                    checksSection
                    
                    // Error Message
                    if let error = result.errorMessage {
                        errorSection(error)
                    }
                    
                    // Footer
                    footerSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.Verify.resultTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Result.close) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Status Header
    
    private var statusHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(result.overallStatus.color.opacity(0.15))
                    .frame(width: 100, height: 100)
                
                Image(systemName: result.overallStatus.icon)
                    .font(.system(size: 50, weight: .medium))
                    .foregroundColor(result.overallStatus.color)
            }
            
            VStack(spacing: 4) {
                Text(result.overallStatus.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(result.overallStatus.color)
                
                Text("\(result.passedChecks)/\(result.totalChecks) \(L10n.Verify.itemsPassed)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // 非技術者向け結論行
            HStack(spacing: 8) {
                Image(systemName: conclusionIcon)
                    .foregroundColor(result.overallStatus.color)
                Text(conclusionText)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(result.overallStatus.color.opacity(0.1))
            .cornerRadius(10)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
    /// 非技術者向け結論テキスト
    private var conclusionText: String {
        switch result.overallStatus {
        case .verified, .anchorVerified:
            return L10n.Verify.resultAuthenticMessage
        case .signatureInvalid:
            return L10n.Verify.resultSignatureInvalidMessage
        case .hashMismatch:
            return L10n.Verify.resultHashMismatchMessage
        case .assetMismatch:
            return L10n.Verify.resultAssetMismatchMessage
        case .anchorPending:
            return L10n.Verify.resultAnchorPendingMessage
        case .pending:
            return L10n.Verify.resultPendingMessage
        case .error:
            return L10n.Verify.resultErrorMessage
        }
    }
    
    /// 非技術者向け結論アイコン
    private var conclusionIcon: String {
        switch result.overallStatus {
        case .verified, .anchorVerified:
            return "checkmark.seal.fill"
        case .signatureInvalid, .hashMismatch, .assetMismatch:
            return "exclamationmark.triangle.fill"
        case .anchorPending:
            return "clock.badge.checkmark"
        case .pending:
            return "hourglass"
        case .error:
            return "xmark.octagon.fill"
        }
    }
    
    // MARK: - Proof Details Section
    
    private var proofDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "doc.text.fill", title: L10n.Verify.proofInfo)
            
            VStack(spacing: 0) {
                if let timestamp = result.captureTimestamp {
                    detailRow(icon: "calendar", label: L10n.Verify.captureTime, value: formatTimestamp(timestamp))
                }
                
                if let device = result.deviceModel {
                    detailRow(icon: "iphone", label: L10n.Verify.device, value: device)
                }
                
                if let os = result.osVersion {
                    detailRow(icon: "gear", label: "OS", value: os)
                }
                
                if let generator = result.generatedBy {
                    detailRow(icon: "camera.fill", label: L10n.Verify.generatedBy, value: generator)
                }
                
                if let eventID = result.eventID {
                    detailRow(icon: "number", label: "Event ID", value: truncateID(eventID), isMonospace: true)
                }
                
                // フラッシュモード（中立的に表示、良し悪しの判定なし）
                if let flashMode = result.flashMode {
                    detailRow(icon: "bolt.fill", label: L10n.Verify.flashMode, value: flashMode, isNeutral: true)
                }
                
                // TSA情報（確定済みまたは未確定）
                if let tsaTime = result.tsaTimestamp {
                    detailRow(icon: "clock.badge.checkmark", label: L10n.Verify.tsaTime, value: formatTimestamp(tsaTime))
                    
                    if let tsaService = result.tsaService, !tsaService.isEmpty {
                        detailRow(icon: "globe", label: L10n.Verify.tsaService, value: tsaService, isLast: result.signerName == nil)
                    }
                } else {
                    // TSA未確定の場合
                    detailRow(icon: "clock", label: L10n.Verify.tsaStatus, value: L10n.Verify.tsaPending, isNeutral: true, isLast: result.signerName == nil)
                }
                
                // 署名者情報（監査用）
                if let signerName = result.signerName {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "person.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            Text(L10n.Verify.signerName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(signerName)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        // 保護状態を表示
                        HStack {
                            Spacer()
                            if result.isSignerHashProtected {
                                Label(L10n.Verify.signerProtected, systemImage: "lock.shield.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            } else {
                                Label(L10n.Verify.signerNotProtected, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Attested Capture Section
    
    @State private var showAttestedInfo = false
    
    private var attestedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "person.badge.shield.checkmark", title: L10n.Verify.resultAttestationSection)
            
            // Attestedバッジ（タップで説明表示）
            Button {
                showAttestedInfo = true
            } label: {
                HStack(spacing: 12) {
                    // アイコン
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.15))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.purple)
                    }
                    
                    // テキスト
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(L10n.Verify.attestedBadge)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.purple)
                            
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(L10n.Verify.resultAttestationDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // ステータス
                    if result.attestedVerified {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(PlainButtonStyle())
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .alert(L10n.AttestedCapture.disclaimer, isPresented: $showAttestedInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(L10n.AttestedCapture.badgeTooltip)
            }
        }
    }
    
    // MARK: - Location Section (法務用エクスポートに含まれる場合のみ)
    
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "location.fill", title: L10n.Verify.resultLocationSection)
            
            VStack(spacing: 0) {
                if let location = result.location {
                    // 地図プレビュー
                    MapPreviewView(latitude: location.latitude, longitude: location.longitude)
                        .frame(height: 150)
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    
                    Divider()
                        .padding(.leading, 16)
                    
                    // 緯度
                    detailRow(
                        icon: "arrow.up.and.down",
                        label: L10n.Verify.resultLatitude,
                        value: String(format: "%.6f", location.latitude),
                        isMonospace: true
                    )
                    
                    // 経度
                    detailRow(
                        icon: "arrow.left.and.right",
                        label: L10n.Verify.resultLongitude,
                        value: String(format: "%.6f", location.longitude),
                        isMonospace: true
                    )
                    
                    // 精度（あれば）
                    if let accuracy = location.accuracy {
                        detailRow(
                            icon: "scope",
                            label: "精度",
                            value: String(format: "±%.1f m", accuracy)
                        )
                    }
                    
                    // 高度（あれば）
                    if let altitude = location.altitude {
                        detailRow(
                            icon: "mountain.2",
                            label: "高度",
                            value: String(format: "%.1f m", altitude),
                            isLast: true
                        )
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            
            // 注意書き
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text(L10n.Verify.resultLocationWarning)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Checks Section
    
    private var checksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "checkmark.shield.fill", title: L10n.Verify.checkItems)
            
            VStack(spacing: 0) {
                ForEach(Array(result.checks.enumerated()), id: \.element.id) { index, check in
                    checkRow(check, isLast: index == result.checks.count - 1)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Error Section
    
    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "exclamationmark.triangle.fill", title: L10n.Verify.errorTitle, color: .red)
            
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        VStack(spacing: 8) {
            Text(L10n.Verify.verifiedByVeriCapture)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("© 2026 VeritasChain Standards Organization")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
            
            Text(L10n.Verify.slogan)
                .font(.caption2)
                .italic()
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.top, 16)
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(icon: String, title: String, color: Color = .primary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            
            Text(title)
                .font(.headline)
                .foregroundColor(color)
        }
    }
    
    private func detailRow(icon: String, label: String, value: String, isMonospace: Bool = false, isNeutral: Bool = false, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isNeutral ? .gray : .secondary)
                    .frame(width: 24)
                
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(value)
                    .font(isMonospace ? .system(.subheadline, design: .monospaced) : .subheadline)
                    .foregroundColor(isNeutral ? .gray : .primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            if !isLast {
                Divider()
                    .padding(.leading, 52)
            }
        }
    }
    
    private func checkRow(_ check: CheckResult, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: check.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(check.color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let details = check.details {
                        Text(details)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                Text(check.status.badge)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(check.status.badgeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(check.status.badgeColor.opacity(0.15))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            if !isLast {
                Divider()
                    .padding(.leading, 52)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatTimestamp(_ timestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: timestamp) {
            return formatDateWithTimezone(date)
        }
        
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: timestamp) {
            return formatDateWithTimezone(date)
        }
        
        return timestamp
    }
    
    /// ローカル時刻＋タイムゾーン明示（例：2026/01/18 18:47:05 JST）
    private func formatDateWithTimezone(_ date: Date) -> String {
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        displayFormatter.timeZone = .current
        
        let dateString = displayFormatter.string(from: date)
        
        // タイムゾーン略称（JST, PST等）を取得
        let tzFormatter = DateFormatter()
        tzFormatter.dateFormat = "zzz"
        tzFormatter.timeZone = .current
        let tzAbbrev = tzFormatter.string(from: date)
        
        return "\(dateString) \(tzAbbrev)"
    }
    
    private func truncateID(_ id: String) -> String {
        if id.count > 24 {
            return String(id.prefix(20)) + "..."
        }
        return id
    }
}

// MARK: - Map Preview View

import MapKit

struct MapPreviewView: View {
    let latitude: Double
    let longitude: Double
    
    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    private var cameraPosition: MapCameraPosition {
        .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }
    
    var body: some View {
        Map(initialPosition: cameraPosition, interactionModes: []) {
            Marker(NSLocalizedString("detail.capture_location_marker", comment: ""), coordinate: coordinate)
                .tint(.red)
        }
        .mapStyle(.standard)
    }
}

// MARK: - Preview

#Preview {
    VerifyResultView(result: VerificationResult(
        timestamp: Date(),
        overallStatus: .verified,
        proof: nil,
        checks: [
            CheckResult(name: L10n.Verify.checkJsonParse, description: L10n.Verify.checkJsonParseDesc, passed: true, details: "OK"),
            CheckResult(name: L10n.Verify.checkEventHashName, description: L10n.Verify.checkEventHashDesc, passed: true, details: L10n.Verify.checkHashMatch),
            CheckResult(name: L10n.Verify.checkSignatureName, description: L10n.Verify.checkSignatureDesc, passed: true, details: L10n.Verify.checkSignatureValid)
        ],
        errorMessage: nil,
        shareableAttested: true,  // プレビュー用
        shareableFlashMode: "AUTO",  // プレビュー用
        shareableCaptureTimestamp: "2026-01-18T09:25:35.854Z",  // プレビュー用
        shareableEventId: "019bd06c-95f1-7b33-b969-824f8f7e6bee",  // プレビュー用
        shareableTsaTimestamp: "2026-01-18T09:30:00Z",  // プレビュー用
        shareableTsaService: "RFC3161"  // プレビュー用
    ))
}
