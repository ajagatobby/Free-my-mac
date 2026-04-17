//
//  Theme.swift
//  FreeUp
//
//  Minimal design tokens — Raycast/Linear-inspired.
//  Almost everything uses system semantic colors; category identity is
//  reduced to a tiny colored dot rather than a full color fill.
//

import SwiftUI

// MARK: - FUColors

enum FUColors {
    // Backgrounds
    static let bg = Color(.windowBackgroundColor)
    static let bgElevated = Color(.controlBackgroundColor)
    static let bgHover = Color(.quaternaryLabelColor).opacity(0.5)

    // Text
    static let textPrimary = Color(.labelColor)
    static let textSecondary = Color(.secondaryLabelColor)
    static let textTertiary = Color(.tertiaryLabelColor)

    // Accent — the user's system accent
    static let accent = Color.accentColor
    static let accentDim = Color.accentColor.opacity(0.12)

    // Borders — hairline separators
    static let border = Color(.separatorColor)
    static let borderSubtle = Color(.separatorColor).opacity(0.5)

    // Danger
    static let danger = Color(nsColor: .systemRed)
    static let dangerDim = Color(nsColor: .systemRed).opacity(0.12)

    // Category dots — muted NSColor tints. Used only for the 6px dot in lists.
    static let cacheColor = Color(nsColor: .systemOrange)
    static let logsColor = Color(nsColor: .systemGray)
    static let systemJunkColor = Color(nsColor: .systemRed)
    static let developerColor = Color(nsColor: .systemGreen)
    static let downloadsColor = Color(nsColor: .systemBlue)
    static let duplicatesColor = Color(nsColor: .systemTeal)
    static let photosColor = Color(nsColor: .systemPink)
    static let videosColor = Color(nsColor: .systemPurple)
    static let audioColor = Color(nsColor: .systemYellow)
    static let documentsColor = Color(nsColor: .systemIndigo)
    static let archivesColor = Color(nsColor: .systemBrown)
    static let orphanedColor = Color(nsColor: .systemMint)
}

// MARK: - Fonts

enum FUFont {
    static let body = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11)
    static let captionMedium = Font.system(size: 11, weight: .medium)
    static let label = Font.system(size: 10, weight: .medium)

    // Numeric — always tabular monospace
    static let mono = Font.system(size: 13, design: .monospaced).monospacedDigit()
    static let monoCaption = Font.system(size: 11, design: .monospaced).monospacedDigit()

    // Hero number — rounded mono for warmth, tabular digits for no-jitter updates
    static let hero = Font.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit()
    static let heroSmall = Font.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit()

    // Caps/tracking label (uppercase small label)
    static let eyebrow = Font.system(size: 10, weight: .semibold).width(.expanded)
}

// MARK: - Category color extension

extension FileCategory {
    var themeColor: Color {
        switch self {
        case .cache: return FUColors.cacheColor
        case .logs: return FUColors.logsColor
        case .systemJunk: return FUColors.systemJunkColor
        case .developerFiles: return FUColors.developerColor
        case .downloads: return FUColors.downloadsColor
        case .duplicates: return FUColors.duplicatesColor
        case .photos: return FUColors.photosColor
        case .videos: return FUColors.videosColor
        case .audio: return FUColors.audioColor
        case .documents: return FUColors.documentsColor
        case .archives: return FUColors.archivesColor
        case .orphanedAppData: return FUColors.orphanedColor
        case .applications: return FUColors.accent
        case .other: return FUColors.textSecondary
        }
    }
}

// MARK: - Hairline divider

/// 1px full-width hairline using the system separator color. Use this
/// everywhere — no heavy Dividers, no 2px strokes.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Color(.separatorColor))
            .frame(height: 1)
    }
}

// MARK: - Category dot

/// 6px dot used to carry category identity without loud color fills.
struct CategoryDot: View {
    let color: Color
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}
