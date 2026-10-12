import Foundation

public struct CityFilter: Identifiable, Equatable, Sendable {
  public var id, name, detail: String
  public var tripIDs: Set<String>
  public static func groups(_ trips: [Trip]) -> [Self] {
    func base(_ t: Trip) -> String { geographicKey(nonempty(t.country) ?? t.countryCode ?? "") + "|" + geographicKey(t.city) }
    var known: [String: Set<String>] = [:]
    for t in trips where nonempty(t.city) != nil && nonempty(t.admin1) != nil { known[base(t), default: []].insert(geographicKey(t.admin1!)) }
    var groups: [String: Self] = [:]
    for t in trips {
      let provinces = known[base(t)] ?? []
      let province = nonempty(t.admin1).map(geographicKey) ?? (provinces.count == 1 ? provinces.first! : "")
      let id = nonempty(t.city) == nil ? "unknown-city" : base(t) + "|" + province
      if groups[id] == nil {
        groups[id] = Self(id: id, name: t.cityLabel,
          detail: nonempty(t.city) == nil ? "" : [nonempty(t.country) ?? t.countryCode ?? "未标注国家", nonempty(t.admin1) ?? nonempty(province) ?? "未标注地区"].joined(separator: " · "), tripIDs: [])
      }
      groups[id]!.tripIDs.insert(t.id)
    }
    return groups.values.sorted {
      if $0.id == "unknown-city" { return false }; if $1.id == "unknown-city" { return true }
      return ($0.name + $0.detail).localizedStandardCompare($1.name + $1.detail) == .orderedAscending
    }
  }
}

public struct JourneyFilter: Equatable, Sendable {
  public var query = "", year = "all", cityID: String?
  public init() {}
  public var isActive: Bool { nonempty(query) != nil || year != "all" || cityID != nil }
  public func apply(_ trips: [Trip]) -> [Trip] {
    let ids = CityFilter.groups(trips).first { $0.id == cityID }?.tripIDs
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return trips.filter { t in
      (year == "all" || t.years.contains(year)) && (ids == nil || ids!.contains(t.id)) &&
        (text.isEmpty || [t.placeName, t.address, t.city, t.country, t.title, t.note].compactMap { $0 }.joined(separator: " ").localizedCaseInsensitiveContains(text))
    }.sorted { $0.sortDate == $1.sortDate ? $0.id < $1.id : $0.sortDate > $1.sortDate }
  }
}

public enum MapLevel: String, Sendable { case country, province, city, place }
public struct MapScope: Equatable, Sendable {
  public var level: MapLevel; public var country, province, city: String?
  public init(level: MapLevel = .country, country: String? = nil, province: String? = nil, city: String? = nil) {
    self.level = level; self.country = country; self.province = province; self.city = city
  }
  public func contains(_ t: Trip) -> Bool {
    (country == nil || geographicKey(country!) == geographicKey(t.countryLabel)) &&
    (province == nil || geographicKey(province!) == geographicKey(t.provinceLabel)) &&
    (city == nil || geographicKey(city!) == geographicKey(t.cityLabel))
  }
  public var parent: Self {
    switch level {
    case .country, .province: Self()
    case .city: Self(level: .province, country: country)
    case .place: Self(level: .city, country: country, province: province)
    }
  }
}
public struct MapRegion: Equatable, Sendable {
  public var latitude, longitude, latitudeDelta, longitudeDelta: Double
  public static func wrap(_ longitude: Double) -> Double { (longitude + 180).truncatingRemainder(dividingBy: 360) + (longitude + 180 < 0 ? 360 : 0) - 180 }
  public static func frame(_ trips: [Trip], minimum: Double = 0.3) -> Self {
    guard !trips.isEmpty else { return Self(latitude: 30, longitude: 70, latitudeDelta: 120, longitudeDelta: 150) }
    let lons = trips.map { (wrap($0.longitude) + 360).truncatingRemainder(dividingBy: 360) }.sorted()
    var gap = -1.0, start = lons[0]
    for i in lons.indices {
      let next = lons[(i + 1) % lons.count] + (i == lons.count - 1 ? 360 : 0)
      if next - lons[i] > gap { gap = next - lons[i]; start = next.truncatingRemainder(dividingBy: 360) }
    }
    let south = trips.map(\.latitude).min()!, north = trips.map(\.latitude).max()!
    let width = min(350, max(minimum, (360 - gap) * 1.6, (north - south) * 1.2))
    return Self(latitude: (south + north) / 2, longitude: wrap(start + (360 - gap) / 2), latitudeDelta: min(150, max((north - south) * 1.8, width * 1.4)), longitudeDelta: width)
  }
  public func contains(_ t: Trip) -> Bool { abs(t.latitude - latitude) <= latitudeDelta / 2 && abs(Self.wrap(t.longitude - longitude)) <= longitudeDelta / 2 }
  public func distance(_ t: Trip) -> Double { pow(t.latitude - latitude, 2) + pow(Self.wrap(t.longitude - longitude) * cos(latitude * .pi / 180), 2) }
}
public struct MapGroup: Identifiable, Sendable {
  public var id, label: String
  public var trips: [Trip]
  public var anchor: Trip { trips[0] }
  public func opensPreview(at level: MapLevel) -> Bool {
    level == .place || (level == .city && !trips.contains { nonempty($0.placeName) != nil })
  }
  public func entered(from level: MapLevel) -> MapScope {
    switch level {
    case .country: MapScope(level: .province, country: anchor.countryLabel)
    case .province: MapScope(level: .city, country: anchor.countryLabel, province: anchor.provinceLabel)
    case .city, .place: MapScope(level: .place, country: anchor.countryLabel, province: anchor.provinceLabel, city: anchor.cityLabel)
    }
  }
  public static func groups(_ trips: [Trip], scope: MapScope) -> [Self] {
    let buckets = Dictionary(grouping: trips.filter(scope.contains)) { t in
      var key = [geographicKey(t.countryLabel)]
      if scope.level != .country { key.append(geographicKey(t.provinceLabel)) }
      if scope.level == .city || scope.level == .place { key.append(geographicKey(t.cityLabel)) }
      if scope.level == .place { key.append(nonempty(t.placeName) == nil ? "legacy-city" : t.placeId ?? "\(t.placeName!):\(t.latitude),\(t.longitude)") }
      return key.joined(separator: "\u{1f}")
    }
    return buckets.map { key, items in
      let ordered = items.sorted { $0.sortDate == $1.sortDate ? $0.id < $1.id : $0.sortDate > $1.sortDate }
      let center = MapRegion.frame(items)
      let anchor = items.min { center.distance($0) < center.distance($1) }!
      let label: String
      switch scope.level {
      case .country: label = anchor.countryLabel
      case .province: label = anchor.provinceLabel
      case .city: label = anchor.cityLabel
      case .place: label = nonempty(anchor.placeName) ?? "\(anchor.cityLabel) · 城市记录"
      }
      // Display anchor remains a real stop, independent from preview ordering.
      return Self(id: key, label: label, trips: ordered, latitude: anchor.latitude, longitude: anchor.longitude)
    }.sorted { $0.id < $1.id }
  }
  public var latitude, longitude: Double
}

public enum MapNavigation {
  public static func afterZoom(_ trips: [Trip], scope: MapScope, region: MapRegion) -> MapScope {
    guard !trips.isEmpty else { return MapScope() }
    func nearest(_ records: [Trip]) -> Trip? { records.filter(region.contains).min { region.distance($0) < region.distance($1) } }
    if let country = scope.country, !trips.contains(where: { geographicKey($0.countryLabel) == geographicKey(country) }) { return MapScope() }
    if scope.level == .country {
      guard region.longitudeDelta <= 38, let t = nearest(trips) else { return scope }
      return afterZoom(trips, scope: MapScope(level: .province, country: t.countryLabel), region: region)
    }
    let countryTrips = trips.filter { scope.country == nil || geographicKey($0.countryLabel) == geographicKey(scope.country!) }
    let countryFrame = MapRegion.frame(countryTrips, minimum: 14)
    if region.longitudeDelta >= max(46, countryFrame.longitudeDelta * 1.6) { return MapScope() }
    if scope.level == .province {
      guard region.longitudeDelta < min(6, countryFrame.longitudeDelta * 0.4), let t = nearest(countryTrips) else { return scope }
      return afterZoom(trips, scope: MapScope(level: .city, country: t.countryLabel, province: t.provinceLabel), region: region)
    }
    let provinceTrips = countryTrips.filter { scope.province == nil || geographicKey($0.provinceLabel) == geographicKey(scope.province!) }
    if provinceTrips.isEmpty || region.longitudeDelta >= max(8, MapRegion.frame(provinceTrips, minimum: 1.2).longitudeDelta * 1.6) { return MapScope(level: .province, country: scope.country) }
    if scope.level == .place {
      let cityTrips = provinceTrips.filter(scope.contains)
      if cityTrips.isEmpty || region.longitudeDelta >= max(0.24, MapRegion.frame(cityTrips, minimum: 0.1).longitudeDelta * 1.6) { return scope.parent }
    } else if region.longitudeDelta < 0.16, let t = nearest(provinceTrips) {
      let next = MapScope(level: .place, country: t.countryLabel, province: t.provinceLabel, city: t.cityLabel)
      if provinceTrips.filter(next.contains).contains(where: { nonempty($0.placeName) != nil }) { return next }
    }
    return scope
  }
}
