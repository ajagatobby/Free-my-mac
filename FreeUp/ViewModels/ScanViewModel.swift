//
//  ScanViewModel.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import Foundation
import SwiftUI
import AppKit

/// State of the scanning process
enum ScanState: Equatable {
    case idle
    case scanning(progress: Double, currentDirectory: String?)
    case detectingDuplicates(progress: Double)
    case completed(totalFiles: Int, totalSize: Int64, duration: TimeInterval)
    case error(String)
    
    static func == (lhs: ScanState, rhs: ScanState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.scanning(let p1, let d1), .scanning(let p2, let d2)):
            return p1 == p2 && d1 == d2
        case (.detectingDuplicates(let p1), .detectingDuplicates(let p2)):
            return p1 == p2
        case (.completed(let f1, let s1, let d1), .completed(let f2, let s2, let d2)):
            return f1 == f2 && s1 == s2 && d1 == d2
        case (.error(let e1), .error(let e2)):
            return e1 == e2
        default:
            return false
        }
    }
}

/// Main view model for scanning operations
@MainActor
@Observable
final class ScanViewModel {
    
    // MARK: - Published State
    
    private(set) var scanState: ScanState = .idle
    private(set) var totalFilesScanned: Int = 0
    private(set) var totalSizeScanned: Int64 = 0
    private(set) var categoryStats: [FileCategory: CategoryStats] = [:]
    private(set) var volumeInfo: VolumeInfo?
    private(set) var snapshotWarning: String?
    private(set) var fullDiskAccessStatus: PermissionStatus = .notDetermined
    
    /// All scanned files grouped by category
    private(set) var scannedFiles: [FileCategory: [ScannedFileInfo]] = [:]
    
    /// Detected duplicate file groups
    private(set) var duplicateGroups: [DuplicateGroup] = []
    
    /// Cached sub-category stats (recomputed only when scannedFiles changes)
    private(set) var cachedSubCategoryStats: [FileCategory: [(source: String, count: Int, totalSize: Int64)]] = [:]
    
    /// Selected items for deletion
    var selectedItems: Set<UUID> = []
    
    /// Whether deletion is in progress
    private(set) var isDeletingFiles = false
    
    /// Last deletion result for display
    private(set) var lastDeletionResult: DeletionResult?
    private(set) var showDeletionResult = false
    
    // MARK: - Services
    
    private let smartScanner = SmartScannerService()
    private let ultraScanner = UltraScannerService()
    private let turboScanner = TurboScannerService()
    private let standardScanner = ScannerService()
    private let apfsService = APFSService()
    private let permissionService = PermissionService()
    private let duplicateService = DuplicateDetectionService()
    private let deletionService = DeletionService()
    
    // MARK: - Throttle State
    
    /// Last reported progress value for throttling UI updates
    private var lastReportedProgress: Double = 0
    
    /// Pending APFS identifiers to batch-register
    private var pendingAPFSIdentifiers: [(Int64, String)] = []
    
    // MARK: - Computed Properties
    
    var reclaimableSpace: Int64 {
        let reclaimableCategories: [FileCategory] = [.cache, .logs, .systemJunk, .developerFiles, .duplicates]
        return reclaimableCategories.reduce(0) { sum, category in
            sum + (categoryStats[category]?.totalSize ?? 0)
        }
    }
    
    var isScanning: Bool {
        if case .scanning = scanState { return true }
        if case .detectingDuplicates = scanState { return true }
        return false
    }
    
    var duplicateWastedSpace: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.wastedSpace }
    }
    
    var totalDuplicateCount: Int {
        duplicateGroups.reduce(0) { $0 + $1.duplicateCount }
    }
    
    // MARK: - Settings
    
    var currentDeleteMode: DeletionService.DeleteMode {
        // Default is permanent delete: moving cache/log junk to Trash keeps it
        // on disk, which defeats the whole point of the app. Users can still
        // opt into the safer "Move to Trash" mode in Settings.
        let mode = UserDefaults.standard.string(forKey: "deleteMode") ?? "permanent"
        return mode == "permanent" ? .permanent : .moveToTrash
    }
    
    var showHiddenFiles: Bool {
        UserDefaults.standard.bool(forKey: "showHiddenFiles")
    }
    
    // MARK: - Public Methods
    
    func startScan(directory: URL? = nil) async {
        // Reset state
        scanState = .scanning(progress: 0, currentDirectory: nil)
        totalFilesScanned = 0
        totalSizeScanned = 0
        categoryStats = [:]
        scannedFiles = [:]
        selectedItems = []
        duplicateGroups = []
        cachedSubCategoryStats = [:]
        lastReportedProgress = 0
        pendingAPFSIdentifiers = []
        
        await apfsService.clearCache()
        volumeInfo = await apfsService.getVolumeInfo()
        
        Task {
            snapshotWarning = await apfsService.snapshotWarning
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let scanStream: AsyncStream<ScanResult>
        let scannerName: String
        
        if let customDirectory = directory {
            if ultraScanner.canUseBSDAPIs(for: customDirectory) {
                scanStream = await ultraScanner.scan(directory: customDirectory)
                scannerName = "UltraScanner"
            } else {
                scanStream = await turboScanner.scan(directory: customDirectory)
                scannerName = "TurboScanner"
            }
        } else {
            scanStream = await smartScanner.scan()
            scannerName = "SmartScanner"
        }
        
        for await result in scanStream {
            switch result {
            case .batch(let files):
                processBatch(files)
                
            case .progress(let file):
                processSingleFile(file)
                
            case .directoryStarted(let url):
                let relativePath = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                updateProgressThrottled(currentDirectory: relativePath)
                
            case .directoryCompleted(_, fileCount: _, totalSize: _):
                updateProgressThrottled(currentDirectory: nil)
                
            case .error(let error):
                handleError(error)
                
            case .completed(totalFiles: let files, totalSize: let size):
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                print("\(scannerName) completed: \(files) files, \(ByteFormatter.format(size)) in \(String(format: "%.2f", duration))s")
                
                // Flush pending APFS registrations
                await flushAPFSRegistrations()
                
                // Rebuild sub-category stats cache
                rebuildSubCategoryStatsCache()
                
                // Detect duplicates (runs once, stores result) — only for user content categories
                await detectDuplicates()
                
                let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
                scanState = .completed(totalFiles: totalFilesScanned, totalSize: totalSizeScanned, duration: totalDuration)
            }
        }
    }
    
    func cancelScan() {
        Task {
            await smartScanner.cancel()
            await ultraScanner.cancel()
            await turboScanner.cancel()
            await standardScanner.cancel()
            await duplicateService.cancel()
        }
        scanState = .idle
    }
    
    func files(for category: FileCategory) -> [ScannedFileInfo] {
        return scannedFiles[category] ?? []
    }
    
    /// Get sub-category stats from cache (O(1) lookup, not recomputed per call)
    func subCategoryStats(for category: FileCategory) -> [(source: String, count: Int, totalSize: Int64)] {
        return cachedSubCategoryStats[category] ?? []
    }
    
    func checkPermissions() {
        fullDiskAccessStatus = permissionService.checkFullDiskAccess()
    }
    
    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func selectDirectory() async -> URL? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = false
                panel.title = "Select Folder to Scan"
                panel.prompt = "Scan"
                
                if panel.runModal() == .OK {
                    continuation.resume(returning: panel.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    // MARK: - Deletion Methods
    
    func deleteSelectedFiles(from category: FileCategory) async {
        guard !selectedItems.isEmpty else { return }
        
        // Use selectedItems Set for O(1) lookup instead of filtering entire array
        let files = scannedFiles[category] ?? []
        var selectedFiles: [ScannedFileInfo] = []
        selectedFiles.reserveCapacity(min(selectedItems.count, files.count))
        for file in files {
            if selectedItems.contains(file.id) {
                selectedFiles.append(file)
            }
        }
        guard !selectedFiles.isEmpty else { return }
        
        isDeletingFiles = true
        let result = await deletionService.deleteFilesFast(selectedFiles, mode: currentDeleteMode)
        
        if result.successCount > 0 {
            // Use failed URLs to determine which files actually succeeded
            let failedURLs = Set(result.errors.map(\.url))
            let successfulFiles = selectedFiles.filter { !failedURLs.contains($0.url) }
            removeDeletedFilesFast(successfulFiles, fromCategories: [category])
        }
        
        lastDeletionResult = result
        showDeletionResult = true
        isDeletingFiles = false
    }
    
    func cleanUpReclaimableFiles() async {
        let reclaimableCategories: [FileCategory] = [.cache, .logs, .systemJunk]
        var allFiles: [ScannedFileInfo] = []
        
        for category in reclaimableCategories {
            allFiles.append(contentsOf: scannedFiles[category] ?? [])
        }
        
        guard !allFiles.isEmpty else { return }
        isDeletingFiles = true
        
        let result = await deletionService.deleteFilesFast(allFiles, mode: currentDeleteMode)
        
        if result.successCount > 0 {
            removeDeletedFilesFast(allFiles, fromCategories: reclaimableCategories)
        }
        
        lastDeletionResult = result
        showDeletionResult = true
        isDeletingFiles = false
    }
    
    func deleteFiles(_ files: [ScannedFileInfo]) async {
        guard !files.isEmpty else { return }
        isDeletingFiles = true
        
        let result = await deletionService.deleteFilesFast(files, mode: currentDeleteMode)
        
        if result.successCount > 0 {
            let deletedIDs = Set(files.map(\.id))
            
            duplicateGroups = duplicateGroups.compactMap { group in
                let remaining = group.files.filter { !deletedIDs.contains($0.id) }
                if remaining.count <= 1 { return nil }
                return DuplicateGroup(id: group.id, hash: group.hash, fileSize: group.fileSize, files: remaining)
            }
            
            updateDuplicateStats()
            
            // Group deleted files by category, remove all at once
            var byCategory: [FileCategory: [ScannedFileInfo]] = [:]
            for file in files {
                byCategory[file.category, default: []].append(file)
            }
            for (cat, catFiles) in byCategory {
                removeDeletedFilesFast(catFiles, fromCategories: [cat])
            }
        }
        
        lastDeletionResult = result
        showDeletionResult = true
        isDeletingFiles = false
    }
    
    func dismissDeletionResult() {
        showDeletionResult = false
        lastDeletionResult = nil
    }
    
    func selectAllFiles(in category: FileCategory) {
        let files = scannedFiles[category] ?? []
        // Build locally, assign once (single @Observable notification)
        var updated = selectedItems
        for file in files {
            updated.insert(file.id)
        }
        selectedItems = updated
    }
    
    func deselectAllFiles(in category: FileCategory) {
        let files = scannedFiles[category] ?? []
        var updated = selectedItems
        for file in files {
            updated.remove(file.id)
        }
        selectedItems = updated
    }
    
    // MARK: - Batch File Processing (Fix #2 + #3)
    
    /// Process a batch of files with a SINGLE Observable mutation (not per-file)
    private func processBatch(_ files: [ScannedFileInfo]) {
        // Accumulate batch totals locally (no @Observable overhead)
        var batchSize: Int64 = 0
        var batchCategoryUpdates: [FileCategory: [ScannedFileInfo]] = [:]
        var batchStats: [FileCategory: (count: Int, size: Int64)] = [:]
        var batchAPFS: [(Int64, String)] = []
        
        for file in files {
            batchSize += file.allocatedSize
            
            // Accumulate into local dictionary (no COW on scannedFiles)
            if batchCategoryUpdates[file.category] == nil {
                batchCategoryUpdates[file.category] = []
            }
            batchCategoryUpdates[file.category]!.append(file)
            
            var stats = batchStats[file.category] ?? (0, 0)
            stats.count += 1
            stats.size += file.allocatedSize
            batchStats[file.category] = stats
            
            if let identifier = file.fileContentIdentifier {
                batchAPFS.append((identifier, file.url.path))
            }
        }
        
        // Single mutation of @Observable properties
        totalFilesScanned += files.count
        totalSizeScanned += batchSize
        
        // In-place array append (avoids COW by using subscript directly)
        for (cat, newFiles) in batchCategoryUpdates {
            if scannedFiles[cat] == nil {
                scannedFiles[cat] = []
            }
            scannedFiles[cat]!.append(contentsOf: newFiles)
            
            var existingStats = categoryStats[cat] ?? CategoryStats(count: 0, totalSize: 0)
            existingStats.count += batchStats[cat]!.count
            existingStats.totalSize += batchStats[cat]!.size
            categoryStats[cat] = existingStats
        }
        
        // Batch APFS registrations
        pendingAPFSIdentifiers.append(contentsOf: batchAPFS)
        
        // Throttled UI update
        updateProgressThrottled(currentDirectory: nil)
    }
    
    /// Process a single file (fallback for .progress events)
    private func processSingleFile(_ file: ScannedFileInfo) {
        totalFilesScanned += 1
        totalSizeScanned += file.allocatedSize
        
        var stats = categoryStats[file.category] ?? CategoryStats(count: 0, totalSize: 0)
        stats.count += 1
        stats.totalSize += file.allocatedSize
        categoryStats[file.category] = stats
        
        // In-place append (avoids COW)
        if scannedFiles[file.category] == nil {
            scannedFiles[file.category] = []
        }
        scannedFiles[file.category]!.append(file)
        
        if let identifier = file.fileContentIdentifier {
            pendingAPFSIdentifiers.append((identifier, file.url.path))
        }
    }
    
    // MARK: - Throttled Progress Updates (Fix #18)
    
    private func updateProgressThrottled(currentDirectory: String?) {
        let newProgress = estimateProgress()
        // Only update UI when progress changes by > 1%
        if abs(newProgress - lastReportedProgress) > 0.01 {
            scanState = .scanning(progress: newProgress, currentDirectory: currentDirectory)
            lastReportedProgress = newProgress
        }
    }
    
    private func handleError(_ error: ScanError) {
        switch error {
        case .accessDenied(let url):
            print("Access denied: \(url.path)")
        case .cancelled:
            scanState = .idle
        case .invalidPath(let path):
            scanState = .error("Invalid path: \(path)")
        case .unknown(let message):
            scanState = .error(message)
        }
    }
    
    private func estimateProgress() -> Double {
        let estimatedTotal = 50_000.0
        return min(0.99, Double(totalFilesScanned) / estimatedTotal)
    }
    
    // MARK: - Batch APFS Registration (Fix #17)
    
    private func flushAPFSRegistrations() async {
        guard !pendingAPFSIdentifiers.isEmpty else { return }
        let batch = pendingAPFSIdentifiers.map { (identifier: $0.0, path: $0.1) }
        pendingAPFSIdentifiers = []
        
        // Single actor call instead of serial await per-registration
        await apfsService.registerFiles(batch)
    }
    
    // MARK: - Sub-Category Stats Cache (Fix #7)
    
    private func rebuildSubCategoryStatsCache() {
        var cache: [FileCategory: [(source: String, count: Int, totalSize: Int64)]] = [:]
        
        for (category, files) in scannedFiles {
            var groups: [String: (count: Int, size: Int64)] = [:]
            for file in files {
                let source = file.source ?? "Other"
                var current = groups[source] ?? (0, 0)
                current.count += 1
                current.size += file.allocatedSize
                groups[source] = current
            }
            
            cache[category] = groups.map { (source: $0.key, count: $0.value.count, totalSize: $0.value.size) }
                .sorted { $0.totalSize > $1.totalSize }
        }
        
        cachedSubCategoryStats = cache
    }
    
    // MARK: - Duplicate Detection (Fix #1 -- runs once, retrieves stored result)
    
    private func detectDuplicates() async {
        // Only check categories where duplicates are meaningful and actionable
        let duplicateCategories: Set<FileCategory> = [.downloads, .documents, .videos, .photos, .audio]
        var allFiles: [ScannedFileInfo] = []
        
        for (category, files) in scannedFiles {
            if duplicateCategories.contains(category) {
                allFiles.append(contentsOf: files)
            }
        }
        
        // Skip entirely if too few files to have meaningful duplicates
        guard allFiles.count > 10 else { return }
        
        scanState = .detectingDuplicates(progress: 0)
        
        // Run detection with progress (stores result internally)
        for await progress in await duplicateService.detectDuplicates(from: allFiles) {
            switch progress.phase {
            case .groupingBySize:
                scanState = .detectingDuplicates(progress: 0.1)
            case .hashing:
                scanState = .detectingDuplicates(progress: 0.1 + progress.percentage * 0.85)
            case .completed:
                scanState = .detectingDuplicates(progress: 1.0)
            }
        }
        
        // Retrieve stored result (no re-scan!)
        duplicateGroups = await duplicateService.getLastResult()
        updateDuplicateStats()
        
        if !duplicateGroups.isEmpty {
            print("Found \(duplicateGroups.count) duplicate groups, \(totalDuplicateCount) duplicates, \(ByteFormatter.format(duplicateWastedSpace)) wasted")
        }
    }
    
    private func updateDuplicateStats() {
        if !duplicateGroups.isEmpty {
            var duplicateFiles: [ScannedFileInfo] = []
            duplicateFiles.reserveCapacity(totalDuplicateCount)
            
            for group in duplicateGroups {
                for file in group.files.dropFirst() {
                    let dupFile = ScannedFileInfo(
                        url: file.url,
                        allocatedSize: file.allocatedSize,
                        fileSize: file.fileSize,
                        contentType: file.contentType,
                        category: .duplicates,
                        lastAccessDate: file.lastAccessDate,
                        fileContentIdentifier: file.fileContentIdentifier,
                        isPurgeable: file.isPurgeable,
                        source: "Duplicate of \(group.files.first?.fileName ?? "unknown")"
                    )
                    duplicateFiles.append(dupFile)
                }
            }
            
            scannedFiles[.duplicates] = duplicateFiles
            categoryStats[.duplicates] = CategoryStats(count: duplicateFiles.count, totalSize: duplicateWastedSpace)
        } else {
            scannedFiles.removeValue(forKey: .duplicates)
            categoryStats.removeValue(forKey: .duplicates)
        }
    }
    
    // MARK: - Orphaned App Data Filtering (Fix #13 + #14)
    
    private func filterOrphanedAppData() async {
        guard let orphanedFiles = scannedFiles[.orphanedAppData], !orphanedFiles.isEmpty else { return }
        
        // Move I/O-heavy plist reading off main thread
        let installedApps = await Task.detached {
            Self.getInstalledAppBundleIdentifiers()
        }.value
        
        // Pre-compute lowercased set once (Fix #13)
        let installedAppsLower = Set(installedApps.map { $0.lowercased() })
        
        let filteredFiles = orphanedFiles.filter { file in
            let pathComponents = file.url.pathComponents
            guard let appSupportIndex = pathComponents.firstIndex(of: "Application Support"),
                  appSupportIndex + 1 < pathComponents.count else {
                return true
            }
            
            let folderName = pathComponents[appSupportIndex + 1]
            
            // O(1) set lookup instead of O(n) loop
            if installedApps.contains(folderName) {
                return false
            }
            
            let folderLower = folderName.lowercased()
            // Check against pre-lowercased set
            for id in installedAppsLower {
                if id.contains(folderLower) || folderLower.contains(id) {
                    return false
                }
            }
            
            return true
        }
        
        scannedFiles[.orphanedAppData] = filteredFiles
        let newSize = filteredFiles.reduce(Int64(0)) { $0 + $1.allocatedSize }
        categoryStats[.orphanedAppData] = CategoryStats(count: filteredFiles.count, totalSize: newSize)
        
        rebuildSubCategoryStatsCache()
    }
    
    /// Get bundle identifiers of installed apps -- nonisolated for off-main-thread use
    private nonisolated static func getInstalledAppBundleIdentifiers() -> Set<String> {
        var identifiers = Set<String>()
        
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        
        let fm = FileManager.default
        for appDir in appDirs {
            guard let contents = try? fm.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil) else {
                continue
            }
            
            for item in contents {
                if item.pathExtension == "app" {
                    identifiers.insert(item.deletingPathExtension().lastPathComponent)
                    
                    let plistURL = item.appendingPathComponent("Contents/Info.plist")
                    if let plistData = try? Data(contentsOf: plistURL),
                       let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                       let bundleId = plist["CFBundleIdentifier"] as? String {
                        identifiers.insert(bundleId)
                        if let lastComponent = bundleId.split(separator: ".").last {
                            identifiers.insert(String(lastComponent))
                        }
                    }
                }
            }
        }
        
        return identifiers
    }
    
    // MARK: - File Removal After Deletion (fast batch version)
    
    /// Remove deleted files from model state — single pass, single mutation per collection
    private func removeDeletedFilesFast(_ deletedFiles: [ScannedFileInfo], fromCategories categories: [FileCategory]) {
        let deletedIDs = Set(deletedFiles.map(\.id))
        
        for category in categories {
            guard var files = scannedFiles[category] else { continue }
            let beforeCount = files.count
            files.removeAll { deletedIDs.contains($0.id) }
            
            if files.count != beforeCount {
                // Compute new size in single pass
                var newSize: Int64 = 0
                for f in files { newSize += f.allocatedSize }
                scannedFiles[category] = files
                categoryStats[category] = CategoryStats(count: files.count, totalSize: newSize)
            }
        }
        
        // Remove from selection — single Set mutation
        var updatedSelection = selectedItems
        for id in deletedIDs {
            updatedSelection.remove(id)
        }
        selectedItems = updatedSelection
        
        rebuildSubCategoryStatsCache()
    }
}

// MARK: - Full Disk Access Status Alias

typealias FullDiskAccessStatus = PermissionStatus
