//
//  FileRowView.swift
//  FreeUp
//
//  Created by Abdulbasit Ajaga on 02/02/2026.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - FileRowView

/// Clean file row — no cards, no hover lift, just data.
struct FileRowView: View, Equatable {
    let file: ScannedFileInfo
    let isSelected: Bool
    let isClone: Bool
    let index: Int
    let onToggleSelection: () -> Void
    let onRevealInFinder: () -> Void

    @State private var isHovered = false

    static func == (lhs: FileRowView, rhs: FileRowView) -> Bool {
        lhs.file == rhs.file &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isClone == rhs.isClone &&
        lhs.index == rhs.index
    }

    var body: some View {
        HStack(spacing: 10) {
            checkbox
            FileIconView(contentType: file.contentType)
            nameAndPath
            Spacer(minLength: 4)
            lastAccess
            sizeLabel
            moreMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var checkbox: some View {
        Button(action: onToggleSelection) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabelColor))
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Deselect \(file.fileName)" : "Select \(file.fileName)")
        .accessibilityLabel(isSelected ? "Deselect \(file.fileName)" : "Select \(file.fileName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var nameAndPath: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Text(file.fileName)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if isClone {
                    BadgeLabel(text: "Clone", color: .orange)
                }
                if file.isPurgeable {
                    BadgeLabel(text: "Purgeable", color: .green)
                }
            }

            Text(file.parentPath)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
                .help(file.url.path)
        }
    }

    @ViewBuilder
    private var lastAccess: some View {
        if let date = file.lastAccessDate {
            Text(date, style: .relative)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .trailing)
        }
    }

    private var sizeLabel: some View {
        Text(ByteFormatter.format(file.allocatedSize))
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 75, alignment: .trailing)
    }

    private var moreMenu: some View {
        Menu {
            Button("Reveal in Finder", action: onRevealInFinder)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.url.path, forType: .string)
            } label: {
                Label("Copy Path", systemImage: "doc.on.doc")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
        .opacity(isHovered ? 1 : 0)
        .help("More actions")
        .accessibilityLabel("More actions for \(file.fileName)")
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.10)
        }
        return index.isMultiple(of: 2) ? Color.clear : Color(.separatorColor).opacity(0.08)
    }
}

// MARK: - FileIconView

struct FileIconView: View {
    let contentType: UTType?

    private var config: (name: String, color: Color) {
        guard let type = contentType else { return ("doc", .secondary) }
        if type.conforms(to: .image)       { return ("photo", .pink) }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return ("film", .purple) }
        if type.conforms(to: .audio)       { return ("waveform", .orange) }
        if type.conforms(to: .archive)     { return ("archivebox", .brown) }
        if type.conforms(to: .pdf)         { return ("doc.text", .red) }
        if type.conforms(to: .folder)      { return ("folder.fill", .blue) }
        if type.conforms(to: .application) { return ("app", .cyan) }
        return ("doc", .blue)
    }

    var body: some View {
        Image(systemName: config.name)
            .font(.system(size: 16))
            .foregroundStyle(config.color)
            .frame(width: 24, height: 24)
    }
}

// MARK: - BadgeLabel

struct BadgeLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Legacy compatibility aliases

typealias CloneBadge = EmptyView
typealias PurgeableBadge = EmptyView
