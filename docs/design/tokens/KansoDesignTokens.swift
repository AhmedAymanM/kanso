// KansoDesignTokens.swift — the shared design contract for Kanso v1 (KAN-2).
// Pure SwiftUI/AppKit, no dependencies. Drop into KansoUI (or app/Sources/Kanso/) as-is.
//
// RULES
//  1. Color values here are the SAME values as `K` / `Tint` in app/Sources/Kanso/Theme.swift. When the two
//     disagree, this file is the contract: change it deliberately, in one place, and tell the CTO.
//  2. Never hard-code a color, point size, or duration in a view. Use `KT.*`.
//  3. Prefer system semantic colors/fonts where one exists (NSColor.labelColor etc.). Tokens below cover only
//     what the system does not: Kanso's surfaces, the pastel/ink pairs, spacing, radii, motion.
//  4. Contrast (measured WCAG 2.x): text/window 15.1:1 L, text2/window 4.5:1 L, text2/card 5.1:1 L and 5.4:1 D.
//     `text3` is 3.1:1 — decoration and disabled only; NEVER for information a user must read.
import AppKit
import SwiftUI

public enum KT {

    // MARK: Color ---------------------------------------------------------------------------------------

    public enum Color {
        // Surfaces
        public static let window     = dyn(0xF4F2EE, 0x1C1C1E)
        public static let sidebar    = dyn(0xECE8E1, 0x232325)
        public static let card       = dyn(0xFFFFFF, 0x2C2C2E)
        public static let separator  = dyn(0x000000, 0xFFFFFF, 0.10, 0.12)
        public static let hover      = dyn(0x000000, 0xFFFFFF, 0.04, 0.07)   // row hover
        public static let selected   = dyn(0x000000, 0xFFFFFF, 0.08, 0.10)   // selected row, inactive window
        // Text
        public static let text       = dyn(0x1D1D1F, 0xF5F5F7)   // 15.1:1 L / 12.8:1 D
        public static let text2      = dyn(0x6E6E73, 0xA1A1A6)   // 4.5:1 L / 5.4:1 D — secondary information
        public static let text3      = dyn(0x8A8A8E, 0x8E8E93)   // 3.1:1 — decoration only
        // Meaning: each is a pastel surface + deep ink (ink is text/icon; pastel is fill). Light / dark.
        public static let move       = Tint(0xCFE8D8, 0x2E5A4B, 0x2D3A37)   // mint:     will move, success, brand
        public static let rule       = Tint(0xE5DCF7, 0x5A4687, 0x3A3449)   // lavender: rules, "matched by"
        public static let attention  = Tint(0xF7E4B5, 0x7E531B, 0x453828)   // butter:   collision (resolved), caution
        public static let stay       = Tint(0xECEAE5, 0x48484D, 0x343437)   // stone:    no rule matched, neutral
        public static let blocked    = Tint(0xF6D9D6, 0x9B2C2C, 0x4A2B2A)   // rose:     could not move (ink 6.7:1 on window)
        public static let focus      = move.ink                              // custom focus ring; system ring elsewhere
        /// Primary buttons use the system accent via `.borderedProminent`; do not recolor them.

        public struct Tint {
            public let pastel: SwiftUI.Color, ink: SwiftUI.Color, darkSurface: SwiftUI.Color
            init(_ pastel: UInt32, _ ink: UInt32, _ darkSurface: UInt32) {
                self.pastel = dyn(pastel, darkSurface)   // fill: pastel in light, ink-tinted surface in dark
                self.ink = dyn(ink, pastel)              // text/icon: deep ink in light, the pastel in dark
                self.darkSurface = SwiftUI.Color(nsColor: NSColor(hex: darkSurface))
            }
        }

        static func dyn(_ light: UInt32, _ dark: UInt32, _ la: CGFloat = 1, _ da: CGFloat = 1) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { ap in
                ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark, alpha: da) : NSColor(hex: light, alpha: la)
            })
        }
    }

    // MARK: Type ----------------------------------------------------------------------------------------
    // All styles are system text styles so Dynamic Type / "Larger Text" scale them. Sizes are the macOS defaults
    // at the standard setting; the point value is for the spec only — do not pass it to `.font(.system(size:))`.

    public enum Font {
        public static let windowTitle  = SwiftUI.Font.title2.weight(.semibold)   // 17 — summary headline in Preview
        public static let sectionTitle = SwiftUI.Font.headline                   // 13 semibold — destination group headers
        public static let body         = SwiftUI.Font.body                       // 13 — rows, rule sentences
        public static let secondary    = SwiftUI.Font.callout                    // 12 — paths, rule-matched column
        public static let caption      = SwiftUI.Font.caption                    // 10 — badges only; never sole carrier of info
        public static let mono         = SwiftUI.Font.system(.body, design: .monospaced)   // glob patterns being typed
    }

    // MARK: Spacing, size, radius ----------------------------------------------------------------------
    // 4-pt grid. Use these names, not literals.

    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs:  CGFloat = 4
        public static let s:   CGFloat = 8
        public static let m:   CGFloat = 12
        public static let l:   CGFloat = 16
        public static let xl:  CGFloat = 24
        public static let xxl: CGFloat = 32
        /// Window content inset (leading/trailing of summary bar and lists).
        public static let gutter: CGFloat = 16
    }

    public enum Size {
        public static let rowHeight: CGFloat = 32          // preview + rule rows (single line + path fits at body size)
        public static let groupHeaderHeight: CGFloat = 28
        public static let summaryBarHeight: CGFloat = 56
        public static let actionBarHeight: CGFloat = 52
        public static let ruleColumnWidth: CGFloat = 320   // default; min 260, max 420
        public static let ruleColumnMin: CGFloat = 260
        public static let ruleColumnMax: CGFloat = 420
        public static let windowDefault = CGSize(width: 1000, height: 660)
        public static let windowMin = CGSize(width: 800, height: 520)
        public static let editorPopoverWidth: CGFloat = 440
        public static let minHitTarget: CGFloat = 24        // clickable minimum (checkbox, disclosure, ⋯)
        public static let fileIcon: CGFloat = 20
        public static let badgeHeight: CGFloat = 18
    }

    public enum Radius {
        public static let badge: CGFloat = 9     // capsule at badgeHeight 18
        public static let card:  CGFloat = 10
        public static let row:   CGFloat = 6     // selection/hover highlight
    }

    // MARK: Motion --------------------------------------------------------------------------------------
    // Every animation goes through `KT.Motion.animation(_:)` so Reduce Motion is honored in one place.

    public enum Motion {
        public static let fast: Double = 0.12      // hover, checkbox
        public static let standard: Double = 0.22  // group expand, row exclude, list diff after rule edit
        public static let previewDebounce: Double = 0.15   // rule edit -> recompute plan (seconds)
        /// nil when the user prefers reduced motion: state changes still happen, instantly (cross-fade allowed).
        public static func animation(_ duration: Double) -> Animation? {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeInOut(duration: duration)
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
