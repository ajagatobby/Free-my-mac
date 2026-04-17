//
//  CategoryCard.swift
//  FreeUp
//
//  Minimal sidebar row. 6px dot + full category name + mono size.
//  Size line wraps below name if there's not enough horizontal room,
//  rather than truncating the name.
//

import SwiftUI

struct SidebarCategoryRow: View {
    let category: FileCategory
    let stats: CategoryDisplayStats?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                CategoryDot(color: category.themeColor)

                Text(category.rawValue)
                    .font(FUFont.body)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                Spacer(minLength: 6)

                if let stats, stats.totalSize > 0 {
                    Text(ByteFormatter.format(stats.totalSize))
                        .font(FUFont.monoCaption)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color(.tertiaryLabelColor))
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundFill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var backgroundFill: Color {
        if isSelected { return Color.accentColor }
        if isHovered { return Color(.quaternaryLabelColor).opacity(0.4) }
        return .clear
    }
}
