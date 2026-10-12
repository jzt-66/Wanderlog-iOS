import Foundation
import CryptoKit

public enum TripPhotoInput: Sendable { case existing(String), added(Data) }
public struct PendingTripDeletion: Codable, Equatable, Sendable, Identifiable {
  public var id: String { trip.id }
  public let trip: Trip
  public let index: Int
}

public enum StoreError: LocalizedError {
  case invalidRecords, missingLegacyFile, conflictingLegacyStores, storageUnavailable
  public var errorDescription: String? {
    switch self {
    case .invalidRecords: "记录格式异常，原数据已保留。请重试或恢复备份。"
    case .missingLegacyFile: "旧记录文件缺失，原数据已保留，暂不能保存新记录。"
    case .conflictingLegacyStores: "发现多份不同的旧记录，已保留全部文件，暂不能自动导入。"
    case .storageUnavailable: "本地存储不可用，请重试。"
    }
  }
}

// No dependency on React Native. Legacy AsyncStorage files are never modified or removed.
public struct TripRepository: Sendable {
  public static let legacyKey = "wanderlog.custom-trips.v1"
  public let documents, support: URL
  public let bundleID: String
  public var directory: URL { support.appendingPathComponent(bundleID).appendingPathComponent("WanderlogNative") }
  public var recordsURL: URL { directory.appendingPathComponent("trips.json") }
  public var migrationBackupURL: URL { directory.appendingPathComponent("legacy-import.json") }
  public init(documents: URL, support: URL, bundleID: String = "com.wanderlog.travel") {
    self.documents = documents; self.support = support; self.bundleID = bundleID
  }
  public static func live() throws -> Self {
    let fm = FileManager.default
    guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first,
          let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { throw StoreError.storageUnavailable }
    return Self(documents: docs, support: support)
  }
  public func load() throws -> [Trip] {
    if FileManager.default.fileExists(atPath: recordsURL.path) { return try decode(Data(contentsOf: recordsURL)) }
    let candidates = [
      support.appendingPathComponent(bundleID).appendingPathComponent("RCTAsyncLocalStorage_V1"),
      documents.appendingPathComponent("RCTAsyncLocalStorage_V1"),
      documents.appendingPathComponent("RCTAsyncLocalStorage"),
      documents.appendingPathComponent("RCTAsyncLocalStorage_V0")
    ]
    var payloads: [Data] = []
    for folder in candidates {
      let manifestURL = folder.appendingPathComponent("manifest.json")
      guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }
      guard let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any] else { throw StoreError.invalidRecords }
      guard let value = manifest[Self.legacyKey] else { continue }
      let data: Data
      if let text = value as? String { data = Data(text.utf8) }
      else if value is NSNull {
        let file = folder.appendingPathComponent(Self.legacyFilename)
        guard FileManager.default.fileExists(atPath: file.path) else { throw StoreError.missingLegacyFile }
        data = try Data(contentsOf: file)
      } else { throw StoreError.invalidRecords }
      _ = try decode(data)
      payloads.append(data)
    }
    if let first = payloads.first {
      let records = try decode(first)
      guard try payloads.allSatisfy({ try decode($0) == records }) else { throw StoreError.conflictingLegacyStores }
      try ensureDirectory()
      // Backup must succeed before the new canonical store is established.
      if !FileManager.default.fileExists(atPath: migrationBackupURL.path) { try first.write(to: migrationBackupURL, options: .atomic) }
      try first.write(to: recordsURL, options: .atomic)
      return records
    }
    // An empty first launch still establishes the canonical store, preventing later stale import.
    try save([]); return []
  }
  public static var legacyFilename: String { Insecure.MD5.hash(data: Data(legacyKey.utf8)).map { String(format: "%02x", $0) }.joined() }
  public func decode(_ data: Data) throws -> [Trip] {
    let records = try JSONDecoder().decode([Trip].self, from: data)
    guard Set(records.map(\.id)).count == records.count else { throw StoreError.invalidRecords }
    return records
  }
  private func ensureDirectory() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
  public func save(_ records: [Trip]) throws {
    for trip in records { try trip.validate() }
    guard Set(records.map(\.id)).count == records.count else { throw StoreError.invalidRecords }
    try ensureDirectory()
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(records)
    // Keep the last successfully persisted state before each mutation.
    if FileManager.default.fileExists(atPath: recordsURL.path) {
      try Data(contentsOf: recordsURL).write(to: directory.appendingPathComponent("trips.previous.json"), options: .atomic)
    }
    try data.write(to: recordsURL, options: .atomic)
  }
  public func create(_ trip: Trip, photos: [Data], existing: [Trip]) throws -> Trip {
    guard trip.id.hasPrefix("local-"), (1...8).contains(photos.count) else { throw StoreError.invalidRecords }
    var record = trip
    var written: [URL] = []
    do {
      try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
      for (i, data) in photos.enumerated() {
        let url = documents.appendingPathComponent("wanderlog-\(trip.id)-\(i).jpg")
        guard !FileManager.default.fileExists(atPath: url.path) else { throw StoreError.invalidRecords }
        try data.write(to: url, options: .atomic); written.append(url)
      }
      record.photos = written.map(\.absoluteString)
      try save(existing + [record]); return record
    } catch {
      for url in written { try? FileManager.default.removeItem(at: url) }; throw error
    }
  }
  public func photoURL(_ value: String) -> URL? {
    guard let url = URL(string: value) else { return nil }
    if url.isFileURL, Self.ownsPhoto(filename: url.lastPathComponent), url.path.contains("/Documents/") {
      return documents.appendingPathComponent(url.lastPathComponent)
    }
    return url
  }
  public func update(_ trip: Trip, photos: [TripPhotoInput], existing: [Trip], protected: [Trip] = []) throws -> Trip {
    guard let index = existing.firstIndex(where: { $0.id == trip.id }), trip.isPersonal,
          (1...8).contains(photos.count) else { throw StoreError.invalidRecords }
    let original = existing[index]
    var record = trip
    record.extra = original.extra
    var written: [URL] = []
    do {
      try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
      record.photos = try photos.map { input in
        switch input {
        case .existing(let uri):
          guard original.photos.contains(uri) else { throw StoreError.invalidRecords }
          return uri
        case .added(let data):
          let url = documents.appendingPathComponent("wanderlog-\(trip.id)-\(UUID().uuidString.lowercased()).jpg")
          try data.write(to: url, options: .atomic); written.append(url); return url.absoluteString
        }
      }
      var records = existing; records[index] = record
      try save(records)
      removeOwnedPhotos(of: original, remaining: records + protected)
      return record
    } catch {
      for url in written { try? FileManager.default.removeItem(at: url) }; throw error
    }
  }
  private var deletionURL: URL { directory.appendingPathComponent("pending-deletion.json") }
  public func pendingDeletion(records: [Trip]) throws -> PendingTripDeletion? {
    guard FileManager.default.fileExists(atPath: deletionURL.path) else { return nil }
    let pending = try JSONDecoder().decode(PendingTripDeletion.self, from: Data(contentsOf: deletionURL))
    // A crash before removing the record, or after undo, must never delete its photos.
    if records.contains(where: { $0.id == pending.id }) { try clearDeletion(); return nil }
    return pending
  }
  public func stageDeletion(_ trip: Trip, existing: [Trip]) throws -> PendingTripDeletion {
    guard let index = existing.firstIndex(where: { $0.id == trip.id }), trip.isPersonal else { throw StoreError.invalidRecords }
    let pending = PendingTripDeletion(trip: existing[index], index: index)
    try ensureDirectory()
    try JSONEncoder().encode(pending).write(to: deletionURL, options: .atomic)
    try save(existing.filter { $0.id != trip.id })
    return pending
  }
  public func undoDeletion(_ pending: PendingTripDeletion, existing: [Trip]) throws -> [Trip] {
    guard !existing.contains(where: { $0.id == pending.id }) else { throw StoreError.invalidRecords }
    var restored = existing; restored.insert(pending.trip, at: min(max(0, pending.index), restored.count))
    try save(restored)
    // A leftover marker is harmless: pendingDeletion reconciles it against records.
    try? clearDeletion()
    return restored
  }
  public func finalizeDeletion(_ pending: PendingTripDeletion, remaining: [Trip]) throws {
    guard !remaining.contains(where: { $0.id == pending.id }) else { return }
    try clearDeletion()
    removeOwnedPhotos(of: pending.trip, remaining: remaining)
  }
  private func clearDeletion() throws {
    if FileManager.default.fileExists(atPath: deletionURL.path) { try FileManager.default.removeItem(at: deletionURL) }
  }
  public static func ownsPhoto(filename: String) -> Bool {
    filename.range(of: "^wanderlog-local-[a-zA-Z0-9-]+\\.[a-zA-Z0-9]{2,5}$", options: .regularExpression) != nil
  }
  public func removeOwnedPhotos(of removed: Trip, remaining: [Trip]) {
    let referenced = Set(remaining.flatMap(\.photos).compactMap(photoURL).map(\.standardizedFileURL))
    for value in removed.photos {
      guard let url = photoURL(value), url.isFileURL, url.deletingLastPathComponent().standardizedFileURL == documents.standardizedFileURL,
            Self.ownsPhoto(filename: url.lastPathComponent), !referenced.contains(url.standardizedFileURL) else { continue }
      try? FileManager.default.removeItem(at: url)
    }
  }
}
