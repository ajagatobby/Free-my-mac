//
//  CategoryCard.swift
//  FreeUp
//
//  Raycast-style sidebar row. Colored rounded icon square + title +
//  mono size. Selection is a translucent white@8% fill, not a solid
//  accent bar.
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
                IconSquare(
                    systemName: category.iconName,
                    color: category.themeColor,
                    size: 22
                )

                Text(category.rawValue)
                    .font(FUFont.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                Spacer(minLength: 6)

                if let stats, stats.totalSize > 0 {
                    Text(ByteFormatter.format(stats.totalSize))
                        .font(FUFont.monoCaption)
                        .foregroundStyle(.secondary)
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
        if isSelected { return Color.primary.opacity(0.10) }
        if isHovered { return Color.primary.opacity(0.05) }
        return .clear
    }
}
