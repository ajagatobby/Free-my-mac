//
//  DashboardView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI

// MARK: - Dashboard

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

    private var sortedCategories: [FileCategory] {
        let visible = FileCategory.allCases.filter {
            viewModel.categoryStats[$0] != nil && viewModel.categoryStats[$0]!.count > 0
        }
        // During scanning, keep stable declaration order to prevent row reordering animation.
        // Only sort by size once scanning is complete.
        if isScanning {
            return visible
        }
        return visible.sorted {
            (viewModel.categoryStats[$0]?.totalSize ?? 0) > (viewModel.categoryStats[$1]?.totalSize ?? 0)
        }
    }

    private var hasResults: Bool { !sortedCategories.isEmpty }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        // Alerts
        .alert("Clean Up", isPresented: $showCleanupConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clean Up", role: .destructive) {
                Task { await viewModel.cleanUpReclaimableFiles() }
            }
        } message: {
            Text("This will \(viewModel.currentDeleteMode == .moveToTrash ? "move to Trash" : "permanently delete") cache, logs, and junk to free \(ByteFormatter.format(viewModel.reclaimableSpace)).")
        }
        .alert(
            viewModel.lastDeletionResult?.allSuccessful == true ? "Cleanup Complete" : "Cleanup Result",
            isPresented: Binding(
                get: {
                    // Suppress the generic alert when the failure is a
                    // permission problem — we show the dedicated FDA sheet
                    // instead (see .onChange below).
                    guard viewModel.showDeletionResult else { return false }
                    if viewModel.lastDeletionResult?.isPermissionBlocked == true {
                        return false
                    }
                    return true
                },
                set: { if !$0 { viewModel.dismissDeletionResult() } }
            )
        ) {
            Button("OK") { viewModel.dismissDeletionResult() }
        } message: {
            if let r = viewModel.lastDeletionResult {
                if r.successCount > 0 && r.failureCount == 0 {
                    Text("Freed \(ByteFormatter.format(r.freedSpace)). \(r.successCount) files removed.")
                } else if r.successCount == 0 {
                    Text("All \(r.failureCount) files failed. \(r.errors.first?.error ?? "")")
                } else {
                    Text("Freed \(ByteFormatter.format(r.freedSpace)). \(r.successCount) removed, \(r.failureCount) failed.")
                }
            }
        }
        // Route permission-denied failures to the FDA walkthrough sheet so
        // the user isn't stuck re-reading the same generic alert.
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

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: Binding(
            get: { selectedCategory?.rawValue },
            set: { newValue in
                selectedCategory = newValue.flatMap { FileCategory(rawValue: $0) }
            }
        )) {
            // Home
            Button {
                selectedCategory = nil
            } label: {
                Label("Overview", systemImage: "house")
            }
            .listRowSeparator(.hidden)
            .foregroundStyle(selectedCategory == nil ? Color.accentColor : .primary)

            if !sortedCategories.isEmpty || isScanning {
                Section("Categories") {
                    ForEach(sortedCategories) { category in
                        SidebarCategoryRow(
                            category: category,
                            stats: viewModel.categoryStats[category],
                            isSelected: selectedCategory == category,
                            action: {
                                selectedCategory = category
                            }
                        )
                        .tag(category.rawValue)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .animation(nil, value: sortedCategories.map(\.rawValue))
        .animation(nil, value: isScanning)
        .safeAreaInset(edge: .top) {
            sidebarHeader
        }
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
    }

    // MARK: - Sidebar Header

    private var sidebarHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("FreeUp")
                    .font(.headline)

                Spacer()

                Button {
                    if isScanning {
                        viewModel.cancelScan()
                    } else {
                        Task { await viewModel.startScan() }
                    }
                } label: {
                    Image(systemName: isScanning ? "stop.fill" : "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(isScanning ? .red : .accentColor)
                .help(isScanning ? "Stop" : "Scan")
            }

            // Fixed-height scanning indicator — uses opacity instead of
            // conditional insertion to prevent the list from shifting vertically.
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("\(viewModel.totalFilesScanned) files found...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(height: 16)
            .opacity(isScanning ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(nil, value: isScanning)
    }

    // MARK: - Sidebar Footer

    private var sidebarFooter: some View {
        VStack(spacing: 8) {
            Divider()

            // Storage
            if let info = viewModel.volumeInfo {
                HStack {
                    Text(info.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(ByteFormatter.format(info.availableCapacity)) free")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: Double(info.usedCapacity), total: Double(max(info.totalCapacity, 1)))
                    .tint(.blue)
            }

            // Reclaimable — always reserve space, toggle visibility to prevent layout shift
            if viewModel.reclaimableSpace > 0 {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Reclaimable")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(ByteFormatter.format(viewModel.reclaimableSpace))
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    Button("Clean Up") {
                        showCleanupConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isScanning)
                }
                .opacity(isScanning ? 0.4 : 1.0)
            }

            if viewModel.fullDiskAccessStatus == .denied {
                Button {
                    viewModel.openFullDiskAccessSettings()
                } label: {
                    Label("Grant Full Disk Access", systemImage: "lock.shield")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .animation(nil, value: isScanning)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if isScanning && !hasResults {
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
            overviewPane
        }
    }

    // MARK: - Overview

    private var overviewPane: some View {
        ScrollView {
            VStack(spacing: 16) {
                StorageBar(
                    volumeInfo: viewModel.volumeInfo,
                    reclaimableSpace: viewModel.reclaimableSpace
                )

                // Warnings
                if let warning = viewModel.snapshotWarning {
                    WarningBanner(icon: "clock.arrow.circlepath", message: warning, color: .orange)
                }

                if viewModel.fullDiskAccessStatus == .denied {
                    WarningBanner(
                        icon: "lock.shield",
                        message: "Grant Full Disk Access to scan protected folders",
                        color: .yellow,
                        action: ("Open Settings", { viewModel.openFullDiskAccessSettings() })
                    )
                }

                if case .detectingDuplicates(let p) = viewModel.scanState {
                    HStack(spacing: 10) {
                        ProgressView(value: p)
                            .tint(.accentColor)
                        Text("Finding duplicates...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if !hasResults && !isScanning {
                    heroScan
                } else if hasResults {
                    scanSummary
                }
            }
            .padding(20)
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Hero Scan

    @State private var pulsePhase = false

    private var heroScan: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            ZStack {
                // Pulse rings
                Circle()
                    .stroke(Color.accentColor.opacity(pulsePhase ? 0.0 : 0.15), lineWidth: 2)
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulsePhase ? 1.4 : 1.0)

                Circle()
                    .stroke(Color.accentColor.opacity(pulsePhase ? 0.0 : 0.1), lineWidth: 1.5)
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulsePhase ? 1.8 : 1.0)

                Button {
                    Task { await viewModel.startScan() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 72, height: 72)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 12, y: 4)

                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    pulsePhase = true
                }
            }

            Text("Smart Scan")
                .font(.title3.weight(.medium))

            Text("Analyze your storage and find reclaimable space")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Scan Summary

    private var scanSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Scan Results")
                    .font(.headline)

                Spacer()

                if case .completed(let files, let size, let dur) = viewModel.scanState {
                    Text("\(files) files \u{2022} \(ByteFormatter.format(size)) \u{2022} \(formatDuration(dur))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if isScanning {
                    InlineScanProgress(state: viewModel.scanState, filesScanned: viewModel.totalFilesScanned)
                }
            }

            ForEach(sortedCategories) { category in
                Button {
                    selectedCategory = category
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: category.iconName)
                            .font(.system(size: 14))
                            .foregroundStyle(category.themeColor)
                            .frame(width: 22)

                        Text(category.rawValue)
                            .font(.body)
                            .foregroundStyle(.primary)

                        Spacer()

                        if let stats = viewModel.categoryStats[category] {
                            Text("\(stats.formattedCount)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            Text(ByteFormatter.format(stats.totalSize))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 70, alignment: .trailing)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func formatDuration(_ d: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute, .second]
        f.unitsStyle = .abbreviated
        return f.string(from: d) ?? ""
    }
}

// MARK: - Warning Banner

struct WarningBanner: View {
    let icon: String
    let message: String
    let color: Color
    var action: (title: String, handler: () -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(.subheadline)
            Spacer()
            if let action {
                Button(action.title, action: action.handler)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Sidebar Home Row

struct SidebarHomeRow: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Overview", systemImage: "house")
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reclaimable Summary

struct ReclaimableSummary: View {
    let reclaimableSpace: Int64
    let onCleanup: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reclaimable Space")
                    .font(.subheadline.weight(.medium))
                Text("Remove cache, logs, and junk files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ByteFormatter.format(reclaimableSpace))
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.accentColor)
            Button("Clean Up", action: onCleanup)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
