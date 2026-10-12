import Foundation

public struct Place: Identifiable, Codable, Equatable, Sendable {
  public var id, name, city, country, countryCode, admin1, address, source: String
  public var category: String?
  public var latitude, longitude: Double
  public init(id: String, name: String, city: String = "", country: String = "", countryCode: String = "", admin1: String = "", address: String = "", source: String = "manual", category: String? = nil, latitude: Double, longitude: Double) {
    self.id = id; self.name = name; self.city = city; self.country = country; self.countryCode = countryCode
    self.admin1 = admin1; self.address = address; self.source = source; self.category = category; self.latitude = latitude; self.longitude = longitude
  }
  public var subtitle: String { [country, nonempty(address) ?? [city, admin1].filter { !$0.isEmpty }.joined(separator: " · ")].filter { !$0.isEmpty }.joined(separator: " · ") }
  public var valid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 && nonempty(name) != nil }
}
public struct LandmarkIntent: Sendable {
  public var aliases: [String], query: String, country: String, cities: [String], names: [String]
  public static let all: [Self] = [
    .init(aliases: ["巴黎铁塔", "埃菲尔铁塔", "艾菲尔铁塔", "巴黎埃菲尔铁塔", "法国巴黎铁塔", "Eiffel Tower", "Tour Eiffel", "Eiffel Tower Paris"], query: "Eiffel Tower Paris", country: "FR", cities: ["Paris", "巴黎"], names: ["Eiffel Tower", "Tour Eiffel", "埃菲尔铁塔", "艾菲尔铁塔", "巴黎铁塔"]),
    .init(aliases: ["卢浮宫", "巴黎卢浮宫", "Louvre", "Louvre Museum"], query: "Louvre Museum Paris", country: "FR", cities: ["Paris", "巴黎"], names: ["Louvre", "Louvre Museum", "Musée du Louvre", "卢浮宫", "卢浮宫博物馆"]),
    .init(aliases: ["大本钟", "伦敦大本钟", "Big Ben"], query: "Big Ben London", country: "GB", cities: ["London", "Westminster", "伦敦", "威斯敏斯特"], names: ["Big Ben", "Elizabeth Tower", "大本钟", "伊丽莎白塔"]),
    .init(aliases: ["自由女神像", "纽约自由女神像", "Statue of Liberty"], query: "Statue of Liberty New York", country: "US", cities: ["New York", "纽约"], names: ["Statue of Liberty", "Statue of Liberty Enlightening the World", "自由女神像"]),
    .init(aliases: ["悉尼歌剧院", "Sydney Opera House"], query: "Sydney Opera House Sydney", country: "AU", cities: ["Sydney", "悉尼"], names: ["Sydney Opera House", "悉尼歌剧院"]),
    .init(aliases: ["东京塔", "东京铁塔", "Tokyo Tower"], query: "Tokyo Tower Tokyo", country: "JP", cities: ["Tokyo", "Minato", "东京", "東京", "港区"], names: ["Tokyo Tower", "東京タワー", "东京塔", "东京铁塔"]),
    .init(aliases: ["罗马斗兽场", "罗马竞技场", "Colosseum"], query: "Colosseum Rome", country: "IT", cities: ["Rome", "Roma", "罗马"], names: ["Colosseum", "Colosseo", "罗马斗兽场", "罗马竞技场"])
  ]
  public static func normalize(_ text: String) -> String {
    text.folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined().lowercased()
  }
  public static func match(_ text: String) -> Self? { all.first { $0.aliases.contains { normalize($0) == normalize(text) } } }
  public func accepts(_ place: Place) -> Bool {
    let category = place.category ?? ""
    if category.range(of: "^(information|highway|railway|public_transport|shop|office):|^tourism:(information|hotel|hostel|guest_house|apartment)$|^amenity:(cafe|restaurant|parking|post_office|bus_station)$|^apple:.*(Hotel|PublicTransport|Restaurant|Cafe|Parking|Store|GasStation|Bank)$", options: .regularExpression) != nil { return false }
    let area = Self.normalize(nonempty(place.city) ?? [place.admin1, place.address].joined(separator: " "))
    return place.countryCode.uppercased() == country && cities.contains { area.contains(Self.normalize($0)) } && names.contains { Self.normalize($0) == Self.normalize(place.name) }
  }
}
public enum PlaceRules {
  public static func acceptsNearbyBias(_ query: String) -> Bool {
    query.range(of: "^(附近的?|周边的?|nearby\\s+)?(咖啡|咖啡店|咖啡馆|餐厅|餐馆|饭店|酒店|旅馆|超市|便利店|公园|博物馆|药店|加油站|停车场|星巴克|麦当劳|肯德基|coffee|caf[eé]s?|restaurants?|hotels?|supermarkets?|pharmac(?:y|ies)|starbucks|mcdonald'?s|kfc)(\\s+near me)?$", options: [.regularExpression, .caseInsensitive]) != nil
  }
  public static func deduplicated(_ places: [Place]) -> [Place] {
    var found: [Place] = []
    for place in places where place.valid {
      if found.contains(where: { $0.id == place.id || (LandmarkIntent.normalize($0.name) == LandmarkIntent.normalize(place.name) && distance($0, place) < 0.2) }) { continue }
      found.append(place)
    }
    return Array(found.prefix(12))
  }
  public static func distance(_ a: Place, _ b: Place) -> Double {
    let rad = Double.pi / 180
    let value = pow(sin((b.latitude - a.latitude) * rad / 2), 2) + cos(a.latitude * rad) * cos(b.latitude * rad) * pow(sin((b.longitude - a.longitude) * rad / 2), 2)
    return 12742 * asin(sqrt(min(1, max(0, value))))
  }
}
