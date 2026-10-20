import Foundation
import XCTest
@testable import AMT

@MainActor
final class LegalReviewFastRouterTests: XCTestCase {
    func testPlainLocalTextAndKnownRulesCanUseLocalBase() async throws {
        let provider=Probe([]);let router=LegalReviewFastRouter(dictionaryStore:LegalDictionaryStore(entries:[]),provider:provider)
        for text in ["Penyedia menjaga dokumen.","Penyedia memasukan dokumen.","Penyedia wajib wajib hadir."] {
            let decision=try await router.route(text,fullFresh:true)
            XCTAssertFalse(decision.needsHybrid,text)
        }
        XCTAssertTrue(provider.excluded.contains("memasukan"))
    }
    func testUnknownSpellingCandidateKeepsFullHybridWithoutChangingEvidence() async throws {
        let provider=Probe([.init(original:"perjanjain",replacement:"perjanjian",sourceLocation:0,sourceLength:10)])
        let decision=try await LegalReviewFastRouter(dictionaryStore:LegalDictionaryStore(entries:[]),provider:provider).route("perjanjain berlaku.",fullFresh:true)
        XCTAssertTrue(decision.needsHybrid);XCTAssertEqual(decision.reason,"nativeSpellingCandidate")
    }
    func testDefinitionsQuotesSourcesRisksAndLongDocumentsRetainHybrid() async throws {
        let router=LegalReviewFastRouter(dictionaryStore:LegalDictionaryStore(entries:[]),provider:Probe([]))
        for text in ["Yang dimaksud dengan Hari adalah hari kerja.","Merek ‘Data Data’ dipertahankan.","Kutipan 'wajib wajib' disimpan.","Dokumen mengikuti Undang-Undang Nomor 9.","Pihak bertanggung jawab tanpa batas.",String(repeating:"Penyedia hadir. ",count:600)] {
            let decision=try await router.route(text,fullFresh:true)
            XCTAssertTrue(decision.needsHybrid,text)
        }
    }
    func testLexicallySupportedImplicitDefinitionRetainsHybrid() async throws {
        let entry=LegalDictionaryEntry(id:"t",term:"Arsip Khusus",definition:"Dokumen rahasia mengenai proses pengadaan barang.",regulation:"Test",regulationTitle:"Test",sourceURL:nil,authority:.verified,corpusVersion:"test-corpus",isActionable:true)
        let router=LegalReviewFastRouter(dictionaryStore:LegalDictionaryStore(entries:[entry]),provider:Probe([]))
        let decision=try await router.route("Arsip Khusus berisi dokumen rahasia mengenai proses pengadaan barang.",fullFresh:true)
        XCTAssertTrue(decision.needsHybrid)
    }
    func testExistingLexicalSeedRetainsFullPathEvenForOrdinaryMention() async throws {
        let entry=LegalDictionaryEntry(id:"t",term:"Arsip Khusus",definition:"Dokumen rahasia mengenai proses pengadaan barang.",regulation:"Test",regulationTitle:"Test",sourceURL:nil,authority:.verified,corpusVersion:"test-corpus",isActionable:true)
        let router=LegalReviewFastRouter(dictionaryStore:LegalDictionaryStore(entries:[entry]),provider:Probe([]))
        let decision=try await router.route("Arsip Khusus disimpan.",fullFresh:true)
        XCTAssertTrue(decision.needsHybrid)
    }
    func testFullFreshBypassesRouteResultCacheAndChangedInputInvalidates() async throws {
        let provider=Probe([]);let router=LegalReviewFastRouter(dictionaryStore:LegalDictionaryStore(entries:[]),provider:provider)
        _=try await router.route("Pihak hadir.",fullFresh:false)
        let cached=try await router.route("Pihak hadir.",fullFresh:false)
        XCTAssertTrue(cached.cacheHit);XCTAssertEqual(provider.calls,1)
        _=try await router.route("Pihak hadir.",fullFresh:true);XCTAssertEqual(provider.calls,2)
        let changed=try await router.route("Pihak lain hadir.",fullFresh:false);XCTAssertFalse(changed.cacheHit)
        router.clearCache();let reset=try await router.route("Pihak hadir.",fullFresh:false);XCTAssertFalse(reset.cacheHit)
    }
    func testTwoDocumentsDoNotShareRoutingCache() async throws {
        let store=LegalDictionaryStore(entries:[])
        let one=LegalReviewFastRouter(dictionaryStore:store,provider:Probe([])),two=LegalReviewFastRouter(dictionaryStore:store,provider:Probe([]))
        _=try await one.route("Pihak hadir.",fullFresh:false)
        let independent=try await two.route("Pihak hadir.",fullFresh:false);XCTAssertFalse(independent.cacheHit)
    }
    func testNativeRiskReviewRequirementRetainsHybrid() async throws {
        let router=LegalReviewFastRouter(dictionaryStore:LegalDictionaryStore(entries:[]),provider:Probe([]))
        let text="Pihak Pertama wajib menyerahkan laporan. Pihak Pertama tidak wajib menyerahkan laporan."
        let decision=try await router.route(text,fullFresh:true)
        XCTAssertTrue(decision.needsHybrid)
        XCTAssertEqual(decision.reason,"nativeRiskCandidate")
    }
    func testCancellationDoesNotCreateSuccessfulRoutingResult() async throws {
        let router=LegalReviewFastRouter(dictionaryStore:LegalDictionaryStore(entries:[]),provider:Probe([]))
        let task=Task{@MainActor in try await Task.sleep(nanoseconds:20_000_000);return try await router.route("Pihak hadir.",fullFresh:false)}
        task.cancel()
        do{_=try await task.value;XCTFail("Expected cancellation")}catch is CancellationError{}
        let clean=try await router.route("Pihak hadir.",fullFresh:false);XCTAssertFalse(clean.cacheHit)
    }
    func testOversizedContextKeepsLocalResultsWithoutModelAndRemainsPartial() async throws {
        var calls=0
        let agent=LegalReviewAgent(dictionaryStore:LegalDictionaryStore(entries:[])) { _,_ in calls+=1;throw LegalReviewAgent.Failure.invalidCall }
        let execution=agent
        let text="Penyedia wajib wajib hadir.\n"+(0..<70).map{"Catatan nomor \($0) diterima."}.joined(separator:"\n")
        XCTAssertFalse(execution.prepareLocal(documentText:text).findings.isEmpty)
        let result=await execution.review(documentText:text)
        XCTAssertEqual(calls,0);XCTAssertEqual(result.status,"partial");XCTAssertFalse(result.findings.isEmpty)
        XCTAssertTrue(result.failures.contains("contextPolicySkipped:unitBudget"))
        XCTAssertFalse(result.cacheHit)
    }
    func testPreparedLocalRevisionCannotLeakToChangedText() async throws {
        let agent=LegalReviewAgent(dictionaryStore:LegalDictionaryStore(entries:[])) { _,_ in throw LegalReviewAgent.Failure.invalidCall }
        let execution=agent
        XCTAssertFalse(execution.prepareLocal(documentText:"Penyedia wajib wajib hadir.").findings.isEmpty)
        let changed=await execution.review(documentText:"Penyedia hadir.")
        XCTAssertTrue(changed.findings.isEmpty)
        XCTAssertEqual(changed.revision,DocumentFingerprinting.contentSHA256("Penyedia hadir."))
    }
    private final class Probe:AIConnectorSpellingCandidateProviding {
        let values:[AIConnectorSpellingCandidate];var calls=0;var excluded=Set<String>()
        init(_ values:[AIConnectorSpellingCandidate]){self.values=values}
        func candidates(for segment:AIReviewSegment,protectionContext:AIConnectorDocumentProtectionContext,excludedOriginals:Set<String>)->[AIConnectorSpellingCandidate]{calls+=1;excluded.formUnion(excludedOriginals);return values}
    }
}
