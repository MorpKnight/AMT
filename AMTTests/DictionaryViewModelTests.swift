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
