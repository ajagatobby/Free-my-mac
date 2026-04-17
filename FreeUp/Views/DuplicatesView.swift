//
//  DuplicatesView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

/// View for browsing and managing duplicate file groups — dark themed
struct DuplicatesView: View {
    @Bindable var viewModel: ScanViewModel
    @State private var searchText = ""
    @State private var sortOrder: DuplicateSortOrder = .sizeDescending
    @State private var selectedForDeletion: Set<URL> = []
    @State private var showDeleteConfirmation = false
    @State private var expandedGroups: Set<UUID> = []
    
    private var filteredGroups: [DuplicateGroup] {
        var groups = viewModel.duplicateGroups
        
        // Apply search filter
        if !searchText.isEmpty {
            groups = groups.filter { group in
                group.files.contains { file in
                    file.fileName.localizedCaseInsensitiveContains(searchText) ||
                    file.parentPath.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
        
        // Apply sort
        switch sortOrder {
        case .sizeDescending:
            groups.sort { $0.wastedSpace > $1.wastedSpace }
        case .sizeAscending:
            groups.sort { $0.wastedSpace < $1.wastedSpace }
        case .countDescending:
            groups.sort { $0.files.count > $1.files.count }
        case .nameAscending:
            groups.sort { ($0.files.first?.fileName ?? "") < ($1.files.first?.fileName ?? "") }
        }
        
        return groups
    }
    
    private var totalSelectedSize: Int64 {
        var size: Int64 = 0
        for group in viewModel.duplicateGroups {
            for file in group.files {
                if selectedForDeletion.contains(file.url) {
                    size += file.allocatedSize
                }
            }
        }
        return size
    }
    
    var body: some View {
        ZStack {
            Color(.windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                DuplicatesHeader(
                    totalGroups: viewModel.duplicateGroups.count,
                    totalDuplicates: viewModel.totalDuplicateCount,
                    wastedSpace: viewModel.duplicateWastedSpace,
                    selectedCount: selectedForDeletion.count,
                    selectedSize: totalSelectedSize
                )
                
                // Inline toolbar: search + sort
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        TextField("Search duplicates...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Menu {
                        Section("Sort By") {
                            Button { sortOrder = .sizeDescending } label: {
                                Label("Largest Waste First", systemImage: sortOrder == .sizeDescending ? "checkmark" : "")
                            }
                            Button { sortOrder = .sizeAscending } label: {
                                Label("Smallest Waste First", systemImage: sortOrder == .sizeAscending ? "checkmark" : "")
                            }
                            Button { sortOrder = .countDescending } label: {
                                Label("Most Copies First", systemImage: sortOrder == .countDescending ? "checkmark" : "")
                            }
                            Button { sortOrder = .nameAscending } label: {
                                Label("Name A-Z", systemImage: sortOrder == .nameAscending ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor))

                Rectangle()
                    .fill(Color(.separatorColor))
                    .frame(height: 1)
                
                if filteredGroups.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Spacer()

                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 64, height: 64)

                            Image(systemName: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass")
                                .font(.system(size: 26))
                                .foregroundStyle(Color.accentColor)
                        }

                        Text(searchText.isEmpty ? "No Duplicates Found" : "No Results")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(searchText.isEmpty
                             ? "Great! No duplicate files were found on your system."
                             : "Try a different search term")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Duplicate groups list
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredGroups) { group in
                                DuplicateGroupRow(
                                    group: group,
                                    selectedForDeletion: $selectedForDeletion,
                                    isExpanded: expandedGroups.contains(group.id),
                                    onToggleExpand: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if expandedGroups.contains(group.id) {
                                                expandedGroups.remove(group.id)
                                            } else {
                                                expandedGroups.insert(group.id)
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .scrollContentBackground(.hidden)
                }
                
                // Bottom action bar
                if !selectedForDeletion.isEmpty {
                    DuplicateActionBar(
                        selectedCount: selectedForDeletion.count,
                        selectedSize: totalSelectedSize,
                        isDeleting: viewModel.isDeletingFiles,
                        onDelete: {
                            showDeleteConfirmation = true
                        },
                        onAutoSelect: {
                            autoSelectDuplicates()
                        },
                        onDeselect: {
                            selectedForDeletion.removeAll()
                        }
                    )
                } else {
                    // Show auto-select button when nothing is selected
                    HStack {
                        Spacer()
                        
                        Button {
                            autoSelectDuplicates()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Auto-Select Duplicates")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.accentColor)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Automatically select duplicate copies, keeping the oldest file in each group")
                        
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(Color(.controlBackgroundColor))
                }
            }
        }
        .alert("Delete Duplicates", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(selectedForDeletion.count) Files", role: .destructive) {
                Task {
                    await deleteDuplicates()
                }
            }
        } message: {
            Text("This will \(viewModel.currentDeleteMode == .moveToTrash ? "move" : "permanently delete") \(selectedForDeletion.count) duplicate files (\(ByteFormatter.format(totalSelectedSize))) to free up space. This action cannot be undone.")
        }
        .onAppear {
            // Auto-expand all groups if there are few
            if viewModel.duplicateGroups.count <= 10 {
                expandedGroups = Set(viewModel.duplicateGroups.map { $0.id })
            }
        }
    }
    
    /// Auto-select all duplicate copies, keeping the oldest file in each group
    private func autoSelectDuplicates() {
        selectedForDeletion.removeAll()
        
        for group in viewModel.duplicateGroups {
            // Keep the file with the earliest access date (or first alphabetically)
            let sorted = group.files.sorted { file1, file2 in
                let date1 = file1.lastAccessDate ?? .distantPast
                let date2 = file2.lastAccessDate ?? .distantPast
                return date1 < date2
            }
            
            // Select all except the first (the "original" to keep)
            for file in sorted.dropFirst() {
                selectedForDeletion.insert(file.url)
            }
        }
    }
    
    /// Delete selected duplicate files
    private func deleteDuplicates() async {
        var filesToDelete: [ScannedFileInfo] = []
        
        for group in viewModel.duplicateGroups {
            for file in group.files {
                if selectedForDeletion.contains(file.url) {
                    filesToDelete.append(file)
                }
            }
        }
        
        await viewModel.deleteFiles(filesToDelete)
        selectedForDeletion.removeAll()
    }
}

// MARK: - Sort Order

enum DuplicateSortOrder {
    case sizeDescending, sizeAscending, countDescending, nameAscending
}

// MARK: - Header

struct DuplicatesHeader: View {
    let totalGroups: Int
    let totalDuplicates: Int
    let wastedSpace: Int64
    let selectedCount: Int
    let selectedSize: Int64
    
    var body: some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.teal.opacity(0.12))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.teal)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(totalGroups) duplicate groups")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                
                HStack(spacing: 8) {
                    Text("\(totalDuplicates) extra copies")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text("~")
                        .foregroundStyle(.tertiary)
                    
                    Text(ByteFormatter.format(wastedSpace) + " wasted")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.teal)
                }
            }
            
            Spacer()
            
            if selectedCount > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(selectedCount) selected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Text(ByteFormatter.format(selectedSize))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(16)
        .background(Color(.controlBackgroundColor))
    }
}

// MARK: - Duplicate Group Row

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    @Binding var selectedForDeletion: Set<URL>
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Group header
            Button(action: onToggleExpand) {
                HStack(spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    // File icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.teal.opacity(0.12))
                            .frame(width: 36, height: 36)

                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.teal)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(group.files.first?.fileName ?? "Unknown")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text("Keep")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.green.opacity(0.15)))
                                .foregroundStyle(Color.green)
                        }

                        Text("\(group.files.count) copies · removes \(group.files.count - 1)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(ByteFormatter.format(group.wastedSpace))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.teal)

                        Text("wasted")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse group" : "Expand group")
            .accessibilityLabel(isExpanded
                ? "Collapse \(group.files.first?.fileName ?? "group")"
                : "Expand \(group.files.first?.fileName ?? "group")")
            
            // Expanded file list
            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(Array(group.files.enumerated()), id: \.element.url) { index, file in
                        DuplicateFileRow(
                            file: file,
                            isOriginal: index == 0,
                            isSelectedForDeletion: selectedForDeletion.contains(file.url),
                            onToggle: {
                                if selectedForDeletion.contains(file.url) {
                                    selectedForDeletion.remove(file.url)
                                } else {
                                    selectedForDeletion.insert(file.url)
                                }
                            },
                            onRevealInFinder: {
                                NSWorkspace.shared.selectFile(
                                    file.url.path,
                                    inFileViewerRootedAtPath: file.url.deletingLastPathComponent().path
                                )
                            }
                        )
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color(.quaternaryLabelColor) : Color(.unemphasizedSelectedContentBackgroundColor))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Individual Duplicate File Row

struct DuplicateFileRow: View {
    let file: ScannedFileInfo
    let isOriginal: Bool
    let isSelectedForDeletion: Bool
    let onToggle: () -> Void
    let onRevealInFinder: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Selection checkbox
            Button(action: onToggle) {
                Image(systemName: isSelectedForDeletion ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelectedForDeletion ? Color.red : Color(.tertiaryLabelColor))
            }
            .buttonStyle(.plain)
            
            // Original badge or copy indicator
            if isOriginal {
                Text("Keep")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.green.opacity(0.15))
                    )
                    .foregroundStyle(Color.green)
            }
            
            // File path
            VStack(alignment: .leading, spacing: 1) {
                Text(file.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(file.parentPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            
            Spacer()
            
            // Size
            Text(ByteFormatter.format(file.allocatedSize))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            
            // Reveal in Finder
            Button(action: onRevealInFinder) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(isHovered ? Color.accentColor : Color(.tertiaryLabelColor))
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelectedForDeletion ? Color.red.opacity(0.12) : (isHovered ? Color(.quaternaryLabelColor) : Color.clear))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Action Bar

struct DuplicateActionBar: View {
    let selectedCount: Int
    let selectedSize: Int64
    let isDeleting: Bool
    let onDelete: () -> Void
    let onAutoSelect: () -> Void
    let onDeselect: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedCount) duplicates selected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text(ByteFormatter.format(selectedSize) + " to free")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isDeleting {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.accentColor)
                    .padding(.horizontal)
            }
            
            Button("Deselect All", action: onDeselect)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            Button(action: onDelete) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Delete Duplicates")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red)
                )
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
        }
        .padding(16)
        .background(Color(.controlBackgroundColor))
    }
}

#Preview("Duplicates View") {
    NavigationStack {
        DuplicatesView(viewModel: ScanViewModel())
    }
    .preferredColorScheme(.dark)
}
