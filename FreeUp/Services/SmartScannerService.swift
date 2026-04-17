//
//  SmartScannerService.swift
//  FreeUp
//
//  Lightning-fast scanner that targets KNOWN junk locations only
//  This is how CleanMyMac achieves 30-second scans
//
//  Strategy:
//  1. Pre-defined list of ~30 known junk locations
//  2. Scan ALL locations in parallel simultaneously
//  3. No UTType detection needed - category known from path
//  4. Use fts for fast traversal within each location
//  5. Minimal metadata collection (just size)
//

import Foundation
import UniformTypeIdentifiers

// MARK: - Scan Target

/// A specific directory to scan with its known category
private struct ScanTarget: Sendable {
    let url: URL
    let category: FileCategory
    let description: String
    /// When true, walk the target's immediate children in parallel rather than as a
    /// single serial fts traversal. Worthwhile for directories that tend to hold
    /// many independent, heavyweight subtrees (Xcode DerivedData, iOS Simulators).
    let splitChildren: Bool

    nonisolated init(
        url: URL,
        category: FileCategory,
        description: String,
        splitChildren: Bool = false
    ) {
        self.url = url
        self.category = category
        self.description = description
        self.splitChildren = splitChildren
    }
}

// MARK: - SmartScannerService

/// Lightning-fast scanner that only scans known junk locations
actor SmartScannerService {
    
    // MARK: - Configuration
    
    /// Batch size for yielding results
    private let batchSize: Int = 500
    
    private var isCancelled = false
    
    // MARK: - Known Junk Locations
    
    /// All known locations where cleanable files accumulate
    private static func getScanTargets() -> [ScanTarget] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        
        var targets: [ScanTarget] = []
        
        // ============ CACHE (typically largest) ============
        // Scan ~/Library/Caches with smart source detection (sub-categorizes by app)
        // NOTE: Do NOT add individual browser cache targets -- they overlap with this
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Caches"),
            category: .cache,
            description: "User Caches",
            splitChildren: true
        ))
        targets.append(ScanTarget(
            url: URL(fileURLWithPath: "/Library/Caches"),
            category: .cache,
            description: "System Caches",
            splitChildren: true
        ))
        
        // ============ LOGS ============
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Logs"),
            category: .logs,
            description: "User Logs"
        ))
        targets.append(ScanTarget(
            url: URL(fileURLWithPath: "/Library/Logs"),
            category: .logs,
            description: "System Logs"
        ))
        targets.append(ScanTarget(
            url: URL(fileURLWithPath: "/var/log"),
            category: .logs,
            description: "Unix Logs"
        ))
        
        // ============ SYSTEM JUNK ============
        // NOTE: ~/.Trash is intentionally NOT scanned. It contained 200k+ files
        // on some machines, all showing as "System Junk". Deleting them tried to
        // move-to-Trash files already in the Trash, causing Finder to hang.
        // The app offers "Empty Trash" as a separate action instead.
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Saved Application State"),
            category: .systemJunk,
            description: "Saved App State"
        ))
        
        // ============ DEVELOPER FILES (often HUGE) ============
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Developer/Xcode/DerivedData"),
            category: .developerFiles,
            description: "Xcode DerivedData",
            splitChildren: true
        ))
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Developer/Xcode/iOS DeviceSupport"),
            category: .developerFiles,
            description: "iOS Device Support",
            splitChildren: true
        ))
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Developer/Xcode/watchOS DeviceSupport"),
            category: .developerFiles,
            description: "watchOS Device Support",
            splitChildren: true
        ))
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Developer/CoreSimulator/Devices"),
            category: .developerFiles,
            description: "iOS Simulators",
            splitChildren: true
        ))
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Developer/Xcode/Archives"),
            category: .developerFiles,
            description: "Xcode Archives",
            splitChildren: true
        ))
        targets.append(ScanTarget(
            url: home.appendingPathComponent(".npm"),
            category: .developerFiles,
            description: "NPM Cache",
            splitChildren: true
        ))
        targets.append(ScanTarget(
            url: home.appendingPathComponent(".gradle"),
            category: .developerFiles,
            description: "Gradle Cache",
            splitChildren: true
        ))
        targets.append(ScanTarget(
            url: home.appendingPathComponent(".cocoapods"),
            category: .developerFiles,
            description: "CocoaPods Cache",
            splitChildren: true
        ))
        targets.append(ScanTarget(
            url: home.appendingPathComponent(".cargo"),
            category: .developerFiles,
            description: "Cargo Cache"
        ))
        targets.append(ScanTarget(
            url: home.appendingPathComponent(".pub-cache"),
            category: .developerFiles,
            description: "Dart/Flutter Cache"
        ))
        targets.append(ScanTarget(
            url: home.appendingPathComponent(".nuget"),
            category: .developerFiles,
            description: "NuGet Cache"
        ))
        targets.append(ScanTarget(
            url: home.appendingPathComponent(".m2"),
            category: .developerFiles,
            description: "Maven Cache"
        ))
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Android/sdk"),
            category: .developerFiles,
            description: "Android SDK"
        ))
        // NOTE: CocoaPods Cache and Homebrew Cache are under ~/Library/Caches
        // and already covered by the general Caches target. Don't duplicate.
        
        // ============ DOWNLOADS ============
        targets.append(ScanTarget(
            url: home.appendingPathComponent("Downloads"),
            category: .downloads,
            description: "Downloads"
        ))
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Mail Downloads"),
            category: .downloads,
            description: "Mail Downloads"
        ))
        
        // ============ iOS BACKUPS (can be HUGE) ============
        targets.append(ScanTarget(
            url: library.appendingPathComponent("Application Support/MobileSync/Backup"),
            category: .systemJunk,
            description: "iOS Backups"
        ))
        
        // NOTE: Language Models (Caches/com.apple.LanguageModeling) is already covered
        // by the ~/Library/Caches target. Spotlight Index is system-managed and should
        // not be offered for deletion.
        
        // NOTE: ~/Library/Application Support and ~/Library/Containers are intentionally
        // NOT scanned here. They contain active app data (often 100k+ files, multi-GB)
        // and scanning them causes 99% CPU, 3+ GB memory, and multi-minute stalls.
        // Orphaned app detection should use a shallow top-level-only approach instead.
        
        return targets
    }
    
    // MARK: - Public API
    
    func cancel() {
        isCancelled = true
    }
    
    private func resetCancellation() {
        isCancelled = false
    }
    
    /// Lightning-fast smart scan - only scans known junk locations
    func scan(directory: URL? = nil) -> AsyncStream<ScanResult> {
        AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }
            
            Task.detached(priority: .userInitiated) {
                await self.resetCancellation()
                await self.performSmartScan(continuation: continuation)
            }
        }
    }
    
    // MARK: - Core Smart Scan
    
    private func performSmartScan(
        continuation: AsyncStream<ScanResult>.Continuation
    ) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let targets = Self.getScanTargets()
        
        // Track totals
        var totalFiles = 0
        var totalSize: Int64 = 0
        
        // Scan ALL targets in parallel - this is the key to speed
        await withTaskGroup(of: (Int, Int64).self) { group in
            for target in targets {
                group.addTask { [weak self] in
                    guard let self = self else { return (0, 0) }
                    return await self.scanTarget(target, continuation: continuation)
                }
            }
            
            // Collect results as they complete
            for await (count, size) in group {
                totalFiles += count
                totalSize += size
                
                if self.isCancelled {
                    continuation.yield(.error(.cancelled))
                    continuation.finish()
                    return
                }
            }
        }
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let formattedSize = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        print("⚡ SmartScanner: Scanned \(totalFiles) files (\(formattedSize)) in \(String(format: "%.2f", elapsed))s")
        
        continuation.yield(.completed(totalFiles: totalFiles, totalSize: totalSize))
        continuation.finish()
    }
    
    /// Scan a single target location using fts for speed
    private func scanTarget(
        _ target: ScanTarget,
        continuation: AsyncStream<ScanResult>.Continuation
    ) async -> (Int, Int64) {
        // Check if directory exists
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.url.path, isDirectory: &isDir),
              isDir.boolValue else {
            return (0, 0)
        }

        // Check if we can read it
        guard FileManager.default.isReadableFile(atPath: target.url.path) else {
            return (0, 0)
        }

        continuation.yield(.directoryStarted(target.url))

        // For targets known to hold many independent heavy subtrees (Xcode
        // DerivedData, Simulators, ~/Library/Caches etc.), walk each immediate
        // child in parallel. This overlaps I/O and spreads work across cores.
        if target.splitChildren, let children = immediateChildren(of: target.url), !children.isEmpty {
            return await scanChildrenInParallel(
                parent: target,
                children: children,
                continuation: continuation
            )
        }

        return scanSingleTree(target: target, root: target.url, continuation: continuation)
    }

    /// Walk a single directory tree synchronously via fts and yield batches.
    /// Called either directly or as one work unit in the split-children path.
    private func scanSingleTree(
        target: ScanTarget,
        root: URL,
        continuation: AsyncStream<ScanResult>.Continuation
    ) -> (Int, Int64) {
        var totalCount = 0
        var totalSize: Int64 = 0
        var batch: [ScannedFileInfo] = []
        batch.reserveCapacity(batchSize)

        let path = root.path
        guard let pathCString = strdup(path) else {
            return (0, 0)
        }
        defer { free(pathCString) }

        var pathArray: [UnsafeMutablePointer<CChar>?] = [pathCString, nil]
        guard let fts = fts_open(&pathArray, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
            // Extremely rare — defer to the slower FileManager enumerator on this
            // subtree only so we don't silently drop unreadable edge cases.
            return scanSubtreeFallback(target: target, root: root, continuation: continuation)
        }
        defer { fts_close(fts) }

        while let entry = fts_read(fts) {
            if totalCount % 500 == 0 && isCancelled {
                break
            }

            let info = entry.pointee.fts_info
            guard info == FTS_F else { continue }

            if let stat = entry.pointee.fts_statp {
                let allocatedSize = Int64(stat.pointee.st_blocks) * 512
                let fileSize = Int64(stat.pointee.st_size)
                let filePath = String(cString: entry.pointee.fts_path)
                let fileURL = URL(fileURLWithPath: filePath)

                let fileInfo = ScannedFileInfo(
                    url: fileURL,
                    allocatedSize: allocatedSize,
                    fileSize: fileSize,
                    contentType: nil,
                    category: target.category,
                    lastAccessDate: nil,
                    fileContentIdentifier: nil,
                    isPurgeable: false,
                    source: target.description
                )

                batch.append(fileInfo)
                totalCount += 1
                totalSize += allocatedSize

                if batch.count >= batchSize {
                    continuation.yield(.batch(batch))
                    batch.removeAll(keepingCapacity: true)
                }
            }
        }

        if !batch.isEmpty {
            continuation.yield(.batch(batch))
        }

        return (totalCount, totalSize)
    }

    /// FileManager-based fallback for a single subtree root.
    private func scanSubtreeFallback(
        target: ScanTarget,
        root: URL,
        continuation: AsyncStream<ScanResult>.Continuation
    ) -> (Int, Int64) {
        var totalCount = 0
        var totalSize: Int64 = 0
        var batch: [ScannedFileInfo] = []
        batch.reserveCapacity(batchSize)

        let resourceKeys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .isRegularFileKey,
            .isDirectoryKey
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return (0, 0)
        }

        while let fileURL = enumerator.nextObject() as? URL {
            if totalCount % 500 == 0 && isCancelled { break }

            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true, values.isDirectory != true else {
                continue
            }

            let allocatedSize = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)

            let fileInfo = ScannedFileInfo(
                url: fileURL,
                allocatedSize: allocatedSize,
                fileSize: allocatedSize,
                contentType: nil,
                category: target.category,
                lastAccessDate: nil,
                fileContentIdentifier: nil,
                isPurgeable: false,
                source: target.description
            )

            batch.append(fileInfo)
            totalCount += 1
            totalSize += allocatedSize

            if batch.count >= batchSize {
                continuation.yield(.batch(batch))
                batch.removeAll(keepingCapacity: true)
            }
        }

        if !batch.isEmpty {
            continuation.yield(.batch(batch))
        }

        return (totalCount, totalSize)
    }

    /// Return direct children (files and dirs) of a URL, or nil if unreadable.
    /// Uses readdir via FileManager; no recursion.
    private nonisolated func immediateChildren(of url: URL) -> [URL]? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return entries
    }

    /// Scan a target's immediate children in parallel. Files at the root are
    /// folded into a single synthetic task so they're not dropped.
    private func scanChildrenInParallel(
        parent: ScanTarget,
        children: [URL],
        continuation: AsyncStream<ScanResult>.Continuation
    ) async -> (Int, Int64) {
        var totalCount = 0
        var totalSize: Int64 = 0

        // Partition: directories get their own task, loose files batched together.
        // Build into vars, then freeze to lets so the sending closures below can
        // safely capture them without risking a data race with later mutation.
        let (childDirs, looseFiles): ([URL], [URL]) = {
            var dirs: [URL] = []
            var files: [URL] = []
            dirs.reserveCapacity(children.count)
            for child in children {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        dirs.append(child)
                    } else {
                        files.append(child)
                    }
                }
            }
            return (dirs, files)
        }()

        await withTaskGroup(of: (Int, Int64).self) { group in
            for childDir in childDirs {
                group.addTask { [weak self] in
                    guard let self else { return (0, 0) }
                    return await self.scanChildSubtree(
                        target: parent,
                        root: childDir,
                        continuation: continuation
                    )
                }
            }

            if !looseFiles.isEmpty {
                let filesToScan = looseFiles
                group.addTask { [weak self] in
                    guard let self else { return (0, 0) }
                    return await self.statLooseFiles(
                        target: parent,
                        files: filesToScan,
                        continuation: continuation
                    )
                }
            }

            for await (count, size) in group {
                if isCancelled { break }
                totalCount += count
                totalSize += size
            }
        }

        return (totalCount, totalSize)
    }

    /// Actor-isolated wrapper so each child subtree walk can run in its own task.
    private func scanChildSubtree(
        target: ScanTarget,
        root: URL,
        continuation: AsyncStream<ScanResult>.Continuation
    ) -> (Int, Int64) {
        scanSingleTree(target: target, root: root, continuation: continuation)
    }

    /// Stat loose (non-directory) files at a target's root without fts.
    private func statLooseFiles(
        target: ScanTarget,
        files: [URL],
        continuation: AsyncStream<ScanResult>.Continuation
    ) -> (Int, Int64) {
        var totalCount = 0
        var totalSize: Int64 = 0
        var batch: [ScannedFileInfo] = []
        batch.reserveCapacity(min(batchSize, files.count))

        for url in files {
            if totalCount % 500 == 0 && isCancelled { break }

            var st = stat()
            guard lstat(url.path, &st) == 0 else { continue }
            // Only regular files
            let mode = mode_t(st.st_mode)
            guard (mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { continue }

            let allocatedSize = Int64(st.st_blocks) * 512
            let fileSize = Int64(st.st_size)

            let fileInfo = ScannedFileInfo(
                url: url,
                allocatedSize: allocatedSize,
                fileSize: fileSize,
                contentType: nil,
                category: target.category,
                lastAccessDate: nil,
                fileContentIdentifier: nil,
                isPurgeable: false,
                source: target.description
            )

            batch.append(fileInfo)
            totalCount += 1
            totalSize += allocatedSize

            if batch.count >= batchSize {
                continuation.yield(.batch(batch))
                batch.removeAll(keepingCapacity: true)
            }
        }

        if !batch.isEmpty {
            continuation.yield(.batch(batch))
        }

        return (totalCount, totalSize)
    }
    
    // MARK: - Quick Stats (even faster - just sizes)
    
    /// Ultra-fast scan that only returns category totals (no file list)
    func quickStats() async -> [FileCategory: (count: Int, size: Int64)] {
        var results: [FileCategory: (count: Int, size: Int64)] = [:]
        
        let targets = Self.getScanTargets()
        
        await withTaskGroup(of: (FileCategory, Int, Int64).self) { group in
            for target in targets {
                group.addTask {
                    let (count, size) = await self.getDirectoryStats(target.url)
                    return (target.category, count, size)
                }
            }
            
            // Results are processed sequentially here - no lock needed
            for await (category, count, size) in group {
                var current = results[category] ?? (0, 0)
                current.count += count
                current.size += size
                results[category] = current
            }
        }
        
        return results
    }
    
    /// Get just count and size for a directory (no file enumeration)
    private func getDirectoryStats(_ url: URL) async -> (Int, Int64) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue,
              FileManager.default.isReadableFile(atPath: url.path) else {
            return (0, 0)
        }
        
        var totalCount = 0
        var totalSize: Int64 = 0
        
        guard let pathCString = strdup(url.path) else {
            return (0, 0)
        }
        defer { free(pathCString) }
        
        var pathArray: [UnsafeMutablePointer<CChar>?] = [pathCString, nil]
        guard let fts = fts_open(&pathArray, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
            return (0, 0)
        }
        defer { fts_close(fts) }
        
        while let entry = fts_read(fts) {
            guard entry.pointee.fts_info == FTS_F else { continue }
            
            if let stat = entry.pointee.fts_statp {
                totalCount += 1
                totalSize += Int64(stat.pointee.st_blocks) * 512
            }
        }
        
        return (totalCount, totalSize)
    }
}
