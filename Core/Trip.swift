import Foundation

// Unknown legacy fields are retained when writing records, including paused cover metadata.
public enum JSONValue: Codable, Equatable, Sendable {
  case string(String), number(Double), bool(Bool), null, array([JSONValue]), object([String: JSONValue])
  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null }
    else if let v = try? c.decode(Bool.self) { self = .bool(v) }
    else if let v = try? c.decode(String.self) { self = .string(v) }
    else if let v = try? c.decode(Double.self) { self = .number(v) }
    else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
    else { self = .object(try c.decode([String: JSONValue].self)) }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .string(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .bool(let v): try c.encode(v)
    case .null: try c.encodeNil()
    case .array(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    }
  }
}

public struct Trip: Codable, Identifiable, Equatable, Sendable {
  public var id, city, country, date, title, note: String
  public var latitude, longitude: Double
  public var photos: [String]
  public var admin1, countryCode, placeName, placeId, placeSource, address, endDate: String?
  public var extra: [String: JSONValue] = [:]

  public init(id: String, city: String, country: String, date: String, title: String, note: String,
              latitude: Double, longitude: Double, photos: [String], admin1: String? = nil,
              countryCode: String? = nil, placeName: String? = nil, placeId: String? = nil,
              placeSource: String? = nil, address: String? = nil, endDate: String? = nil) {
    self.id = id; self.city = city; self.country = country; self.date = date; self.title = title; self.note = note
    self.latitude = latitude; self.longitude = longitude; self.photos = photos; self.admin1 = admin1
    self.countryCode = countryCode; self.placeName = placeName; self.placeId = placeId
    self.placeSource = placeSource; self.address = address; self.endDate = endDate
  }
  public init(from decoder: Decoder) throws {
    let fields = try [String: JSONValue](from: decoder)
    func string(_ key: String) throws -> String {
      guard case .string(let v) = fields[key] else { throw StoreError.invalidRecords }
      return v
    }
    func optional(_ key: String) throws -> String? {
      guard let field = fields[key] else { return nil }
      guard case .string(let v) = field else { throw StoreError.invalidRecords }; return v
    }
    id = try string("id"); city = try string("city"); country = try string("country")
    date = try string("date"); title = try string("title"); note = try string("note")
    guard case .number(let lat) = fields["latitude"], case .number(let lon) = fields["longitude"],
          case .array(let items) = fields["photos"] else { throw StoreError.invalidRecords }
    latitude = lat; longitude = lon
    photos = try items.map { guard case .string(let v) = $0 else { throw StoreError.invalidRecords }; return v }
    admin1 = try optional("admin1"); countryCode = try optional("countryCode"); placeName = try optional("placeName")
    placeId = try optional("placeId"); placeSource = try optional("placeSource"); address = try optional("address")
    endDate = try optional("endDate")
    extra = fields.filter { !Self.knownFields.contains($0.key) }
    try validate()
  }
  private static let knownFields: Set<String> = ["id", "city", "country", "date", "title", "note", "latitude", "longitude", "photos", "admin1", "countryCode", "placeName", "placeId", "placeSource", "address", "endDate"]
  public func encode(to encoder: Encoder) throws {
    var values = extra
    for (k, v) in ["id": id, "city": city, "country": country, "date": date, "title": title, "note": note] { values[k] = .string(v) }
    for (k, v) in ["admin1": admin1, "countryCode": countryCode, "placeName": placeName, "placeId": placeId, "placeSource": placeSource, "address": address, "endDate": endDate] {
      if let v { values[k] = .string(v) }
    }
    values["latitude"] = .number(latitude); values["longitude"] = .number(longitude)
    values["photos"] = .array(photos.map(JSONValue.string))
    try values.encode(to: encoder)
  }
  public func validate() throws {
    guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180,
          !photos.isEmpty, VisitDate.valid(date),
          endDate.map({ VisitDate.isDay(date) && VisitDate.isDay($0) && (VisitDate.normalized($0) ?? "") >= (VisitDate.normalized(date) ?? "") }) ?? true,
          placeSource.map({ ["apple", "manual", "osm"].contains($0) }) ?? true else { throw StoreError.invalidRecords }
  }
  public var isPersonal: Bool { id.hasPrefix("local-") }
  public var locationTitle: String { nonempty(placeName) ?? nonempty(city) ?? "未命名地点" }
  public var countryLabel: String { nonempty(country) ?? "未标注国家" }
  public var provinceLabel: String { nonempty(admin1) ?? "未标注地区" }
  public var cityLabel: String { nonempty(city) ?? "未标注城市" }
  public var years: [String] {
    guard let normalized = VisitDate.normalized(date), let first = Int(normalized.prefix(4)) else { return [] }
    let last = max(first, Int((VisitDate.normalized(endDate ?? date) ?? normalized).prefix(4)) ?? first)
    return (first...last).map { String(format: "%04d", $0) }
  }
  public var dateLabel: String {
    let normalized = VisitDate.normalized(date) ?? date
    let start = normalized.replacingOccurrences(of: "-", with: ".")
    guard let endDate, endDate != date else { return start }
    let end = endDate.prefix(4) == normalized.prefix(4) ? String(endDate.dropFirst(5)) : endDate
    return start + " — " + end.replacingOccurrences(of: "-", with: ".")
  }
  public var sortDate: String { VisitDate.normalized(date) ?? "" }
}

public func nonempty(_ value: String?) -> String? {
  guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }; return v
}
public func geographicKey(_ value: String) -> String {
  var text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  if text == "中国大陆" { text = "中国" }
  if text.range(of: "^[\\p{Han}]{2,}[省市]$", options: .regularExpression) != nil { text.removeLast() }
  return text
}

public enum VisitDate {
  public static func day(_ date: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
    f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
  }
  public static func isDay(_ text: String) -> Bool {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return false }
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
    f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
    guard let date = f.date(from: text), Int(text.prefix(4)) ?? 0 > 0 else { return false }
    return f.string(from: date) == text
  }
  public static func valid(_ text: String) -> Bool {
    normalized(text) != nil
  }
  public static func normalized(_ value: String) -> String? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if isDay(text) { return text }
    guard text.range(of: "^[0-9]{4}[-.](0?[1-9]|1[0-2])$", options: .regularExpression) != nil else { return nil }
    let parts = text.replacingOccurrences(of: ".", with: "-").split(separator: "-")
    return "\(parts[0])-\(String(format: "%02d", Int(parts[1])!))"
  }
  public static func error(start: String, end: String?, today: String = day(Date())) -> String? {
    guard isDay(start), isDay(end ?? start) else { return "请选择有效日期。" }
    if (end ?? start) < start { return "结束日期不能早于开始日期。" }
    if start > today || (end ?? start) > today { return "到访日期不能晚于今天。" }
    return nil
  }
}
