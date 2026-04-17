//
//  FontLoader.swift
//  FreeUp
//
//  Registers bundled TTF/OTF fonts at app startup. ATSApplicationFontsPath
//  in Info.plist handles this for most cases, but we also walk the bundle
//  manually as a safety net — the Xcode synchronized project group puts
//  resources in slightly different spots depending on version.
//

import Foundation
import CoreText

enum FontLoader {
    /// Registers every TTF/OTF found in the main bundle with CoreText, so
    /// Font(.custom: …) works regardless of how the build system placed the
    /// font files. Safe to call multiple times — already-registered fonts
    /// just get a duplicate warning that CoreText swallows.
    static func registerBundledFonts() {
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard ext == "ttf" || ext == "otf" else { continue }

            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            // Duplicates just mean this ran twice; ignore silently.
        }
    }
}
