import SwiftData
import XCTest
@testable import Ketsuatsu

@MainActor
final class DataStoreTests: XCTestCase {

    private struct OpenFailure: LocalizedError {
        var errorDescription: String? { "ストアを開けません（テスト）" }
    }

    private func inMemoryContainer() throws -> ModelContainer {
        try ModelContainer(for: BPRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testOpensPersistentStore() throws {
        let store = DataStore(open: { try self.inMemoryContainer() })

        XCTAssertTrue(store.isPersistent)
        XCTAssertNil(store.failureDescription)
    }

    /// ストアを開けなかったときは、開けなかったことが分かる（黙ってメモリ上で動かさない）。
    func testReportsFailureInsteadOfSilentlyRunningInMemory() {
        let store = DataStore(open: { throw OpenFailure() })

        XCTAssertFalse(store.isPersistent)
        XCTAssertEqual(store.failureDescription, "ストアを開けません（テスト）")
    }

    /// 空き容量を空けたあとなどに、もう一度開ける。開けるまでは状態が変わらない。
    func testRetryRecoversWhenStoreOpens() throws {
        var shouldFail = true
        let store = DataStore(open: {
            if shouldFail { throw OpenFailure() }
            return try self.inMemoryContainer()
        })

        store.retry()
        XCTAssertFalse(store.isPersistent)

        shouldFail = false
        store.retry()
        XCTAssertTrue(store.isPersistent)
        XCTAssertNil(store.failureDescription)
    }
}
