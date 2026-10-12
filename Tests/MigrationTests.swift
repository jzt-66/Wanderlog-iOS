import Foundation
import Testing
@testable import WanderlogCore

struct MigrationTests {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  var repository: TripRepository { TripRepository(documents: root.appendingPathComponent("Documents"), support: root.appendingPathComponent("Library/Application Support")) }
  var trip: Trip { Trip(id: "local-123", city: "温州", country: "中国", date: "2024.04", title: "散步", note: "", latitude: 28, longitude: 120, photos: ["file:///old/Containers/Data/Application/old/Documents/wanderlog-local-123-0.jpg"]) }
  func legacy(_ records: [Trip], folder: String = "current", external: Bool = false) throws -> (URL, Data) {
    let directory = folder == "current" ? repository.support.appendingPathComponent(repository.bundleID).appendingPathComponent("RCTAsyncLocalStorage_V1") : repository.documents.appendingPathComponent(folder)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let payload = try JSONEncoder().encode(records)
    let value: Any = external ? NSNull() : String(data: payload, encoding: .utf8)!
    try JSONSerialization.data(withJSONObject: [TripRepository.legacyKey: value]).write(to: directory.appendingPathComponent("manifest.json"))
    if external { try payload.write(to: directory.appendingPathComponent(TripRepository.legacyFilename)) }
    return (directory, payload)
  }
  @Test func inlineMigrationPreservesLegacyAndIsIdempotent() throws {
    let (dir, data) = try legacy([trip])
    let manifest = try Data(contentsOf: dir.appendingPathComponent("manifest.json"))
    #expect(try repository.load() == [trip])
    #expect(try Data(contentsOf: repository.migrationBackupURL) == data)
    try repository.save([])
    #expect(try repository.load().isEmpty)
    #expect(try Data(contentsOf: dir.appendingPathComponent("manifest.json")) == manifest)
  }
  @Test func externalMD5StorageMigrates() throws {
    let (dir, data) = try legacy([trip], external: true)
    #expect(try repository.load() == [trip])
    #expect(try Data(contentsOf: dir.appendingPathComponent(TripRepository.legacyFilename)) == data)
  }
  @Test func documentsLegacyFoldersMigrate() throws {
    _ = try legacy([trip], folder: "RCTAsyncLocalStorage")
    #expect(try repository.load() == [trip])
  }
  @Test func missingExternalPayloadDoesNotCreateEmptyStore() throws {
    let (dir, _) = try legacy([trip], external: true)
    try FileManager.default.removeItem(at: dir.appendingPathComponent(TripRepository.legacyFilename))
    #expect(throws: (any Error).self) { try repository.load() }
    #expect(!FileManager.default.fileExists(atPath: repository.recordsURL.path))
  }
  @Test func corruptLegacyPreserved() throws {
    let (dir, _) = try legacy([trip], external: true)
    let bad = Data("broken json".utf8)
    try bad.write(to: dir.appendingPathComponent(TripRepository.legacyFilename))
    #expect(throws: (any Error).self) { try repository.load() }
    #expect(try Data(contentsOf: dir.appendingPathComponent(TripRepository.legacyFilename)) == bad)
    #expect(!FileManager.default.fileExists(atPath: repository.recordsURL.path))
  }
  @Test func conflictingCopiesNeverSilentlyChooseOne() throws {
    _ = try legacy([trip])
    var other = trip; other.note = "另一份记录"
    _ = try legacy([other], folder: "RCTAsyncLocalStorage_V1")
    #expect(throws: (any Error).self) { try repository.load() }
    #expect(!FileManager.default.fileExists(atPath: repository.recordsURL.path))
  }
  @Test func corruptCanonicalNeverFallsBackToOldData() throws {
    _ = try legacy([trip]); _ = try repository.load()
    try Data("broken".utf8).write(to: repository.recordsURL)
    #expect(throws: (any Error).self) { try repository.load() }
    #expect(try Data(contentsOf: repository.recordsURL) == Data("broken".utf8))
  }
  @Test func pausedMetadataSurvivesSave() throws {
    var record = trip; record.extra = ["cover": .object(["path": .string("old-cover.png"), "state": .string("ready")])]
    try repository.save([record]); #expect(try repository.load() == [record])
  }
  @Test func previousCommittedVersionBackedUp() throws {
    try repository.save([trip]); let old = try Data(contentsOf: repository.recordsURL)
    try repository.save([])
    #expect(try Data(contentsOf: repository.directory.appendingPathComponent("trips.previous.json")) == old)
  }
  @Test func movedContainerPhotoResolutionDoesNotRewriteOtherURLs() {
    #expect(repository.photoURL(trip.photos[0]) == repository.documents.appendingPathComponent("wanderlog-local-123-0.jpg"))
    #expect(repository.photoURL("https://example.com/a.jpg")?.absoluteString == "https://example.com/a.jpg")
    #expect(repository.photoURL("file:///elsewhere/unrelated.jpg")?.path == "/elsewhere/unrelated.jpg")
  }
  @Test func deletionPreservesSharedAndUnownedPhotos() throws {
    try FileManager.default.createDirectory(at: repository.documents, withIntermediateDirectories: true)
    let photo = repository.photoURL(trip.photos[0])!
    try Data([1, 2, 3]).write(to: photo)
    var other = trip; other.id = "local-other"
    repository.removeOwnedPhotos(of: trip, remaining: [other])
    #expect(FileManager.default.fileExists(atPath: photo.path))
    repository.removeOwnedPhotos(of: trip, remaining: [])
    #expect(!FileManager.default.fileExists(atPath: photo.path))
  }
  @Test func invalidCoordinatesAndDatesRejected() throws {
    var bad = trip; bad.latitude = 91
    #expect(throws: (any Error).self) { try repository.save([bad]) }
    bad = trip; bad.date = "2024-02-30"
    #expect(throws: (any Error).self) { try repository.save([bad]) }
    #expect(throws: (any Error).self) { try repository.save([trip, trip]) }
  }
  @Test func photoCommitAndFailedCommitAreAtomic() throws {
    var next = trip; next.id = "local-new"; next.photos = []
    let created = try repository.create(next, photos: [Data([1,2,3])], existing: [trip])
    #expect(try repository.load() == [trip, created])
    #expect(FileManager.default.fileExists(atPath: repository.photoURL(created.photos[0])!.path))
    next.id = "local-invalid"; next.date = "2024-02-30"
    #expect(throws: (any Error).self) { try repository.create(next, photos: [Data([4,5])], existing: [trip, created]) }
    #expect(!FileManager.default.fileExists(atPath: repository.documents.appendingPathComponent("wanderlog-local-invalid-0.jpg").path))
    #expect(try repository.load() == [trip, created])
  }
  @Test func photoCommitNeverOverwritesExistingPhoto() throws {
    try FileManager.default.createDirectory(at: repository.documents, withIntermediateDirectories: true)
    let file = repository.documents.appendingPathComponent("wanderlog-local-123-0.jpg")
    try Data([7,8]).write(to: file)
    #expect(throws: (any Error).self) { try repository.create(trip, photos: [Data([9])], existing: []) }
    #expect(try Data(contentsOf: file) == Data([7,8]))
  }
  @Test func editingPreservesIdentityLegacyDatesMetadataAndOriginalBytes() throws {
    var original = trip; original.extra = ["pausedCover": .string("retained.png")]
    try FileManager.default.createDirectory(at: repository.documents, withIntermediateDirectories: true)
    let photo = repository.photoURL(original.photos[0])!; try Data([1,2,3]).write(to: photo)
    try repository.save([original])
    var edited = original; edited.title = "新标题"; edited.note = "新回忆"
    let updated = try repository.update(edited, photos: [.existing(original.photos[0]), .added(Data([4,5]))], existing: [original])
    #expect(updated.id == original.id && updated.extra == original.extra && updated.date == "2024.04")
    #expect(try Data(contentsOf: photo) == Data([1,2,3]))
    #expect(updated.photos[0] == original.photos[0])
    #expect(try repository.load() == [updated])
  }
  @Test func failedEditRollsBackNewPhotosAndLeavesOriginal() throws {
    try repository.save([trip]); var edited = trip; edited.date = "2024-02-30"
    #expect(throws: (any Error).self) { try repository.update(edited, photos: [.added(Data([1]))], existing: [trip]) }
    #expect(try repository.load() == [trip])
    #expect(try FileManager.default.contentsOfDirectory(atPath: repository.documents.path).isEmpty)
    #expect(throws: (any Error).self) { try repository.update(trip, photos: [.existing("file:///unknown.jpg")], existing: [trip]) }
  }
  @Test func deleteUndoSurvivesRelaunchWithoutTouchingPhotoBytes() throws {
    try FileManager.default.createDirectory(at: repository.documents, withIntermediateDirectories: true)
    let photo = repository.photoURL(trip.photos[0])!; try Data([7,8]).write(to: photo)
    try repository.save([trip])
    let pending = try repository.stageDeletion(trip, existing: [trip])
    #expect(try repository.load().isEmpty)
    #expect(try repository.pendingDeletion(records: repository.load()) == pending)
    #expect(try Data(contentsOf: photo) == Data([7,8]))
    #expect(try repository.undoDeletion(pending, existing: []) == [trip])
    #expect(try repository.load() == [trip])
    #expect(try repository.pendingDeletion(records: [trip]) == nil)
    #expect(try Data(contentsOf: photo) == Data([7,8]))
  }
  @Test func finalDeleteCleansOnlyUnreferencedOwnedCopies() throws {
    try FileManager.default.createDirectory(at: repository.documents, withIntermediateDirectories: true)
    let photo = repository.photoURL(trip.photos[0])!; try Data([7]).write(to: photo)
    var shared = trip; shared.id = "local-shared"
    try repository.save([trip, shared])
    let pending = try repository.stageDeletion(trip, existing: [trip, shared])
    try repository.finalizeDeletion(pending, remaining: [shared])
    #expect(FileManager.default.fileExists(atPath: photo.path))
    let last = try repository.stageDeletion(shared, existing: [shared])
    try repository.finalizeDeletion(last, remaining: [])
    #expect(!FileManager.default.fileExists(atPath: photo.path))
    #expect(try repository.pendingDeletion(records: []) == nil)
  }
  @Test func failedDeleteKeepsRecordAndReconcilesRecoveryMarker() throws {
    try repository.save([trip]); var invalid = trip; invalid.id = "local-invalid"; invalid.date = "invalid"
    #expect(throws: (any Error).self) { try repository.stageDeletion(trip, existing: [trip, invalid]) }
    #expect(try repository.load() == [trip])
    #expect(try repository.pendingDeletion(records: [trip]) == nil)
  }

  @Test func editingDatesAndReplacingPhotosCommitsAndProtectsPendingUndoReferences() throws {
    try FileManager.default.createDirectory(at: repository.documents, withIntermediateDirectories: true)
    let photo = repository.photoURL(trip.photos[0])!; try Data([1]).write(to: photo)
    var edited = trip; edited.date = "2025-01-01"; edited.endDate = "2025-01-03"
    let updated = try repository.update(edited, photos: [.added(Data([2]))], existing: [trip], protected: [trip])
    #expect(updated.date == "2025-01-01" && updated.endDate == "2025-01-03")
    #expect(try Data(contentsOf: photo) == Data([1]))
    #expect(try Data(contentsOf: repository.photoURL(updated.photos[0])!) == Data([2]))
    #expect(try repository.load() == [updated])
  }

}
