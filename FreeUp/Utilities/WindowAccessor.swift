//
//  WindowAccessor.swift
//  FreeUp
//
//  SwiftUI bridge for tweaking the underlying NSWindow — needed for the
//  Raycast-style translucent backdrop (clear window + vibrancy through
//  the content's .ultraThinMaterial background).
//

import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { }
}

extension View {
    /// Install vibrancy on the hosting NSWindow. The clear background lets
    /// our ultraThinMaterial backdrop carry the frosted look end-to-end.
    func transparentWindow() -> some View {
        background(
            WindowAccessor { window in
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
                // Invisible titlebar so our custom top-left area is unobstructed.
                window.titleVisibility = .hidden
                // Rounded corners on the window itself — Raycast's signature.
                window.hasShadow = true
            }
        )
    }
}
