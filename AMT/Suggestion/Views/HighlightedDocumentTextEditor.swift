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
    let annotations: [EditorReviewAnnotation]
    let definitionResolutions: [UUID: AIConnectorDefinitionResolution]
    let definitionResolutionLoadingIDs: Set<UUID>
    let reviewedReviewItemIDs: Set<UUID>
    let selectedReviewItemID: UUID?
    let onSelect: (UUID?) -> Void
    let onCaretLocationChanged: (Int?) -> Void
    let onTextEdited: () -> Void
    let onSuggestionAccepted: (EditorSuggestion, String, String) -> Void
    let onDismiss: (UUID) -> Void
    let onMarkReviewed: (UUID) -> Void
    let onReopenReviewed: (UUID) -> Void
    let onRequestDefinitionResolution: (UUID) -> Void
    let onDefinitionResolutionApplied: (AIConnectorDefinitionResolutionOption, String, String) -> Void

    var formattingViewModel: EditorViewModel? = nil

    init(
        documentID: UUID,
        text: Binding<String>,
        richTextData: Binding<Data?>,
        structuredDocument: Binding<StructuredDocument?>,
        zoomPercent: Binding<Int>,
        suggestions: [EditorSuggestion],
        annotations: [EditorReviewAnnotation],
        definitionResolutions: [UUID: AIConnectorDefinitionResolution] = [:],
        definitionResolutionLoadingIDs: Set<UUID> = [],
        reviewedReviewItemIDs: Set<UUID>,
        selectedReviewItemID: UUID?,
        onSelect: @escaping (UUID?) -> Void,
        onCaretLocationChanged: @escaping (Int?) -> Void = { _ in },
        onTextEdited: @escaping () -> Void,
        onSuggestionAccepted: @escaping (EditorSuggestion, String, String) -> Void,
        onDismiss: @escaping (UUID) -> Void,
        onMarkReviewed: @escaping (UUID) -> Void,
        onReopenReviewed: @escaping (UUID) -> Void,
        onRequestDefinitionResolution: @escaping (UUID) -> Void = { _ in },
        onDefinitionResolutionApplied: @escaping (AIConnectorDefinitionResolutionOption, String, String) -> Void = { _, _, _ in },
        formattingViewModel: EditorViewModel? = nil
    ) {
        self.documentID = documentID
        self._text = text
        self._richTextData = richTextData
        self._structuredDocument = structuredDocument
        self._zoomPercent = zoomPercent
        self.suggestions = suggestions
        self.annotations = annotations
        self.definitionResolutions = definitionResolutions
        self.definitionResolutionLoadingIDs = definitionResolutionLoadingIDs
        self.reviewedReviewItemIDs = reviewedReviewItemIDs
        self.selectedReviewItemID = selectedReviewItemID
        self.onSelect = onSelect
        self.onCaretLocationChanged = onCaretLocationChanged
        self.onTextEdited = onTextEdited
        self.onSuggestionAccepted = onSuggestionAccepted
        self.onDismiss = onDismiss
        self.onMarkReviewed = onMarkReviewed
        self.onReopenReviewed = onReopenReviewed
        self.onRequestDefinitionResolution = onRequestDefinitionResolution
        self.onDefinitionResolutionApplied = onDefinitionResolutionApplied
        self.formattingViewModel = formattingViewModel
    }

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
            annotations: annotations,
            selectedReviewItemID: selectedReviewItemID
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
            annotations: annotations,
            selectedReviewItemID: selectedReviewItemID
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
        private var popover: NSPopover?
        private var presentedSuggestionID: UUID?
        private var lastDefinitionResolutionSignature: String?
        private var lastSelectedReviewItemID: UUID?
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
            publishCaretLocation()
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
            else { return }

            // Use AppKit's centered setter rather than mutating the property
            // during a SwiftUI representable update. It clips to the scroll
            // view's limits and avoids leaving the clip view in a transient
            // invalid state while its bounds are being recalculated.
            let visibleRect = scrollView.documentVisibleRect
            scrollView.setMagnification(
                magnification,
                centeredAt: NSPoint(x: visibleRect.midX, y: visibleRect.midY)
            )
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
            annotations: [EditorReviewAnnotation],
            selectedReviewItemID: UUID?
        ) {
            layoutManager?.update(
                suggestions: suggestions,
                annotations: annotations,
                selectedReviewItemID: selectedReviewItemID,
                reviewedReviewItemIDs: parent.reviewedReviewItemIDs
            )

            if let presentedSuggestionID,
               !(suggestions.map(\.id) + annotations.map(\.id))
                    .contains(presentedSuggestionID) {
                closePopover(notifySelection: true)
            }

            let selectionChanged = lastSelectedReviewItemID != selectedReviewItemID
            lastSelectedReviewItemID = selectedReviewItemID
            let resolutionChanged = definitionResolutionSignature(for: selectedReviewItemID)
                != lastDefinitionResolutionSignature
            guard selectionChanged || resolutionChanged,
                  let selectedReviewItemID,
                  let selectedItem = allReviewItems.first(where: {
                      $0.id == selectedReviewItemID
                  }) else {
                return
            }

            // Navigator selection is driven by SwiftUI. Defer the AppKit
            // scroll/popover work until the representable has finished its
            // update pass to avoid re-entering NSTextView layout.
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.lastSelectedReviewItemID == selectedReviewItemID else {
                    return
                }
                self.scroll(to: selectedItem)
                self.presentPopover(
                    for: selectedItem,
                    anchor: self.anchor(for: selectedItem),
                    isStale: !self.rangeContainsOriginal(selectedItem)
                )
            }
        }

        func handleHover(at point: NSPoint) {
            guard let textView,
                  let layoutManager,
                  let textContainer,
                  !allReviewItems.isEmpty
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
                  let item = reviewItem(at: characterIndex)
            else {
                return
            }

            if presentedSuggestionID != item.id {
                parent.onSelect(item.id)
                layoutManager.update(
                    suggestions: parent.suggestions,
                    annotations: parent.annotations,
                    selectedReviewItemID: item.id,
                    reviewedReviewItemIDs: parent.reviewedReviewItemIDs
                )
                presentPopover(
                    for: item,
                    anchor: anchor(for: item),
                    isStale: !rangeContainsOriginal(item)
                )
            }
        }

        func handleClick(at point: NSPoint) {
            guard let textView,
                  let layoutManager,
                  let textContainer,
                  !allReviewItems.isEmpty
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
                  let item = reviewItem(at: characterIndex)
            else {
                closePopover(notifySelection: true)
                return
            }

            parent.onSelect(item.id)
            layoutManager.update(
                suggestions: parent.suggestions,
                annotations: parent.annotations,
                selectedReviewItemID: item.id,
                reviewedReviewItemIDs: parent.reviewedReviewItemIDs
            )
            presentPopover(
                for: item,
                anchor: anchor(for: item),
                isStale: !rangeContainsOriginal(item)
            )
        }

        private var allReviewItems: [EditorReviewItem] {
            let items = parent.suggestions.map(EditorReviewItem.suggestion)
                + parent.annotations.map(EditorReviewItem.annotation)
            return items.sorted { lhs, rhs in
                if lhs.sourceRange.location != rhs.sourceRange.location {
                    return lhs.sourceRange.location < rhs.sourceRange.location
                }
                let lhsPriority = reviewItemPriority(lhs)
                let rhsPriority = reviewItemPriority(rhs)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return lhs.sourceRange.length < rhs.sourceRange.length
            }
        }

        private func reviewItem(at characterIndex: Int) -> EditorReviewItem? {
            allReviewItems.first(where: {
                NSLocationInRange(characterIndex, $0.sourceRange)
            })
        }

        private func reviewItemPriority(_ item: EditorReviewItem) -> Int {
            switch item {
            case .suggestion:
                1
            case let .annotation(annotation):
                annotation.definitionDiagnosticStatus == .matches ? 2 : 0
            }
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
            layoutManager?.update(suggestions: [], annotations: [], selectedReviewItemID: nil)
            parent.onTextEdited()
            pushFormattingState()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            pushFormattingState()
            publishHistoryState()
            publishCaretLocation()
        }

        private func publishCaretLocation() {
            guard let textView else {
                parent.onCaretLocationChanged(nil)
                return
            }
            let location = textView.selectedRange().location
            parent.onCaretLocationChanged(location == NSNotFound ? nil : location)
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
            layoutManager?.update(suggestions: [], annotations: [], selectedReviewItemID: nil)
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
            layoutManager?.update(suggestions: [], annotations: [], selectedReviewItemID: nil)
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
            layoutManager?.update(suggestions: [], annotations: [], selectedReviewItemID: nil)
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
            layoutManager?.update(suggestions: [], annotations: [], selectedReviewItemID: nil)
            parent.onTextEdited()
            pushFormattingState()
            publishHistoryState()
        }

        func accept(_ suggestion: EditorSuggestion) {
            guard let textView else { return }
            guard !suggestion.isReadOnlyDiagnostic else { return }

            guard rangeContainsOriginal(suggestion) else {
                presentPopover(
                    for: .suggestion(suggestion),
                    anchor: anchor(for: suggestion),
                    isStale: true
                )
                return
            }

            let previousText = textView.string
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
            parent.onSuggestionAccepted(suggestion, previousText, textView.string)
            closePopover(notifySelection: true)
            publishHistoryState()
        }

        func applyDefinitionResolution(_ option: AIConnectorDefinitionResolutionOption) {
            guard let textView, option.isActionable else { return }

            guard rangeContainsOriginal(option) else {
                if let annotation = parent.annotations.first(where: { annotation in
                    parent.definitionResolutions[annotation.id]?.options.contains {
                        $0.id == option.id
                    } == true
                }) {
                    presentPopover(
                        for: .annotation(annotation),
                        anchor: anchor(for: annotation),
                        isStale: true
                    )
                }
                return
            }

            guard let replacement = option.replacement else { return }
            let previousText = textView.string
            textView.breakUndoCoalescing()
            let before = snapshot(from: textView)
            let undoManager = textView.undoManager
            undoManager?.disableUndoRegistration()
            isApplyingProgrammaticMutation = true
            textView.insertText(replacement, replacementRange: option.targetRange)
            isApplyingProgrammaticMutation = false
            undoManager?.enableUndoRegistration()

            let after = snapshot(from: textView)
            registerSnapshotUndo(
                before: before,
                after: after,
                actionName: "Apply Definition Resolution"
            )
            persistRichText(from: textView)
            parent.onDefinitionResolutionApplied(option, previousText, textView.string)
            closePopover(notifySelection: true)
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

        func dismiss(_ item: EditorReviewItem) {
            parent.onDismiss(item.id)
            closePopover(notifySelection: true)
        }

        private func presentPopover(
            for item: EditorReviewItem,
            anchor: NSRect,
            isStale: Bool
        ) {
            guard let textView else { return }

            let popover = self.popover ?? NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.delegate = self
            switch item {
            case let .suggestion(suggestion):
                popover.contentViewController = NSHostingController(
                    rootView: SuggestionPopoverView(
                        suggestion: suggestion,
                        isStale: isStale,
                        onAccept: { [weak self] in
                            self?.accept(suggestion)
                        },
                        onDismiss: { [weak self] in
                            self?.dismiss(.suggestion(suggestion))
                        }
                    )
                )
                popover.contentSize = NSSize(width: 400, height: 460)
            case let .annotation(annotation):
                let overlappingAnnotations = parent.annotations.filter { other in
                    other.id != annotation.id
                        && NSIntersectionRange(other.sourceRange, annotation.sourceRange).length > 0
                }
                popover.contentViewController = NSHostingController(
                    rootView: ReviewAnnotationPopoverView(
                        annotation: annotation,
                        isStale: isStale,
                        isReviewed: parent.reviewedReviewItemIDs.contains(annotation.id),
                        overlappingAnnotations: overlappingAnnotations,
                        resolution: parent.definitionResolutions[annotation.id],
                        isResolutionLoading: parent.definitionResolutionLoadingIDs.contains(annotation.id),
                        onDismiss: { [weak self] in
                            self?.dismiss(.annotation(annotation))
                        },
                        onMarkReviewed: { [weak self] in
                            self?.parent.onMarkReviewed(annotation.id)
                            self?.closePopover(notifySelection: true)
                        },
                        onReopenReviewed: { [weak self] in
                            self?.parent.onReopenReviewed(annotation.id)
                            self?.closePopover(notifySelection: true)
                        },
                        onNavigateToEvidence: { [weak self] evidence in
                            self?.scroll(to: evidence.sourceRange)
                        },
                        onSelectOverlapping: { [weak self] id in
                            self?.closePopover(notifySelection: false)
                            self?.parent.onSelect(id)
                        },
                        onRequestResolution: { [weak self] in
                            self?.parent.onRequestDefinitionResolution(annotation.id)
                        },
                        onApplyResolution: { [weak self] option in
                            self?.applyDefinitionResolution(option)
                        }
                    )
                )
                popover.contentSize = NSSize(width: 440, height: 520)
            }
            self.popover = popover
            presentedSuggestionID = item.id
            lastDefinitionResolutionSignature = definitionResolutionSignature(for: item.id)

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
            lastDefinitionResolutionSignature = nil

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

        private func rangeContainsOriginal(
            _ option: AIConnectorDefinitionResolutionOption
        ) -> Bool {
            guard let textView,
                  option.targetRange.location >= 0,
                  option.targetRange.length > 0,
                  NSMaxRange(option.targetRange) <= textView.string.utf16.count else {
                return false
            }
            return (textView.string as NSString).substring(with: option.targetRange)
                == option.original
        }

        private func definitionResolutionSignature(for id: UUID?) -> String? {
            guard let id else { return nil }
            let resolution = parent.definitionResolutions[id]
            let loading = parent.definitionResolutionLoadingIDs.contains(id)
            return "\(id.uuidString)|\(loading)|\(resolution?.id ?? "-")|\(resolution?.options.count ?? 0)"
        }

        private func rangeContainsOriginal(_ item: EditorReviewItem) -> Bool {
            switch item {
            case let .suggestion(suggestion):
                return rangeContainsOriginal(suggestion)
            case let .annotation(annotation):
                guard let textView,
                      annotation.sourceRange.location >= 0,
                      NSMaxRange(annotation.sourceRange) <= textView.string.utf16.count else {
                    return false
                }
                return (textView.string as NSString).substring(
                    with: annotation.sourceRange
                ) == annotation.original
            }
        }

        private func scroll(to item: EditorReviewItem) {
            scroll(to: item.sourceRange)
        }

        private func scroll(to range: NSRange) {
            guard let textView,
                  range.location >= 0,
                  range.length > 0,
                  NSMaxRange(range) <= textView.string.utf16.count else {
                return
            }
            textView.scrollRangeToVisible(range)
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

        private func anchor(for annotation: EditorReviewAnnotation) -> NSRect {
            anchor(for: .annotation(annotation))
        }

        private func anchor(for item: EditorReviewItem) -> NSRect {
            switch item {
            case let .suggestion(suggestion):
                return anchor(for: suggestion)
            case let .annotation(annotation):
                guard let textView,
                      let layoutManager,
                      annotation.sourceRange.location >= 0,
                      annotation.sourceRange.length > 0,
                      NSMaxRange(annotation.sourceRange) <= textView.string.utf16.count else {
                    return NSRect(x: 0, y: 0, width: 1, height: 1)
                }
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: annotation.sourceRange,
                    actualCharacterRange: nil
                )
                guard glyphRange.length > 0,
                      glyphRange.location < layoutManager.numberOfGlyphs else {
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
            lastDefinitionResolutionSignature = nil
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
        let isReadOnlyDiagnostic: Bool
        let annotationKind: EditorReviewAnnotationKind?
        let definitionDiagnosticStatus: EditorDefinitionDiagnosticStatus?
        let isReviewed: Bool
        let isStale: Bool
    }

    private(set) var drawingRanges: [DrawingRange] = []

    func update(
        suggestions: [EditorSuggestion],
        annotations: [EditorReviewAnnotation] = [],
        selectedReviewItemID: UUID?,
        reviewedReviewItemIDs: Set<UUID> = []
    ) {
        let text = textStorage?.string ?? ""
        let suggestionRanges = suggestions.map {
            DrawingRange(
                id: $0.id,
                range: $0.sourceRange,
                isSelected: $0.id == selectedReviewItemID,
                isReadOnlyDiagnostic: false,
                annotationKind: nil,
                definitionDiagnosticStatus: nil,
                isReviewed: false,
                isStale: !rangeContainsOriginal(
                    range: $0.sourceRange,
                    original: $0.original,
                    in: text
                )
            )
        }
        let annotationRanges = annotations.map {
            DrawingRange(
                id: $0.id,
                range: $0.sourceRange,
                isSelected: $0.id == selectedReviewItemID,
                isReadOnlyDiagnostic: true,
                annotationKind: $0.kind,
                definitionDiagnosticStatus: $0.definitionDiagnosticStatus,
                isReviewed: reviewedReviewItemIDs.contains($0.id),
                isStale: !rangeContainsOriginal(
                    range: $0.sourceRange,
                    original: $0.original,
                    in: text
                )
            )
        }
        drawingRanges = (annotationRanges + suggestionRanges).sorted { lhs, rhs in
            let lhsPriority = visualPriority(for: lhs)
            let rhsPriority = visualPriority(for: rhs)
            if lhsPriority != rhsPriority {
                // Lower numbers are more important and should be applied
                // later so definition/needs-review colors win overlaps.
                return lhsPriority > rhsPriority
            }
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }
            return lhs.range.length < rhs.range.length
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
                value: foregroundColor(for: item),
                forCharacterRange: item.range
            )
            addTemporaryAttribute(
                .font,
                value: EditorTypography.bodyBoldFont,
                forCharacterRange: item.range
            )
            if item.isStale {
                addTemporaryAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    forCharacterRange: item.range
                )
            }
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
                let color = self.backgroundColor(for: item)
                color.setFill()
                NSBezierPath(
                    roundedRect: drawRect,
                    xRadius: 6,
                    yRadius: 6
                ).fill()

                if item.isSelected {
                    let outline = NSBezierPath(
                        roundedRect: drawRect,
                        xRadius: 6,
                        yRadius: 6
                    )
                    outline.lineWidth = 1.5
                    NSColor.controlAccentColor.withAlphaComponent(0.75).setStroke()
                    outline.stroke()
                }
            }
        }
    }

    private func visualPriority(for item: DrawingRange) -> Int {
        guard item.isReadOnlyDiagnostic else { return 1 }
        return item.definitionDiagnosticStatus == .matches ? 2 : 0
    }

    private func foregroundColor(for item: DrawingRange) -> NSColor {
        if item.isStale {
            return NSColor.secondaryLabelColor
        }

        if item.isReviewed {
            return NSColor.secondaryLabelColor
        }

        guard item.isReadOnlyDiagnostic else {
            return NSColor(red: 0.65, green: 0.12, blue: 0.18, alpha: 1.0)
        }

        switch annotationColor(for: item) {
        case .matches:
            return NSColor(red: 0.12, green: 0.52, blue: 0.24, alpha: 1.0)
        case .mismatch:
            return NSColor(red: 0.72, green: 0.10, blue: 0.14, alpha: 1.0)
        case .needsReview:
            return NSColor(red: 0.70, green: 0.40, blue: 0.02, alpha: 1.0)
        }
    }

    private func backgroundColor(for item: DrawingRange) -> NSColor {
        if item.isStale {
            return NSColor.secondaryLabelColor.withAlphaComponent(0.15)
        }

        if item.isReviewed {
            return NSColor.secondaryLabelColor.withAlphaComponent(0.16)
        }

        guard item.isReadOnlyDiagnostic else {
            return NSColor(red: 0.98, green: 0.88, blue: 0.90, alpha: 1.0)
        }

        switch annotationColor(for: item) {
        case .matches:
            return NSColor(red: 0.86, green: 0.96, blue: 0.88, alpha: 1.0)
        case .mismatch:
            return NSColor(red: 0.99, green: 0.86, blue: 0.88, alpha: 1.0)
        case .needsReview:
            return NSColor(red: 0.99, green: 0.94, blue: 0.78, alpha: 1.0)
        }
    }

    private func annotationColor(
        for item: DrawingRange
    ) -> EditorDefinitionDiagnosticStatus {
        if let definitionDiagnosticStatus = item.definitionDiagnosticStatus {
            return definitionDiagnosticStatus
        }
        switch item.annotationKind {
        case .some(.needsReview), .some(.definedTerm), .some(.legalRisk), .none:
            return .needsReview
        case .some(.definition):
            return .needsReview
        }
    }

    private func rangeContainsOriginal(
        range: NSRange,
        original: String,
        in text: String
    ) -> Bool {
        guard range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= text.utf16.count else {
            return false
        }
        return (text as NSString).substring(with: range) == original
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
        annotations: [],
        reviewedReviewItemIDs: [],
        selectedReviewItemID: nil,
        onSelect: { _ in },
        onTextEdited: {},
        onSuggestionAccepted: { _, _, _ in },
        onDismiss: { _ in },
        onMarkReviewed: { _ in },
        onReopenReviewed: { _ in }
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
        annotations: [],
        reviewedReviewItemIDs: [],
        selectedReviewItemID: nil,
        onSelect: { _ in },
        onTextEdited: {},
        onSuggestionAccepted: { _, _, _ in },
        onDismiss: { _ in },
        onMarkReviewed: { _ in },
        onReopenReviewed: { _ in }
    )
    .frame(width: 520, height: 180)
    .preferredColorScheme(.dark)
}
