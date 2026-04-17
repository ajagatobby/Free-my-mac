//
//  ScanProgressView.swift
//  FreeUp
//
//  Minimal full-screen scan state — centered stats + thin progress bar.
//  No orbital rings, no glows, no pulse.
//

import SwiftUI

struct ScanProgressView: View {
    let state: ScanState
    let filesScanned: Int
    let sizeScanned: Int64
    let onCancel: () -> Void

    private var progress: Double {
        switch state {
        case .scanning(let p, _): return p
        case .detectingDuplicates(let p): return p
        default: return 0
        }
    }

    private var currentDirectory: String? {
        if case .scanning(_, let dir) = state { return dir }
        return nil
    }

    private var title: String {
        if case .detectingDuplicates = state { return "Finding duplicates" }
        return "Scanning"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Eyebrow
                Text(title.uppercased())
                    .font(FUFont.eyebrow)
                    .foregroundStyle(.tertiary)

                // Hero stats — two big mono numbers side by side
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    stat(
                        value: formatCount(filesScanned),
                        label: "files"
                    )

                    Rectangle()
                        .fill(Color(.separatorColor))
                        .frame(width: 1, height: 32)

                    stat(
                        value: ByteFormatter.format(sizeScanned),
                        label: "scanned"
                    )
                }

                // Progress bar
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .frame(width: 220)

                // Current directory
                if let dir = currentDirectory {
                    Text(dir)
                        .font(FUFont.monoCaption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 320)
                } else {
                    Text(" ")
                        .font(FUFont.monoCaption)
                }

                // Cancel
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(FUFont.bodyMedium)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(FUFont.heroSmall)
                .foregroundStyle(.primary)
            Text(label)
                .font(FUFont.label)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
        }
    }

    private func formatCount(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Inline progress (for embedded use)

struct InlineScanProgress: View {
    let state: ScanState
    let filesScanned: Int

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini)

            switch state {
            case .scanning:
                Text("\(filesScanned) files")
                    .font(FUFont.monoCaption)
                    .foregroundStyle(.secondary)
            case .detectingDuplicates:
                Text("finding duplicates")
                    .font(FUFont.caption)
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
    }
}
