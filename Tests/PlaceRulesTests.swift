import Testing
@testable import WanderlogCore

struct PlaceRulesTests {
  @Test func landmarkAliasesPreserveCountryAndNameChecks() {
    let intent = LandmarkIntent.match("埃菲尔铁塔")!
    #expect(intent.query == "Eiffel Tower Paris")
    var place = Place(id: "a", name: "Tour Eiffel", city: "Paris", countryCode: "FR", source: "osm", category: "tourism:attraction", latitude: 48.85, longitude: 2.29)
    #expect(intent.accepts(place))
    place.category = "tourism:information"; #expect(!intent.accepts(place))
    place.category = "tourism:attraction"; place.countryCode = "US"; #expect(!intent.accepts(place))
    #expect(LandmarkIntent.match("不存在的地标") == nil)
  }
  @Test func nearbyBiasLimitedToUnqualifiedCategories() {
    #expect(PlaceRules.acceptsNearbyBias("咖啡店"))
    #expect(PlaceRules.acceptsNearbyBias("starbucks"))
    #expect(!PlaceRules.acceptsNearbyBias("巴黎咖啡店"))
    #expect(!PlaceRules.acceptsNearbyBias("埃菲尔铁塔"))
  }
  @Test func duplicateProviderResultsMergeButDifferentBranchesRemain() {
    let a = Place(id: "apple:a", name: "咖啡店", latitude: 30, longitude: 120)
    let b = Place(id: "osm:b", name: "咖啡店", latitude: 30.0001, longitude: 120)
    let c = Place(id: "osm:c", name: "咖啡店", latitude: 30.1, longitude: 120)
    #expect(PlaceRules.deduplicated([a,b,c]).map(\.id) == [a.id,c.id])
  }
}
