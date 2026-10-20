import Foundation
import MLXLMCommon
import XCTest
@testable import AMT

@MainActor
final class LegalReviewSelectiveTests: XCTestCase {
    func testUnitsAndFindingsPreserveUTF16AcrossSentencesAndHeadings() throws {
        let text="Pasal 1\n🧑🏽‍⚖️ Pelaksana menjaga menjaga bukti. Salinan diterima.\nPasal 2\nPenerima hadir."
        let plan=LegalReviewSignalPlanner().build(text)
        XCTAssertGreaterThanOrEqual(plan.units.count,3)
        for unit in plan.units { XCTAssertEqual((text as NSString).substring(with:unit.range),unit.text) }
        let found=try XCTUnwrap(plan.local.first)
        XCTAssertEqual((text as NSString).substring(with:found.range),"menjaga menjaga")
        XCTAssertTrue(found.actionable)
    }
    func testDuplicateDoesNotNeedModelAndLocalCallbackPrecedesInference() async throws {
        var count=0;var published=false
        let service=LegalReviewAgent(dictionaryStore:LegalDictionaryStore(entries:[])) { _,_ in count+=1;XCTAssertTrue(published);throw LegalReviewAgent.Failure.invalidCall }
        let result=await service.review(documentText:"Penyedia wajib wajib hadir.",onLocal:{ f in published=true;XCTAssertEqual(f.count,1) })
        XCTAssertEqual(count,0);XCTAssertEqual(result.status,"policySkipped");XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(result.toolTrace.contains("policySkipped:contextual:noPairSignal"))
    }
    func testQuotedNamesAcronymsAndCapitalizedRepetitionsStayProtected() {
        for text in ["Kutipan: “menjaga menjaga”.","PT Data Data Teknologi hadir.","Nama merek adalah Bisa Bisa.","Identifier NDA NDA dipertahankan."] {
            XCTAssertTrue(LegalReviewSignalPlanner().build(text).local.isEmpty,text)
        }
    }
    func testMultipleOccurrencesKeepDistinctStableIDsAndApplyMinimalRevision() async throws {
        let text="Penyedia wajib wajib hadir; Pelanggan wajib wajib hadir."
        let one=LegalReviewSignalPlanner().build(text),two=LegalReviewSignalPlanner().build(text)
        XCTAssertEqual(one.local.count,2);XCTAssertEqual(one.local,two.local)
        XCTAssertNotEqual(one.local[0].id,one.local[1].id)
        let changed=try LegalReviewAgent.apply(one.local[1],revision:DocumentFingerprinting.contentSHA256(text),to:text)
        XCTAssertEqual(changed,"Penyedia wajib wajib hadir; Pelanggan wajib hadir.")
        XCTAssertThrowsError(try LegalReviewAgent.apply(one.local[1],revision:DocumentFingerprinting.contentSHA256(text),to:"Prefix "+text))
    }
    func testExplicitParametersAreReadOnlyAndNotLegalDefectConclusion() {
        let plan=LegalReviewSignalPlanner().build("Barang diberikan kepada [NAMA PEMESAN]. Nilai akan ditentukan kemudian.")
        XCTAssertEqual(plan.local.count,2);XCTAssertTrue(plan.local.allSatisfy{!$0.actionable && $0.replacement==nil})
        XCTAssertTrue(plan.local.allSatisfy{$0.reason.contains("bukan kesimpulan")})
        XCTAssertTrue(LegalReviewSignalPlanner().build("Alamat Jalan Melati 10, Jakarta. Email legal@datta.test.").local.isEmpty)
    }
    func testPairsRouteValueOperatorAndExplicitDefinitionDifferences() {
        for text in ["Pembeli membayar tagihan dalam 8 hari.\nBatas pembayaran tagihan yang sama ditetapkan 21 hari.","Pemegang dilarang menyebarkan arsip.\nPemegang wajib menyebarkan arsip.","Yang dimaksud dengan Bukti adalah catatan tertulis.\nYang dimaksud dengan Bukti adalah catatan lisan."] {
            XCTAssertFalse(LegalReviewSignalPlanner().build(text).pairs.isEmpty,text)
        }
    }
    func testIdenticalFactsAndUnrelatedObjectsDoNotBecomeProvenConflictLocally() {
        let text="Pemasok mengirim dokumen.\nPemasok mengirim dokumen."
        XCTAssertTrue(LegalReviewSignalPlanner().build(text).pairs.isEmpty)
        let plan=LegalReviewSignalPlanner().build("Pembeli membayar dalam 8 hari.\nPelaksana menyerahkan rekap dalam 21 hari.")
        XCTAssertTrue(plan.local.isEmpty)
        // Even when lexical candidates share a verb, no conflict is emitted locally.
        XCTAssertFalse(plan.local.contains{$0.category=="conflict"})
    }
    func testConflictUsesBothEvidenceAnchorsAndCannotProposeReplacement() async throws {
        let text="Pembeli membayar tagihan dalam 8 hari.\nBatas pembayaran tagihan yang sama ditetapkan 21 hari."
        let service=agent(verdict:"conflict")
        let result=await service.review(documentText:text)
        XCTAssertEqual(result.status,"completePairs");XCTAssertEqual(result.findings.count,1)
        let f=try XCTUnwrap(result.findings.first)
        XCTAssertEqual(f.evidenceIDs.count,2);XCTAssertNil(f.replacement);XCTAssertFalse(f.actionable)
        XCTAssertTrue(f.original.contains("21 hari"));XCTAssertEqual((text as NSString).substring(with:f.range),f.original)
        XCTAssertThrowsError(try LegalReviewAgent.apply(f,revision:result.revision,to:text))
    }
    func testCompatibleReturnsNoFindingAndUncertainRemainsPartialUncached() async throws {
        let text="Pembeli membayar tagihan dalam 8 hari.\nPembeli membayar tagihan akhir dalam 21 hari."
        let compatible=await agent(verdict:"compatible").review(documentText:text)
        XCTAssertTrue(compatible.findings.isEmpty);XCTAssertEqual(compatible.status,"completePairs")
        let uncertain=agent(verdict:"uncertain")
        let first=await uncertain.review(documentText:text,fullFresh:false)
        let second=await uncertain.review(documentText:text,fullFresh:false)
        XCTAssertEqual(first.status,"partial");XCTAssertFalse(second.cacheHit);XCTAssertEqual(uncertain.modelRequestCount,2)
    }
    func testWrongPairUnknownEvidenceAndReplacementFieldAreRejected() async throws {
        let text="Pembeli membayar tagihan dalam 8 hari.\nBatas pembayaran tagihan yang sama ditetapkan 21 hari."
        for mode in ["pair","evidence","replacement","omission"] {
            let service=LegalReviewAgent(dictionaryStore:LegalDictionaryStore(entries:[])) { messages,_ in
                var rows=try self.decisions(messages,verdict:"conflict")
                if mode=="pair" { rows[0]["pair_id"]="invented" }
                if mode=="evidence" { rows[0]["evidence_ids"]=["invented","invented"] }
                if mode=="replacement" { rows[0]["replacement"]="wajib" }
                if mode=="omission" { rows=[] }
                return try self.turn("submit_review",["decisions":rows])
            }
            let result=await service.review(documentText:text)
            XCTAssertEqual(result.status,"partial",mode);XCTAssertTrue(result.findings.isEmpty,mode)
        }
    }
    func testInvalidModelOutputNeverSuppressesLocalCorrections() async throws {
        let text="Pembeli wajib wajib membayar tagihan dalam 8 hari.\nPembeli membayar tagihan dalam 21 hari."
        var local=false
        let service=LegalReviewAgent(dictionaryStore:LegalDictionaryStore(entries:[])) { _,_ in
            XCTAssertTrue(local);throw LegalReviewAgent.Failure.inputBudget
        }
        let result=await service.review(documentText:text,onLocal:{local = !$0.isEmpty})
        XCTAssertEqual(result.status,"partial");XCTAssertTrue(result.findings.contains{$0.actionable})
    }
    func testFullFreshCacheResetAndIndependentOwners() async throws {
        let text="Pembeli membayar tagihan dalam 8 hari.\nBatas pembayaran tagihan yang sama ditetapkan 21 hari."
        let one=agent(verdict:"conflict"),two=agent(verdict:"conflict")
        _=await one.review(documentText:text,fullFresh:false)
        let cached=await one.review(documentText:text,fullFresh:false)
        XCTAssertTrue(cached.cacheHit);XCTAssertEqual(cached.modelCalls,0)
        _=await one.review(documentText:text,fullFresh:true);XCTAssertEqual(one.modelRequestCount,2)
        let independent=await two.review(documentText:text,fullFresh:false);XCTAssertFalse(independent.cacheHit)
        one.clearCache();let reset=await one.review(documentText:text,fullFresh:false);XCTAssertFalse(reset.cacheHit)
    }
    func testIncrementalEqualsFreshAfterPrefixHeadingAndDefinitionChange() async throws {
        let service=agent(verdict:"conflict")
        for prefix in ["Pasal 1\n","Pengantar.\nPasal 2\n","Definisi\n"] {
            let text=prefix+"Yang dimaksud dengan Hari adalah hari kerja.\nYang dimaksud dengan Hari adalah hari kalender.\nPelaksana menjaga menjaga bukti."
            let incremental=await service.review(documentText:text,fullFresh:false)
            let fresh=await service.review(documentText:text,fullFresh:true)
            XCTAssertEqual(incremental.findings,fresh.findings);XCTAssertEqual(incremental.status,fresh.status)
            XCTAssertFalse(fresh.findings.isEmpty)
        }
    }
    func testCancellationAndTimeoutAreOwnedAndLocalFindingsSurvive() async throws {
        let text="Pembeli wajib wajib membayar tagihan dalam 8 hari.\nPembeli membayar tagihan dalam 21 hari."
        let one=LegalReviewAgent(dictionaryStore:LegalDictionaryStore(entries:[]),timeLimit:0.01) { _,_ in
            try await Task.sleep(nanoseconds:1_000_000_000);throw LegalReviewAgent.Failure.invalidCall
        }
        let result=await one.review(documentText:text)
        XCTAssertEqual(result.status,"partial");XCTAssertTrue(result.failures.contains("timeBudget"));XCTAssertFalse(result.findings.isEmpty)
        let two=await agent(verdict:"compatible").review(documentText:text)
        XCTAssertEqual(two.status,"completePairs")
    }
    func testGraphWindowLimitRemainsPartialEvenWhenNoPairs() async throws {
        let text=(0..<70).map{"Catatan nomor \($0) diterima."}.joined(separator:"\n")
        let service=agent(verdict:"compatible");let result=await service.review(documentText:text)
        XCTAssertEqual(result.status,"partial");XCTAssertTrue(result.failures.contains{$0.hasPrefix("unitLimit:")})
    }
    func testModelCannotInventArbitraryToolsOrRunUnboundedLoop() async throws {
        let service=LegalReviewAgent(dictionaryStore:LegalDictionaryStore(entries:[])) { _,_ in try self.turn("shell",["command":"ignored"]) }
        let result=await service.review(documentText:"Pembeli membayar tagihan dalam 8 hari.\nBatas pembayaran tagihan yang sama ditetapkan 21 hari.")
        XCTAssertEqual(result.modelCalls,1);XCTAssertEqual(result.status,"partial")
    }
    func testForgedActionableMeaningChangeIsRejectedAtApplyBoundary() throws {
        let text="Penerima dapat membuka arsip."
        let range=(text as NSString).range(of:"dapat")
        let forged=LegalReviewAgent.Finding(id:"invented",category:"grammar",original:"dapat",replacement:"wajib",range:range,actionable:true,reason:"invented",evidenceIDs:[])
        XCTAssertThrowsError(try LegalReviewAgent.apply(forged,revision:DocumentFingerprinting.contentSHA256(text),to:text))
    }
    func testIndonesianReduplicationIsNotBlindlyDeleted() {
        for text in ["Masing masing pihak berhak hadir.","Pihak bersama sama menjaga barang barang.","Undang undang berlaku.","Kondisi sewaktu waktu berubah."] {
            XCTAssertTrue(LegalReviewSignalPlanner().build(text).local.isEmpty,text)
        }
    }
    func testLiteralParameterDifferenceIsReadOnlyWithoutModelButConditionsRemainDistinct() async throws {
        var calls=0
        let service=LegalReviewAgent(dictionaryStore:LegalDictionaryStore(entries:[])) { _,_ in calls+=1;throw LegalReviewAgent.Failure.invalidCall }
        let literal="Penyewa melunasi tagihan dalam 4 hari.\nPenyewa melunasi tagihan yang sama dalam 6 hari."
        let result=await service.review(documentText:literal)
        XCTAssertEqual(calls,0);XCTAssertEqual(result.findings.count,1);XCTAssertFalse(result.findings[0].actionable)
        XCTAssertEqual(result.findings[0].evidenceIDs.count,2)
        for text in ["Penyewa melunasi tagihan awal dalam 4 hari.\nPenyewa melunasi tagihan akhir dalam 6 hari.","Penyewa melunasi tagihan dalam 4 hari jika barang diterima.\nPenyewa melunasi tagihan dalam 6 hari kecuali barang rusak.","Tagihan dilunasi dalam 04 hari.\nTagihan dilunasi dalam 4 hari."] {
            XCTAssertFalse(LegalReviewSignalPlanner().build(text).local.contains{$0.category=="consistency"},text)
        }
    }
    func testDifferentPhaseHeadingsCannotBecomeLiteralParameterFinding() {
        let text="## Tahap Pengujian\nPembeli membayar tagihan dalam 4 hari.\n## Tahap Operasional\nPembeli membayar tagihan dalam 6 hari."
        let plan=LegalReviewSignalPlanner().build(text)
        XCTAssertFalse(plan.local.contains{$0.category=="consistency"})
        XCTAssertFalse(plan.pairs.isEmpty)
        XCTAssertTrue(plan.units.contains{$0.heading.contains("Pengujian")})
        let legal = LegalReviewSignalPlanner().build("BAB I PENGUJIAN\nPembeli membayar tagihan dalam 4 hari.\nBAB II OPERASIONAL\nPembeli membayar tagihan dalam 6 hari.")
        XCTAssertFalse(legal.local.contains{$0.category=="consistency"})
    }
    func testLiteralFrequencyDifferenceKeepsItsTwoSources() {
        let text="Pihak mengirim rekap harian.\nPihak mengirim rekap yang sama secara mingguan."
        let plan=LegalReviewSignalPlanner().build(text)
        XCTAssertTrue(plan.local.contains{$0.category=="consistency" && $0.evidenceIDs.count==2})
        XCTAssertTrue(plan.pairs.isEmpty)
    }
    func testMeaningWithoutSharedLexicalSignalIsExplicitBlindSpot() {
        // Planner is deliberately lexical. A future paraphrase detector needs independent evidence.
        let plan=LegalReviewSignalPlanner().build("Penjual mengenkripsi arsip.\nPembeli mengompresi berkas.")
        XCTAssertTrue(plan.pairs.isEmpty)
    }
    private func agent(verdict:String)->LegalReviewAgent {
        LegalReviewAgent(dictionaryStore:LegalDictionaryStore(entries:[])) { messages,_ in try self.turn("submit_review",["decisions":self.decisions(messages,verdict:verdict)]) }
    }
    private func decisions(_ messages:[Chat.Message],verdict:String)throws->[[String:Any]] {
        let payload=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(try XCTUnwrap(messages.dropFirst().first?.content).utf8)) as? [String:Any])
        let pairs=try XCTUnwrap(payload["pairs"] as? [[String:String]])
        return pairs.map{["pair_id":$0["id"] ?? "","verdict":verdict,"evidence_ids":[$0["first_id"] ?? "",$0["second_id"] ?? ""]]}
    }
    private func turn(_ name:String,_ args:[String:Any])throws->LegalReviewAgent.Turn {
        let data=try JSONSerialization.data(withJSONObject:["function":["name":name,"arguments":args]])
        let call=try JSONDecoder().decode(ToolCall.self,from:data)
        return .init(text:"",calls:[call],stopReason:"stop",promptTokens:200,outputTokens:60)
    }
}
