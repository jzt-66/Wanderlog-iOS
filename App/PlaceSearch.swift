import SwiftUI
import MapKit
import CoreLocation
import Observation

private enum SearchFailure: LocalizedError {
  case timeout, unavailable, denied, notFound
  var errorDescription: String? {
    switch self {
    case .timeout: "地点搜索超时，请重试。"
    case .unavailable: "地点服务暂时不可用，请重试。"
    case .denied: "未开启定位，仍可搜索地点。"
    case .notFound: "未能获取地址，可继续手动填写。"
    }
  }
}

@MainActor private final class AppleSearchOperation {
  let search: MKLocalSearch
  var continuation: CheckedContinuation<[Place], Error>?
  var timeout: DispatchWorkItem?
  init(_ request: MKLocalSearch.Request) { search = MKLocalSearch(request: request) }
  func run() async throws -> [Place] {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        let timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(SearchFailure.timeout)) }
        self.timeout = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
        search.start { [self] response, error in
          Task { @MainActor in
            if let error { finish(.failure(error)) }
            else { finish(.success((response?.mapItems ?? []).prefix(8).map(PlaceSearchService.place))) }
          }
        }
        if Task.isCancelled { finish(.failure(CancellationError())) }
      }
    } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError())) } }
  }
  func finish(_ result: Result<[Place], Error>) {
    guard let continuation else { return }
    self.continuation = nil; timeout?.cancel(); timeout = nil; search.cancel(); continuation.resume(with: result)
  }
}

@MainActor final class OneShotLocation: NSObject, @preconcurrency CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
  private var timeout: DispatchWorkItem?
  private var requested = false
  func locate() async throws -> CLLocationCoordinate2D {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation; manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyKilometer
        let work = DispatchWorkItem { [weak self] in self?.finish(.failure(SearchFailure.timeout)) }
        timeout = work; DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: work)
        authorize()
      }
    } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError())) } }
  }
  private func authorize() {
    guard continuation != nil else { return }
    switch manager.authorizationStatus {
    case .notDetermined: manager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse, .authorizedAlways:
      if !requested { requested = true; manager.requestLocation() }
    case .denied, .restricted: finish(.failure(SearchFailure.denied))
    @unknown default: finish(.failure(SearchFailure.unavailable))
    }
  }
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { authorize() }
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last(where: { $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 120 && CLLocationCoordinate2DIsValid($0.coordinate) }) else { finish(.failure(SearchFailure.unavailable)); return }
    let c = location.coordinate
    finish(.success(CLLocationCoordinate2D(latitude: (c.latitude * 100).rounded() / 100, longitude: (c.longitude * 100).rounded() / 100)))
  }
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { finish(.failure(error)) }
  private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
    guard let continuation else { return }; self.continuation = nil
    timeout?.cancel(); timeout = nil; manager.stopUpdatingLocation(); manager.delegate = nil; continuation.resume(with: result)
  }
}

@MainActor enum PlaceSearchService {
  static func place(_ item: MKMapItem) -> Place {
    let p = item.placemark, c = p.coordinate, code = p.isoCountryCode ?? ""
    let country = code == "CN" ? "中国" : Locale(identifier: "zh_CN").localizedString(forRegionCode: code) ?? p.country ?? ""
    var seen = Set<String>()
    let address = [p.administrativeArea, p.locality, p.subLocality, p.thoroughfare, p.subThoroughfare].compactMap(nonempty).filter { seen.insert($0).inserted }.joined(separator: " · ")
    let name = item.name ?? p.name ?? ""
    var id = "apple:\(c.latitude),\(c.longitude):\(name)"
    if #available(iOS 18.0, *), let identifier = item.identifier { id = "apple:\(identifier.rawValue)" }
    return Place(id: id, name: name, city: p.locality ?? "", country: country, countryCode: code, admin1: p.administrativeArea ?? "", address: address, source: "apple", category: item.pointOfInterestCategory.map { "apple:\($0.rawValue)" }, latitude: c.latitude, longitude: c.longitude)
  }
  static func search(_ query: String, near: CLLocationCoordinate2D?) async throws -> (places: [Place], partial: Bool) {
    let intent = LandmarkIntent.match(query)
    let text = intent?.query ?? query
    let bias = PlaceRules.acceptsNearbyBias(query) ? near : nil
    async let apple = attempt { try await appleSearch(text, near: bias) }
    async let global = attempt { try await photon(text, country: intent?.country, near: bias) }
    let (a, b) = await (apple, global)
    try Task.checkCancellation()
    let all = (try? a.get()) ?? []
    let more = (try? b.get()) ?? []
    if case .failure = a, case .failure = b { throw SearchFailure.unavailable }
    let records = PlaceRules.deduplicated((all + more).filter { intent?.accepts($0) ?? true })
    return (records, a.isFailure || b.isFailure)
  }
  private static func attempt<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
    do { return .success(try await operation()) } catch { return .failure(error) }
  }
  private static func appleSearch(_ text: String, near: CLLocationCoordinate2D?) async throws -> [Place] {
    let request = MKLocalSearch.Request(); request.naturalLanguageQuery = text; request.resultTypes = [.address, .pointOfInterest]
    if let near { request.region = MKCoordinateRegion(center: near, latitudinalMeters: 30000, longitudinalMeters: 30000) }
    return try await AppleSearchOperation(request).run()
  }
  private static func photon(_ query: String, country: String?, near: CLLocationCoordinate2D?) async throws -> [Place] {
    let endpoint = Bundle.main.object(forInfoDictionaryKey: "WanderlogPhotonURL") as? String ?? "https://photon.komoot.io"
    guard var url = URLComponents(string: endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/") else { throw SearchFailure.unavailable }
    var items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "8")]
    if let country { items.append(URLQueryItem(name: "countrycode", value: country)) }
    if let near { items.append(URLQueryItem(name: "lat", value: "\(near.latitude)")); items.append(URLQueryItem(name: "lon", value: "\(near.longitude)")) }
    url.queryItems = items
    guard let address = url.url else { throw SearchFailure.unavailable }
    var request = URLRequest(url: address); request.timeoutInterval = 12; request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let features = object["features"] as? [[String: Any]] else { throw SearchFailure.unavailable }
    return features.compactMap { f in
      guard let p = f["properties"] as? [String: Any], let g = f["geometry"] as? [String: Any], g["type"] as? String == "Point",
            let c = g["coordinates"] as? [Double], c.count >= 2, let name = p["name"] as? String, !name.isEmpty,
            let kind = p["osm_type"] as? String, ["N", "W", "R"].contains(kind), let id = p["osm_id"] as? NSNumber, id.int64Value > 0 else { return nil }
      func text(_ key: String) -> String { nonempty(p[key] as? String) ?? "" }
      let city = nonempty(text("city")) ?? (text("type") == "city" ? name : "")
      let code = text("countrycode").uppercased()
      let country = code == "CN" ? "中国" : Locale(identifier: "zh_CN").localizedString(forRegionCode: code) ?? text("country")
      var seen = Set<String>()
      let address = [text("state"), city, text("district"), text("street"), text("housenumber")].filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: " · ")
      let place = Place(id: "osm:\(kind):\(id)", name: name, city: city, country: country, countryCode: code, admin1: text("state"), address: address, source: "osm", category: "\(text("osm_key")):\(text("osm_value"))", latitude: c[1], longitude: c[0])
      return place.valid ? place : nil
    }
  }
  static func reverse(_ coordinate: CLLocationCoordinate2D) async throws -> Place {
    let geocoder = CLGeocoder()
    return try await withTaskCancellationHandler {
      let marks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), preferredLocale: Locale(identifier: "zh_CN"))
      guard let mark = marks.first else { throw SearchFailure.notFound }
      var result = place(MKMapItem(placemark: MKPlacemark(placemark: mark)))
      result.id = "manual:\(coordinate.latitude),\(coordinate.longitude)"; result.source = "manual"; return result
    } onCancel: { Task { @MainActor in geocoder.cancelGeocode() } }
  }
}
private extension Result {
  var isFailure: Bool { if case .failure = self { return true }; return false }
}

@MainActor @Observable final class PlaceSearchModel {
  var results: [Place] = []
  var loading = false
  var error: String?
  var searched = false
  var partial = false
  var near: CLLocationCoordinate2D?
  var locating = false
  private var task: Task<Void, Never>?
  private var locationTask: Task<Void, Never>?
  private var generation = 0
  private var cache: [String: (Date, [Place])] = [:]
  func search(_ query: String, immediately: Bool = false) {
    cancelSearch(); results = []; error = nil; searched = false; partial = false
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.count >= 2 else { return }
    let current = generation
    task = Task {
      if !immediately { try? await Task.sleep(for: .milliseconds(900)) }
      guard !Task.isCancelled else { return }
      loading = true
      let key = text + "|\(near?.latitude ?? 0),\(near?.longitude ?? 0)"
      if let (date, cached) = cache[key], Date().timeIntervalSince(date) < 120 { results = cached; searched = true; loading = false; return }
      do {
        let result = try await PlaceSearchService.search(text, near: near)
        guard current == generation, !Task.isCancelled else { return }
        results = result.places; partial = result.partial; searched = true
        if !result.partial { if cache.count >= 20 { cache.removeAll() }; cache[key] = (Date(), results) }
      } catch { if current == generation && !Task.isCancelled { self.error = error.localizedDescription } }
      if current == generation { loading = false }
    }
  }
  func locate(query: String) {
    guard !locating else { return }; locating = true; error = nil
    locationTask = Task {
      do { near = try await OneShotLocation().locate(); if !Task.isCancelled { search(query, immediately: true) } }
      catch { if !Task.isCancelled { self.error = error.localizedDescription } }
      locating = false
    }
  }
  private func cancelSearch() { generation += 1; task?.cancel(); task = nil; loading = false }
  func stop() { cancelSearch(); locationTask?.cancel(); locationTask = nil; locating = false }
}
