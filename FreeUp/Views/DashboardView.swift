//
//  DashboardView.swift
//  FreeUp
//
//  Raycast/Linear-inspired dashboard. Two panes:
//  - Sidebar: dense, minimal, monospace sizes, no colored tiles.
//  - Detail: either the overview (single hero number + CTA + category list)
//    or a specific category / duplicates view.
//
//  Zero animations on the sidebar and zero decorative chrome on the
//  overview. Numbers are the visual motif.
//

import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: ScanViewModel
    @State private var selectedCategory: FileCategory?
    @State private var showingPermissionsSheet = false
    @State private var showCleanupConfirmation = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var isScanning: Bool {
        if case .scanning = viewModel.scanState { return true }
        if case .detectingDuplicates = viewModel.scanState { return true }
        return false
    }

    private var hasEverScanned: Bool {
        if case .completed = viewModel.scanState { return true }
        return !viewModel.categoryStats.isEmpty
    }

    private var sortedCategories: [FileCategory] {
        let visible = FileCategory.allCases.filter {
            (viewModel.categoryStats[$0]?.count ?? 0) > 0
        }
        if isScanning { return visible }
        return visible.sorted {
            (viewModel.categoryStats[$0]?.totalSize ?? 0) > (viewModel.categoryStats[$1]?.totalSize ?? 0)
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        // Alerts & sheets unchanged — the behavior stays the same.
        .alert("Free Up Space", isPresented: $showCleanupConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button(cleanupActionTitle, role: .destructive) {
                Task { await viewModel.cleanUpReclaimableFiles() }
            }
        } message: {
            Text(cleanupMessage)
        }
        .alert(
            viewModel.lastDeletionResult?.allSuccessful == true ? "Done" : "Cleanup result",
            isPresented: Binding(
                get: {
                    guard viewModel.showDeletionResult else { return false }
                    if viewModel.lastDeletionResult?.isPermissionBlocked == true { return false }
                    return true
                },
                set: { if !$0 { viewModel.dismissDeletionResult() } }
            )
        ) {
            Button("OK") { viewModel.dismissDeletionResult() }
        } message: {
            if let r = viewModel.lastDeletionResult {
                if r.allSuccessful {
                    Text("Freed \(ByteFormatter.format(r.freedSpace)). \(r.successCount) files removed.")
                } else if r.successCount == 0 {
                    Text("Couldn't delete \(r.failureCount) files. \(r.errors.first?.error ?? "")")
                } else {
                    Text("Freed \(ByteFormatter.format(r.freedSpace)). \(r.successCount) removed, \(r.failureCount) failed.")
                }
            }
        }
        .onChange(of: viewModel.showDeletionResult) { _, isShowing in
            guard isShowing,
                  viewModel.lastDeletionResult?.isPermissionBlocked == true
            else { return }
            viewModel.checkPermissions()
            showingPermissionsSheet = true
            viewModel.dismissDeletionResult()
        }
        .sheet(isPresented: $showingPermissionsSheet) {
            PermissionsView(
                fdaStatus: viewModel.fullDiskAccessStatus,
                onOpenSettings: { viewModel.openFullDiskAccessSettings() },
                onDismiss: {
                    showingPermissionsSheet = false
                    viewModel.checkPermissions()
                }
            )
        }
        .onAppear {
            viewModel.checkPermissions()
            if viewModel.fullDiskAccessStatus == .denied {
                showingPermissionsSheet = true
            }
        }
    }

    private var cleanupActionTitle: String {
        viewModel.currentDeleteMode == .moveToTrash ? "Move to Trash" : "Delete"
    }

    private var cleanupMessage: String {
        let verb = viewModel.currentDeleteMode == .moveToTrash ? "move to Trash" : "permanently delete"
        return "This will \(verb) \(ByteFormatter.format(viewModel.reclaimableSpace)) of cache, logs, and junk."
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: Binding(
            get: { selectedCategory?.rawValue },
            set: { selectedCategory = $0.flatMap { FileCategory(rawValue: $0) } }
        )) {
            Button {
                selectedCategory = nil
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 12))
                        .foregroundStyle(selectedCategory == nil ? Color.accentColor : Color.secondary)
                        .frame(width: 14)
                    Text("Overview")
                        .font(FUFont.body)
                        .foregroundStyle(selectedCategory == nil ? Color.accentColor : Color.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)

            if !sortedCategories.isEmpty || isScanning {
                Section {
                    ForEach(sortedCategories) { category in
                        SidebarCategoryRow(
                            category: category,
                            stats: viewModel.categoryStats[category],
                            isSelected: selectedCategory == category,
                            action: { selectedCategory = category }
                        )
                        .tag(category.rawValue)
                    }
                } header: {
                    Text("CATEGORIES")
                        .font(FUFont.eyebrow)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .listStyle(.sidebar)
        .animation(nil, value: sortedCategories.map(\.rawValue))
        .animation(nil, value: isScanning)
        .safeAreaInset(edge: .top) { sidebarHeader }
        .safeAreaInset(edge: .bottom) { sidebarFooter }
    }

    private var sidebarHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("FreeUp")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    if isScanning {
                        viewModel.cancelScan()
                    } else {
                        Task { await viewModel.startScan() }
                    }
                } label: {
                    Image(systemName: isScanning ? "stop.fill" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isScanning ? Color(nsColor: .systemRed) : Color.accentColor)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isScanning ? "Stop scan (⌘.)" : "Scan now (⌘R)")
                .keyboardShortcut(isScanning ? "." : "r", modifiers: .command)
            }

            // Fixed-height scanning indicator — opacity toggle avoids layout shift.
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("\(viewModel.totalFilesScanned) files")
                    .font(FUFont.monoCaption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer()
            }
            .frame(height: 14)
            .opacity(isScanning ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var sidebarFooter: some View {
        VStack(spacing: 10) {
            Hairline()

            if let info = viewModel.volumeInfo {
                HStack(spacing: 0) {
                    Text(info.name)
                        .font(FUFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(ByteFormatter.format(info.availableCapacity))
                        .font(FUFont.monoCaption)
                        .foregroundStyle(.secondary)
                    Text(" / ")
                        .font(FUFont.caption)
                        .foregroundStyle(.tertiary)
                    Text(info.formattedTotal)
                        .font(FUFont.monoCaption)
                        .foregroundStyle(.tertiary)
                }

                StorageBar(volumeInfo: info, reclaimableSpace: viewModel.reclaimableSpace)
                    .frame(height: 36)
            }

            if viewModel.fullDiskAccessStatus == .denied {
                Button {
                    viewModel.openFullDiskAccessSettings()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 10))
                        Text("Grant Full Disk Access")
                            .font(FUFont.caption)
                    }
                    .foregroundStyle(Color(nsColor: .systemOrange))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .padding(.top, 4)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if isScanning && !hasEverScanned {
            ScanProgressView(
                state: viewModel.scanState,
                filesScanned: viewModel.totalFilesScanned,
                sizeScanned: viewModel.totalSizeScanned,
                onCancel: { viewModel.cancelScan() }
            )
        } else if let category = selectedCategory {
            if category == .duplicates {
                DuplicatesView(viewModel: viewModel)
                    .id(category)
            } else {
                CategoryDetailView(category: category, viewModel: viewModel)
                    .id(category)
            }
        } else {
            OverviewPane(
                viewModel: viewModel,
                sortedCategories: sortedCategories,
                isScanning: isScanning,
                onClean: { showCleanupConfirmation = true },
                onSelectCategory: { selectedCategory = $0 }
            )
        }
    }
}

// MARK: - Overview pane

/// The headline pane: eyebrow, hero number, single CTA, category list below.
private struct OverviewPane: View {
    @Bindable var viewModel: ScanViewModel
    let sortedCategories: [FileCategory]
    let isScanning: Bool
    let onClean: () -> Void
    let onSelectCategory: (FileCategory) -> Void

    private var hasResults: Bool { !sortedCategories.isEmpty }
    private var reclaimable: Int64 { viewModel.reclaimableSpace }

    var body: some View {
        VStack(spacing: 0) {
            // Top strip — minimal breadcrumb/toolbar line.
            HStack {
                Text("OVERVIEW")
                    .font(FUFont.eyebrow)
                    .foregroundStyle(.tertiary)
                Spacer()
                if case .completed(let files, _, let dur) = viewModel.scanState {
                    HStack(spacing: 8) {
                        Text("\(files) files")
                            .font(FUFont.monoCaption)
                            .foregroundStyle(.tertiary)
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Text("\(Self.formatDuration(dur))")
                            .font(FUFont.monoCaption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if isScanning {
                    InlineScanProgress(state: viewModel.scanState, filesScanned: viewModel.totalFilesScanned)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Hairline()

            ScrollView {
                VStack(spacing: 0) {
                    hero
                        .padding(.top, 40)
                        .padding(.bottom, 36)

                    if hasResults {
                        Hairline()
                        categoriesList
                    }

                    Spacer(minLength: 24)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: Hero

    @ViewBuilder
    private var hero: some View {
        if hasResults {
            hasResultsHero
        } else if !isScanning {
            firstRunHero
        } else {
            // Scanning but no results yet (first batch not in) — minimal placeholder.
            VStack(spacing: 12) {
                Text("SCANNING")
                    .font(FUFont.eyebrow)
                    .foregroundStyle(.tertiary)
                Text("\(viewModel.totalFilesScanned)")
                    .font(FUFont.hero)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("files found so far")
                    .font(FUFont.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var hasResultsHero: some View {
        VStack(spacing: 14) {
            Text(reclaimable > 0 ? "RECLAIMABLE" : "ALL CLEAN")
                .font(FUFont.eyebrow)
                .foregroundStyle(.tertiary)

            Text(ByteFormatter.format(reclaimable))
                .font(FUFont.hero)
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .monospacedDigit()

            if reclaimable > 0 {
                HStack(spacing: 10) {
                    Button(action: onClean) {
                        HStack(spacing: 8) {
                            Text("Free Up")
                                .font(.system(size: 14, weight: .semibold))
                            Text(ByteFormatter.format(reclaimable))
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .monospacedDigit()
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isScanning)
                    .keyboardShortcut(.defaultAction)

                    Button("Rescan") {
                        Task { await viewModel.startScan() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .keyboardShortcut("r", modifiers: .command)
                }
            } else {
                Text("Nothing to reclaim right now.")
                    .font(FUFont.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var firstRunHero: some View {
        VStack(spacing: 14) {
            Text("READY")
                .font(FUFont.eyebrow)
                .foregroundStyle(.tertiary)

            Text("0 B")
                .font(FUFont.hero)
                .foregroundStyle(.tertiary)

            Button {
                Task { await viewModel.startScan() }
            } label: {
                HStack(spacing: 6) {
                    Text("Scan")
                        .font(.system(size: 14, weight: .semibold))
                    Text("⌘R")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor)
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)

            Text("Finds caches, logs, duplicates, and junk across your Mac.")
                .font(FUFont.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Categories list

    private var categoriesList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(sortedCategories.enumerated()), id: \.element.rawValue) { idx, category in
                OverviewCategoryRow(
                    category: category,
                    stats: viewModel.categoryStats[category],
                    totalReclaimable: reclaimable,
                    action: { onSelectCategory(category) }
                )
                if idx < sortedCategories.count - 1 {
                    Hairline()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }

    private static func formatDuration(_ d: TimeInterval) -> String {
        if d < 60 { return String(format: "%.1fs", d) }
        let m = Int(d) / 60
        let s = Int(d) % 60
        return "\(m)m \(s)s"
    }
}

// MARK: - Overview category row

private struct OverviewCategoryRow: View {
    let category: FileCategory
    let stats: CategoryDisplayStats?
    let totalReclaimable: Int64
    let action: () -> Void

    @State private var isHovered = false

    private var size: Int64 { stats?.totalSize ?? 0 }
    private var ratio: Double {
        guard totalReclaimable > 0 else { return 0 }
        return min(1.0, Double(size) / Double(totalReclaimable))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CategoryDot(color: category.themeColor)

                Text(category.rawValue)
                    .font(FUFont.body)
                    .foregroundStyle(.primary)
                    .frame(width: 150, alignment: .leading)

                // Micro bar — conveys share of reclaimable at a glance.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(.quaternaryLabelColor).opacity(0.5))
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(category.themeColor.opacity(0.85))
                            .frame(width: max(2, geo.size.width * ratio))
                    }
                    .frame(height: 3)
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 3)

                Text("\(stats?.count ?? 0)")
                    .font(FUFont.monoCaption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 48, alignment: .trailing)

                Text(ByteFormatter.format(size))
                    .font(FUFont.mono)
                    .foregroundStyle(.primary)
                    .frame(width: 72, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 8)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
            .background(isHovered ? Color(.quaternaryLabelColor).opacity(0.4) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Warning banner (kept for reuse; now hairline-bordered, not material-filled)

struct WarningBanner: View {
    let icon: String
    let message: String
    let color: Color
    var action: (title: String, handler: () -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 12))
            Text(message)
                .font(FUFont.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let action {
                Button(action.title, action: action.handler)
                    .buttonStyle(.plain)
                    .font(FUFont.captionMedium)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
    }
}
