//
//  CaseManagementViews.swift
//  VeraSnap
//
//  Created by VeritasChain on 2026/01/21.
//  Copyright © 2026 VeritasChain Co., Ltd. All rights reserved.
//
//  Case Management Views - v40.0
//  UI components for case/project management.
//

import SwiftUI
import UIKit

// MARK: - CaseListView

/// Main case management screen
struct CaseListView: View {
    @ObservedObject private var caseService = CaseService.shared
    @State private var showCreateSheet = false
    @State private var showArchivedCases = false
    @State private var selectedCaseForEdit: Case?
    @State private var selectedCaseForStats: Case?
    @State private var showDeleteConfirmation = false
    @State private var caseToDelete: Case?
    @State private var forceDelete = false
    @State private var isExporting = false
    @State private var showExportOptions = false
    @State private var caseToExport: Case?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // Current Case Section
                if let current = caseService.currentCase {
                    Section(header: Text(L10n.Case.current)) {
                        CaseRow(caseItem: current, isCurrent: true)
                            .contentShape(Rectangle())
                            .contextMenu {
                                caseContextMenu(for: current)
                            }
                    }
                }
                
                // Other Cases Section
                let otherCases = caseService.cases.filter { $0.caseId != caseService.currentCase?.caseId }
                if !otherCases.isEmpty {
                    Section(header: Text(L10n.Case.other)) {
                        ForEach(otherCases) { caseItem in
                            CaseRow(caseItem: caseItem, isCurrent: false)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    caseService.selectCase(caseItem)
                                }
                                .contextMenu {
                                    caseContextMenu(for: caseItem)
                                }
                        }
                    }
                }
                
                // Archived Cases Section
                if showArchivedCases {
                    let archivedCases = caseService.allCases.filter { $0.isArchived }
                    if !archivedCases.isEmpty {
                        Section(header: Text(L10n.Case.archived)) {
                            ForEach(archivedCases) { caseItem in
                                CaseRow(caseItem: caseItem, isCurrent: false, isArchived: true)
                                    .contentShape(Rectangle())
                                    .contextMenu {
                                        archivedCaseContextMenu(for: caseItem)
                                    }
                            }
                        }
                    }
                }
                
                // Show Archived Toggle
                Section {
                    Toggle(L10n.Case.showArchived, isOn: $showArchivedCases)
                }
                
                // Empty State
                if caseService.cases.isEmpty {
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text(L10n.Case.emptyTitle)
                                .font(.headline)
                            Text(L10n.Case.emptyMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                }
            }
            .navigationTitle(L10n.Case.title)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.Common.done) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateCaseSheet()
            }
            .sheet(item: $selectedCaseForEdit) { caseItem in
                EditCaseSheet(caseItem: caseItem)
            }
            .sheet(item: $selectedCaseForStats) { caseItem in
                CaseStatisticsView(caseItem: caseItem)
            }
            .alert(L10n.Case.deleteConfirmTitle, isPresented: $showDeleteConfirmation) {
                Button(L10n.Common.cancel, role: .cancel) {
                    caseToDelete = nil
                }
                Button(L10n.Case.delete, role: .destructive) {
                    if let caseItem = caseToDelete {
                        Task {
                            try? await caseService.deleteCase(caseItem, force: forceDelete)
                        }
                    }
                }
            } message: {
                if let caseItem = caseToDelete {
                    let stats = caseService.getCaseStatistics(caseItem)
                    if let count = stats?.eventCount, count > 0 {
                        Text(String(format: L10n.Case.deleteHasEvents, count))
                    } else {
                        Text(L10n.Case.deleteConfirmMessage)
                    }
                }
            }
            .refreshable {
                await caseService.loadCases()
            }
            .overlay {
                if isExporting {
                    ZStack {
                        Color.black.opacity(0.3)
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                    }
                    .ignoresSafeArea()
                }
            }
            .confirmationDialog(
                L10n.Case.exportTitle,
                isPresented: $showExportOptions,
                titleVisibility: .visible
            ) {
                Button(L10n.Case.exportMetadataOnly) {
                    guard let caseItem = caseToExport else { return }
                    isExporting = true
                    Task {
                        do {
                            let url = try await caseService.exportCase(caseItem)
                            isExporting = false
                            presentShareSheet(items: [url])
                        } catch {
                            print("[CaseListView] Export error: \(error)")
                            isExporting = false
                        }
                    }
                }
                
                Button(L10n.Case.exportFullPackage) {
                    guard let caseItem = caseToExport else { return }
                    isExporting = true
                    Task {
                        do {
                            let url = try await caseService.exportCaseAsZip(caseItem)
                            isExporting = false
                            presentShareSheet(items: [url])
                        } catch {
                            print("[CaseListView] Export ZIP error: \(error)")
                            isExporting = false
                        }
                    }
                }
                
                Button(L10n.Common.cancel, role: .cancel) {
                    caseToExport = nil
                }
            } message: {
                Text(L10n.Case.exportMessage)
            }
        }
    }
    
    // MARK: Context Menus
    
    @ViewBuilder
    private func caseContextMenu(for caseItem: Case) -> some View {
        // Select - only show if not current case
        if caseService.currentCase?.caseId != caseItem.caseId {
            Button {
                caseService.selectCase(caseItem)
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            } label: {
                Label(L10n.Case.select, systemImage: "checkmark.circle")
            }
        }
        
        Button {
            selectedCaseForEdit = caseItem
        } label: {
            Label(L10n.Case.edit, systemImage: "pencil")
        }
        
        Button {
            selectedCaseForStats = caseItem
        } label: {
            Label(L10n.Case.statsTitle, systemImage: "chart.bar")
        }
        
        Button {
            caseToExport = caseItem
            showExportOptions = true
        } label: {
            Label(L10n.Case.export, systemImage: "square.and.arrow.up")
        }
        
        Divider()
        
        Button {
            Task {
                try? await caseService.archiveCase(caseItem)
            }
        } label: {
            Label(L10n.Case.archive, systemImage: "archivebox")
        }
        
        Button(role: .destructive) {
            caseToDelete = caseItem
            forceDelete = false
            showDeleteConfirmation = true
        } label: {
            Label(L10n.Case.delete, systemImage: "trash")
        }
    }
    
    @ViewBuilder
    private func archivedCaseContextMenu(for caseItem: Case) -> some View {
        Button {
            Task {
                try? await caseService.unarchiveCase(caseItem)
            }
        } label: {
            Label(L10n.Case.unarchive, systemImage: "archivebox.fill")
        }
        
        Button(role: .destructive) {
            caseToDelete = caseItem
            forceDelete = true
            showDeleteConfirmation = true
        } label: {
            Label(L10n.Case.delete, systemImage: "trash")
        }
    }
}

// MARK: - CaseRow

/// Individual case row in list
struct CaseRow: View {
    let caseItem: Case
    let isCurrent: Bool
    var isArchived: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(caseItem.color.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: caseItem.icon)
                    .font(.system(size: 20))
                    .foregroundColor(caseItem.color)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(caseItem.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if isArchived {
                        Text(L10n.Case.archived)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                HStack {
                    Text(L10n.Case.photoCount(caseItem.eventCount))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let lastCapture = caseItem.lastCaptureFormatted {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(L10n.Case.lastCapture(lastCapture))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Current indicator
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
        .opacity(isArchived ? 0.6 : 1.0)
    }
}

// MARK: - CreateCaseSheet

/// New case creation form
struct CreateCaseSheet: View {
    @ObservedObject private var caseService = CaseService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var description = ""
    @State private var selectedIcon: CaseIcon = .folder
    @State private var selectedColor: CaseColor = .blue
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                // Name
                Section(header: Text(L10n.Case.name)) {
                    TextField(L10n.Case.namePlaceholder, text: $name)
                        .autocorrectionDisabled()
                }
                
                // Description
                Section(header: Text(L10n.Case.description)) {
                    TextField(L10n.Case.descriptionPlaceholder, text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                // Icon Selection
                Section(header: Text(L10n.Case.icon)) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(CaseIcon.allCases, id: \.self) { icon in
                            IconButton(
                                icon: icon,
                                isSelected: selectedIcon == icon,
                                color: selectedColor
                            ) {
                                selectedIcon = icon
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Color Selection
                Section(header: Text(L10n.Case.color)) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(CaseColor.allCases, id: \.self) { color in
                            ColorButton(
                                color: color,
                                isSelected: selectedColor == color
                            ) {
                                selectedColor = color
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Error Message
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(L10n.Case.createTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Case.create) {
                        createCase()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
            .interactiveDismissDisabled(isCreating)
        }
    }
    
    private func createCase() {
        isCreating = true
        errorMessage = nil
        
        Task {
            do {
                _ = try await caseService.createCase(
                    name: name,
                    description: description.isEmpty ? nil : description,
                    icon: selectedIcon,
                    color: selectedColor
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}

// MARK: - EditCaseSheet

/// Case metadata editor
struct EditCaseSheet: View {
    let caseItem: Case
    
    @ObservedObject private var caseService = CaseService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var description: String
    @State private var selectedIcon: CaseIcon
    @State private var selectedColor: CaseColor
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    init(caseItem: Case) {
        self.caseItem = caseItem
        _name = State(initialValue: caseItem.name)
        _description = State(initialValue: caseItem.description ?? "")
        _selectedIcon = State(initialValue: CaseIcon(rawValue: caseItem.icon) ?? .folder)
        _selectedColor = State(initialValue: CaseColor(rawValue: caseItem.colorHex) ?? .blue)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Name
                Section(header: Text(L10n.Case.name)) {
                    TextField(L10n.Case.namePlaceholder, text: $name)
                        .autocorrectionDisabled()
                }
                
                // Description
                Section(header: Text(L10n.Case.description)) {
                    TextField(L10n.Case.descriptionPlaceholder, text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                // Icon Selection
                Section(header: Text(L10n.Case.icon)) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(CaseIcon.allCases, id: \.self) { icon in
                            IconButton(
                                icon: icon,
                                isSelected: selectedIcon == icon,
                                color: selectedColor
                            ) {
                                selectedIcon = icon
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Color Selection
                Section(header: Text(L10n.Case.color)) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(CaseColor.allCases, id: \.self) { color in
                            ColorButton(
                                color: color,
                                isSelected: selectedColor == color
                            ) {
                                selectedColor = color
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Case Info (Read-only)
                Section(header: Text(L10n.Case.sectionInfo)) {
                    LabeledContent("Case ID", value: String(caseItem.caseId.prefix(8)) + "...")
                    LabeledContent("Chain ID", value: String(caseItem.chainId.prefix(8)) + "...")
                    LabeledContent("Created", value: caseItem.createdAtFormatted)
                }
                
                // Error Message
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(L10n.Case.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Case.save) {
                        saveCase()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }
    
    private func saveCase() {
        isSaving = true
        errorMessage = nil
        
        var updatedCase = caseItem
        updatedCase.name = name
        updatedCase.description = description.isEmpty ? nil : description
        updatedCase.icon = selectedIcon.rawValue
        updatedCase.colorHex = selectedColor.rawValue
        
        Task {
            do {
                try await caseService.updateCase(updatedCase)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - CaseSelectorButton

/// Compact case selector button for camera view
struct CaseSelectorButton: View {
    @ObservedObject private var caseService = CaseService.shared
    @State private var showSelector = false
    
    var body: some View {
        Button {
            showSelector = true
        } label: {
            HStack(spacing: 6) {
                if let current = caseService.currentCase {
                    Circle()
                        .fill(current.color)
                        .frame(width: 10, height: 10)
                    Text(current.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                } else {
                    Image(systemName: "folder")
                    Text(L10n.Case.select)
                        .font(.subheadline)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSelector) {
            CaseSelectorSheet()
        }
    }
}

// MARK: - CaseSelectorSheet

/// Quick case selection sheet
struct CaseSelectorSheet: View {
    @ObservedObject private var caseService = CaseService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showCreateSheet = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(caseService.cases) { caseItem in
                    Button {
                        caseService.selectCase(caseItem)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(caseItem.color.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                Image(systemName: caseItem.icon)
                                    .foregroundColor(caseItem.color)
                            }
                            
                            VStack(alignment: .leading) {
                                Text(caseItem.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(L10n.Case.photoCount(caseItem.eventCount))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if caseService.currentCase?.caseId == caseItem.caseId {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
                
                // Create New
                Button {
                    showCreateSheet = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(Color.accentColor, lineWidth: 2)
                                .frame(width: 36, height: 36)
                            Image(systemName: "plus")
                                .foregroundColor(.accentColor)
                        }
                        
                        Text(L10n.Case.createNew)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .navigationTitle(L10n.Case.selectorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Common.done) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateCaseSheet()
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            // 表示時に全ケースの統計を再計算
            Task {
                await caseService.refreshAllCaseStatistics()
            }
        }
    }
}

// MARK: - CaseStatisticsView

/// Detailed case statistics
struct CaseStatisticsView: View {
    let caseItem: Case
    @ObservedObject private var caseService = CaseService.shared
    @Environment(\.dismiss) private var dismiss
    
    private var stats: CaseStatistics? {
        caseService.getCaseStatistics(caseItem)
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Overview
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(caseItem.color.opacity(0.2))
                                .frame(width: 60, height: 60)
                            Image(systemName: caseItem.icon)
                                .font(.system(size: 28))
                                .foregroundColor(caseItem.color)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(caseItem.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            if let desc = caseItem.description {
                                Text(desc)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Event Statistics
                Section(header: Text(L10n.Case.sectionEvents)) {
                    StatRow(title: L10n.Case.statsTotal, value: "\(stats?.eventCount ?? caseItem.eventCount)")
                    StatRow(title: L10n.Case.statsActive, value: "\(stats?.activeCount ?? 0)", color: .green)
                    StatRow(title: L10n.Case.statsInvalidated, value: "\(stats?.invalidatedCount ?? 0)", color: .red)
                    StatRow(title: L10n.Case.statsAnchored, value: "\(stats?.anchoredCount ?? 0)", color: .blue)
                    StatRow(title: L10n.Case.statsPending, value: "\(stats?.pendingCount ?? 0)", color: .orange)
                }
                
                // Date Range
                Section(header: Text(L10n.Case.statsDateRange)) {
                    if let range = stats?.dateRangeFormatted {
                        Text(range)
                    } else {
                        Text(L10n.Case.noEvents)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Storage
                Section(header: Text(L10n.Case.statsSize)) {
                    Text(stats?.formattedSize ?? "0 bytes")
                }
                
                // Technical Info
                Section(header: Text(L10n.Case.sectionTechnical)) {
                    LabeledContent("Case ID", value: caseItem.caseId)
                        .font(.caption)
                    LabeledContent("Chain ID", value: caseItem.chainId)
                        .font(.caption)
                    LabeledContent("Created", value: caseItem.createdAtFormatted)
                        .font(.caption)
                }
            }
            .navigationTitle(L10n.Case.statsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Common.done) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - GalleryCaseInfoBar

/// Shows case context at top of gallery
struct GalleryCaseInfoBar: View {
    @ObservedObject private var caseService = CaseService.shared
    @State private var showCaseList = false
    
    var body: some View {
        Button {
            showCaseList = true
        } label: {
            HStack(spacing: 12) {
                if let current = caseService.currentCase {
                    ZStack {
                        Circle()
                            .fill(current.color.opacity(0.2))
                            .frame(width: 32, height: 32)
                        Image(systemName: current.icon)
                            .font(.system(size: 14))
                            .foregroundColor(current.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Text(L10n.Case.tapToChange)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showCaseList) {
            CaseListView()
        }
    }
}

// MARK: - Helper Views

struct IconButton: View {
    let icon: CaseIcon
    let isSelected: Bool
    let color: CaseColor
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isSelected ? color.color.opacity(0.2) : Color.secondary.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: icon.rawValue)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? color.color : .secondary)
                
                if isSelected {
                    Circle()
                        .stroke(color.color, lineWidth: 2)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct ColorButton: View {
    let color: CaseColor
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color.color)
                    .frame(width: 40, height: 40)
                
                if isSelected {
                    Circle()
                        .stroke(Color.primary, lineWidth: 3)
                        .frame(width: 44, height: 44)
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct StatRow: View {
    let title: String
    let value: String
    var color: Color = .primary
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

// MARK: - Preview

#Preview("Case List") {
    CaseListView()
}

#Preview("Create Case") {
    CreateCaseSheet()
}

#Preview("Case Selector Button") {
    CaseSelectorButton()
        .padding()
        .background(Color.black)
}
