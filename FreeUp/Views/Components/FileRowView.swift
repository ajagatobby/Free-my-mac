//
//  FileRowView.swift
//  FreeUp
//
//  Minimal row — no card, no colored icon, no hover lift. Just a checkbox,
//  name, path (dim), date, and a monospace size.
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

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(file.fileName)
                        .font(FUFont.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if isClone {
                        tag("clone")
                    }
                    if file.isPurgeable {
                        tag("purgeable")
                    }
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

    @ViewBuilder
    private func tag(_ text: String) -> some View {
        Text(text)
            .font(FUFont.label)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color(.separatorColor), lineWidth: 1)
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
        if isSelected { return Color.accentColor.opacity(0.08) }
        if isHovered { return Color(.quaternaryLabelColor).opacity(0.4) }
        return .clear
    }
}
