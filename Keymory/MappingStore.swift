//
//  MappingStore.swift
//  Keymory
//

import Foundation

/// A remembered input source for one application.
struct AppEntry: Codable, Equatable {
    var sourceID: String
}

/// Persists the bundle-ID → input-source map as a single JSON blob in
/// UserDefaults. Entries are never evicted automatically: the spec requires
/// that an app unused for a year still restores its last layout.
final class MappingStore {
    private static let storageKey = "mappings.v1"

    private let defaults: UserDefaults
    private var entries: [String: AppEntry]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: AppEntry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    var count: Int { entries.count }

    func entry(for bundleID: String) -> AppEntry? {
        entries[bundleID]
    }

    /// Upserts the entry; skips the write entirely when the stored source is
    /// already the same, which absorbs duplicate change notifications and means
    /// merely activating an app (without changing layout) writes nothing.
    func record(sourceID: String, for bundleID: String) {
        guard entries[bundleID]?.sourceID != sourceID else { return }
        entries[bundleID] = AppEntry(sourceID: sourceID)
        save()
    }

    func removeAll() {
        entries = [:]
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
