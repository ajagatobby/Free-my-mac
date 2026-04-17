//
//  DeletionService.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import Foundation
import AppKit

/// Result of a deletion operation
struct DeletionResult: Sendable {
    let successCount: Int
    let failureCount: Int
    let freedSpace: Int64
    let errors: [DeletionError]

    var totalAttempted: Int { successCount + failureCount }
    var allSuccessful: Bool { failureCount == 0 }

    /// True if the dominant failure cause is a TCC/FDA permission problem —
    /// the UI uses this to surface the Full Disk Access flow instead of a
    /// generic alert.
    var isPermissionBlocked: Bool {
        guard failureCount > 0 else { return false }
        let permissionFailures = errors.filter { $0.reason == .permissionDenied }.count
        // If at least half the failures are permission-denied, treat the whole
        // run as blocked. One-offs (a single locked file) stay as generic errors.
        return permissionFailures * 2 >= failureCount
    }
}

/// Why a specific file failed to delete. Used by the UI to decide whether to
/// offer Full Disk Access guidance vs a generic error.
enum DeletionFailureReason: Sendable, Equatable {
    case permissionDenied
    case fileNotFound
    case busyOrLocked
    case other
}

/// Error during deletion
struct DeletionError: Sendable, Identifiable {
    let id = UUID()
    let url: URL
    let error: String
    let reason: DeletionFailureReason

    init(url: URL, error: String, reason: DeletionFailureReason = .other) {
        self.url = url
        self.error = error
        self.reason = reason
    }

    /// Classify an `NSError` (usually from FileManager) into a reason.
    static func classify(_ error: Error) -> DeletionFailureReason {
        let ns = error as NSError
        // Cocoa-level classification first.
        switch ns.code {
        case NSFileReadNoPermissionError,
             NSFileWriteNoPermissionError:
            return .permissionDenied
        case NSFileNoSuchFileError,
             NSFileReadNoSuchFileError:
            return .fileNotFound
        case NSFileWriteFileExistsError,
             NSFileLockingError:
            return .busyOrLocked
        default:
            break
        }
        // POSIX fallback — `removeItem` often surfaces errno via NSPOSIXErrorDomain.
        if ns.domain == NSPOSIXErrorDomain {
            switch Int32(ns.code) {
            case EPERM, EACCES:
                return .permissionDenied
            case ENOENT:
                return .fileNotFound
            case EBUSY, ETXTBSY:
                return .busyOrLocked
            default:
                return .other
            }
        }
        return .other
    }
}

/// Progress update during batch deletion
struct DeletionProgress: Sendable {
    let current: Int
    let total: Int
    let currentFile: String
    let bytesFreed: Int64
    
    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

/// Service for fast file deletion with parallel batch support
actor DeletionService {
    /// Delete mode preference
    enum DeleteMode: Sendable {
        case moveToTrash
        case permanent
    }
    
    private var isCancelled = false
    
    func cancel() {
        isCancelled = true
    }
    
    private func resetCancellation() {
        isCancelled = false
    }
    
    /// Fast batch deletion
    /// - Move to Trash: uses parallel `FileManager.trashItem` (no Apple Events
    ///   to Finder, returns real per-file error codes).
    /// - Permanent: uses parallel FileManager.removeItem (fast but needs FDA
    ///   for protected dirs).
    ///
    /// Early-abort: if the first handful of attempts all fail with permission
    /// errors, we stop the whole batch. Running 600 more of the same doomed
    /// call just wastes time and clutters the error list. The UI can then
    /// surface the Full Disk Access flow instead of a generic alert.
    func deleteFilesFast(
        _ files: [ScannedFileInfo],
        mode: DeleteMode = .moveToTrash
    ) async -> DeletionResult {
        guard !files.isEmpty else {
            return DeletionResult(successCount: 0, failureCount: 0, freedSpace: 0, errors: [])
        }

        isCancelled = false

        switch mode {
        case .moveToTrash:
            return await trashFilesParallel(files)
        case .permanent:
            return await deleteFilesBatchParallel(files)
        }
    }

    // MARK: - Batch Trash via FileManager.trashItem (parallel)

    /// Trash files using `FileManager.trashItem` directly — no Apple Events,
    /// no Finder IPC, no silent "couldn't move" errors. Each task returns a
    /// classified result so we can tell permission errors from other failures.
    private func trashFilesParallel(_ files: [ScannedFileInfo]) async -> DeletionResult {
        // Keep concurrency well under the default file-handle limit.
        let maxConcurrency = 16
        // Early-abort threshold: if the first `probeSize` attempts all fail
        // with permission-denied, there's no point running the rest.
        let probeSize = min(8, files.count)

        var successCount = 0
        var failureCount = 0
        var freedSpace: Int64 = 0
        var errors: [DeletionError] = []
        errors.reserveCapacity(16)

        var completedSoFar = 0
        var permissionFailuresSoFar = 0
        var earlyAborted = false

        await withTaskGroup(of: (success: Bool, size: Int64, error: DeletionError?).self) { group in
            var submitted = 0

            for file in files {
                if isCancelled || earlyAborted { break }

                if submitted >= maxConcurrency {
                    if let result = await group.next() {
                        tallyResult(
                            result,
                            successCount: &successCount,
                            failureCount: &failureCount,
                            freedSpace: &freedSpace,
                            errors: &errors,
                            permissionFailuresSoFar: &permissionFailuresSoFar
                        )
                        completedSoFar += 1

                        // If the probe window is fully permission-denied,
                        // abort the rest of the submissions.
                        if completedSoFar >= probeSize,
                           permissionFailuresSoFar == completedSoFar {
                            earlyAborted = true
                            break
                        }
                    }
                }

                let fileURL = file.url
                let fileSize = file.allocatedSize
                group.addTask {
                    var resultingURL: NSURL?
                    do {
                        try FileManager.default.trashItem(at: fileURL, resultingItemURL: &resultingURL)
                        return (true, fileSize, nil)
                    } catch {
                        return (
                            false,
                            0,
                            DeletionError(
                                url: fileURL,
                                error: error.localizedDescription,
                                reason: DeletionError.classify(error)
                            )
                        )
                    }
                }
                submitted += 1
            }

            // Drain remaining tasks (even on early-abort we want to count
            // what already ran so the UI reports accurate totals).
            for await result in group {
                tallyResult(
                    result,
                    successCount: &successCount,
                    failureCount: &failureCount,
                    freedSpace: &freedSpace,
                    errors: &errors,
                    permissionFailuresSoFar: &permissionFailuresSoFar
                )
            }
        }

        // If we aborted early, account for the files we never even attempted.
        // The UI shouldn't claim they "failed" — they were skipped because the
        // probe told us the whole batch was blocked.
        if earlyAborted {
            let attempted = successCount + failureCount
            let skipped = files.count - attempted
            if skipped > 0 {
                // Surface a single representative error so isPermissionBlocked
                // stays true and the UI routes to the FDA sheet.
                errors.append(DeletionError(
                    url: files.last?.url ?? URL(fileURLWithPath: "/"),
                    error: "Skipped \(skipped) more files — Full Disk Access required.",
                    reason: .permissionDenied
                ))
                failureCount += skipped
            }
        }

        return DeletionResult(
            successCount: successCount,
            failureCount: failureCount,
            freedSpace: freedSpace,
            errors: errors
        )
    }

    /// Fold a task result into running totals. Shared by the throttled
    /// submit loop and the final drain.
    private func tallyResult(
        _ result: (success: Bool, size: Int64, error: DeletionError?),
        successCount: inout Int,
        failureCount: inout Int,
        freedSpace: inout Int64,
        errors: inout [DeletionError],
        permissionFailuresSoFar: inout Int
    ) {
        if result.success {
            successCount += 1
            freedSpace += result.size
        } else {
            failureCount += 1
            if let err = result.error {
                if err.reason == .permissionDenied {
                    permissionFailuresSoFar += 1
                }
                errors.append(err)
            }
        }
    }
    
    // MARK: - Parallel Permanent Deletion
    
    /// Delete files permanently using parallel TaskGroup
    private func deleteFilesBatchParallel(_ files: [ScannedFileInfo]) async -> DeletionResult {
        let maxConcurrency = 16
        var successCount = 0
        var failureCount = 0
        var freedSpace: Int64 = 0
        var errors: [DeletionError] = []
        
        await withTaskGroup(of: (Bool, Int64, DeletionError?).self) { group in
            var submitted = 0
            
            for file in files {
                if isCancelled { break }
                
                if submitted >= maxConcurrency {
                    if let result = await group.next() {
                        if result.0 {
                            successCount += 1
                            freedSpace += result.1
                        } else {
                            failureCount += 1
                            if let err = result.2 {
                                errors.append(err)
                            }
                        }
                    }
                }
                
                let fileURL = file.url
                let fileSize = file.allocatedSize
                group.addTask {
                    do {
                        try FileManager.default.removeItem(at: fileURL)
                        return (true, fileSize, nil)
                    } catch {
                        return (false, Int64(0), DeletionError(url: fileURL, error: error.localizedDescription))
                    }
                }
                submitted += 1
            }
            
            for await result in group {
                if result.0 {
                    successCount += 1
                    freedSpace += result.1
                } else {
                    failureCount += 1
                    if let err = result.2 {
                        errors.append(err)
                    }
                }
            }
        }
        
        return DeletionResult(
            successCount: successCount,
            failureCount: failureCount,
            freedSpace: freedSpace,
            errors: errors
        )
    }
    
    // MARK: - Utilities
    
    /// Empty the Trash
    nonisolated func emptyTrash() async -> Bool {
        let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        return error == nil
    }
    
    /// Get Trash size
    func getTrashSize() async -> Int64 {
        let fileManager = FileManager.default
        guard let trashURL = fileManager.urls(for: .trashDirectory, in: .userDomainMask).first else {
            return 0
        }
        return calculateDirectorySize(trashURL)
    }
    
    private func calculateDirectorySize(_ url: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            totalSize += Int64(fileSize)
        }
        
        return totalSize
    }
    
    /// Thin local Time Machine snapshots
    func thinLocalSnapshots(urgentGB: Int = 10) async -> (success: Bool, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["thinlocalsnapshots", "/", "\(urgentGB * 1_000_000_000)", "1"]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                return (true, "Thinned local snapshots. \(output)")
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                return (false, "Failed: \(errorMessage)")
            }
        } catch {
            return (false, "Error: \(error.localizedDescription)")
        }
    }
    
    /// Purge purgeable space
    func purgePurgeableSpace() async -> (success: Bool, freedBytes: Int64) {
        guard let initialInfo = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey]) else {
            return (false, 0)
        }
        let initialAvailable = Int64(initialInfo.volumeAvailableCapacity ?? 0)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // purge might fail without admin
        }
        
        guard let finalInfo = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey]) else {
            return (false, 0)
        }
        let finalAvailable = Int64(finalInfo.volumeAvailableCapacity ?? 0)
        
        let freed = finalAvailable - initialAvailable
        return (freed > 0, max(0, freed))
    }
}

// MARK: - Deletion ViewModel

@MainActor
@Observable
final class DeletionViewModel {
    private(set) var isDeleting = false
    private(set) var progress: DeletionProgress?
    private(set) var result: DeletionResult?
    private(set) var showResult = false
    
    private let deletionService = DeletionService()
    
    /// Delete files with progress tracking
    func deleteFiles(_ files: [ScannedFileInfo], mode: DeletionService.DeleteMode = .moveToTrash) async {
        guard !files.isEmpty else { return }
        
        isDeleting = true
        progress = nil
        result = nil
        
        let deletionResult = await deletionService.deleteFilesFast(files, mode: mode)
        result = deletionResult
        isDeleting = false
        showResult = true
    }
    
    func cancel() {
        Task {
            await deletionService.cancel()
        }
        isDeleting = false
    }
    
    func dismissResult() {
        showResult = false
        result = nil
    }
    
    func emptyTrash() async -> Bool {
        await deletionService.emptyTrash()
    }
    
    func getTrashSize() async -> Int64 {
        await deletionService.getTrashSize()
    }
}
