import Foundation
import XCTest
@testable import AMT

@MainActor
final class DictionaryViewModelTests: XCTestCase {
    func testUnknownTermDoesNotCreateSyntheticDetailResult() async {
        let viewModel = DictionaryViewModel(dictionaryStore: LegalDictionaryStore())

        viewModel.lookupTerm("justifikasi")
        await waitForLookupToFinish(viewModel)

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isShowingDetail)
        XCTAssertTrue(viewModel.isNotFound)
        XCTAssertNil(viewModel.selectedEntry)
        XCTAssertTrue(viewModel.topMatches.isEmpty)
    }

    func testKnownTermStillOpensDictionaryDetail() async {
        let viewModel = DictionaryViewModel(dictionaryStore: LegalDictionaryStore())

        viewModel.lookupTerm("Data Pribadi")
        await waitForLookupToFinish(viewModel)

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isNotFound)
        XCTAssertFalse(viewModel.topMatches.isEmpty)
    }

    func testKnownTermDetailRetainsMultipleOfficialReferences() async {
        let viewModel = DictionaryViewModel(dictionaryStore: LegalDictionaryStore())

        viewModel.lookupTerm("Pelayanan Terpadu Satu Pintu")
        await waitForLookupToFinish(viewModel)

        let enrichedDefinition = viewModel.selectedEntry?.definitions.first {
            $0.allReferences.count >= 2
        }
        let referenceIDs = Set(
            enrichedDefinition?.allReferences.compactMap(\.referenceID) ?? []
        )

        XCTAssertGreaterThanOrEqual(enrichedDefinition?.allReferences.count ?? 0, 2)
        XCTAssertTrue(referenceIDs.contains("peraturan.go.id:pp-no-1-tahun-2020"))
        XCTAssertTrue(referenceIDs.contains("peraturan.go.id:pp-no-64-tahun-2016"))
    }

    func testCorpusSummaryIsAvailableToDictionaryPresentation() {
        let viewModel = DictionaryViewModel(dictionaryStore: LegalDictionaryStore())

        XCTAssertTrue(viewModel.corpusSummary.isEnriched)
        XCTAssertEqual(viewModel.corpusSummary.sourceDatasetView, "combined-deduplicated")
    }

    func testPopularTermsCountIsThree() async {
        let viewModel = DictionaryViewModel(dictionaryStore: LegalDictionaryStore())
        XCTAssertEqual(viewModel.popularTerms.count, 3)
    }

    func testRefreshPopularTermsUpdatesTerms() async {
        let viewModel = DictionaryViewModel(dictionaryStore: LegalDictionaryStore())
        XCTAssertEqual(viewModel.popularTerms.count, 3)

        viewModel.refreshPopularTerms()
        XCTAssertEqual(viewModel.popularTerms.count, 3)
    }

    private func waitForLookupToFinish(_ viewModel: DictionaryViewModel) async {
        for _ in 0..<100 {
            if !viewModel.isLoading { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
