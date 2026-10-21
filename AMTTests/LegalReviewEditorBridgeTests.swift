import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import AMT

@MainActor
final class LegalReviewEditorBridgeTests: XCTestCase {
    private func result(_ text: String) -> LegalReviewAgent.Result {
        let plan = LegalReviewSignalPlanner().build(text)
        return .init(revision: DocumentFingerprinting.contentSHA256(text), findings: plan.local, status: "policySkipped", failures: [], toolTrace: [], modelCalls: 0, cacheHit: false, cacheEvictions: 0)
    }
    func testMapsTwoEvidenceClausesAndStableSuggestionIdentities() throws {
        let text="🧑🏽‍⚖️ Pelaksana menjaga menjaga bukti.\nPenyewa membayar dalam 4 hari.\nPenyewa membayar dalam 6 hari."
        let bridge=LegalReviewEditorBridge();let input=result(text)
        let first=bridge.map(input,text:text,corpusVersion:"v1")
        let second=bridge.map(input,text:text,corpusVersion:"v1")
        XCTAssertEqual(first.coverageStatus,"policySkipped");XCTAssertEqual(first.suggestions.count,1);XCTAssertEqual(first.suggestions,second.suggestions)
        let annotation=try XCTUnwrap(first.annotations.first)
        XCTAssertEqual(annotation.relatedEvidence.count,2)
        XCTAssertTrue(annotation.relatedEvidence.allSatisfy{$0.isAnchored(to:text)})
        XCTAssertTrue(bridge.validate(try XCTUnwrap(first.suggestions.first),text:text,corpusVersion:"v1"))
    }
    func testRejectsStaleTextCorpusForgedOptionAndReset() throws {
        let text="Penyedia wajib wajib hadir.";let bridge=LegalReviewEditorBridge()
        let mapped=bridge.map(result(text),text:text,corpusVersion:"v1");let item=try XCTUnwrap(mapped.suggestions.first)
        XCTAssertFalse(bridge.validate(item,text:"Prefix "+text,corpusVersion:"v1"))
        XCTAssertFalse(bridge.validate(item,text:text,corpusVersion:"v2"))
        let forged=EditorSuggestion(id:item.id,sourceRange:item.sourceRange,original:item.original,replacement:"dapat",category:.grammar,reason:item.reason,origin:.deterministic)
        XCTAssertFalse(bridge.validate(forged,text:text,corpusVersion:"v1"))
        bridge.reset();XCTAssertFalse(bridge.validate(item,text:text,corpusVersion:"v1"))
        XCTAssertTrue(bridge.map(result(text),text:"Changed "+text,corpusVersion:"v1").incomplete)
    }
    func testRestoredEditorItemsCannotApplyWithoutRuntimeProvenance() throws {
        let text="Penyedia wajib wajib hadir.";let bridge=LegalReviewEditorBridge()
        let item=try XCTUnwrap(bridge.map(result(text),text:text,corpusVersion:"v1").suggestions.first)
        let restored=try JSONDecoder().decode(EditorSuggestion.self,from:JSONEncoder().encode(item))
        XCTAssertFalse(LegalReviewEditorBridge().validate(restored,text:text,corpusVersion:"v1"))
    }
    func testInvalidEvidenceAndForgedActionableNeverMap() {
        let text="Penerima dapat membuka arsip.";let range=(text as NSString).range(of:"dapat")
        let invalid=LegalReviewAgent.Finding(id:"forged",category:"grammar",original:"dapat",replacement:"wajib",range:range,actionable:true,reason:"forged",evidenceIDs:[])
        let readonly=LegalReviewAgent.Finding(id:"unknown-evidence",category:"conflict",original:"dapat",replacement:nil,range:range,actionable:false,reason:"forged",evidenceIDs:["unknown"])
        let result=LegalReviewAgent.Result(revision:DocumentFingerprinting.contentSHA256(text),findings:[invalid,readonly],status:"completePairs",failures:[],toolTrace:[],modelCalls:0,cacheHit:false,cacheEvictions:0)
        let output=LegalReviewEditorBridge().map(result,text:text,corpusVersion:"v1")
        XCTAssertTrue(output.incomplete);XCTAssertTrue(output.suggestions.isEmpty);XCTAssertTrue(output.annotations.isEmpty)
    }
    func testFinalEditorBoundaryRejectsSingleQuotesGuillemetsAndCode() {
        for wrapped in ["'wajib wajib'", "‘wajib wajib’", "«wajib wajib»", "`wajib wajib`", "```\nwajib wajib\n```"] {
            let text="Kutipan atau kode: " + wrapped
            let bridge=LegalReviewEditorBridge()
            let mapped=bridge.map(result(text),text:text,corpusVersion:"v1")
            XCTAssertTrue(mapped.suggestions.isEmpty,text)
        }
    }
    func testExistingEditorAppliesValidatedDuplicateSupportsUndoRedoAndSave() async throws {
        let text="🧾 Penyedia menyimpan menyimpan arsip."
        let bridge=LegalReviewEditorBridge();let mapped=bridge.map(result(text),text:text,corpusVersion:"v1")
        let item=try XCTUnwrap(mapped.suggestions.first)
        let state=BridgeEditorState();state.text=text
        let parent=HighlightedDocumentTextEditor(documentID:UUID(),text:Binding(get:{state.text},set:{state.text=$0}),richTextData:Binding(get:{state.rich},set:{state.rich=$0}),structuredDocument:Binding(get:{state.structured},set:{state.structured=$0}),zoomPercent:.constant(100),suggestions:mapped.suggestions,annotations:mapped.annotations,reviewedReviewItemIDs:[],selectedReviewItemID:nil,onSelect:{_ in},onTextEdited:{},validateSuggestion:{bridge.validate($0,text:$1,corpusVersion:"v1")},validateDefinitionResolution:{_,_ in false},onSuggestionAccepted:{_,_,_ in bridge.invalidateAfterEdit()},onDismiss:{_ in},onMarkReviewed:{_ in},onReopenReviewed:{_ in})
        let coordinator=parent.makeCoordinator();let storage=NSTextStorage(string:text);let layout=SuggestionLayoutManager();let container=NSTextContainer(size:NSSize(width:600,height:1000))
        storage.addLayoutManager(layout);layout.addTextContainer(container)
        let view=SuggestionTextView(frame:NSRect(x:0,y:0,width:600,height:400),textContainer:container);view.allowsUndo=true
        let scroll=NSScrollView(frame:view.frame);scroll.documentView=view
        let window=NSWindow(contentRect:view.frame,styleMask:[.titled],backing:.buffered,defer:false);window.contentView=scroll;window.makeFirstResponder(view)
        defer{window.orderOut(nil)}
        coordinator.connect(scrollView:scroll,textView:view,layoutManager:layout,textContainer:container,documentID:parent.documentID,text:text,richTextData:nil,structuredDocument:nil,zoomPercent:100)
        let undo=try XCTUnwrap(view.undoManager);undo.groupsByEvent=false
        undo.beginUndoGrouping();coordinator.accept(item);undo.endUndoGrouping()
        XCTAssertEqual(view.string,"🧾 Penyedia menyimpan arsip.");XCTAssertEqual(state.text,view.string)
        XCTAssertNotNil(state.rich);XCTAssertNotNil(state.structured)
        XCTAssertFalse(bridge.validate(item,text:text,corpusVersion:"v1"))
        undo.undo();XCTAssertEqual(state.text,text)
        undo.redo();XCTAssertEqual(state.text,"🧾 Penyedia menyimpan arsip.")
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("AMT-LegalReviewBridge-\(UUID().uuidString)",isDirectory:true)
        defer{try? FileManager.default.removeItem(at:directory)}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var document=DashboardDocument(content:text)
        try JSONEncoder().encode(document).write(to:directory.appendingPathComponent("\(document.id.uuidString).json"))
        let store=DocumentStorageManager(storageDirectoryURL:directory)
        document.content=state.text;document.richTextData=state.rich;document.structuredDocument=state.structured
        _=store.updateDraft(document);await store.flushAllPendingSaves()
        let saved=try XCTUnwrap(DocumentStorageManager(storageDirectoryURL:directory).documents.first{$0.id==document.id})
        XCTAssertEqual(saved.content,state.text);XCTAssertEqual(saved.richTextData,state.rich);XCTAssertEqual(saved.structuredDocument,state.structured)
    }
}
@MainActor
private final class BridgeEditorState {
    var text="";var rich:Data?;var structured:StructuredDocument?
}
