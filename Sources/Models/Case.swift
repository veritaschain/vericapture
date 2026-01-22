//
//  Case.swift
//  VeriCapture
//
//  Created by VeritasChain on 2026/01/21.
//  Copyright © 2026 VeritasChain Co., Ltd. All rights reserved.
//
//  Case (Project) Model - v40.0
//  Enables project-based organization of capture events.
//  Each case maintains its own independent hash chain (1 Case = 1 ChainID).
//

import Foundation
import SwiftUI

// MARK: - Case Model

/// Case represents a project/site container for organizing captures.
/// Each case has its own dedicated ChainID, ensuring complete isolation
/// of hash chains between different contexts.
struct Case: Identifiable, Codable, Hashable, Sendable {
    // MARK: Identity
    
    /// Unique case identifier (UUIDv7 format)
    let caseId: String
    
    /// Dedicated chain identifier for this case (UUIDv7 format)
    /// All events captured in this case will use this chainId
    let chainId: String
    
    // MARK: User-defined Metadata
    
    /// Display name (e.g., "Construction Site A", "Incident 2026-01")
    var name: String
    
    /// Optional description or notes
    var description: String?
    
    /// SF Symbol name for icon display
    var icon: String
    
    /// Hex color code for UI theming (e.g., "007AFF")
    var colorHex: String
    
    // MARK: Timestamps
    
    /// Case creation timestamp
    let createdAt: Date
    
    /// Last modification timestamp
    var updatedAt: Date
    
    // MARK: State
    
    /// Whether the case is archived (hidden from active list)
    var isArchived: Bool
    
    /// Cached event count for performance
    var eventCount: Int
    
    /// Timestamp of last capture in this case
    var lastCaptureAt: Date?
    
    // MARK: Identifiable
    
    var id: String { caseId }
    
    // MARK: Computed Properties
    
    /// SwiftUI Color from hex string
    var color: Color {
        Color(hex: colorHex) ?? .blue
    }
    
    /// Formatted creation date
    var createdAtFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
    /// Formatted last capture date
    var lastCaptureFormatted: String? {
        guard let date = lastCaptureAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: Initialization
    
    init(
        caseId: String? = nil,
        chainId: String? = nil,
        name: String,
        description: String? = nil,
        icon: String = CaseIcon.folder.rawValue,
        colorHex: String = CaseColor.blue.rawValue,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        eventCount: Int = 0,
        lastCaptureAt: Date? = nil
    ) {
        self.caseId = caseId ?? Self.generateUUIDv7()
        self.chainId = chainId ?? Self.generateUUIDv7()
        self.name = name
        self.description = description
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.eventCount = eventCount
        self.lastCaptureAt = lastCaptureAt
    }
    
    // MARK: Factory Methods
    
    /// Create default case (used for migration)
    static func createDefault(existingChainId: String? = nil) -> Case {
        Case(
            chainId: existingChainId,
            name: "Default",
            description: nil,
            icon: CaseIcon.folder.rawValue,
            colorHex: CaseColor.blue.rawValue
        )
    }
    
    // MARK: UUIDv7 Generator
    
    private static func generateUUIDv7() -> String {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        var uuid = [UInt8](repeating: 0, count: 16)
        
        // Timestamp (48 bits)
        uuid[0] = UInt8((timestamp >> 40) & 0xFF)
        uuid[1] = UInt8((timestamp >> 32) & 0xFF)
        uuid[2] = UInt8((timestamp >> 24) & 0xFF)
        uuid[3] = UInt8((timestamp >> 16) & 0xFF)
        uuid[4] = UInt8((timestamp >> 8) & 0xFF)
        uuid[5] = UInt8(timestamp & 0xFF)
        
        // Version 7 + random
        uuid[6] = UInt8.random(in: 0...255)
        uuid[6] = (uuid[6] & 0x0F) | 0x70
        
        // Random
        uuid[7] = UInt8.random(in: 0...255)
        
        // Variant + random
        uuid[8] = UInt8.random(in: 0...255)
        uuid[8] = (uuid[8] & 0x3F) | 0x80
        
        // Random
        for i in 9..<16 {
            uuid[i] = UInt8.random(in: 0...255)
        }
        
        // Format as UUID string
        let hex = uuid.map { String(format: "%02x", $0) }.joined()
        let index1 = hex.index(hex.startIndex, offsetBy: 8)
        let index2 = hex.index(hex.startIndex, offsetBy: 12)
        let index3 = hex.index(hex.startIndex, offsetBy: 16)
        let index4 = hex.index(hex.startIndex, offsetBy: 20)
        
        return "\(hex[..<index1])-\(hex[index1..<index2])-\(hex[index2..<index3])-\(hex[index3..<index4])-\(hex[index4...])"
    }
}

// MARK: - CaseColor

/// Predefined color options for cases
enum CaseColor: String, CaseIterable, Codable, Sendable {
    case blue = "007AFF"
    case green = "34C759"
    case orange = "FF9500"
    case red = "FF3B30"
    case purple = "AF52DE"
    case pink = "FF2D55"
    case teal = "5AC8FA"
    case indigo = "5856D6"
    case brown = "A2845E"
    case gray = "8E8E93"
    
    var color: Color {
        Color(hex: rawValue) ?? .blue
    }
    
    var name: String {
        switch self {
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .red: return "Red"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .teal: return "Teal"
        case .indigo: return "Indigo"
        case .brown: return "Brown"
        case .gray: return "Gray"
        }
    }
}

// MARK: - CaseIcon

/// Predefined SF Symbol icons for cases
enum CaseIcon: String, CaseIterable, Codable, Sendable {
    case folder = "folder.fill"
    case building = "building.2.fill"
    case house = "house.fill"
    case car = "car.fill"
    case wrench = "wrench.and.screwdriver.fill"
    case doc = "doc.fill"
    case camera = "camera.fill"
    case map = "map.fill"
    case person = "person.fill"
    case briefcase = "briefcase.fill"
    case shippingbox = "shippingbox.fill"
    case hammer = "hammer.fill"
    
    var name: String {
        switch self {
        case .folder: return "Folder"
        case .building: return "Building"
        case .house: return "House"
        case .car: return "Vehicle"
        case .wrench: return "Tools"
        case .doc: return "Document"
        case .camera: return "Camera"
        case .map: return "Location"
        case .person: return "Person"
        case .briefcase: return "Business"
        case .shippingbox: return "Package"
        case .hammer: return "Construction"
        }
    }
}

// MARK: - CaseStatistics

/// Detailed statistics for a case
struct CaseStatistics: Sendable {
    let caseId: String
    let caseName: String
    let eventCount: Int
    let activeCount: Int
    let invalidatedCount: Int
    let tombstoneCount: Int
    let anchoredCount: Int
    let pendingCount: Int
    let firstEventDate: Date?
    let lastEventDate: Date?
    let totalMediaSize: Int64
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalMediaSize, countStyle: .file)
    }
    
    var dateRangeFormatted: String? {
        guard let first = firstEventDate, let last = lastEventDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return "\(formatter.string(from: first)) - \(formatter.string(from: last))"
    }
}

// MARK: - CaseExportPackage

/// Self-contained export package for a case
struct CaseExportPackage: Codable, Sendable {
    let exportVersion: String
    let exportedAt: String
    let caseInfo: CaseExportInfo
    let chainInfo: ChainExportInfo
    let events: [CaseExportEvent]
    let tombstones: [CaseExportTombstone]
    let statistics: CaseExportStatistics
}

struct CaseExportInfo: Codable, Sendable {
    let caseId: String
    let name: String
    let description: String?
    let createdAt: String
    let icon: String
    let colorHex: String
}

struct ChainExportInfo: Codable, Sendable {
    let chainId: String
    let genesisEventId: String?
    let latestEventId: String?
    let latestEventHash: String?
}

struct CaseExportEvent: Codable, Sendable {
    let eventId: String
    let timestamp: String
    let eventHash: String
    let assetHash: String
    let isAnchored: Bool
}

struct CaseExportTombstone: Codable, Sendable {
    let tombstoneId: String
    let targetEventId: String
    let reasonCode: String
    let timestamp: String
}

struct CaseExportStatistics: Codable, Sendable {
    let totalEvents: Int
    let activeEvents: Int
    let invalidatedEvents: Int
    let anchoredEvents: Int
    let pendingEvents: Int
}

// MARK: - CaseError

/// Errors related to case operations
enum CaseError: Error, LocalizedError {
    case caseNotFound
    case caseHasEvents(count: Int)
    case nameTooLong
    case nameEmpty
    case duplicateName
    case chainIdConflict
    case migrationFailed(Error)
    case exportFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .caseNotFound:
            return "Case not found"
        case .caseHasEvents(let count):
            return "Case contains \(count) events. Delete events first or use force delete."
        case .nameTooLong:
            return "Case name is too long (max 100 characters)"
        case .nameEmpty:
            return "Case name cannot be empty"
        case .duplicateName:
            return "A case with this name already exists"
        case .chainIdConflict:
            return "Chain ID conflict detected"
        case .migrationFailed(let error):
            return "Migration failed: \(error.localizedDescription)"
        case .exportFailed(let error):
            return "Export failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        guard hexSanitized.count == 6 else { return nil }
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
    
    var hexString: String? {
        guard let components = UIColor(self).cgColor.components else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
