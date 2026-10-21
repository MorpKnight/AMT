import Foundation
import XCTest
@testable import AMT

@MainActor
final class LegalReviewTermIndexTests:XCTestCase {
    func testDefinedStopWordAndActorTermsRemainIndexedWhenBodiesShareNoWords() {
        for text in ["Yang dimaksud dengan Hari adalah kalender.\nHari berarti waktu kerja.","Yang dimaksud dengan Penerima adalah PT Sinar.\nPenerima adalah PT Bulan untuk Perjanjian yang sama."] {
            let plan=LegalReviewSignalPlanner().build(text)
            XCTAssertTrue(plan.pairs.contains{$0.kind=="definition"},text)
        }
    }
    func testInternalTermMatchingNormalizesWhitespaceCaseAndDiacritics() {
        let text="Yang dimaksud dengan Dáta   Publik adalah informasi terbuka.\nYang dimaksud dengan data publik adalah arsip tertutup."
        XCTAssertTrue(LegalReviewSignalPlanner().build(text).pairs.contains{$0.kind=="definition"})
    }
    func testPlainIdentityDefinitionDoesNotTriggerOperatorPairsWithItsUsages() {
        let text="Yang dimaksud dengan Informasi adalah dokumen tertulis.\nPenerima wajib menjaga Informasi."
        XCTAssertTrue(LegalReviewSignalPlanner().build(text).pairs.isEmpty)
        let normative="Yang dimaksud dengan Informasi adalah dokumen yang tidak boleh diungkapkan.\nPenerima wajib mengungkapkan Informasi."
        XCTAssertFalse(LegalReviewSignalPlanner().build(normative).pairs.isEmpty)
    }
    func testDifferentTermsAndOrdinaryMentionsDoNotBecomeDefinitionPair() {
        for text in ["Yang dimaksud dengan Laporan Awal adalah catatan ringkas.\nYang dimaksud dengan Laporan Akhir adalah arsip lengkap.","Penerima menyimpan arsip.\nPenerima menyerahkan salinan."] {
            XCTAssertFalse(LegalReviewSignalPlanner().build(text).pairs.contains{$0.kind=="definition"},text)
        }
    }
}
