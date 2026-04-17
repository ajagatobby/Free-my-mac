//
//  DuplicateDetectionService.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import Foundation
import CryptoKit

/// A group of duplicate files sharing the same content
struct DuplicateGroup: Identifiable, Sendable {
    let id: UUID
    let hash: String
    let fileSize: Int64
    let files: [ScannedFileInfo]
    
    /// Space that can be reclaimed by keeping only one copy
    nonisolated var wastedSpace: Int64 {
        guard files.count > 1 else { return 0 }
        return fileSize * Int64(files.count - 1)
    }
    
    /// Number of duplicate copies (total - 1 original)
    nonisolated var duplicateCount: Int {
        max(0, files.count - 1)
    }
    
    /// Total space consumed by all copies
    nonisolated var totalSpace: Int64 {
        fileSize * Int64(files.count)
    }
    
    nonisolated init(id: UUID, hash: String, fileSize: Int64, files: [ScannedFileInfo]) {
        self.id = id
        self.hash = hash
        self.fileSize = fileSize
        self.files = files
    }
}

/// Progress update during duplicate detection
struct DuplicateDetectionProgress: Sendable {
    let phase: Phase
    let current: Int
    let total: Int
    let currentFile: String?
    
    enum Phase: Sendable {
        case groupingBySize
        case hashing
        case completed
    }
    
    nonisolated var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
    
    nonisolated init(phase: Phase, current: Int, total: Int, currentFile: String?) {
        self.phase = phase
        self.current = current
        self.total = total
        self.currentFile = currentFile
    }
}

// MARK: - Fast Hex Conversion

/// Pre-computed hex lookup table for fast SHA256 -> hex string conversion
nonisolated(unsafe) private let hexLookup: [UInt8] = Array("0123456789abcdef".utf8)

/// Convert SHA256 digest to hex string without String(format:) overhead
@inline(__always)
private nonisolated func fastHexString(from digest: SHA256.Digest) -> String {
    var result = [UInt8](repeating: 0, count: 64)
    for (i, byte) in digest.enumerated() {
        result[i &* 2] = hexLookup[Int(byte >> 4)]
        result[i &* 2 &+ 1] = hexLookup[Int(byte & 0x0F)]
    }
    return String(bytes: result, encoding: .ascii)!
}

// MARK: - Standalone Hashing Functions (nonisolated for parallel execution)

/// Hash first N bytes AND last N bytes (plus file size as salt) to aggressively
/// discriminate files that share an identical header — common for container
/// formats, compiled binaries, and archives. Still only O(sampleSize) I/O.
/// For files smaller than 2×sampleSize, we just hash the whole thing.
private nonisolated func computePartialHashStatic(
    for url: URL,
    fileSize: Int64,
    sampleSize: Int
) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }

    var hasher = SHA256()

    // Salt with file size so files of different sizes never collide.
    withUnsafeBytes(of: fileSize.littleEndian) { hasher.update(bufferPointer: $0) }

    if fileSize <= Int64(sampleSize) * 2 {
        // Small enough — hash the whole file in one read.
        let data = handle.readData(ofLength: Int(fileSize))
        guard !data.isEmpty else { return nil }
        hasher.update(data: data)
    } else {
        // Head
        let head = handle.readData(ofLength: sampleSize)
        guard !head.isEmpty else { return nil }
        hasher.update(data: head)

        // Tail
        let tailOffset = UInt64(fileSize) - UInt64(sampleSize)
        do {
            try handle.seek(toOffset: tailOffset)
        } catch {
            return nil
        }
        let tail = handle.readData(ofLength: sampleSize)
        guard !tail.isEmpty else { return nil }
        hasher.update(data: tail)
    }

    return fastHexString(from: hasher.finalize())
}

/// Compute full SHA256 hash of entire file (streaming) - runs off actor
private nonisolated func computeFullHashStatic(for url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }

    var hasher = SHA256()
    let bufferSize = 1024 * 1024 // 1MB chunks

    while true {
        let data = handle.readData(ofLength: bufferSize)
        if data.isEmpty { break }
        hasher.update(data: data)
    }

    let hash = hasher.finalize()
    return fastHexString(from: hash)
}

/// High-performance duplicate file detection service
/// Strategy:
/// 1. Group files by size (instant - O(n))
/// 2. Filter groups with only one file (can't be duplicates)
/// 3. For remaining groups, hash first 4KB in parallel (fast pre-filter)
/// 4. For files with matching partial hashes, compute full SHA256 in parallel
/// 5. Group by full hash to identify exact duplicates
actor DuplicateDetectionService {
    
    /// Minimum file size to consider for duplicate detection (skip small files)
    private let minimumFileSize: Int64 = 102_400 // 100KB - small files aren't worth the hashing cost
    
    /// Size of partial hash sample (first N bytes)
    private let partialHashSize: Int = 4096 // 4KB
    
    private var isCancelled = false
    
    /// Stored result from last detection run (avoids running twice)
    private var lastResult: [DuplicateGroup] = []
    
    func cancel() {
        isCancelled = true
    }
    
    private func resetCancellation() {
        isCancelled = false
    }
    
    /// Detect duplicate files with progress updates, stores result for retrieval
    func detectDuplicates(
        from files: [ScannedFileInfo]
    ) -> AsyncStream<DuplicateDetectionProgress> {
        AsyncStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                await self.resetCancellation()
                await self.performDetection(files: files, continuation: continuation)
            }
        }
    }
    
    /// Retrieve the result from the last detectDuplicates() call (no re-scan)
    func getLastResult() -> [DuplicateGroup] {
        lastResult
    }
    
    // MARK: - Core Detection Logic
    
    private func performDetection(
        files: [ScannedFileInfo],
        continuation: AsyncStream<DuplicateDetectionProgress>.Continuation
    ) async {
        continuation.yield(DuplicateDetectionProgress(
            phase: .groupingBySize, current: 0, total: files.count, currentFile: nil
        ))
        
        lastResult = await findDuplicates(in: files, progressContinuation: continuation)
        
        continuation.yield(DuplicateDetectionProgress(
            phase: .completed, current: 1, total: 1, currentFile: nil
        ))
        continuation.finish()
    }
    
    private func findDuplicates(
        in files: [ScannedFileInfo],
        progressContinuation: AsyncStream<DuplicateDetectionProgress>.Continuation? = nil
    ) async -> [DuplicateGroup] {
        // Phase 1: Group by size (instant filter - files must be same size to be duplicates)
        var sizeGroups: [Int64: [ScannedFileInfo]] = [:]
        for file in files {
            guard file.fileSize >= minimumFileSize else { continue }
            if sizeGroups[file.fileSize] == nil {
                sizeGroups[file.fileSize] = []
            }
            sizeGroups[file.fileSize]!.append(file)
        }
        
        // Remove groups with only one file (can't have duplicates)
        let candidateGroups = sizeGroups.filter { $0.value.count > 1 }
        
        if candidateGroups.isEmpty { return [] }
        
        // Flatten candidates for parallel processing
        let allCandidates: [(Int64, ScannedFileInfo)] = candidateGroups.flatMap { (size, files) in
            files.map { (size, $0) }
        }
        let totalToHash = allCandidates.count
        
        progressContinuation?.yield(DuplicateDetectionProgress(
            phase: .hashing, current: 0, total: totalToHash, currentFile: nil
        ))
        
        // Phase 2: Parallel partial hash (head+tail) to quickly eliminate non-duplicates
        let hashSize = partialHashSize
        var partialHashGroups: [String: [ScannedFileInfo]] = [:]
        var hashesCompleted = 0

        // Partial hash is tiny I/O (≤8KB per file) — push concurrency hard.
        // File-handle ceiling (typically 10240 on macOS) is well above this.
        let partialConcurrency = 32
        await withTaskGroup(of: (String, ScannedFileInfo)?.self) { group in
            var submitted = 0

            for (fileSize, file) in allCandidates {
                // Limit in-flight tasks to avoid opening thousands of FileHandles
                if submitted >= partialConcurrency {
                    if let result = await group.next() {
                        if isCancelled { break }
                        if let (key, file) = result {
                            if partialHashGroups[key] == nil {
                                partialHashGroups[key] = []
                            }
                            partialHashGroups[key]!.append(file)
                        }
                        hashesCompleted += 1
                    }
                }

                group.addTask {
                    guard let hash = computePartialHashStatic(
                        for: file.url, fileSize: fileSize, sampleSize: hashSize
                    ) else {
                        return nil
                    }
                    // fileSize is already baked into the hash, so the hash alone
                    // is a safe group key.
                    return (hash, file)
                }
                submitted += 1
            }
            
            // Drain remaining results
            for await result in group {
                if isCancelled { break }
                
                if let (key, file) = result {
                    if partialHashGroups[key] == nil {
                        partialHashGroups[key] = []
                    }
                    partialHashGroups[key]!.append(file)
                }
                
                hashesCompleted += 1
                if hashesCompleted % 100 == 0 {
                    progressContinuation?.yield(DuplicateDetectionProgress(
                        phase: .hashing,
                        current: hashesCompleted,
                        total: totalToHash,
                        currentFile: nil
                    ))
                }
            }
        }
        
        if isCancelled { return [] }
        
        // Remove non-matching partial hashes
        let partialCandidates = partialHashGroups.filter { $0.value.count > 1 }
        if partialCandidates.isEmpty { return [] }
        
        // Phase 3: Parallel full SHA256 hash for final confirmation
        let fullCandidates = partialCandidates.values.flatMap { $0 }
        let totalFullHash = fullCandidates.count
        var fullHashGroups: [String: [ScannedFileInfo]] = [:]
        var fullHashCompleted = 0
        
        // Full hashing reads entire files; match the SSD queue depth rather than
        // the old blanket cap of 8. Processor count is a good proxy on Apple silicon.
        let fullConcurrency = max(8, min(16, ProcessInfo.processInfo.activeProcessorCount))
        await withTaskGroup(of: (String, ScannedFileInfo)?.self) { group in
            var submitted = 0

            for file in fullCandidates {
                // Limit concurrency for full hashing (these read entire files)
                if submitted >= fullConcurrency {
                    if let result = await group.next() {
                        if isCancelled { break }
                        if let (hash, file) = result {
                            if fullHashGroups[hash] == nil {
                                fullHashGroups[hash] = []
                            }
                            fullHashGroups[hash]!.append(file)
                        }
                        fullHashCompleted += 1
                    }
                }
                
                group.addTask {
                    guard let hash = computeFullHashStatic(for: file.url) else { return nil }
                    return (hash, file)
                }
                submitted += 1
            }
            
            // Drain remaining
            for await result in group {
                if isCancelled { break }
                
                if let (hash, file) = result {
                    if fullHashGroups[hash] == nil {
                        fullHashGroups[hash] = []
                    }
                    fullHashGroups[hash]!.append(file)
                }
                
                fullHashCompleted += 1
                if fullHashCompleted % 20 == 0 {
                    progressContinuation?.yield(DuplicateDetectionProgress(
                        phase: .hashing,
                        current: hashesCompleted + fullHashCompleted,
                        total: totalToHash + totalFullHash,
                        currentFile: nil
                    ))
                }
            }
        }
        
        if isCancelled { return [] }
        
        // Build duplicate groups (only groups with 2+ files)
        var duplicateGroups: [DuplicateGroup] = []
        duplicateGroups.reserveCapacity(fullHashGroups.count)
        
        for (hash, groupFiles) in fullHashGroups {
            guard groupFiles.count > 1 else { continue }
            
            let group = DuplicateGroup(
                id: UUID(),
                hash: hash,
                fileSize: groupFiles[0].fileSize,
                files: groupFiles.sorted { $0.url.path < $1.url.path }
            )
            duplicateGroups.append(group)
        }
        
        // Sort by wasted space (largest first)
        duplicateGroups.sort { $0.wastedSpace > $1.wastedSpace }
        
        return duplicateGroups
    }
}
