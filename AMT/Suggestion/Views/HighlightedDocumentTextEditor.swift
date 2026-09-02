//
//  HighlightedDocumentTextEditor.swift
//  AMT
//

import AppKit
import SwiftUI

/// An AppKit-backed editor that keeps the document as plain `String` while
/// drawing suggestion highlights as temporary layout attributes.
struct HighlightedDocumentTextEditor: NSViewRepresentable {
    @Binding var text: String

    let suggestions: [EditorSuggestion]
    let selectedSuggestionID: UUID?
    let onSelect: (UUID?) -> Void
    let onTextEdited: () -> Void
    let onAccept: (EditorSuggestion) -> Void
    let onDismiss: (UUID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textStorage = NSTextStorage()
        let layoutManager = SuggestionLayoutManager()
        let textContainer = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = true

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let textView = SuggestionTextView(
            frame: .zero,
            textContainer: textContainer
        )
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = NSColor.clear
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.labelColor
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = NSView.AutoresizingMask.width
        textView.typingAttributes = [
            NSAttributedString.Key.font: textView.font ?? NSFont.systemFont(ofSize: 16),
            NSAttributedString.Key.foregroundColor: NSColor.labelColor
        ]
        textView.setAccessibilityRole(NSAccessibility.Role.textArea)
        textView.setAccessibilityLabel("Isi dokumen")
        textView.onClick = { [weak coordinator = context.coordinator] point in
            coordinator?.handleClick(at: point)
        }
        textView.onHover = { [weak coordinator = context.coordinator] point in
            coordinator?.handleHover(at: point)
        }

        textStorage.setAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    .font: textView.font ?? NSFont.systemFont(ofSize: 16),
                    .foregroundColor: NSColor.labelColor
                ]
            )
        )

        scrollView.documentView = textView
        context.coordinator.connect(
            scrollView: scrollView,
            textView: textView,
            layoutManager: layoutManager,
            textContainer: textContainer
        )
        context.coordinator.updateHighlights(
            suggestions: suggestions,
            selectedSuggestionID: selectedSuggestionID
        )

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateTextIfNeeded(text)
        context.coordinator.updateHighlights(
            suggestions: suggestions,
            selectedSuggestionID: selectedSuggestionID
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSPopoverDelegate {
        var parent: HighlightedDocumentTextEditor

        private weak var scrollView: NSScrollView?
        private weak var textView: SuggestionTextView?
        private var layoutManager: SuggestionLayoutManager?
        private var textContainer: NSTextContainer?
        private var boundsObserver: NSObjectProtocol?
        private var popover: NSPopover?
        private var presentedSuggestionID: UUID?
        private var isApplyingProgrammaticMutation = false

        init(parent: HighlightedDocumentTextEditor) {
            self.parent = parent
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func connect(
            scrollView: NSScrollView,
            textView: SuggestionTextView,
            layoutManager: SuggestionLayoutManager,
            textContainer: NSTextContainer
        ) {
            self.scrollView = scrollView
            self.textView = textView
            self.layoutManager = layoutManager
            self.textContainer = textContainer

            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleScroll()
                }
            }
        }

        func updateTextIfNeeded(_ text: String) {
            guard let textView, textView.string != text else { return }

            isApplyingProgrammaticMutation = true
            defer { isApplyingProgrammaticMutation = false }

            let font = textView.font ?? NSFont.systemFont(ofSize: 16)
            textView.textStorage?.setAttributedString(
                NSAttributedString(
                    string: text,
                    attributes: [
                        NSAttributedString.Key.font: font,
                        NSAttributedString.Key.foregroundColor: NSColor.labelColor
                    ]
                )
            )
            textView.setSelectedRange(
                NSRange(location: min(textView.selectedRange().location, text.utf16.count), length: 0)
            )
        }

        func updateHighlights(
            suggestions: [EditorSuggestion],
            selectedSuggestionID: UUID?
        ) {
            layoutManager?.update(
                suggestions: suggestions,
                selectedSuggestionID: selectedSuggestionID
            )

            if let presentedSuggestionID,
               !suggestions.contains(where: { $0.id == presentedSuggestionID }) {
                closePopover(notifySelection: true)
            }
        }

        func handleHover(at point: NSPoint) {
            guard let textView,
                  let layoutManager,
                  let textContainer,
                  !parent.suggestions.isEmpty
            else {
                return
            }

            let containerPoint = NSPoint(
                x: point.x - textView.textContainerOrigin.x,
                y: point.y - textView.textContainerOrigin.y
            )
            let characterIndex = layoutManager.characterIndex(
                for: containerPoint,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )

            guard characterIndex != NSNotFound,
                  let suggestion = parent.suggestions.first(where: {
                      NSLocationInRange(characterIndex, $0.sourceRange)
                  })
            else {
                return
            }

            if presentedSuggestionID != suggestion.id {
                parent.onSelect(suggestion.id)
                layoutManager.update(
                    suggestions: parent.suggestions,
                    selectedSuggestionID: suggestion.id
                )
                presentPopover(
                    for: suggestion,
                    anchor: anchor(for: suggestion),
                    isStale: !rangeContainsOriginal(suggestion)
                )
            }
        }

        func handleClick(at point: NSPoint) {
            guard let textView,
                  let layoutManager,
                  let textContainer,
                  !parent.suggestions.isEmpty
            else {
                closePopover(notifySelection: true)
                return
            }

            let containerPoint = NSPoint(
                x: point.x - textView.textContainerOrigin.x,
                y: point.y - textView.textContainerOrigin.y
            )
            let characterIndex = layoutManager.characterIndex(
                for: containerPoint,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )

            guard characterIndex != NSNotFound,
                  let suggestion = parent.suggestions.first(where: {
                      NSLocationInRange(characterIndex, $0.sourceRange)
                  })
            else {
                closePopover(notifySelection: true)
                return
            }

            parent.onSelect(suggestion.id)
            layoutManager.update(
                suggestions: parent.suggestions,
                selectedSuggestionID: suggestion.id
            )
            presentPopover(
                for: suggestion,
                anchor: anchor(for: suggestion),
                isStale: !rangeContainsOriginal(suggestion)
            )
        }

        func handleScroll() {
            closePopover(notifySelection: true)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticMutation,
                  let textView
            else {
                return
            }

            parent.text = textView.string
            closePopover(notifySelection: true)
            layoutManager?.update(suggestions: [], selectedSuggestionID: nil)
            parent.onTextEdited()
        }

        func accept(_ suggestion: EditorSuggestion) {
            guard let textView else { return }

            guard rangeContainsOriginal(suggestion) else {
                presentPopover(
                    for: suggestion,
                    anchor: anchor(for: suggestion),
                    isStale: true
                )
                return
            }

            isApplyingProgrammaticMutation = true
            textView.insertText(
                suggestion.replacement,
                replacementRange: suggestion.sourceRange
            )
            isApplyingProgrammaticMutation = false

            parent.text = textView.string
            parent.onAccept(suggestion)
            closePopover(notifySelection: true)
        }

        func dismiss(_ suggestion: EditorSuggestion) {
            parent.onDismiss(suggestion.id)
            closePopover(notifySelection: true)
        }

        private func presentPopover(
            for suggestion: EditorSuggestion,
            anchor: NSRect,
            isStale: Bool
        ) {
            guard let textView else { return }

            let popover = self.popover ?? NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.delegate = self
            popover.contentViewController = NSHostingController(
                rootView: SuggestionPopoverView(
                    suggestion: suggestion,
                    isStale: isStale,
                    onAccept: { [weak self] in
                        self?.accept(suggestion)
                    },
                    onDismiss: { [weak self] in
                        self?.dismiss(suggestion)
                    }
                )
            )
            popover.contentSize = NSSize(width: 400, height: 460)
            self.popover = popover
            presentedSuggestionID = suggestion.id

            if popover.isShown {
                popover.delegate = nil
                popover.close()
            }
            popover.delegate = self
            popover.show(
                relativeTo: anchor,
                of: textView,
                preferredEdge: .maxX
            )
        }

        private func closePopover(notifySelection: Bool) {
            if let popover {
                popover.delegate = nil
                popover.performClose(nil)
            }
            popover = nil
            presentedSuggestionID = nil

            if notifySelection {
                parent.onSelect(nil)
            }
        }

        private func rangeContainsOriginal(_ suggestion: EditorSuggestion) -> Bool {
            guard let textView,
                  suggestion.sourceRange.location >= 0,
                  NSMaxRange(suggestion.sourceRange) <= textView.string.utf16.count
            else {
                return false
            }

            return (textView.string as NSString).substring(
                with: suggestion.sourceRange
            ) == suggestion.original
        }

        private func anchor(for suggestion: EditorSuggestion) -> NSRect {
            guard let textView,
                  let layoutManager,
                  suggestion.sourceRange.location >= 0,
                  suggestion.sourceRange.length > 0,
                  NSMaxRange(suggestion.sourceRange) <= textView.string.utf16.count
            else {
                return NSRect(
                    x: 0,
                    y: 0,
                    width: 1,
                    height: 1
                )
            }

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: suggestion.sourceRange,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0,
                  glyphRange.location < layoutManager.numberOfGlyphs
            else {
                return NSRect(
                    x: textView.textContainerOrigin.x,
                    y: textView.textContainerOrigin.y,
                    width: 1,
                    height: textView.font?.pointSize ?? 16
                )
            }

            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil,
                withoutAdditionalLayout: false
            )
            return lineRect.offsetBy(
                dx: textView.textContainerOrigin.x,
                dy: textView.textContainerOrigin.y
            )
        }

        private func lineAnchor(
            point: NSPoint
        ) -> NSRect {
            guard let textView,
                  let layoutManager,
                  let textContainer
            else {
                return NSRect(origin: point, size: NSSize(width: 1, height: 1))
            }

            return lineAnchor(
                point: point,
                textView: textView,
                layoutManager: layoutManager,
                textContainer: textContainer
            )
        }

        private func lineAnchor(
            point: NSPoint,
            textView: NSTextView,
            layoutManager: NSLayoutManager,
            textContainer: NSTextContainer
        ) -> NSRect {
            let glyphIndex = layoutManager.glyphIndex(
                for: point,
                in: textContainer
            )
            guard glyphIndex < layoutManager.numberOfGlyphs else {
                return NSRect(
                    x: point.x + textView.textContainerOrigin.x,
                    y: point.y + textView.textContainerOrigin.y,
                    width: 1,
                    height: textView.font?.pointSize ?? 16
                )
            }

            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil,
                withoutAdditionalLayout: false
            )
            return lineRect.offsetBy(
                dx: textView.textContainerOrigin.x,
                dy: textView.textContainerOrigin.y
            )
        }

        func popoverDidClose(_ notification: Notification) {
            popover = nil
            presentedSuggestionID = nil
            parent.onSelect(nil)
        }
    }
}

final class SuggestionTextView: NSTextView {
    var onClick: ((NSPoint) -> Void)?
    var onHover: ((NSPoint) -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow]
        let newArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        self.trackingArea = newArea
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        onHover?(point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        super.mouseDown(with: event)
        onClick?(point)
    }
}

final class SuggestionLayoutManager: NSLayoutManager {
    struct DrawingRange {
        let id: UUID
        let range: NSRange
        let isSelected: Bool
        let isDebugOnly: Bool
    }

    private(set) var drawingRanges: [DrawingRange] = []

    func update(
        suggestions: [EditorSuggestion],
        selectedSuggestionID: UUID?
    ) {
        drawingRanges = suggestions.map {
            DrawingRange(
                id: $0.id,
                range: $0.sourceRange,
                isSelected: $0.id == selectedSuggestionID,
                isDebugOnly: $0.isDebugOnly
            )
        }

        guard let textStorage, textStorage.length > 0 else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
        removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
        removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)
        removeTemporaryAttribute(.font, forCharacterRange: fullRange)

        for item in drawingRanges {
            guard item.range.location >= 0,
                  NSMaxRange(item.range) <= textStorage.length
            else {
                continue
            }

            addTemporaryAttribute(
                .foregroundColor,
                value: item.isDebugOnly
                    ? NSColor.systemGreen
                    : NSColor(red: 0.65, green: 0.12, blue: 0.18, alpha: 1.0),
                forCharacterRange: item.range
            )
            addTemporaryAttribute(
                .font,
                value: NSFont.systemFont(ofSize: 16, weight: .bold),
                forCharacterRange: item.range
            )
        }

        invalidateDisplay(forCharacterRange: fullRange)
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard glyphsToShow.length > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        for item in drawingRanges {
            let glyphRange = glyphRange(
                forCharacterRange: item.range,
                actualCharacterRange: nil
            )
            let visibleGlyphRange = NSIntersectionRange(glyphRange, glyphsToShow)
            guard visibleGlyphRange.length > 0,
                  let textContainer = textContainer(
                      forGlyphAt: visibleGlyphRange.location,
                      effectiveRange: nil
                  )
            else {
                continue
            }

            enumerateEnclosingRects(
                forGlyphRange: visibleGlyphRange,
                withinSelectedGlyphRange: NSRange(
                    location: NSNotFound,
                    length: 0
                ),
                in: textContainer
            ) { rect, _ in
                let drawRect = rect
                    .offsetBy(dx: origin.x, dy: origin.y)
                    .insetBy(dx: -4, dy: 1)
                let color = item.isDebugOnly
                    ? NSColor(red: 0.86, green: 0.96, blue: 0.88, alpha: 1.0)
                    : NSColor(red: 0.98, green: 0.88, blue: 0.90, alpha: 1.0)
                color.setFill()
                NSBezierPath(
                    roundedRect: drawRect,
                    xRadius: 6,
                    yRadius: 6
                ).fill()
            }
        }
    }
}

#Preview("Two highlights") {
    let text = "Pihak Kedua wajib untuk menyerahkan laporan. Perjanjian ini telah ditanda tangani oleh Para Pihak."
    HighlightedDocumentTextEditor(
        text: .constant(text),
        suggestions: [
            EditorSuggestion(
                id: UUID(),
                sourceRange: (text as NSString).range(of: "wajib untuk"),
                original: "wajib untuk",
                replacement: "wajib",
                category: .grammar,
                reason: "Bentuk ini lebih ringkas tanpa mengubah makna.",
                origin: .deterministic,
                reference: nil
            ),
            EditorSuggestion(
                id: UUID(),
                sourceRange: (text as NSString).range(of: "ditanda tangani"),
                original: "ditanda tangani",
                replacement: "ditandatangani",
                category: .spelling,
                reason: "Bentuk baku ditulis sebagai satu kata.",
                origin: .deterministic,
                reference: nil
            )
        ],
        selectedSuggestionID: nil,
        onSelect: { _ in },
        onTextEdited: {},
        onAccept: { _ in },
        onDismiss: { _ in }
    )
    .frame(width: 720, height: 280)
}

#Preview("Dark mode") {
    let text = "Pihak Kedua wajib untuk menyerahkan laporan."
    HighlightedDocumentTextEditor(
        text: .constant(text),
        suggestions: [
            EditorSuggestion(
                id: UUID(),
                sourceRange: (text as NSString).range(of: "wajib untuk"),
                original: "wajib untuk",
                replacement: "wajib",
                category: .grammar,
                reason: "Bentuk ini lebih ringkas tanpa mengubah makna.",
                origin: .deterministic,
                reference: nil
            )
        ],
        selectedSuggestionID: nil,
        onSelect: { _ in },
        onTextEdited: {},
        onAccept: { _ in },
        onDismiss: { _ in }
    )
    .frame(width: 520, height: 180)
    .preferredColorScheme(.dark)
}
