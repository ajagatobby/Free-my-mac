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
                window.titleVisibility = .hidden
                window.hasShadow = true
            }
        )
    }

    /// Disable the green traffic light zoom-to-fullscreen behaviour so
    /// clicking it becomes a no-op instead of entering full screen. The
    /// window can still be resized by dragging corners.
    func disableFullScreen() -> some View {
        background(
            WindowAccessor { window in
                // Remove fullscreen from collection behavior — this is what
                // AppKit actually checks when deciding if Cmd-Ctrl-F and the
                // zoom button can trigger full screen.
                var behavior = window.collectionBehavior
                behavior.remove(.fullScreenPrimary)
                behavior.insert(.fullScreenNone)
                window.collectionBehavior = behavior

                // Also disable the zoom button itself so it visibly greys out.
                window.standardWindowButton(.zoomButton)?.isEnabled = false
            }
        )
    }
}
