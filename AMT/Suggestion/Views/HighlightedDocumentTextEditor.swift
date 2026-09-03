//
//  HighlightedDocumentTextEditor.swift
//  AMT
//

import AppKit
import SwiftUI

struct HighlightedDocumentTextEditor: NSViewRepresentable {
    let documentID: UUID
    @Binding var text: String
    @Binding var richTextData: Data?
    @Binding var structuredDocument: StructuredDocument?
    @Binding var zoomPercent: Int

    let suggestions: [EditorSuggestion]
    let selectedSuggestionID: UUID?
    let onSelect: (UUID?) -> Void
    let onTextEdited: () -> Void
    let onAccept: (EditorSuggestion) -> Void
    let onDismiss: (UUID) -> Void

    var formattingViewModel: EditorViewModel? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = EditorZoom.magnification(for: EditorZoom.minimumPercent)
        scrollView.maxMagnification = EditorZoom.magnification(for: EditorZoom.maximumPercent)

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
        textView.isRichText = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = NSColor.clear
        textView.textColor = NSColor.black
        textView.insertionPointColor = NSColor.black
        textView.font = EditorTypography.defaultFont
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
            NSAttributedString.Key.font: textView.font ?? EditorTypography.defaultFont,
            NSAttributedString.Key.foregroundColor: NSColor.black
        ]
        textView.setAccessibilityRole(NSAccessibility.Role.textArea)
        textView.setAccessibilityLabel("Isi dokumen")
        textView.onClick = { [weak coordinator = context.coordinator] point in
            coordinator?.handleClick(at: point)
        }
        textView.onHover = { [weak coordinator = context.coordinator] point in
            coordinator?.handleHover(at: point)
        }
        textView.onZoomCommand = { [weak coordinator = context.coordinator] command in
            coordinator?.handleZoomCommand(command) ?? false
        }

        textStorage.setAttributedString(
            renderedText(defaultFont: textView.font ?? EditorTypography.defaultFont)
        )

        scrollView.documentView = textView
        context.coordinator.connect(
            scrollView: scrollView,
            textView: textView,
            layoutManager: layoutManager,
            textContainer: textContainer,
            documentID: documentID,
            text: text,
            richTextData: richTextData,
            structuredDocument: structuredDocument,
            zoomPercent: zoomPercent
        )
        context.coordinator.updateHighlights(
            suggestions: suggestions,
            selectedSuggestionID: selectedSuggestionID
        )
        context.coordinator.pushFormattingState()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateTextIfNeeded(
            text,
            richTextData: richTextData,
            structuredDocument: structuredDocument,
            documentID: documentID
        )
        context.coordinator.updateZoom(to: zoomPercent)
        context.coordinator.updateHighlights(
            suggestions: suggestions,
            selectedSuggestionID: selectedSuggestionID
        )
        if let action = formattingViewModel?.pendingAction {
            context.coordinator.applyFormatting(action)
            formattingViewModel?.pendingAction = nil
        }
    }

    private func renderedText(defaultFont: NSFont) -> NSAttributedString {
        if let structuredDocument { return structuredDocument.attributedString() }
        guard let richTextData,
              let richText = try? NSAttributedString(
                data: richTextData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              )
        else {
            return MarkdownRichTextCodec.render(text, defaultFont: defaultFont)
        }
        return richText
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSPopoverDelegate {
        private struct EditorSnapshot {
            let attributedText: NSAttributedString
            let selectedRange: NSRange
            let typingAttributes: [NSAttributedString.Key: Any]
        }

        var parent: HighlightedDocumentTextEditor

        private weak var scrollView: NSScrollView?
        private weak var textView: SuggestionTextView?
        private var layoutManager: SuggestionLayoutManager?
        private var textContainer: NSTextContainer?
        private var boundsObserver: NSObjectProtocol?
        private var magnificationObserver: NSObjectProtocol?
        private var scheduledZoomPercent: Int?
        private var popover: NSPopover?
        private var presentedSuggestionID: UUID?
        private var isApplyingProgrammaticMutation = false
        private var currentDocumentID: UUID?
        private var currentText = ""
        private var currentRichTextData: Data?
        private var currentStructuredDocument: StructuredDocument?

        init(parent: HighlightedDocumentTextEditor) {
            self.parent = parent
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            if let magnificationObserver {
                NotificationCenter.default.removeObserver(magnificationObserver)
            }
        }

        func connect(
            scrollView: NSScrollView,
            textView: SuggestionTextView,
            layoutManager: SuggestionLayoutManager,
            textContainer: NSTextContainer,
            documentID: UUID,
            text: String,
            richTextData: Data?,
            structuredDocument: StructuredDocument?,
            zoomPercent: Int
        ) {
            self.scrollView = scrollView
            self.textView = textView
            self.layoutManager = layoutManager
            self.textContainer = textContainer
            self.currentDocumentID = documentID
            currentText = text
            currentRichTextData = richTextData
            currentStructuredDocument = structuredDocument

            updateZoom(to: zoomPercent)

            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleScroll()
                }
            }

            magnificationObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didEndLiveMagnifyNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncZoomFromScrollView()
                }
            }

            publishHistoryState()
        }

        func updateTextIfNeeded(
            _ text: String,
            richTextData: Data?,
            structuredDocument: StructuredDocument?,
            documentID: UUID
        ) {
            guard let textView,
                  currentDocumentID != documentID
                    || currentText != text
                    || currentRichTextData != richTextData
                    || currentStructuredDocument != structuredDocument
            else { return }

            isApplyingProgrammaticMutation = true
            defer { isApplyingProgrammaticMutation = false }

            let didChangeDocument = currentDocumentID != documentID
            if didChangeDocument {
                textView.undoManager?.removeAllActions()
                currentDocumentID = documentID
                parent.formattingViewModel?.resetHistoryState()
            }

            let font = textView.font ?? EditorTypography.defaultFont
            currentText = text
            currentRichTextData = richTextData
            currentStructuredDocument = structuredDocument
            let rendered = parent.renderedText(defaultFont: font)

            // A text edit writes the canonical bindings back to SwiftUI. The
            // representable may receive that update while AppKit is still
            // finishing the original edit, even though the visible
            // attributed string is already current. Avoid replacing the
            // storage in that case; replacing it resets NSTextView's viewport
            // and is what makes an edit in the middle jump to the end.
            if rendered.isEqual(to: textView.attributedString()) {
                publishHistoryState()
                pushFormattingState()
                return
            }

            let previousSelection = textView.selectedRange()
            let previousBoundsOrigin = didChangeDocument
                ? nil
                : textView.enclosingScrollView?.contentView.bounds.origin
            let undoManager = textView.undoManager
            undoManager?.disableUndoRegistration()
            textView.textStorage?.setAttributedString(rendered)
            undoManager?.enableUndoRegistration()
            let textLength = textView.string.utf16.count
            let selectionLocation = min(max(previousSelection.location, 0), textLength)
            let selectionLength = min(
                max(previousSelection.length, 0),
                textLength - selectionLocation
            )
            textView.setSelectedRange(
                NSRange(location: selectionLocation, length: selectionLength)
            )
            if let previousBoundsOrigin,
               let enclosingScrollView = textView.enclosingScrollView {
                if let textContainer = textView.textContainer {
                    textView.layoutManager?.ensureLayout(for: textContainer)
                }
                enclosingScrollView.contentView.setBoundsOrigin(previousBoundsOrigin)
                enclosingScrollView.reflectScrolledClipView(enclosingScrollView.contentView)
            }
            if didChangeDocument {
                textView.undoManager?.removeAllActions()
            }
            publishHistoryState()
            pushFormattingState()
        }

        func updateZoom(to percent: Int) {
            guard let scrollView else { return }
            let clampedPercent = EditorZoom.clamp(percent)
            let magnification = EditorZoom.magnification(for: clampedPercent)
            let currentMagnification = scrollView.magnification

            guard !currentMagnification.isFinite
                    || abs(currentMagnification - magnification) > 0.001
            else {
                scheduledZoomPercent = nil
                return
            }

            // A SwiftUI representable update can run from inside AppKit's
            // layout transaction. Mutating NSScrollView.magnification here
            // synchronously re-enters layout and AppKit raises an
            // NSException (which appears in Xcode as EXC_BREAKPOINT at
            // _crashOnException). Defer the mutation until the current
            // layout pass has completed and discard stale requests when the
            // user clicks the zoom controls repeatedly.
            scheduledZoomPercent = clampedPercent
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.scheduledZoomPercent == clampedPercent,
                      let scrollView = self.scrollView else {
                    return
                }
                self.scheduledZoomPercent = nil

                guard scrollView.window != nil,
                      scrollView.bounds.width.isFinite,
                      scrollView.bounds.height.isFinite,
                      scrollView.bounds.width > 0,
                      scrollView.bounds.height > 0 else {
                    return
                }

                let visibleRect = scrollView.documentVisibleRect
                guard visibleRect.origin.x.isFinite,
                      visibleRect.origin.y.isFinite,
                      visibleRect.size.width.isFinite,
                      visibleRect.size.height.isFinite else {
                    return
                }

                let currentMagnification = scrollView.magnification
                guard !currentMagnification.isFinite
                        || abs(currentMagnification - magnification) > 0.001 else {
                    return
                }

                scrollView.setMagnification(
                    magnification,
                    centeredAt: NSPoint(x: visibleRect.midX, y: visibleRect.midY)
                )
            }
        }

        func handleZoomCommand(_ command: EditorZoomCommand) -> Bool {
            guard parent.formattingViewModel != nil else { return false }
            switch command {
            case .zoomIn:
                parent.formattingViewModel?.zoomIn()
            case .zoomOut:
                parent.formattingViewModel?.zoomOut()
            case .reset:
                parent.formattingViewModel?.resetZoom()
            }
            // The binding change drives `updateNSView` on the next SwiftUI
            // pass. Avoid mutating the AppKit scroll view again from inside
            // `performKeyEquivalent`, where a synchronous layout pass can
            // re-enter the representable update cycle.
            return true
        }

        private func syncZoomFromScrollView() {
            guard let scrollView else { return }
            let percent = EditorZoom.percent(for: scrollView.magnification)
            guard parent.zoomPercent != percent else { return }
            parent.zoomPercent = percent
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
            guard popover != nil || presentedSuggestionID != nil else { return }
            closePopover(notifySelection: true)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticMutation,
                  let textView
            else {
                return
            }

            persistRichText(from: textView)
            closePopover(notifySelection: true)
            layoutManager?.update(suggestions: [], selectedSuggestionID: nil)
            parent.onTextEdited()
            pushFormattingState()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            pushFormattingState()
            publishHistoryState()
        }

        /// Applies a toolbar action to the active AppKit editor selection.
        func applyFormatting(_ action: FormattingAction) {
            guard let textView else { return }

            switch action {
            case .undo:
                undo()
            case .redo:
                redo()
            default:
                performUndoableMutation(named: actionName(for: action)) {
                    RichTextFormatter.apply(action, to: textView)
                }
            }
        }

        /// Reflects the current cursor context in the toolbar.
        func pushFormattingState() {
            guard let textView else { return }
            parent.formattingViewModel?.activeState = RichTextFormatter.state(for: textView)
        }

        private func publishHistoryState() {
            guard let textView else {
                parent.formattingViewModel?.resetHistoryState()
                return
            }
            parent.formattingViewModel?.canUndo = textView.undoManager?.canUndo == true
            parent.formattingViewModel?.canRedo = textView.undoManager?.canRedo == true
        }

        private func actionName(for action: FormattingAction) -> String {
            switch action {
            case .textStyle(let style): return style.rawValue
            case .bold: return "Bold"
            case .italic: return "Italic"
            case .underline: return "Underline"
            case .strikethrough: return "Strikethrough"
            case .listStyle(let style):
                return style == .bulleted ? "Bulleted List" : "Numbered List"
            case .undo, .redo: return ""
            }
        }

        private func snapshot(from textView: NSTextView) -> EditorSnapshot {
            EditorSnapshot(
                attributedText: textView.attributedString(),
                selectedRange: textView.selectedRange(),
                typingAttributes: textView.typingAttributes
            )
        }

        private func performUndoableMutation(named actionName: String, _ mutation: () -> Bool) {
            guard let textView else { return }

            textView.breakUndoCoalescing()
            let before = snapshot(from: textView)
            let undoManager = textView.undoManager
            undoManager?.disableUndoRegistration()
            isApplyingProgrammaticMutation = true
            let didChange = mutation()
            isApplyingProgrammaticMutation = false
            undoManager?.enableUndoRegistration()

            guard didChange else {
                publishHistoryState()
                return
            }

            let after = snapshot(from: textView)
            registerSnapshotUndo(before: before, after: after, actionName: actionName)
            persistRichText(from: textView)
            closePopover(notifySelection: true)
            layoutManager?.update(suggestions: [], selectedSuggestionID: nil)
            parent.onTextEdited()
            pushFormattingState()
            publishHistoryState()
        }

        private func registerSnapshotUndo(
            before: EditorSnapshot,
            after: EditorSnapshot,
            actionName: String
        ) {
            guard let undoManager = textView?.undoManager else { return }
            undoManager.registerUndo(withTarget: self) { target in
                target.restoreSnapshot(
                    before,
                    registeringRedo: after,
                    actionName: actionName
                )
            }
            undoManager.setActionName(actionName)
        }

        private func restoreSnapshot(
            _ snapshot: EditorSnapshot,
            registeringRedo opposite: EditorSnapshot,
            actionName: String
        ) {
            guard let textView else { return }

            let undoManager = textView.undoManager
            undoManager?.disableUndoRegistration()
            isApplyingProgrammaticMutation = true
            textView.textStorage?.setAttributedString(snapshot.attributedText)
            textView.typingAttributes = snapshot.typingAttributes
            let location = min(snapshot.selectedRange.location, textView.string.utf16.count)
            let length = min(snapshot.selectedRange.length, textView.string.utf16.count - location)
            textView.setSelectedRange(NSRange(location: location, length: length))
            isApplyingProgrammaticMutation = false
            undoManager?.enableUndoRegistration()

            undoManager?.registerUndo(withTarget: self) { target in
                target.restoreSnapshot(
                    opposite,
                    registeringRedo: snapshot,
                    actionName: actionName
                )
            }
            undoManager?.setActionName(actionName)
            persistRichText(from: textView)
            closePopover(notifySelection: true)
            layoutManager?.update(suggestions: [], selectedSuggestionID: nil)
            parent.onTextEdited()
            pushFormattingState()
            publishHistoryState()
        }

        private func undo() {
            guard let textView,
                  textView.undoManager?.canUndo == true else {
                publishHistoryState()
                return
            }
            isApplyingProgrammaticMutation = true
            textView.undoManager?.undo()
            isApplyingProgrammaticMutation = false
            persistRichText(from: textView)
            closePopover(notifySelection: true)
            layoutManager?.update(suggestions: [], selectedSuggestionID: nil)
            parent.onTextEdited()
            pushFormattingState()
            publishHistoryState()
        }

        private func redo() {
            guard let textView,
                  textView.undoManager?.canRedo == true else {
                publishHistoryState()
                return
            }
            isApplyingProgrammaticMutation = true
            textView.undoManager?.redo()
            isApplyingProgrammaticMutation = false
            persistRichText(from: textView)
            closePopover(notifySelection: true)
            layoutManager?.update(suggestions: [], selectedSuggestionID: nil)
            parent.onTextEdited()
            pushFormattingState()
            publishHistoryState()
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

            textView.breakUndoCoalescing()
            let before = snapshot(from: textView)
            let undoManager = textView.undoManager
            undoManager?.disableUndoRegistration()
            isApplyingProgrammaticMutation = true
            textView.insertText(
                suggestion.replacement,
                replacementRange: suggestion.sourceRange
            )
            isApplyingProgrammaticMutation = false
            undoManager?.enableUndoRegistration()

            let after = snapshot(from: textView)
            registerSnapshotUndo(before: before, after: after, actionName: "Accept Suggestion")
            persistRichText(from: textView)
            parent.onAccept(suggestion)
            closePopover(notifySelection: true)
            parent.onTextEdited()
            publishHistoryState()
        }

        private func persistRichText(from textView: NSTextView) {
            let richText = textView.attributedString()
            let plainText = richText.string
                .replacingOccurrences(of: "\u{2028}", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rtfData = try? DocxToMarkdownConverter.rtfData(from: richText)

            currentText = plainText
            currentRichTextData = rtfData
            parent.text = plainText
            parent.richTextData = rtfData
            let normalized = StructuredDocument.normalize(richText)
            currentStructuredDocument = normalized
            parent.structuredDocument = normalized
            publishHistoryState()
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
                    height: textView.font?.pointSize ?? EditorTypography.bodyPointSize
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
                    height: textView.font?.pointSize ?? EditorTypography.bodyPointSize
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
    var onZoomCommand: ((EditorZoomCommand) -> Bool)?

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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command),
              !modifiers.contains(.option),
              !modifiers.contains(.control),
              let characters = event.charactersIgnoringModifiers?.lowercased()
        else {
            return super.performKeyEquivalent(with: event)
        }

        let command: EditorZoomCommand?
        switch characters {
        case "-", "_": command = .zoomOut
        case "=", "+": command = .zoomIn
        case "0": command = .reset
        default: command = nil
        }

        if let command, onZoomCommand?(command) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
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
                value: EditorTypography.bodyBoldFont,
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
        documentID: UUID(),
        text: .constant(text),
        richTextData: .constant(nil),
        structuredDocument: .constant(nil),
        zoomPercent: .constant(EditorZoom.defaultPercent),
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
        documentID: UUID(),
        text: .constant(text),
        richTextData: .constant(nil),
        structuredDocument: .constant(nil),
        zoomPercent: .constant(EditorZoom.defaultPercent),
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
