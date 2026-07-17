//
//  MappingStoreTests.swift
//  KeymoryTests
//

import XCTest
@testable import Keymory

@MainActor
final class MappingStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: MappingStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")
        store = MappingStore(defaults: defaults)
    }

    func testRecordAndLookup() {
        store.record(sourceID: "com.apple.keylayout.US", for: "com.google.Chrome")

        XCTAssertEqual(store.entry(for: "com.google.Chrome")?.sourceID, "com.apple.keylayout.US")
        XCTAssertEqual(store.count, 1)
        XCTAssertNil(store.entry(for: "unknown.app"))
    }

    func testRecordOverwritesPreviousSource() {
        store.record(sourceID: "com.apple.keylayout.US", for: "app.a")
        store.record(sourceID: "com.apple.keylayout.Ukrainian", for: "app.a")

        XCTAssertEqual(store.entry(for: "app.a")?.sourceID, "com.apple.keylayout.Ukrainian")
        XCTAssertEqual(store.count, 1)
    }

    func testRecordSkipsWriteWhenSourceUnchanged() {
        store.record(sourceID: "com.apple.keylayout.US", for: "app.a")
        let firstLastUsed = store.entry(for: "app.a")?.lastUsed

        store.record(sourceID: "com.apple.keylayout.US", for: "app.a")

        XCTAssertEqual(store.entry(for: "app.a")?.lastUsed, firstLastUsed)
    }

    func testTouchUpdatesLastUsedOnly() {
        store.record(sourceID: "com.apple.keylayout.US", for: "app.a")
        let firstLastUsed = store.entry(for: "app.a")!.lastUsed

        store.touch("app.a")

        let entry = store.entry(for: "app.a")!
        XCTAssertEqual(entry.sourceID, "com.apple.keylayout.US")
        XCTAssertGreaterThanOrEqual(entry.lastUsed, firstLastUsed)
    }

    func testTouchUnknownAppIsNoOp() {
        store.touch("unknown.app")

        XCTAssertEqual(store.count, 0)
    }

    func testPersistenceAcrossInstances() {
        store.record(sourceID: "com.apple.keylayout.Ukrainian", for: "app.a")
        store.record(sourceID: "com.apple.keylayout.US", for: "app.b")

        let reloaded = MappingStore(defaults: defaults)

        XCTAssertEqual(reloaded.count, 2)
        XCTAssertEqual(reloaded.entry(for: "app.a")?.sourceID, "com.apple.keylayout.Ukrainian")
        XCTAssertEqual(reloaded.entry(for: "app.b")?.sourceID, "com.apple.keylayout.US")
    }

    func testRemoveAll() {
        store.record(sourceID: "com.apple.keylayout.US", for: "app.a")

        store.removeAll()

        XCTAssertEqual(store.count, 0)
        XCTAssertEqual(MappingStore(defaults: defaults).count, 0)
    }

    func testCorruptDataFallsBackToEmpty() {
        defaults.set(Data("not json at all".utf8), forKey: "mappings.v1")

        let corrupted = MappingStore(defaults: defaults)

        XCTAssertEqual(corrupted.count, 0)
    }
}
