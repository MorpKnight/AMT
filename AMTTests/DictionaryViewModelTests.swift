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
        XCTAssertNil(viewModel.selectedEntry)
        XCTAssertTrue(viewModel.topMatches.isEmpty)
    }

    func testKnownTermStillOpensDictionaryDetail() async {
        let viewModel = DictionaryViewModel(dictionaryStore: LegalDictionaryStore())

        viewModel.lookupTerm("Data Pribadi")
        await waitForLookupToFinish(viewModel)

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.isShowingDetail)
        XCTAssertEqual(viewModel.selectedEntry?.term, "Data Pribadi")
        XCTAssertFalse(viewModel.topMatches.isEmpty)
    }

    private func waitForLookupToFinish(_ viewModel: DictionaryViewModel) async {
        for _ in 0..<100 {
            if !viewModel.isLoading { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
