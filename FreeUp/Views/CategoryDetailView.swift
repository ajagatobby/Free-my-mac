//
//  CategoryDetailView.swift
//  FreeUp
//
//  Detail pane for a single category. Minimal header, dense list.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Lightweight display model

private struct DisplayGroup: Identifiable, Sendable {
    let id: String
    let source: String
    let fileCount: Int
    let totalSize: Int64
    let previewFiles: [ScannedFileInfo]
    let allFileIDs: [UUID]
}

struct CategoryDetailView: View {
    let category: FileCategory
    @Bindable var viewModel: ScanViewModel

    @State private var sortOrder: SortOrder = .sizeDescending
    @State private var searchText = ""
    @State private var showCloneWarning = false
    @State private var expandedSections: Set<String> = []

    @State private var displayGroups: [DisplayGroup] = []
    @State private var displayFlatFiles: [ScannedFileInfo] = []
    @State private var hasMultipleSources = false
    @State private var totalFileCount: Int = 0
    @State private var totalSize: Int64 = 0
    @State private var isLoading = true

    @State private var localSelectedCount: Int = 0
    @State private var localSelectedSize: Int64 = 0

    private let pageSize = 200

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            toolbar
            Hairline()

            Group {
                if isLoading {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading")
                            .font(FUFont.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if displayFlatFiles.isEmpty && displayGroups.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No files" : "No results",
                        systemImage: searchText.isEmpty ? "tray" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "This category is empty." : "Try a different search term.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if hasMultipleSources {
                    groupedListView
                } else {
                    flatListView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.windowBackgroundColor))

            bottomBar
        }
        .background(Color.clear)
        .alert("Clone detected", isPresented: $showCloneWarning) {
            Button("OK") { }
        } message: {
            Text("This file shares data blocks with another file (APFS clone). Deleting it may not free the expected space.")
        }
        .task(id: SortSearchKey(sort: sortOrder, search: searchText, fileCount: viewModel.files(for: category).count)) {
            await rebuildDisplayData()
        }
    }

    // MARK: Header — minimal. No icon tile. Mono numbers.

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: 20) // traffic lights room

            HStack(spacing: 10) {
                IconSquare(systemName: category.iconName, color: category.themeColor, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.rawValue)
                        .font(FUFont.title)
                        .foregroundStyle(.primary)
                    Text("\(totalFileCount) files · \(ByteFormatter.format(totalSize))")
                        .font(FUFont.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if localSelectedCount > 0 {
                    HStack(spacing: 6) {
                        Text("\(localSelectedCount)")
                            .font(FUFont.bodyMedium)
                            .foregroundStyle(Color.accentColor)
                        Text("selected")
                            .font(FUFont.caption)
                            .foregroundStyle(.tertiary)
                        Text("·").foregroundStyle(.quaternary)
                        Text(ByteFormatter.format(localSelectedSize))
                            .font(FUFont.mono)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    private var bottomBar: some View {
        CommandBar {
            if localSelectedCount > 0 {
                HStack(spacing: 6) {
                    Text("\(localSelectedCount)")
                        .font(FUFont.bodyMedium)
                        .foregroundStyle(.primary)
                    Text("selected")
                        .font(FUFont.caption)
                        .foregroundStyle(.tertiary)
                    Text("·").foregroundStyle(.quaternary)
                    Text(ByteFormatter.format(localSelectedSize))
                        .font(FUFont.mono)
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                Text("\(totalFileCount) items")
                    .font(FUFont.caption)
                    .foregroundStyle(.tertiary)
            }
        } trailing: {
            HStack(spacing: 16) {
                if localSelectedCount > 0 {
                    Button {
                        Task {
                            await viewModel.deleteSelectedFiles(from: category)
                            recomputeSelectionFromScratch()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(viewModel.isDeletingFiles ? "Deleting…" : "Delete")
                                .font(FUFont.captionMedium)
                                .foregroundStyle(Color(nsColor: .systemRed))
                            KBDPill("⏎")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isDeletingFiles)
                    .keyboardShortcut(.defaultAction)

                    Button {
                        deselectAll()
                    } label: {
                        KBDAction(label: "Clear", glyph: "⎋")
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }

                Button {
                    if localSelectedCount == totalFileCount { deselectAll() } else { selectAll() }
                } label: {
                    KBDAction(
                        label: localSelectedCount == totalFileCount ? "Deselect all" : "Select all",
                        glyph: "⌘A"
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("a", modifiers: .command)
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(FUFont.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.quaternaryLabelColor).opacity(0.4))
            )
            .frame(maxWidth: 240)

            Spacer()

            sortMenu
            selectAllButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: Lists

    private var groupedListView: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(displayGroups) { group in
                    Section {
                        if expandedSections.contains(group.source) {
                            ForEach(Array(group.previewFiles.enumerated()), id: \.element.id) { index, file in
                                fileRow(for: file, index: index)
                            }
                            if group.fileCount > group.previewFiles.count {
                                Text("\(group.fileCount - group.previewFiles.count) more")
                                    .font(FUFont.caption)
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                        }
                    } header: {
                        SourceSectionHeader(
                            source: group.source,
                            fileCount: group.fileCount,
                            totalSize: group.totalSize,
                            isCollapsed: !expandedSections.contains(group.source),
                            color: category.themeColor,
                            onToggle: {
                                if expandedSections.contains(group.source) {
                                    expandedSections.remove(group.source)
                                } else {
                                    expandedSections.insert(group.source)
                                }
                            },
                            onSelectAll: {
                                selectFiles(ids: group.allFileIDs, files: group.previewFiles)
                            }
                        )
                        .background(Color(.windowBackgroundColor))
                    }
                }
            }
        }
    }

    private var flatListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(displayFlatFiles.enumerated()), id: \.element.id) { index, file in
                    fileRow(for: file, index: index)
                    if index < displayFlatFiles.count - 1 {
                        Hairline().opacity(0.4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fileRow(for file: ScannedFileInfo, index: Int) -> some View {
        let isSelected = viewModel.selectedItems.contains(file.id)
        let isClone = file.fileContentIdentifier != nil

        FileRowView(
            file: file,
            isSelected: isSelected,
            isClone: isClone,
            index: index,
            onToggleSelection: { toggleSelection(file: file) },
            onRevealInFinder: {
                NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: file.parentPath)
            }
        )
        .equatable()
    }

    // MARK: Selection

    private func toggleSelection(file: ScannedFileInfo) {
        if viewModel.selectedItems.contains(file.id) {
            viewModel.selectedItems.remove(file.id)
            localSelectedCount -= 1
            localSelectedSize -= file.allocatedSize
        } else {
            viewModel.selectedItems.insert(file.id)
            localSelectedCount += 1
            localSelectedSize += file.allocatedSize
            if file.fileContentIdentifier != nil {
                showCloneWarning = true
            }
        }
    }

    private func selectFiles(ids: [UUID], files: [ScannedFileInfo]) {
        var updated = viewModel.selectedItems
        for id in ids { updated.insert(id) }
        viewModel.selectedItems = updated
        recomputeSelectionFromScratch()
    }

    private func selectAll() {
        let allFiles = viewModel.files(for: category)
        var updated = viewModel.selectedItems
        for file in allFiles { updated.insert(file.id) }
        viewModel.selectedItems = updated
        localSelectedCount = allFiles.count
        localSelectedSize = allFiles.reduce(0) { $0 + $1.allocatedSize }
    }

    private func deselectAll() {
        let allFiles = viewModel.files(for: category)
        var updated = viewModel.selectedItems
        for file in allFiles { updated.remove(file.id) }
        viewModel.selectedItems = updated
        localSelectedCount = 0
        localSelectedSize = 0
    }

    private func recomputeSelectionFromScratch() {
        let allFiles = viewModel.files(for: category)
        var count = 0
        var size: Int64 = 0
        for file in allFiles where viewModel.selectedItems.contains(file.id) {
            count += 1
            size += file.allocatedSize
        }
        localSelectedCount = count
        localSelectedSize = size
    }

    // MARK: Toolbar pieces

    private var sortMenu: some View {
        Menu {
            Section("Size") {
                Button { sortOrder = .sizeDescending } label: {
                    Label("Largest first", systemImage: sortOrder == .sizeDescending ? "checkmark" : "")
                }
                Button { sortOrder = .sizeAscending } label: {
                    Label("Smallest first", systemImage: sortOrder == .sizeAscending ? "checkmark" : "")
                }
            }
            Section("Name") {
                Button { sortOrder = .nameAscending } label: {
                    Label("A to Z", systemImage: sortOrder == .nameAscending ? "checkmark" : "")
                }
                Button { sortOrder = .nameDescending } label: {
                    Label("Z to A", systemImage: sortOrder == .nameDescending ? "checkmark" : "")
                }
            }
            Section("Accessed") {
                Button { sortOrder = .dateOldest } label: {
                    Label("Oldest", systemImage: sortOrder == .dateOldest ? "checkmark" : "")
                }
                Button { sortOrder = .dateNewest } label: {
                    Label("Newest", systemImage: sortOrder == .dateNewest ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10))
                Text("Sort")
                    .font(FUFont.caption)
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var selectAllButton: some View {
        Button {
            if localSelectedCount == totalFileCount {
                deselectAll()
            } else {
                selectAll()
            }
        } label: {
            Text(localSelectedCount == totalFileCount ? "Deselect all" : "Select all")
                .font(FUFont.caption)
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    // MARK: Build display data off main thread

    private func rebuildDisplayData() async {
        isLoading = true

        let cat = category
        let sort = sortOrder
        let query = searchText
        let limit = pageSize

        let allFiles = viewModel.files(for: cat)

        let result: (
            groups: [DisplayGroup],
            flat: [ScannedFileInfo],
            multi: Bool,
            count: Int,
            size: Int64
        ) = await Task.detached(priority: .userInitiated) {
            var filtered = allFiles

            if !query.isEmpty {
                filtered = filtered.filter {
                    $0.fileName.localizedCaseInsensitiveContains(query) ||
                    $0.parentPath.localizedCaseInsensitiveContains(query) ||
                    ($0.source?.localizedCaseInsensitiveContains(query) ?? false)
                }
            }

            let totalCount = filtered.count
            var totalSize: Int64 = 0
            for f in filtered { totalSize += f.allocatedSize }

            var sourceSet = Set<String>()
            for f in filtered {
                sourceSet.insert(f.source ?? "Other")
                if sourceSet.count > 1 { break }
            }
            let hasMultiple = sourceSet.count > 1

            if hasMultiple {
                var groups: [String: [ScannedFileInfo]] = [:]
                for file in filtered {
                    groups[file.source ?? "Other", default: []].append(file)
                }

                let displayGroups: [DisplayGroup] = groups.map { key, value in
                    let sorted = Self.sortFiles(value, by: sort)
                    let preview = Array(sorted.prefix(limit))
                    let groupSize = value.reduce(0 as Int64) { $0 + $1.allocatedSize }
                    return DisplayGroup(
                        id: key, source: key,
                        fileCount: value.count, totalSize: groupSize,
                        previewFiles: preview, allFileIDs: value.map(\.id)
                    )
                }.sorted { $0.totalSize > $1.totalSize }

                return (displayGroups, [], true, totalCount, totalSize)
            } else {
                let sorted = Self.sortFiles(filtered, by: sort)
                let page = Array(sorted.prefix(limit))
                return ([], page, false, totalCount, totalSize)
            }
        }.value

        displayGroups = result.groups
        displayFlatFiles = result.flat
        hasMultipleSources = result.multi
        totalFileCount = result.count
        totalSize = result.size
        isLoading = false

        recomputeSelectionFromScratch()
    }

    private nonisolated static func sortFiles(_ files: [ScannedFileInfo], by order: SortOrder) -> [ScannedFileInfo] {
        switch order {
        case .sizeDescending: return files.sorted { $0.allocatedSize > $1.allocatedSize }
        case .sizeAscending:  return files.sorted { $0.allocatedSize < $1.allocatedSize }
        case .nameAscending:  return files.sorted { $0.fileName.localizedCompare($1.fileName) == .orderedAscending }
        case .nameDescending: return files.sorted { $0.fileName.localizedCompare($1.fileName) == .orderedDescending }
        case .dateOldest:     return files.sorted { ($0.lastAccessDate ?? .distantPast) < ($1.lastAccessDate ?? .distantPast) }
        case .dateNewest:     return files.sorted { ($0.lastAccessDate ?? .distantPast) > ($1.lastAccessDate ?? .distantPast) }
        }
    }
}

// MARK: - Sort/Search Key

private struct SortSearchKey: Equatable {
    let sort: SortOrder
    let search: String
    let fileCount: Int
}

// MARK: - Sort Order

enum SortOrder: Equatable {
    case sizeDescending, sizeAscending
    case nameAscending, nameDescending
    case dateOldest, dateNewest
}

// MARK: - Source section header

struct SourceSectionHeader: View {
    let source: String
    let fileCount: Int
    let totalSize: Int64
    let isCollapsed: Bool
    let color: Color
    let onToggle: () -> Void
    let onSelectAll: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Text(source)
                        .font(FUFont.bodyMedium)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Expand" : "Collapse")

            Spacer()

            Text("\(fileCount)")
                .font(FUFont.monoCaption)
                .foregroundStyle(.tertiary)

            Text(ByteFormatter.format(totalSize))
                .font(FUFont.mono)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)

            Button(action: onSelectAll) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Select all in \(source)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Hairline().opacity(0.5) }
    }
}

// (SelectionActionBar removed — CommandBar in CategoryDetailView replaces it.)
