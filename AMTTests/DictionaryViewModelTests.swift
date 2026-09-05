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

    func testKnownTermDetailSeparatesServingAlternativesFromPrimaryDefinition() async throws {
        let viewModel = DictionaryViewModel(dictionaryStore: LegalDictionaryStore())

        viewModel.lookupTerm("Data Pribadi")
        await waitForLookupToFinish(viewModel)

        let entry = try XCTUnwrap(viewModel.selectedEntry)
        let primary = try XCTUnwrap(entry.definitions.first)
        let officialAlternative = try XCTUnwrap(
            entry.contextualAlternatives.first {
                $0.reference?.referenceID == "peraturan.go.id:pp-no-71-tahun-2019"
            }
        )

        XCTAssertEqual(entry.definitions.count, 1)
        XCTAssertEqual(entry.contextualAlternatives.count, 1)
        XCTAssertEqual(primary.role, .primary)
        XCTAssertEqual(primary.reference?.referenceID, "peraturan.go.id:uu-no-27-tahun-2022")
        XCTAssertEqual(primary.provenanceLabel, "Ditemukan dalam teks peraturan")
        XCTAssertEqual(primary.verificationStatus, .machineOCRTolerantUnreviewed)
        XCTAssertFalse(primary.isActionable)
        XCTAssertTrue(primary.sources.isEmpty)
        XCTAssertTrue(primary.sourceURLs.isEmpty)
        XCTAssertEqual(officialAlternative.role, .alternative)
        XCTAssertEqual(officialAlternative.provenanceLabel, "Ditemukan dalam teks peraturan")
        XCTAssertTrue(officialAlternative.reference?.isDefinitionAuthority == true)
        XCTAssertTrue(officialAlternative.sources.isEmpty)
        XCTAssertTrue(officialAlternative.sourceURLs.isEmpty)
        XCTAssertTrue(officialAlternative.isActionable)
    }

    func testKnownTermDetailRetainsMultipleOfficialReferences() async {
        let viewModel = DictionaryViewModel(dictionaryStore: LegalDictionaryStore())

        viewModel.lookupTerm("RKL")
        await waitForLookupToFinish(viewModel)

        let enrichedDefinition = viewModel.selectedEntry?.definitions.first {
            $0.allReferences.count >= 2
        }
        let referenceIDs = Set(
            enrichedDefinition?.allReferences.compactMap(\.referenceID) ?? []
        )

        XCTAssertGreaterThanOrEqual(enrichedDefinition?.allReferences.count ?? 0, 2)
        XCTAssertTrue(referenceIDs.contains("peraturan.go.id:pp-no-12-tahun-2020"))
        XCTAssertTrue(referenceIDs.contains("peraturan.go.id:pp-no-27-tahun-2012"))
    }

    func testCorpusSummaryIsAvailableToDictionaryPresentation() {
        let viewModel = DictionaryViewModel(dictionaryStore: LegalDictionaryStore())

        XCTAssertTrue(viewModel.corpusSummary.isEnriched)
        XCTAssertEqual(viewModel.corpusSummary.sourceDatasetView, "dictionary-official")
        XCTAssertTrue(viewModel.corpusSummary.sourceNames.isEmpty)
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
