//
//  ConformanceLevel.swift
//  VeraSnap
//
//  CPP Conformance Level Model
//  © 2026 VeritasChain Standards Organization
//
//  Defines proof strength levels based on verification capabilities

import SwiftUI

// MARK: - Conformance Level

/// CPP Conformance Level - 証明力レベル
/// 
/// | レベル | 条件 | 証明力 |
/// |--------|------|--------|
/// | Bronze | 端末時刻のみ（TSA待ち） | 低 |
/// | Silver | 外部TSA取得済み | 中 |
/// | Gold | TSA + ACE（生体認証） | 高 |
enum ConformanceLevel: String, Codable, Sendable, CaseIterable {
    case bronze = "Bronze"
    case silver = "Silver"
    case gold = "Gold"
    
    // MARK: - Properties
    
    /// 表示名（ローカライズ済み）
    var displayName: String {
        switch self {
        case .bronze: return L10n.Conformance.bronze
        case .silver: return L10n.Conformance.silver
        case .gold: return L10n.Conformance.gold
        }
    }
    
    /// 説明文（ローカライズ済み）
    var description: String {
        switch self {
        case .bronze: return L10n.Conformance.bronzeDesc
        case .silver: return L10n.Conformance.silverDesc
        case .gold: return L10n.Conformance.goldDesc
        }
    }
    
    /// 証明力の説明
    var proofStrength: String {
        switch self {
        case .bronze: return L10n.Conformance.strengthLow
        case .silver: return L10n.Conformance.strengthMedium
        case .gold: return L10n.Conformance.strengthHigh
        }
    }
    
    /// アイコン
    var icon: String {
        switch self {
        case .bronze: return "shield"
        case .silver: return "shield.lefthalf.filled"
        case .gold: return "shield.fill"
        }
    }
    
    /// カラー
    var color: Color {
        switch self {
        case .bronze: return Color(red: 0.8, green: 0.5, blue: 0.2)  // Bronze color
        case .silver: return Color(red: 0.75, green: 0.75, blue: 0.75)  // Silver color
        case .gold: return Color(red: 1.0, green: 0.84, blue: 0.0)  // Gold color
        }
    }
    
    /// バッジ背景色
    var backgroundColor: Color {
        switch self {
        case .bronze: return Color(red: 0.8, green: 0.5, blue: 0.2).opacity(0.15)
        case .silver: return Color(red: 0.6, green: 0.6, blue: 0.6).opacity(0.15)
        case .gold: return Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.15)
        }
    }
    
    /// 数値レベル（比較用）
    var numericLevel: Int {
        switch self {
        case .bronze: return 1
        case .silver: return 2
        case .gold: return 3
        }
    }
    
    // MARK: - Factory Methods
    
    /// イベントデータからConformanceLevelを判定
    /// - Parameters:
    ///   - hasTimestamp: 外部TSAタイムスタンプがあるか
    ///   - hasHumanAttestation: 生体認証があるか
    /// - Returns: 判定されたConformanceLevel
    static func determine(hasTimestamp: Bool, hasHumanAttestation: Bool) -> ConformanceLevel {
        if hasTimestamp && hasHumanAttestation {
            return .gold
        } else if hasTimestamp {
            return .silver
        } else {
            return .bronze
        }
    }
    
    /// AnchorStatusとAttestation状態から判定
    static func from(anchorStatus: String?, isAttested: Bool) -> ConformanceLevel {
        let hasTimestamp = anchorStatus?.uppercased() == "COMPLETED"
        return determine(hasTimestamp: hasTimestamp, hasHumanAttestation: isAttested)
    }
}

// MARK: - Conformance Badge View

/// コンフォーマンスレベルバッジ（コンパクト版）
struct ConformanceBadge: View {
    let level: ConformanceLevel
    var showLabel: Bool = true
    var size: BadgeSize = .medium
    
    enum BadgeSize {
        case small   // ギャラリーサムネイル用
        case medium  // 詳細画面用
        case large   // 検証画面用
        
        var iconSize: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 16
            case .large: return 20
            }
        }
        
        var fontSize: Font {
            switch self {
            case .small: return .caption2
            case .medium: return .caption
            case .large: return .subheadline
            }
        }
        
        var padding: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            case .large: return 8
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.icon)
                .font(.system(size: size.iconSize, weight: .semibold))
                .foregroundColor(level.color)
            
            if showLabel {
                Text(level.displayName)
                    .font(size.fontSize)
                    .fontWeight(.medium)
                    .foregroundColor(level.color)
            }
        }
        .padding(.horizontal, size.padding)
        .padding(.vertical, size.padding / 2)
        .background(level.backgroundColor)
        .cornerRadius(size.padding)
    }
}

// MARK: - Conformance Level Card

/// コンフォーマンスレベル詳細カード（詳細画面用）
struct ConformanceLevelCard: View {
    let level: ConformanceLevel
    var showDescription: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: level.icon)
                    .font(.title2)
                    .foregroundColor(level.color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(level.proofStrength)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // レベルインジケーター
                HStack(spacing: 4) {
                    ForEach(1...3, id: \.self) { i in
                        Circle()
                            .fill(i <= level.numericLevel ? level.color : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
            }
            
            if showDescription {
                Text(level.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(level.backgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Conformance Level Indicator (Minimal)

/// ミニマルなレベルインジケーター（ギャラリーオーバーレイ用）
struct ConformanceLevelIndicator: View {
    let level: ConformanceLevel
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: level.icon)
                .font(.system(size: 10, weight: .bold))
            
            Text(level.rawValue.prefix(1))  // B, S, G
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(level.color.opacity(0.9))
                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct ConformanceLevel_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Badges
            HStack(spacing: 10) {
                ConformanceBadge(level: .bronze, size: .small)
                ConformanceBadge(level: .silver, size: .small)
                ConformanceBadge(level: .gold, size: .small)
            }
            
            HStack(spacing: 10) {
                ConformanceBadge(level: .bronze, size: .medium)
                ConformanceBadge(level: .silver, size: .medium)
                ConformanceBadge(level: .gold, size: .medium)
            }
            
            // Indicators
            HStack(spacing: 10) {
                ConformanceLevelIndicator(level: .bronze)
                ConformanceLevelIndicator(level: .silver)
                ConformanceLevelIndicator(level: .gold)
            }
            
            Divider()
            
            // Cards
            ConformanceLevelCard(level: .bronze)
            ConformanceLevelCard(level: .silver)
            ConformanceLevelCard(level: .gold)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
