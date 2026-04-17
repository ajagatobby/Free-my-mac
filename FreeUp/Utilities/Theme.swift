//
//  Theme.swift
//  FreeUp
//
//  Raycast-adjacent design tokens. Inter for UI text; SF Mono for
//  numerics and keyboard glyphs. Colored rounded icon squares carry
//  category identity; selection is a translucent fill, not a blue bar.
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

    // Accent (user's system accent) and muted variants
    static let accent = Color.accentColor
    static let accentDim = Color.accentColor.opacity(0.12)

    // Borders — hairline separators at ~8% opacity feel right against the
    // frosted backdrop, closer to Raycast than the harder .separatorColor.
    static let border = Color(.separatorColor)
    static let borderSubtle = Color(.separatorColor).opacity(0.5)

    // Danger
    static let danger = Color(nsColor: .systemRed)
    static let dangerDim = Color(nsColor: .systemRed).opacity(0.12)

    // Category colors — used for the rounded icon squares.
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

/// Inter is the primary UI font. SF Mono remains for numerics and keyboard
/// glyphs since Inter doesn't ship with a matching mono. If Inter isn't
/// registered for some reason these all fall back to SF Pro automatically.
enum FUFont {
    // Core scales — Inter
    static let body = Font.custom("Inter-Regular", size: 13)
    static let bodyMedium = Font.custom("Inter-Medium", size: 13)
    static let bodySemibold = Font.custom("Inter-SemiBold", size: 13)

    static let caption = Font.custom("Inter-Regular", size: 11)
    static let captionMedium = Font.custom("Inter-Medium", size: 11)

    static let label = Font.custom("Inter-Medium", size: 10)

    // Eyebrow — uppercase tracked Raycast-style section label
    static let eyebrow = Font.custom("Inter-SemiBold", size: 10)

    // Titles
    static let title = Font.custom("Inter-SemiBold", size: 14)
    static let titleLarge = Font.custom("Inter-SemiBold", size: 17)

    // Monospace — numerics and kbd glyphs keep tabular SF Mono for alignment.
    static let mono = Font.system(size: 13, design: .monospaced).monospacedDigit()
    static let monoCaption = Font.system(size: 11, design: .monospaced).monospacedDigit()
    static let monoSmall = Font.system(size: 10, weight: .medium, design: .monospaced).monospacedDigit()

    // Hero — rounded mono for warmth + tabular digits for smooth updates.
    static let hero = Font.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit()
    static let heroSmall = Font.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit()
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

// MARK: - Primitives

/// 1px full-width hairline.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Color(.separatorColor))
            .frame(height: 1)
    }
}

/// 6px dot — kept for the odd place we want a minimal identity marker
/// (e.g. toolbar breadcrumbs). Categories themselves use IconSquare now.
struct CategoryDot: View {
    let color: Color
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

/// Raycast-style rounded icon square. Colored tint fill + monochrome glyph
/// in the category color. The only place color lives in the chrome.
struct IconSquare: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 22
    var cornerRadius: CGFloat = 5

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color.opacity(0.18))
            Image(systemName: systemName)
                .font(.system(size: size * 0.55, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

/// Keyboard shortcut pill — small monospace glyph on a subtle fill. Used
/// throughout the action bar and inline next to buttons.
struct KBDPill: View {
    let glyph: String

    init(_ glyph: String) {
        self.glyph = glyph
    }

    var body: some View {
        Text(glyph)
            .font(FUFont.monoSmall)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(minWidth: 18)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

/// Persistent bottom action bar — hairline top, left status text, right
/// action hints in the Raycast `[⏎ Primary] · [⌘K Actions]` pattern.
struct CommandBar<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 10) {
                leading
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Color(.controlBackgroundColor))
    }
}

/// Convenience: render a button label as "Action  ⏎" where the glyph is a kbd pill.
struct KBDAction: View {
    let label: String
    let glyph: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(FUFont.captionMedium)
                .foregroundStyle(color)
            KBDPill(glyph)
        }
    }
}

/// Shimmering placeholder block. Size it via `.frame(...)`; the
/// animation is a gentle opacity pulse — subtle enough not to feel
/// busy, clear enough to read as "loading".
struct SkeletonBlock: View {
    var cornerRadius: CGFloat = 4

    @State private var pulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(pulsing ? 0.12 : 0.05))
            .animation(
                .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}
