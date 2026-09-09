import AppKit

/// Shared typography tokens for the editable document surface. Native Word
/// and RTF imports keep their source fonts; these values are used for Markdown,
/// plain-text fallbacks, and explicit toolbar style actions.
nonisolated enum EditorTypography {
    /// Versioned canonical sizes used by Markdown/plain-text documents and
    /// explicit editor style actions. Native Word/RTF runs never use these
    /// values unless the user explicitly chooses a toolbar style.
    static let typographyVersion = 2
    static let bodyPointSize: CGFloat = 20
    static let heading1PointSize: CGFloat = 36
    static let heading2PointSize: CGFloat = 28
    static let heading3PointSize: CGFloat = 23

    /// The previous canonical scale is kept only for the one-time migration
    /// of persisted Markdown/plain-text documents. Custom sizes are never
    /// treated as migration candidates.
    static let legacyBodyPointSize: CGFloat = 18
    static let legacyHeading1PointSize: CGFloat = 32
    static let legacyHeading2PointSize: CGFloat = 26
    static let legacyHeading3PointSize: CGFloat = 21

    static func canonicalPointSize(for style: TextStyle) -> CGFloat {
        switch style {
        case .body: return bodyPointSize
        case .heading1: return heading1PointSize
        case .heading2: return heading2PointSize
        case .heading3: return heading3PointSize
        }
    }

    static func legacyPointSize(for style: TextStyle) -> CGFloat {
        switch style {
        case .body: return legacyBodyPointSize
        case .heading1: return legacyHeading1PointSize
        case .heading2: return legacyHeading2PointSize
        case .heading3: return legacyHeading3PointSize
        }
    }

    static var defaultFont: NSFont {
        NSFont.systemFont(ofSize: bodyPointSize)
    }

    static var bodyBoldFont: NSFont {
        NSFont.systemFont(ofSize: bodyPointSize, weight: .bold)
    }

    static func font(for style: TextStyle) -> NSFont {
        let pointSize = canonicalPointSize(for: style)
        return NSFont.systemFont(
            ofSize: pointSize,
            weight: style == .body ? .regular : .bold
        )
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

    /// Returns a safe document-space anchor for AppKit magnification.
    /// `setMagnification(_:centeredAt:)` raises an Objective-C exception when
    /// either rect is transiently invalid during a split-view/layout update,
    /// so callers must treat `nil` as "try again after layout".
    static func safeCenter(
        visibleRect: NSRect,
        documentBounds: NSRect
    ) -> NSPoint? {
        guard isValid(rect: visibleRect),
              isValid(rect: documentBounds) else {
            return nil
        }

        let proposed = NSPoint(x: visibleRect.midX, y: visibleRect.midY)
        return NSPoint(
            x: min(max(proposed.x, documentBounds.minX), documentBounds.maxX),
            y: min(max(proposed.y, documentBounds.minY), documentBounds.maxY)
        )
    }

    static func isValid(rect: NSRect) -> Bool {
        rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.size.width.isFinite
            && rect.size.height.isFinite
            && rect.minX.isFinite
            && rect.minY.isFinite
            && rect.maxX.isFinite
            && rect.maxY.isFinite
            && rect.size.width > 0
            && rect.size.height > 0
    }
}

enum EditorZoomCommand {
    case zoomIn
    case zoomOut
    case reset
}
