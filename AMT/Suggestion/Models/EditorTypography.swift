import AppKit

/// Shared typography tokens for the editable document surface. Native Word
/// and RTF imports keep their source fonts; these values are used for Markdown,
/// plain-text fallbacks, and explicit toolbar style actions.
enum EditorTypography {
    static let bodyPointSize: CGFloat = 18
    static let heading1PointSize: CGFloat = 32
    static let heading2PointSize: CGFloat = 26
    static let heading3PointSize: CGFloat = 21

    static var defaultFont: NSFont {
        NSFont.systemFont(ofSize: bodyPointSize)
    }

    static var bodyBoldFont: NSFont {
        NSFont.systemFont(ofSize: bodyPointSize, weight: .bold)
    }

    static func font(for style: TextStyle) -> NSFont {
        switch style {
        case .body:
            return NSFont.systemFont(ofSize: bodyPointSize)
        case .heading1:
            return NSFont.systemFont(ofSize: heading1PointSize, weight: .bold)
        case .heading2:
            return NSFont.systemFont(ofSize: heading2PointSize, weight: .bold)
        case .heading3:
            return NSFont.systemFont(ofSize: heading3PointSize, weight: .bold)
        }
    }

    static func textStyle(for font: NSFont) -> TextStyle {
        if font.pointSize >= heading1PointSize - 2 {
            return .heading1
        }
        if font.pointSize >= heading2PointSize - 1 {
            return .heading2
        }
        if font.pointSize >= heading3PointSize - 1,
           font.fontDescriptor.symbolicTraits.contains(.bold) {
            return .heading3
        }
        return .body
    }
}

enum EditorZoom {
    static let defaultPercent = 100
    static let minimumPercent = 75
    static let maximumPercent = 200
    static let stepPercent = 10

    static func clamp(_ percent: Int) -> Int {
        min(max(percent, minimumPercent), maximumPercent)
    }

    static func magnification(for percent: Int) -> CGFloat {
        CGFloat(clamp(percent)) / 100
    }

    static func percent(for magnification: CGFloat) -> Int {
        // AppKit can briefly report a non-finite value while a scroll view is
        // being attached, resized, or finishing a live magnification gesture.
        // Never convert that value directly to `Int`: Swift traps on NaN and
        // out-of-range floating-point conversions (EXC_BREAKPOINT).
        // Preserve intuitive clamping for +/-infinity while treating NaN as
        // an indeterminate value that should leave the editor at 100%.
        guard !magnification.isNaN else { return defaultPercent }

        let boundedMagnification = min(
            max(magnification, Self.magnification(for: minimumPercent)),
            Self.magnification(for: maximumPercent)
        )
        let rawPercent = Int((boundedMagnification * 100).rounded())
        if rawPercent <= minimumPercent {
            return minimumPercent
        }
        let stepped = Int((Double(rawPercent) / Double(stepPercent)).rounded()) * stepPercent
        return clamp(stepped)
    }
}

enum EditorZoomCommand {
    case zoomIn
    case zoomOut
    case reset
}
