import SwiftUI
import Observation

actor JourneyPersistence {
  let repository: TripRepository
  init(_ repository: TripRepository) { self.repository = repository }
  func load() throws -> [Trip] { try repository.load() }
  func create(_ trip: Trip, photos: [Data], existing: [Trip]) throws -> Trip {
    try repository.create(trip, photos: photos, existing: existing)
  }
  func update(_ trip: Trip, photos: [TripPhotoInput], existing: [Trip], protected: [Trip]) throws -> Trip { try repository.update(trip, photos: photos, existing: existing, protected: protected) }
  func pending(records: [Trip]) throws -> PendingTripDeletion? { try repository.pendingDeletion(records: records) }
  func delete(_ trip: Trip, existing: [Trip]) throws -> PendingTripDeletion { try repository.stageDeletion(trip, existing: existing) }
  func undo(_ pending: PendingTripDeletion, existing: [Trip]) throws -> [Trip] { try repository.undoDeletion(pending, existing: existing) }
  func finalize(_ pending: PendingTripDeletion, remaining: [Trip]) throws { try repository.finalizeDeletion(pending, remaining: remaining) }
}

@MainActor @Observable final class JourneyStore {
  private(set) var personal: [Trip] = []
  private(set) var samples: [Trip] = []
  private(set) var ready = false
  private(set) var busy = false
  private(set) var pendingDeletion: PendingTripDeletion?
  var undoError: String?
  var error: String?
  var showSamples = true
  var filter = JourneyFilter()
  let repository: TripRepository?
  private let persistence: JourneyPersistence?

  init() {
    let live = try? TripRepository.live()
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--ui-test"), let live {
      repository = Self.acceptanceRepository(live)
    } else { repository = live }
    #else
    repository = live
    #endif
    persistence = repository.map(JourneyPersistence.init)
    if let url = Bundle.main.url(forResource: "SampleTrips", withExtension: "json"),
       let data = try? Data(contentsOf: url), let trips = try? JSONDecoder().decode([Trip].self, from: data) { samples = trips }
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--ui-test-empty") { samples = []; showSamples = false }
    #endif
  }
  #if DEBUG
  // UI tests use a completely isolated data root. Release builds cannot enter this path.
  private static func acceptanceRepository(_ live: TripRepository) -> TripRepository {
    let root = live.documents.appendingPathComponent("NativeUIAcceptance")
    if ProcessInfo.processInfo.arguments.contains("--ui-test-reset") { try? FileManager.default.removeItem(at: root) }
    let repository = TripRepository(documents: root.appendingPathComponent("Documents"), support: root.appendingPathComponent("Library/Application Support"))
    if !FileManager.default.fileExists(atPath: repository.recordsURL.path) {
      do {
        try FileManager.default.createDirectory(at: repository.documents, withIntermediateDirectories: true)
        if ProcessInfo.processInfo.arguments.contains("--ui-test-empty") {
          try repository.save([]); return repository
        }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600))
        let data = renderer.jpegData(withCompressionQuality: 0.9) { context in
          UIColor(hex: "92AA98").setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
          UIColor(hex: "1D4B3C").setFill(); context.fill(CGRect(x: 0, y: 200, width: 900, height: 140))
          UIColor(hex: "E9D6AF").setFill(); context.fill(CGRect(x: 180, y: 80, width: 500, height: 440))
        }
        let photo = repository.documents.appendingPathComponent("wanderlog-local-ui-fixture-0.jpg")
        try data.write(to: photo)
        var trip = Trip(id: "local-ui-fixture", city: "温州", country: "中国", date: "2026.09", title: "旧记录迁移验收", note: "保留旧月份与原照片", latitude: 28, longitude: 120.65, photos: ["file:///old-container/Documents/\(photo.lastPathComponent)"], admin1: "浙江省")
        if ProcessInfo.processInfo.arguments.contains("--ui-test-photo-layout") {
          trip.photos = []
          for (index, size) in [CGSize(width: 600, height: 900), CGSize(width: 900, height: 600),
                                CGSize(width: 800, height: 800), CGSize(width: 500, height: 1000)].enumerated() {
            let image = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.9) { context in
              UIColor(hex: index.isMultiple(of: 2) ? "92AA98" : "E9D6AF").setFill()
              context.fill(CGRect(origin: .zero, size: size))
              UIColor(hex: "1D4B3C").setFill()
              context.fill(CGRect(x: 0, y: 0, width: size.width, height: 40))
              context.fill(CGRect(x: 0, y: size.height - 40, width: size.width, height: 40))
            }
            let file = repository.documents.appendingPathComponent("layout-\(index).jpg")
            try image.write(to: file); trip.photos.append(file.absoluteString)
          }
        }
        trip.extra = ["pausedCover": .object(["file": .string("retained.png")])]
        let payload = try JSONEncoder().encode([trip])
        let legacy = repository.support.appendingPathComponent(repository.bundleID).appendingPathComponent("RCTAsyncLocalStorage_V1")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: [TripRepository.legacyKey: NSNull()]).write(to: legacy.appendingPathComponent("manifest.json"))
        try payload.write(to: legacy.appendingPathComponent(TripRepository.legacyFilename))
      } catch { /* The normal load path reports any failure without clearing the fixture. */ }
    }
    return repository
  }
  #endif
  var trips: [Trip] { personal + (showSamples ? samples : []) }
  var visible: [Trip] { filter.apply(trips) }
  var cities: [CityFilter] { CityFilter.groups(trips) }
  var cityCount: Int { Set(trips.filter { nonempty($0.city) != nil }.map { geographicKey($0.country) + "|" + geographicKey($0.city) }).count }
  var countryCount: Int { Set(trips.map { geographicKey($0.country) }.filter { !$0.isEmpty }).count }
  var photoCount: Int { trips.reduce(0) { $0 + $1.photos.count } }
  var years: [String] { Set(trips.flatMap(\.years)).sorted(by: >) }
  func load() async {
    guard !busy else { return }; busy = true; defer { busy = false }
    guard let persistence else { error = StoreError.storageUnavailable.localizedDescription; return }
    do { personal = try await persistence.load(); pendingDeletion = try await persistence.pending(records: personal); ready = true; error = nil }
    catch { self.error = "读取失败，原数据已保留。\n\(error.localizedDescription)"; ready = false }
  }
  func create(_ trip: Trip, photos: [Data]) async throws -> Trip {
    guard ready, !busy, let persistence else { throw StoreError.storageUnavailable }
    busy = true; defer { busy = false }
    let record = try await persistence.create(trip, photos: photos, existing: personal)
    personal.append(record); filter = JourneyFilter(); return record
  }
  func update(_ trip: Trip, photos: [TripPhotoInput]) async throws -> Trip {
    guard ready, !busy, let persistence else { throw StoreError.storageUnavailable }
    busy = true; defer { busy = false }
    let record = try await persistence.update(trip, photos: photos, existing: personal, protected: pendingDeletion.map { [$0.trip] } ?? [])
    if let index = personal.firstIndex(where: { $0.id == trip.id }) { personal[index] = record }
    reconcileFilters(); return record
  }
  func delete(_ trip: Trip) async throws {
    guard ready, !busy, let persistence else { throw StoreError.storageUnavailable }
    busy = true; defer { busy = false }
    if let pendingDeletion { try await persistence.finalize(pendingDeletion, remaining: personal); self.pendingDeletion = nil }
    pendingDeletion = try await persistence.delete(trip, existing: personal)
    personal.removeAll { $0.id == trip.id }; undoError = nil; reconcileFilters()
  }
  func undoDelete() async {
    guard !busy, let pendingDeletion, let persistence else { return }
    busy = true; defer { busy = false }
    do {
      personal = try await persistence.undo(pendingDeletion, existing: personal)
      self.pendingDeletion = nil; undoError = nil; reconcileFilters()
    } catch { undoError = "撤销失败，可重试。\n\(error.localizedDescription)" }
  }
  func finalizeDelete(id: String) async {
    guard !busy, let pendingDeletion, pendingDeletion.id == id, let persistence else { return }
    busy = true; defer { busy = false }
    do { try await persistence.finalize(pendingDeletion, remaining: personal); self.pendingDeletion = nil; undoError = nil }
    catch { undoError = "照片副本清理失败，仍可撤销。" }
  }
  func toggleSamples() { showSamples.toggle(); reconcileFilters() }
  func reconcileFilters() {
    if !years.contains(filter.year) { filter.year = "all" }
    if !cities.contains(where: { $0.id == filter.cityID }) { filter.cityID = nil }
  }
}

@main struct WanderlogApp: App {
  @State private var store = JourneyStore()
  var body: some Scene {
    WindowGroup { JourneyRootView().buttonStyle(JourneyPressStyle()).environment(store).tint(Palette.ink).environment(\.locale, Locale(identifier: "zh_CN")) }
  }
}
