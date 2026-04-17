//
//  FileRowView.swift
//  FreeUp
//
//  Dense file row with the Raycast cadence: compact icon square,
//  title + tertiary subtitle on two lines, right-aligned accessories
//  (date + mono size), and a hover-revealed ellipsis menu.
//

import SwiftUI
import UniformTypeIdentifiers

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
            fileIconSquare

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(file.fileName)
                        .font(FUFont.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if isClone { tag("clone") }
                    if file.isPurgeable { tag("purgeable") }
                }

                Text(file.parentPath)
                    .font(FUFont.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(file.url.path)
            }

            Spacer(minLength: 8)

            if let date = file.lastAccessDate {
                Text(date, style: .relative)
                    .font(FUFont.monoCaption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 76, alignment: .trailing)
            }

            Text(ByteFormatter.format(file.allocatedSize))
                .font(FUFont.mono)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)

            moreMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(background)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var checkbox: some View {
        Button(action: onToggleSelection) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabelColor))
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Deselect" : "Select")
        .accessibilityLabel(isSelected ? "Deselect \(file.fileName)" : "Select \(file.fileName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fileIconSquare: some View {
        IconSquare(
            systemName: Self.iconName(for: file.contentType),
            color: Self.iconColor(for: file.contentType),
            size: 20
        )
    }

    @ViewBuilder
    private func tag(_ text: String) -> some View {
        Text(text)
            .font(FUFont.label)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
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
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .frame(width: 20)
        .opacity(isHovered ? 1 : 0)
        .help("More actions")
        .accessibilityLabel("More actions for \(file.fileName)")
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.10) }
        if isHovered { return Color.primary.opacity(0.05) }
        return .clear
    }

    // Per-UTType glyph + color mapping for the mini icon square.
    private static func iconName(for type: UTType?) -> String {
        guard let type else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "film" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .archive) { return "archivebox" }
        if type.conforms(to: .pdf) { return "doc.text" }
        if type.conforms(to: .folder) { return "folder.fill" }
        if type.conforms(to: .application) { return "app" }
        return "doc"
    }

    private static func iconColor(for type: UTType?) -> Color {
        guard let type else { return FUColors.textSecondary }
        if type.conforms(to: .image) { return FUColors.photosColor }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return FUColors.videosColor }
        if type.conforms(to: .audio) { return FUColors.audioColor }
        if type.conforms(to: .archive) { return FUColors.archivesColor }
        if type.conforms(to: .pdf) { return FUColors.systemJunkColor }
        if type.conforms(to: .folder) { return FUColors.downloadsColor }
        if type.conforms(to: .application) { return FUColors.accent }
        return FUColors.downloadsColor
    }
}
