//
//  DashboardView.swift
//  FreeUp
//
//  Raycast-style chrome.
//  - Translucent window (.ultraThinMaterial backdrop)
//  - Custom sidebar with colored rounded icon squares per category
//  - Persistent bottom CommandBar on the detail pane with ⏎ hints
//  - Dense rows, translucent selection, Inter throughout
//

import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: ScanViewModel
    @State private var selectedCategory: FileCategory?
    @State private var showingPermissionsSheet = false
    @State private var showCleanupConfirmation = false

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
        HStack(spacing: 0) {
            Sidebar(
                viewModel: viewModel,
                selected: $selectedCategory,
                sortedCategories: sortedCategories,
                isScanning: isScanning
            )
            .frame(width: 256)
            .background(Color(.controlBackgroundColor))

            Rectangle()
                .fill(Color(.separatorColor))
                .frame(width: 1)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.windowBackgroundColor))
        }
        .background(Color(.windowBackgroundColor))
        // Hidden titlebar still reserves a ~28pt safe area above content;
        // opt out so panes start flush. The sidebar carves out its own
        // 36pt traffic-lights gap internally.
        .ignoresSafeArea(.all, edges: .top)
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

// MARK: - Custom sidebar

private struct Sidebar: View {
    @Bindable var viewModel: ScanViewModel
    @Binding var selected: FileCategory?
    let sortedCategories: [FileCategory]
    let isScanning: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Room for traffic lights.
            Color.clear.frame(height: 36)

            header
                .padding(.horizontal, 14)
                .padding(.bottom, 14)

            overviewRow
                .padding(.horizontal, 10)

            sectionLabel("CATEGORIES")
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 1) {
                    ForEach(sortedCategories) { category in
                        SidebarCategoryRow(
                            category: category,
                            stats: viewModel.categoryStats[category],
                            isSelected: selected == category,
                            action: { selected = category }
                        )
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Spacer(minLength: 0)

            footer
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            // Tiny brand mark — small rounded square with accent fill.
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: "externaldrive.badge.checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                )

            Text("FreeUp")
                .font(FUFont.title)
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
                    .foregroundStyle(isScanning ? Color(nsColor: .systemRed) : Color.secondary)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help(isScanning ? "Stop scan (⌘.)" : "Scan now (⌘R)")
            .keyboardShortcut(isScanning ? "." : "r", modifiers: .command)
        }
    }

    private var overviewRow: some View {
        Button {
            selected = nil
        } label: {
            HStack(spacing: 10) {
                IconSquare(systemName: "chart.pie.fill", color: Color.accentColor, size: 22)
                Text("Overview")
                    .font(FUFont.body)
                    .foregroundStyle(.primary)
                Spacer()
                if isScanning {
                    Text("\(viewModel.totalFilesScanned)")
                        .font(FUFont.monoCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected == nil ? Color.primary.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(FUFont.eyebrow)
                .kerning(1.2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.fullDiskAccessStatus == .denied {
                Button {
                    viewModel.openFullDiskAccessSettings()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 10))
                        Text("Grant Full Disk Access")
                            .font(FUFont.caption)
                        Spacer()
                    }
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(nsColor: .systemOrange).opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if let info = viewModel.volumeInfo {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(info.name)
                            .font(FUFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Text("\(ByteFormatter.format(info.availableCapacity)) free")
                            .font(FUFont.monoCaption)
                            .foregroundStyle(.tertiary)
                            .layoutPriority(1)
                    }

                    StorageBar(volumeInfo: info, reclaimableSpace: viewModel.reclaimableSpace)
                }
            }
        }
    }
}

// MARK: - Overview pane

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
            // Top strip — breadcrumb + meta.
            HStack {
                Text("OVERVIEW")
                    .font(FUFont.eyebrow)
                    .kerning(1.2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if case .completed(let files, _, let dur) = viewModel.scanState {
                    HStack(spacing: 8) {
                        Text("\(files) files")
                            .font(FUFont.monoCaption)
                            .foregroundStyle(.tertiary)
                        Text("·").foregroundStyle(.quaternary)
                        Text(Self.formatDuration(dur))
                            .font(FUFont.monoCaption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if isScanning {
                    InlineScanProgress(state: viewModel.scanState, filesScanned: viewModel.totalFilesScanned)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Hairline()

            ScrollView {
                VStack(spacing: 0) {
                    hero
                        .padding(.top, 48)
                        .padding(.bottom, 40)

                    if hasResults {
                        Hairline()
                        categoriesList
                    }

                    Spacer(minLength: 24)
                }
            }
            .scrollContentBackground(.hidden)

            bottomBar
        }
    }

    private var bottomBar: some View {
        CommandBar {
            // Leading: context
            if hasResults, reclaimable > 0 {
                HStack(spacing: 8) {
                    Text(ByteFormatter.format(reclaimable))
                        .font(FUFont.mono)
                        .foregroundStyle(.primary)
                    Text("reclaimable")
                        .font(FUFont.caption)
                        .foregroundStyle(.tertiary)
                }
            } else if isScanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Scanning")
                        .font(FUFont.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("No scan yet")
                    .font(FUFont.caption)
                    .foregroundStyle(.tertiary)
            }
        } trailing: {
            HStack(spacing: 16) {
                if hasResults, reclaimable > 0 {
                    Button(action: onClean) {
                        KBDAction(label: "Free Up", glyph: "⏎", color: Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                Button {
                    Task { await viewModel.startScan() }
                } label: {
                    KBDAction(label: "Rescan", glyph: "⌘R")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    // MARK: Hero

    @ViewBuilder
    private var hero: some View {
        if hasResults {
            hasResultsHero
        } else if !isScanning {
            firstRunHero
        } else {
            VStack(spacing: 12) {
                Text("SCANNING")
                    .font(FUFont.eyebrow)
                    .kerning(1.2)
                    .foregroundStyle(.tertiary)
                Text("\(viewModel.totalFilesScanned)")
                    .font(FUFont.hero)
                    .foregroundStyle(.primary)
                Text("files found so far")
                    .font(FUFont.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var hasResultsHero: some View {
        VStack(spacing: 16) {
            Text(reclaimable > 0 ? "RECLAIMABLE" : "ALL CLEAN")
                .font(FUFont.eyebrow)
                .kerning(1.2)
                .foregroundStyle(.tertiary)

            Text(ByteFormatter.format(reclaimable))
                .font(FUFont.hero)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
                // Fixed width — layout stays still while digits roll.
                .frame(width: 420, alignment: .center)
                .animation(.snappy(duration: 0.25), value: reclaimable)

            if reclaimable > 0 {
                Button(action: onClean) {
                    HStack(spacing: 10) {
                        Text("Free Up")
                            .font(FUFont.bodySemibold)
                        // Fixed width on the inline size so the button edges
                        // don't shimmy as digits tick up during a scan.
                        Text(ByteFormatter.format(reclaimable))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.25), value: reclaimable)
                            .frame(width: 80, alignment: .trailing)
                        KBDPill("⏎")
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
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
                .kerning(1.2)
                .foregroundStyle(.tertiary)

            Text("0 B")
                .font(FUFont.hero)
                .foregroundStyle(.tertiary)

            Button {
                Task { await viewModel.startScan() }
            } label: {
                HStack(spacing: 10) {
                    Text("Scan")
                        .font(FUFont.bodySemibold)
                    KBDPill("⌘R")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
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
                    Hairline().opacity(0.5)
                }
            }
        }
        .padding(.horizontal, 20)
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
                IconSquare(systemName: category.iconName, color: category.themeColor, size: 26)

                Text(category.rawValue)
                    .font(FUFont.bodyMedium)
                    .foregroundStyle(.primary)
                    .frame(width: 164, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.primary.opacity(0.08))
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
                    .frame(width: 56, alignment: .trailing)

                Text(ByteFormatter.format(size))
                    .font(FUFont.mono)
                    .foregroundStyle(.primary)
                    .frame(width: 76, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.05) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Warning banner (kept — hairline-bordered)

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
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
