import SwiftUI
import MapKit

struct JourneyMapView: View {
  @Environment(JourneyStore.self) private var store
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reducedMotion
  let focus: MapFocusRequest?
  let open: (Trip) -> Void
  let add: () -> Void
  @State private var position = MapCameraPosition.automatic
  @State private var scope = MapScope()
  @State private var previewID: String?
  @State private var previewIndex = 0
  @State private var headerBottom: CGFloat = 190
  @State private var atlasFitID = UUID()
  private var groups: [MapGroup] { MapGroup.groups(store.trips, scope: scope) }
  private var previewGroup: MapGroup? { groups.first { $0.id == previewID } }
  private var preview: Trip? {
    guard let group = previewGroup, group.trips.indices.contains(previewIndex) else { return nil }; return group.trips[previewIndex]
  }
  var body: some View {
    ZStack(alignment: .top) {
      if scope.level == .country {
        WorldAtlasView(trips: store.trips, groups: groups, fitID: atlasFitID, headerBottom: headerBottom, selected: select) { region in
          let next = MapNavigation.afterZoom(store.trips, scope: scope, region: region)
          if next != scope { navigate(next) }
        }
      } else {
      Map(position: $position, interactionModes: [.pan, .zoom]) {
        ForEach(groups) { group in
          Annotation(group.label, coordinate: CLLocationCoordinate2D(latitude: group.latitude, longitude: group.longitude), anchor: .bottom) {
            Button { select(group) } label: {
              VStack(spacing: 5) {
                HStack(spacing: 8) {
                  Text(group.label).lineLimit(1)
                  Image(systemName: group.opensPreview(at: scope.level) ? "photo" : "chevron.right").font(TypeStyle.caption)
                  Text("\(group.trips.count)").font(TypeStyle.caption).monospacedDigit().foregroundStyle(Palette.muted)
                }.font(TypeStyle.small.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 10)
                  .foregroundStyle(Palette.ink).nativeGlass()
                Circle().fill(Palette.thread).frame(width: 12, height: 12)
                  .overlay(Circle().stroke(.white, lineWidth: 2))
                  .background(Circle().fill(Palette.thread.opacity(0.10)).frame(width: 24, height: 24))
              }
            }.buttonStyle(JourneyPressStyle())
              .accessibilityLabel("\(group.label)，\(group.trips.count) 段旅程，\(group.opensPreview(at: scope.level) ? "预览" : "进入")")
          }.annotationTitles(.hidden)
        }
      }
      .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
      .ignoresSafeArea(edges: .top)
      .onMapCameraChange(frequency: .onEnd) { context in
        guard position.positionedByUser else { return }
        let r = context.region
        let next = MapNavigation.afterZoom(store.trips, scope: scope, region: MapRegion(latitude: r.center.latitude, longitude: r.center.longitude, latitudeDelta: r.span.latitudeDelta, longitudeDelta: r.span.longitudeDelta))
        if next != scope { JourneyHaptics.selection(); scope = next; previewID = nil }
      }
      }
      VStack(spacing: 14) {
        VStack(spacing: 14) {
        mapHeader
          .padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 14)
          .background { MapHeaderMaterial() }
        HStack(spacing: 8) {
          breadcrumbs
          Spacer(minLength: 0)
          Button { fit(scope) } label: { Image(systemName: "viewfinder").font(.system(size: 20)).frame(width: 44, height: 44) }
            .nativeGlass().accessibilityLabel("地图居中").disabled(store.trips.isEmpty)
        }.padding(.horizontal, 20)
        }.onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { headerBottom = $0 }
        if store.ready && store.trips.isEmpty {
          VStack(spacing: 16) {
            Image(systemName: "mappin.and.ellipse").font(.largeTitle).foregroundStyle(Palette.gold)
            Text("把第一段旅程放上地图").font(TypeStyle.title(22))
            Text("添加到访地点与照片，留下属于你的足迹。")
              .font(TypeStyle.small).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            Button(action: add) { Label("添加第一段旅程", systemImage: "plus") }
              .buttonStyle(JourneyActionStyle()).disabled(store.busy)
          }.padding(24).frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 24).accessibilityIdentifier("map-empty-state")
        }
        Spacer(minLength: 16)
        if let preview, let group = previewGroup { previewCard(preview, group: group).padding(.horizontal, 20).padding(.bottom, 16) }
      }
    }
    .onChange(of: store.trips, initial: true) { _, _ in
      if !store.trips.contains(where: scope.contains) { scope = MapScope() }
      previewID = nil; fit(scope, animated: false)
    }
    .onChange(of: focus?.id, initial: true) { _, _ in focusTrip() }
  }
  private var mapHeader: some View {
    VStack(spacing: 14) {
      ViewThatFits(in: .horizontal) {
        HStack { mapBrand; Spacer(); sampleToggle }
        VStack(alignment: .leading, spacing: 4) { mapBrand; sampleToggle }
      }
      if dynamicTypeSize.isAccessibilitySize {
        DisclosureGroup("旅程概览") {
          VStack(spacing: 10) {
            statistic(store.cityCount, "城市")
            statistic(store.countryCount, "国家 / 地区")
            statistic(store.photoCount, "照片")
          }.padding(.top, 10)
        }.font(TypeStyle.caption)
      } else {
        HStack(spacing: 0) {
          statistic(store.cityCount, "城市"); Divider().frame(height: 14)
          statistic(store.countryCount, "国家 / 地区"); Divider().frame(height: 14)
          statistic(store.photoCount, "照片")
        }
      }
    }
  }
  private var mapBrand: some View {
    HStack(spacing: 9) {
      Image(systemName: "map").font(.system(size: 22))
      Text("Wanderlog").font(TypeStyle.title(22)).lineLimit(1).minimumScaleFactor(0.5)
    }
  }
  private var sampleToggle: some View {
    Button { store.toggleSamples() } label: {
      HStack(spacing: 6) {
        Circle().fill(store.showSamples ? Palette.ink : Palette.muted).frame(width: 5, height: 5)
        Text(store.showSamples ? "包含示例旅程" : "不含示例旅程").font(TypeStyle.caption).foregroundStyle(Palette.muted).fixedSize()
      }.frame(minHeight: 44)
    }.accessibilityLabel("包含示例旅程").accessibilityValue(store.showSamples ? "开启" : "关闭")
  }
  private func statistic(_ value: Int, _ name: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(String(format: "%02d", value)).font(TypeStyle.number()).monospacedDigit()
      Text(name).font(TypeStyle.caption).foregroundStyle(Palette.muted)
    }.frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
      .accessibilityElement(children: .combine)
  }
  private var breadcrumbs: some View {
    HStack(spacing: 2) {
      if scope.level != .country {
        Button { navigate(scope.parent) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 44) }.accessibilityLabel("返回上一级")
      }
      Button("世界") { navigate(MapScope()) }.fixedSize(horizontal: true, vertical: false).padding(.horizontal, 8)
      if let country = scope.country {
        Text("/").foregroundStyle(Palette.muted)
        Button(country) { navigate(MapScope(level: .province, country: country)) }.lineLimit(1).padding(.horizontal, 5)
      }
      if let province = scope.province {
        Text("/").foregroundStyle(Palette.muted)
        Button(province) { navigate(MapScope(level: .city, country: scope.country, province: province)) }.lineLimit(1).padding(.horizontal, 5)
      }
      if let city = scope.city { Text("/").foregroundStyle(Palette.muted); Text(city).lineLimit(1).padding(.horizontal, 5) }
    }.font(TypeStyle.caption).padding(.horizontal, 5).frame(minHeight: 44).nativeGlass()
  }
  private func previewCard(_ trip: Trip, group: MapGroup) -> some View {
    VStack(spacing: 6) {
      HStack(spacing: 12) {
        Button { open(trip) } label: {
          HStack(spacing: 14) {
            JourneyPhoto(uri: trip.photos.first ?? "", fit: .fit, pixels: 400).frame(width: 76, height: 84).padding(3).background(Palette.white)
            VStack(alignment: .leading, spacing: 7) {
              HStack(spacing: 6) {
                Text(trip.locationTitle).lineLimit(1)
                if !trip.isPersonal { Text("示例").fixedSize().foregroundStyle(Palette.gold) }
              }.font(TypeStyle.caption).foregroundStyle(Palette.muted)
              Text(trip.title).font(TypeStyle.title(17)).foregroundStyle(Palette.ink).lineLimit(1)
              Text(trip.dateLabel).font(TypeStyle.caption).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
          }
        }.buttonStyle(JourneyPressStyle())
        Button { previewID = nil } label: { Image(systemName: "xmark").font(TypeStyle.small).frame(width: 44, height: 44) }.accessibilityLabel("关闭预览")
      }
      if group.trips.count > 1 {
        Divider()
        HStack {
          Button { previewIndex -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(previewIndex == 0).accessibilityLabel("上一段旅程")
          Spacer(); Text("\(previewIndex + 1) / \(group.trips.count)").font(TypeStyle.caption).monospacedDigit(); Spacer()
          Button { previewIndex += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(previewIndex >= group.trips.count - 1).accessibilityLabel("下一段旅程")
        }
      }
      if trip.placeSource == "osm" { OSMAttribution() }
    }.padding(13).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
      .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
  }
  private func select(_ group: MapGroup) {
    if !group.opensPreview(at: scope.level) {
      navigate(group.entered(from: scope.level))
    } else { JourneyHaptics.selection(); previewID = group.id; previewIndex = 0 }
  }
  private func navigate(_ next: MapScope) { if next != scope { JourneyHaptics.selection() }; scope = next; previewID = nil; fit(next) }
  private func fit(_ next: MapScope, animated: Bool = true) {
    if next.level == .country { atlasFitID = UUID(); return }
    let minimum: Double
    switch next.level { case .country: minimum = 100; case .province: minimum = 14; case .city: minimum = 1.2; case .place: minimum = 0.1 }
    let r = MapRegion.frame(store.trips.filter(next.contains), minimum: minimum)
    // MapKit fits a rect to the actual portrait or landscape viewport. Region
    // spans can be reinterpreted by aspect ratio and clip distant country pins.
    let center = MKMapPoint(CLLocationCoordinate2D(latitude: r.latitude, longitude: r.longitude))
    let north = MKMapPoint(CLLocationCoordinate2D(latitude: min(80, r.latitude + r.latitudeDelta / 2), longitude: r.longitude))
    let south = MKMapPoint(CLLocationCoordinate2D(latitude: max(-80, r.latitude - r.latitudeDelta / 2), longitude: r.longitude))
    let width = MKMapRect.world.width * r.longitudeDelta / 360
    let rect = MKMapRect(x: center.x - width / 2, y: north.y, width: width, height: max(1, south.y - north.y))
    let camera = MapCameraPosition.rect(rect)
    withAnimation(animated && !reducedMotion ? .easeInOut(duration: 0.35) : nil) { position = camera }
  }
  private func focusTrip() {
    guard let trip = focus?.trip else { return }
    scope = MapScope(level: nonempty(trip.placeName) == nil ? .city : .place, country: trip.countryLabel, province: trip.provinceLabel, city: nonempty(trip.placeName) == nil ? nil : trip.cityLabel)
    fit(scope)
    if let group = groups.first(where: { $0.trips.contains(where: { $0.id == trip.id }) }) {
      previewID = group.id; previewIndex = group.trips.firstIndex(where: { $0.id == trip.id }) ?? 0
    }
  }
}

// Maps are not scrolling lists. Keep the system material visible at rest over the
// actual full-bleed MapKit content, with its lower edge fading into the map.
private struct MapHeaderMaterial: View {
  var body: some View {
    Rectangle().fill(.regularMaterial)
      .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.82), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
      .padding(.bottom, -24).ignoresSafeArea(edges: .top)
      .allowsHitTesting(false).accessibilityHidden(true)
  }
}
