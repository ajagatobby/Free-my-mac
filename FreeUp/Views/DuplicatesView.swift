//
//  DuplicatesView.swift
//  FreeUp
//
//  Minimal duplicates browser. Same density as CategoryDetailView.
//

import SwiftUI

struct DuplicatesView: View {
    @Bindable var viewModel: ScanViewModel
    @State private var searchText = ""
    @State private var sortOrder: DuplicateSortOrder = .sizeDescending
    @State private var selectedForDeletion: Set<URL> = []
    @State private var showDeleteConfirmation = false
    @State private var expandedGroups: Set<UUID> = []

    private var filteredGroups: [DuplicateGroup] {
        var groups = viewModel.duplicateGroups

        if !searchText.isEmpty {
            groups = groups.filter { group in
                group.files.contains { file in
                    file.fileName.localizedCaseInsensitiveContains(searchText) ||
                    file.parentPath.localizedCaseInsensitiveContains(searchText)
                }
            }
        }

        switch sortOrder {
        case .sizeDescending:  groups.sort { $0.wastedSpace > $1.wastedSpace }
        case .sizeAscending:   groups.sort { $0.wastedSpace < $1.wastedSpace }
        case .countDescending: groups.sort { $0.files.count > $1.files.count }
        case .nameAscending:   groups.sort { ($0.files.first?.fileName ?? "") < ($1.files.first?.fileName ?? "") }
        }

        return groups
    }

    private var totalSelectedSize: Int64 {
        var size: Int64 = 0
        for group in viewModel.duplicateGroups {
            for file in group.files where selectedForDeletion.contains(file.url) {
                size += file.allocatedSize
            }
        }
        return size
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            toolbar
            Hairline()

            Group {
                if filteredGroups.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No duplicates" : "No results",
                        systemImage: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass",
                        description: Text(searchText.isEmpty
                                          ? "Nothing duplicated on your system right now."
                                          : "Try a different search term.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredGroups.enumerated()), id: \.element.id) { idx, group in
                                DuplicateGroupRow(
                                    group: group,
                                    selectedForDeletion: $selectedForDeletion,
                                    isExpanded: expandedGroups.contains(group.id),
                                    onToggleExpand: {
                                        if expandedGroups.contains(group.id) {
                                            expandedGroups.remove(group.id)
                                        } else {
                                            expandedGroups.insert(group.id)
                                        }
                                    }
                                )
                                if idx < filteredGroups.count - 1 {
                                    Hairline().opacity(0.4)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.windowBackgroundColor))

            if !selectedForDeletion.isEmpty {
                Hairline()
                DuplicateActionBar(
                    selectedCount: selectedForDeletion.count,
                    selectedSize: totalSelectedSize,
                    isDeleting: viewModel.isDeletingFiles,
                    onDelete: { showDeleteConfirmation = true },
                    onDeselect: { selectedForDeletion.removeAll() }
                )
            }
        }
        .background(Color(.windowBackgroundColor))
        .alert("Delete duplicates", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(selectedForDeletion.count) files", role: .destructive) {
                Task { await deleteDuplicates() }
            }
        } message: {
            Text("\(viewModel.currentDeleteMode == .moveToTrash ? "Move" : "Permanently delete") \(selectedForDeletion.count) duplicate files (\(ByteFormatter.format(totalSelectedSize))).")
        }
        .onAppear {
            if viewModel.duplicateGroups.count <= 10 {
                expandedGroups = Set(viewModel.duplicateGroups.map { $0.id })
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                CategoryDot(color: FUColors.duplicatesColor, size: 7)
                Text("DUPLICATES")
                    .font(FUFont.eyebrow)
                    .foregroundStyle(.tertiary)
                Spacer()
                if !selectedForDeletion.isEmpty {
                    Text("\(selectedForDeletion.count) selected · \(ByteFormatter.format(totalSelectedSize))")
                        .font(FUFont.monoCaption)
                        .foregroundStyle(Color.accentColor)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(ByteFormatter.format(viewModel.duplicateWastedSpace))
                    .font(FUFont.heroSmall)
                    .foregroundStyle(.primary)
                Text("wasted across \(viewModel.duplicateGroups.count) groups")
                    .font(FUFont.bodyMedium)
                    .foregroundStyle(.secondary)
                Spacer()

                Button {
                    autoSelectDuplicates()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 10))
                        Text("Auto-select")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Select all duplicates, keeping the first copy per group")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search duplicates", text: $searchText)
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

            Menu {
                Button { sortOrder = .sizeDescending } label: {
                    Label("Largest waste", systemImage: sortOrder == .sizeDescending ? "checkmark" : "")
                }
                Button { sortOrder = .sizeAscending } label: {
                    Label("Smallest waste", systemImage: sortOrder == .sizeAscending ? "checkmark" : "")
                }
                Button { sortOrder = .countDescending } label: {
                    Label("Most copies", systemImage: sortOrder == .countDescending ? "checkmark" : "")
                }
                Button { sortOrder = .nameAscending } label: {
                    Label("Name A–Z", systemImage: sortOrder == .nameAscending ? "checkmark" : "")
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
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: Actions

    private func autoSelectDuplicates() {
        selectedForDeletion.removeAll()
        for group in viewModel.duplicateGroups {
            // group.files[0] is the "keeper"; everything after is a duplicate.
            for file in group.files.dropFirst() {
                selectedForDeletion.insert(file.url)
            }
        }
    }

    private func deleteDuplicates() async {
        var filesToDelete: [ScannedFileInfo] = []
        for group in viewModel.duplicateGroups {
            for file in group.files where selectedForDeletion.contains(file.url) {
                filesToDelete.append(file)
            }
        }
        await viewModel.deleteFiles(filesToDelete)
        selectedForDeletion.removeAll()
    }
}

// MARK: - Sort order

enum DuplicateSortOrder {
    case sizeDescending, sizeAscending, countDescending, nameAscending
}

// MARK: - Group row

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    @Binding var selectedForDeletion: Set<URL>
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggleExpand) {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(group.files.first?.fileName ?? "Unknown")
                                .font(FUFont.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            keepBadge
                        }

                        Text("\(group.files.count) copies · removes \(group.files.count - 1)")
                            .font(FUFont.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 8)

                    Text(ByteFormatter.format(group.wastedSpace))
                        .font(FUFont.mono)
                        .foregroundStyle(FUColors.duplicatesColor)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(isHovered ? Color(.quaternaryLabelColor).opacity(0.4) : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help(isExpanded ? "Collapse" : "Expand")

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(group.files.enumerated()), id: \.element.url) { index, file in
                        DuplicateFileRow(
                            file: file,
                            isOriginal: index == 0,
                            isSelectedForDeletion: selectedForDeletion.contains(file.url),
                            onToggle: {
                                if selectedForDeletion.contains(file.url) {
                                    selectedForDeletion.remove(file.url)
                                } else if index != 0 {
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
                .padding(.bottom, 4)
            }
        }
    }

    private var keepBadge: some View {
        Text("keep")
            .font(FUFont.label)
            .foregroundStyle(Color(nsColor: .systemGreen))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color(nsColor: .systemGreen).opacity(0.4), lineWidth: 1)
            )
    }
}

// MARK: - Individual row

struct DuplicateFileRow: View {
    let file: ScannedFileInfo
    let isOriginal: Bool
    let isSelectedForDeletion: Bool
    let onToggle: () -> Void
    let onRevealInFinder: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: checkboxIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(checkboxColor)
            }
            .buttonStyle(.plain)
            .disabled(isOriginal)
            .opacity(isOriginal ? 0.4 : 1.0)
            .help(isOriginal ? "This file will be kept" : (isSelectedForDeletion ? "Deselect" : "Select for deletion"))

            VStack(alignment: .leading, spacing: 1) {
                Text(file.fileName)
                    .font(FUFont.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(file.parentPath)
                    .font(FUFont.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(file.url.path)
            }

            Spacer()

            Text(ByteFormatter.format(file.allocatedSize))
                .font(FUFont.monoCaption)
                .foregroundStyle(.secondary)

            Button(action: onRevealInFinder) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10))
                    .foregroundStyle(isHovered ? Color.accentColor : Color(.tertiaryLabelColor))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.leading, 44)
        .padding(.trailing, 20)
        .padding(.vertical, 4)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var checkboxIcon: String {
        if isOriginal { return "lock.fill" }
        return isSelectedForDeletion ? "checkmark.square.fill" : "square"
    }

    private var checkboxColor: Color {
        if isOriginal { return Color(nsColor: .systemGreen).opacity(0.6) }
        if isSelectedForDeletion { return Color(nsColor: .systemRed) }
        return Color(.tertiaryLabelColor)
    }

    private var rowBackground: Color {
        if isSelectedForDeletion { return Color(nsColor: .systemRed).opacity(0.06) }
        if isHovered { return Color(.quaternaryLabelColor).opacity(0.4) }
        return .clear
    }
}

// MARK: - Action bar

struct DuplicateActionBar: View {
    let selectedCount: Int
    let selectedSize: Int64
    let isDeleting: Bool
    let onDelete: () -> Void
    let onDeselect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(selectedCount)")
                .font(FUFont.bodyMedium)
                .foregroundStyle(.primary)

            Text("duplicates selected")
                .font(FUFont.caption)
                .foregroundStyle(.tertiary)

            Text("·")
                .foregroundStyle(.quaternary)

            Text(ByteFormatter.format(selectedSize))
                .font(FUFont.mono)
                .foregroundStyle(Color.accentColor)

            Spacer()

            if isDeleting {
                ProgressView().controlSize(.small)
            }

            Button("Deselect", action: onDeselect)
                .buttonStyle(.plain)
                .font(FUFont.captionMedium)
                .foregroundStyle(.secondary)

            Button(action: onDelete) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                    Text("Delete duplicates")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .systemRed))
                )
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.windowBackgroundColor))
    }
}
