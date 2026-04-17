//
//  CategoryCard.swift
//  FreeUp
//
//  Minimal sidebar row. Category identity is a 6px dot; size is mono.
//

import SwiftUI

struct SidebarCategoryRow: View {
    let category: FileCategory
    let stats: CategoryDisplayStats?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                CategoryDot(color: category.themeColor)

                Text(category.rawValue)
                    .font(FUFont.body)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let stats, stats.totalSize > 0 {
                    Text(ByteFormatter.format(stats.totalSize))
                        .font(FUFont.monoCaption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
