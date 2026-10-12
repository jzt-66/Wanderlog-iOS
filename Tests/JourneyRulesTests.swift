import Testing
@testable import WanderlogCore

struct JourneyRulesTests {
  func record(_ id: String, city: String = "温州", country: String = "中国", province: String? = "浙江省", lat: Double = 28, lon: Double = 120) -> Trip {
    Trip(id: id, city: city, country: country, date: "2024-12-30", title: "旅程", note: "咖啡", latitude: lat, longitude: lon, photos: ["a.jpg"], admin1: province)
  }
  @Test func leapDayAndCivilDateValidation() {
    #expect(VisitDate.isDay("2024-02-29")); #expect(!VisitDate.isDay("2025-02-29"))
    #expect(VisitDate.valid("2024.04")); #expect(VisitDate.valid("2024-4"))
    #expect(VisitDate.error(start: "2024-02-29", end: "2024-02-28", today: "2025-01-01") != nil)
    #expect(VisitDate.error(start: "2026-01-02", end: nil, today: "2026-01-01") != nil)
  }
  @Test func dateRangeYearFilteringAndLabel() {
    var t = record("local-1"); t.endDate = "2025-01-02"
    #expect(t.years == ["2024", "2025"]); #expect(t.dateLabel == "2024.12.30 — 2025.01.02")
    var f = JourneyFilter(); f.year = "2025"; f.query = "咖啡"
    #expect(f.apply([t]).count == 1)
    f.query = "不存在"; #expect(f.apply([t]).isEmpty)
  }
  @Test func unpaddedLegacyMonthsSortAndKeepOriginalPayload() {
    var t = record("old"); t.date = " 2024.4 "
    #expect(t.sortDate == "2024-04"); #expect(t.dateLabel == "2024.04")
    #expect(t.date == " 2024.4 "); #expect(t.years == ["2024"])
  }
  @Test func cityGroupsDistinguishAmbiguousNamesAndJoinUniqueLegacyProvince() {
    let a = record("a"), b = record("b", province: nil), c = record("c", country: "其他国家", province: "地区")
    #expect(CityFilter.groups([a, b, c]).count == 2)
    let d = record("d", province: "另一省")
    #expect(CityFilter.groups([a, b, d]).count == 3)
    #expect(geographicKey("中国大陆") == geographicKey("中国"))
    #expect(geographicKey("温州市") == geographicKey("温州"))
  }
  @Test func mapFramesAcrossAntimeridian() {
    let a = record("a", lon: 179), b = record("b", lon: -179)
    let region = MapRegion.frame([a, b])
    #expect(region.longitudeDelta < 5); #expect(region.contains(a)); #expect(region.contains(b))
  }
  @Test func mapHierarchyUsesRecordedFieldsAndRealAnchors() {
    let a = record("a"), b = record("b", city: "杭州", lat: 30, lon: 120.1)
    let countries = MapGroup.groups([a, b], scope: MapScope())
    #expect(countries.count == 1)
    let country = countries[0].entered(from: .country)
    #expect(country.level == .province)
    let provinces = MapGroup.groups([a, b], scope: country)
    let cities = MapGroup.groups([a, b], scope: provinces[0].entered(from: .province))
    #expect(cities.count == 2)
    #expect([a.latitude, b.latitude].contains(countries[0].latitude))
    #expect(MapScope(level: .place, country: "中国", province: "浙江省", city: "温州").parent.level == .city)
  }
  @Test func zoomChangesScopeWithHysteresis() {
    let t = record("a")
    var r = MapRegion.frame([t], minimum: 30)
    #expect(MapNavigation.afterZoom([t], scope: MapScope(), region: r).level == .province)
    r.longitudeDelta = 1
    #expect(MapNavigation.afterZoom([t], scope: MapScope(level: .province, country: "中国"), region: r).level == .city)
    r.longitudeDelta = 100
    #expect(MapNavigation.afterZoom([t], scope: MapScope(level: .province, country: "中国"), region: r).level == .country)
  }
  @Test func mapPinActionMatchesLegacyCityAndPlaceSemantics() {
    let legacy = record("legacy")
    let group = MapGroup.groups([legacy], scope: MapScope(level: .city))[0]
    #expect(!group.opensPreview(at: .country)); #expect(!group.opensPreview(at: .province))
    #expect(group.opensPreview(at: .city)); #expect(group.opensPreview(at: .place))
    var located = legacy; located.placeName = "公园"
    let place = MapGroup.groups([located], scope: MapScope(level: .city))[0]
    #expect(!place.opensPreview(at: .city)); #expect(place.opensPreview(at: .place))
  }

}
