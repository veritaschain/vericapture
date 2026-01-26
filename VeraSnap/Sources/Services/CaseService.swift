//
//  CaseService.swift
//  VeraSnap
//
//  Created by VeritasChain on 2026/01/21.
//  Copyright © 2026 VeritasChain Co., Ltd. All rights reserved.
//
//  CaseService - v40.0
//  Manages case/project lifecycle and provides current active ChainID
//  for capture operations.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the current case selection changes
    static let caseDidChange = Notification.Name("caseDidChange")
    
    /// Posted when case list is updated
    static let casesDidUpdate = Notification.Name("casesDidUpdate")
}

// MARK: - CaseService

@MainActor
final class CaseService: ObservableObject {
    
    // MARK: Singleton
    
    static let shared = CaseService()
    
    // MARK: Published Properties
    
    /// All active (non-archived) cases
    @Published private(set) var cases: [Case] = []
    
    /// All cases including archived
    @Published private(set) var allCases: [Case] = []
    
    /// Currently selected case
    @Published var currentCase: Case? {
        didSet {
            if let caseItem = currentCase {
                UserDefaults.standard.set(caseItem.caseId, forKey: Keys.currentCaseId)
                NotificationCenter.default.post(name: .caseDidChange, object: caseItem)
            }
        }
    }
    
    /// Loading state
    @Published var isLoading = false
    
    /// Error message for display
    @Published var errorMessage: String?
    
    // MARK: Computed Properties
    
    /// Current case's ChainID (used by CaptureViewModel)
    var currentChainId: String? {
        currentCase?.chainId
    }
    
    /// Whether the service has been initialized
    private(set) var isInitialized = false
    
    // MARK: Private Properties
    
    private let storageService = StorageService.shared
    
    // MARK: Keys
    
    private enum Keys {
        static let currentCaseId = "currentCaseId"
        static let hasMigratedToCases = "hasMigratedToCases_v40"
    }
    
    // MARK: Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Initialize case service on app launch
    func initialize() {
        guard !isInitialized else { return }
        
        Task {
            await migrateIfNeeded()
            await loadCases()
            await restoreLastCase()
            
            // Clean up orphaned events (events not belonging to any case)
            storageService.cleanupOrphanedEvents()
            
            isInitialized = true
            print("[CaseService] Initialized with \(cases.count) cases")
        }
    }
    
    /// Load all cases from database
    func loadCases() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            allCases = try storageService.getAllCases(includeArchived: true)
            cases = allCases.filter { !$0.isArchived }
            
            // Sort by last capture date, then by creation date
            cases.sort { (a, b) -> Bool in
                if let aDate = a.lastCaptureAt, let bDate = b.lastCaptureAt {
                    return aDate > bDate
                } else if a.lastCaptureAt != nil {
                    return true
                } else if b.lastCaptureAt != nil {
                    return false
                }
                return a.createdAt > b.createdAt
            }
            
            NotificationCenter.default.post(name: .casesDidUpdate, object: nil)
        } catch {
            errorMessage = "Failed to load cases: \(error.localizedDescription)"
            print("[CaseService] Load error: \(error)")
        }
    }
    
    /// Restore last selected case from UserDefaults
    func restoreLastCase() async {
        if let savedCaseId = UserDefaults.standard.string(forKey: Keys.currentCaseId),
           let savedCase = cases.first(where: { $0.caseId == savedCaseId }) {
            currentCase = savedCase
        } else if let firstCase = cases.first {
            // Default to first case if no saved selection
            currentCase = firstCase
        }
    }
    
    /// Migrate existing data to default case (first launch after v40 update)
    func migrateIfNeeded() async {
        // Check if already migrated
        guard !UserDefaults.standard.bool(forKey: Keys.hasMigratedToCases) else {
            return
        }
        
        do {
            // Check if any cases exist
            let existingCases = try storageService.getAllCases(includeArchived: true)
            if !existingCases.isEmpty {
                // Cases already exist, mark as migrated
                UserDefaults.standard.set(true, forKey: Keys.hasMigratedToCases)
                return
            }
            
            // Get existing chainId from events table
            let existingChainId = try? storageService.getOrCreateChainId()
            
            // Create default case
            let defaultCase = Case.createDefault(existingChainId: existingChainId)
            try storageService.createCase(defaultCase)
            
            // Update event count from existing events
            storageService.updateCaseStatistics(caseId: defaultCase.caseId)
            
            print("[CaseService] Migration complete. Created default case with chainId: \(defaultCase.chainId)")
            
            UserDefaults.standard.set(true, forKey: Keys.hasMigratedToCases)
        } catch {
            print("[CaseService] Migration error: \(error)")
            errorMessage = "Migration failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - CRUD Operations
    
    /// Create new case with dedicated chain
    func createCase(
        name: String,
        description: String? = nil,
        icon: CaseIcon = .folder,
        color: CaseColor = .blue
    ) async throws -> Case {
        // Validation
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CaseError.nameEmpty
        }
        guard trimmedName.count <= 100 else {
            throw CaseError.nameTooLong
        }
        
        // Check for duplicate name
        if cases.contains(where: { $0.name.lowercased() == trimmedName.lowercased() }) {
            throw CaseError.duplicateName
        }
        
        // Create case
        let newCase = Case(
            name: trimmedName,
            description: description,
            icon: icon.rawValue,
            colorHex: color.rawValue
        )
        
        try storageService.createCase(newCase)
        
        // Reload cases
        await loadCases()
        
        // Select the new case
        currentCase = newCase
        
        print("[CaseService] Created case: \(newCase.name) (chainId: \(newCase.chainId))")
        
        return newCase
    }
    
    /// Update case metadata
    func updateCase(_ caseItem: Case) async throws {
        var updatedCase = caseItem
        updatedCase.updatedAt = Date()
        
        try storageService.updateCase(updatedCase)
        
        // Reload cases
        await loadCases()
        
        // Update current case if it was the one edited
        if currentCase?.caseId == updatedCase.caseId {
            currentCase = updatedCase
        }
        
        print("[CaseService] Updated case: \(updatedCase.name)")
    }
    
    /// Select case (sets as current and broadcasts notification)
    func selectCase(_ caseItem: Case) {
        guard currentCase?.caseId != caseItem.caseId else { return }
        currentCase = caseItem
        print("[CaseService] Selected case: \(caseItem.name)")
    }
    
    /// Archive case (hides from active list but preserves data)
    func archiveCase(_ caseItem: Case) async throws {
        var updatedCase = caseItem
        updatedCase.isArchived = true
        updatedCase.updatedAt = Date()
        
        try storageService.updateCase(updatedCase)
        
        await loadCases()
        
        // If archived case was current, switch to first available
        if currentCase?.caseId == caseItem.caseId {
            currentCase = cases.first
        }
        
        print("[CaseService] Archived case: \(caseItem.name)")
    }
    
    /// Unarchive case
    func unarchiveCase(_ caseItem: Case) async throws {
        var updatedCase = caseItem
        updatedCase.isArchived = false
        updatedCase.updatedAt = Date()
        
        try storageService.updateCase(updatedCase)
        
        await loadCases()
        
        print("[CaseService] Unarchived case: \(caseItem.name)")
    }
    
    /// Delete case (fails if events exist unless force=true)
    func deleteCase(_ caseItem: Case, force: Bool = false) async throws {
        // Check event count
        let stats = getCaseStatistics(caseItem)
        if let stats = stats, stats.eventCount > 0 && !force {
            throw CaseError.caseHasEvents(count: stats.eventCount)
        }
        
        try storageService.deleteCase(caseId: caseItem.caseId, force: force)
        
        await loadCases()
        
        // If deleted case was current, switch to first available
        if currentCase?.caseId == caseItem.caseId {
            currentCase = cases.first
        }
        
        print("[CaseService] Deleted case: \(caseItem.name) (force: \(force))")
    }
    
    // MARK: - Statistics
    
    /// Get detailed statistics for a case
    func getCaseStatistics(_ caseItem: Case) -> CaseStatistics? {
        return storageService.getCaseStatistics(caseId: caseItem.caseId)
    }
    
    // MARK: - Export
    
    /// Export case as JSON package (metadata only)
    func exportCase(_ caseItem: Case, includeLocation: Bool = false) async throws -> URL {
        return try storageService.exportCase(caseId: caseItem.caseId, includeLocation: includeLocation)
    }
    
    /// Export case as ZIP package with photos
    func exportCaseAsZip(_ caseItem: Case, includeLocation: Bool = false) async throws -> URL {
        return try storageService.exportCaseAsZip(caseId: caseItem.caseId, includeLocation: includeLocation)
    }
    
    // MARK: - Capture Callbacks
    
    /// Called after successful capture to update case statistics
    func onCaptureCompleted(eventId: String) {
        guard let caseItem = currentCase else { return }
        
        Task {
            // 実際のデータベースからカウントを更新
            storageService.updateCaseStatistics(caseId: caseItem.caseId)
            await loadCases()
            
            // Refresh current case
            if let refreshed = cases.first(where: { $0.caseId == caseItem.caseId }) {
                currentCase = refreshed
            }
        }
    }
    
    /// Called after event deletion to update case statistics
    func onEventDeleted(eventId: String, chainId: String) {
        Task {
            // Find case by chainId
            if let caseItem = allCases.first(where: { $0.chainId == chainId }) {
                storageService.updateCaseStatistics(caseId: caseItem.caseId)
                await loadCases()
                
                // Refresh current case
                if currentCase?.caseId == caseItem.caseId,
                   let refreshed = cases.first(where: { $0.caseId == caseItem.caseId }) {
                    currentCase = refreshed
                }
            }
        }
    }
    
    /// Refresh statistics for all cases
    @MainActor
    func refreshAllCaseStatistics() async {
        for caseItem in allCases {
            storageService.updateCaseStatistics(caseId: caseItem.caseId)
        }
        await loadCases()
        
        // Refresh current case
        if let current = currentCase,
           let refreshed = cases.first(where: { $0.caseId == current.caseId }) {
            currentCase = refreshed
        }
    }
    
    // MARK: - Quick Actions
    
    /// Get or create quick capture case
    func getQuickCaptureCase() async throws -> Case {
        // Look for existing quick capture case
        if let quickCase = cases.first(where: { $0.name == L10n.Case.quickCapture }) {
            return quickCase
        }
        
        // Create new quick capture case
        return try await createCase(
            name: L10n.Case.quickCapture,
            description: nil,
            icon: .camera,
            color: .orange
        )
    }
}
