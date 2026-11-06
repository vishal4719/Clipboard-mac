import AppKit

/// Shared Tahoe-style liquid-glass tokens. Colors resolve against the
/// current appearance so the panel tracks System Settings light/dark.
enum LiquidGlass {

    // MARK: Geometry

    static let windowCorner: CGFloat = 24
    static let rowCorner: CGFloat = 12
    static let chipCorner: CGFloat = 10
    static let controlCorner: CGFloat = 9
    static let hairline: CGFloat = 0.5

    // MARK: Appearance helpers

    static var isDark: Bool {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
    }

    // MARK: Surfaces

    /// Soft fill used for segmented controls / search wells.
    static var wellFill: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.05)
    }

    static var wellStroke: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.10)
            : NSColor.black.withAlphaComponent(0.08)
    }

    /// Selected pill inside a segment.
    static var pillFill: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.18)
            : NSColor.white.withAlphaComponent(0.85)
    }

    static var pillStroke: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.14)
            : NSColor.black.withAlphaComponent(0.06)
    }

    /// Outer glass edge stroke.
    static var glassStroke: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.22)
            : NSColor.white.withAlphaComponent(0.55)
    }

    /// Very light secondary edge (inner rim).
    static var glassInnerStroke: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.06)
            : NSColor.black.withAlphaComponent(0.04)
    }

    /// Tint layered on top of the visual-effect material.
    static var glassTint: NSColor {
        isDark
            ? NSColor.black.withAlphaComponent(0.10)
            : NSColor.white.withAlphaComponent(0.18)
    }

    /// Top-edge sheen gradient stops (top → bottom).
    static var sheenColors: [CGColor] {
        if isDark {
            return [
                NSColor.white.withAlphaComponent(0.18).cgColor,
                NSColor.white.withAlphaComponent(0.05).cgColor,
                NSColor.white.withAlphaComponent(0.0).cgColor,
            ]
        }
        return [
            NSColor.white.withAlphaComponent(0.55).cgColor,
            NSColor.white.withAlphaComponent(0.18).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor,
        ]
    }

    // MARK: Text / icons

    static var primaryText: NSColor { .labelColor }
    static var secondaryText: NSColor { .secondaryLabelColor }
    static var tertiaryText: NSColor { .tertiaryLabelColor }
    static var separator: NSColor { .separatorColor }

    static var iconMuted: NSColor { .secondaryLabelColor }
    static var iconPrimary: NSColor { .labelColor }

    // MARK: Rows

    static var rowHover: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.10)
            : NSColor.black.withAlphaComponent(0.05)
    }

    static var rowHighlight: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.32 : 0.22)
    }

    static var rowHighlightHover: NSColor {
        NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.42 : 0.30)
    }

    static var thumbBorder: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.16)
            : NSColor.black.withAlphaComponent(0.10)
    }

    static var emptyTileFill: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.07)
            : NSColor.black.withAlphaComponent(0.04)
    }

    // MARK: Factory

    /// Builds the layered liquid-glass chrome for a floating panel.
    static func applyChrome(to effectView: NSVisualEffectView, bounds: NSRect, cornerRadius: CGFloat = windowCorner) {
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true

        // Clear any previous chrome layers we own.
        effectView.layer?.sublayers?
            .filter { $0.name?.hasPrefix("lg.") == true }
            .forEach { $0.removeFromSuperlayer() }

        let tint = CALayer()
        tint.name = "lg.tint"
        tint.frame = bounds
        tint.backgroundColor = glassTint.cgColor
        effectView.layer?.addSublayer(tint)

        let sheen = CAGradientLayer()
        sheen.name = "lg.sheen"
        sheen.frame = NSRect(x: 0, y: bounds.height - 140, width: bounds.width, height: 140)
        sheen.colors = sheenColors
        sheen.locations = [0.0, 0.45, 1.0]
        sheen.startPoint = CGPoint(x: 0.5, y: 1.0)
        sheen.endPoint = CGPoint(x: 0.5, y: 0.0)
        effectView.layer?.addSublayer(sheen)

        let stroke = CALayer()
        stroke.name = "lg.stroke"
        stroke.frame = bounds
        stroke.cornerRadius = cornerRadius
        stroke.cornerCurve = .continuous
        stroke.borderWidth = 1.0
        stroke.borderColor = glassStroke.cgColor
        stroke.masksToBounds = true
        effectView.layer?.addSublayer(stroke)

        let inner = CALayer()
        inner.name = "lg.inner"
        inner.frame = bounds.insetBy(dx: 1, dy: 1)
        inner.cornerRadius = max(0, cornerRadius - 1)
        inner.cornerCurve = .continuous
        inner.borderWidth = hairline
        inner.borderColor = glassInnerStroke.cgColor
        effectView.layer?.addSublayer(inner)
    }

    /// Soft glass well used for the segmented tab control / search container.
    static func styleWell(_ view: NSView, corner: CGFloat = controlCorner) {
        view.wantsLayer = true
        view.layer?.backgroundColor = wellFill.cgColor
        view.layer?.cornerRadius = corner
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = hairline
        view.layer?.borderColor = wellStroke.cgColor
    }
}
