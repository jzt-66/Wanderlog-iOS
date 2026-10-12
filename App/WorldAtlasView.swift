import SwiftUI

private struct AtlasLand {
  static let rings: [[[Double]]] = {
    guard let url = Bundle.main.url(forResource: "WorldLand", withExtension: "json"),
          let data = try? Data(contentsOf: url), let rings = try? JSONDecoder().decode([[[Double]]].self, from: data) else { return [] }
    return rings
  }()
}

struct WorldAtlasView: View {
  let trips: [Trip]
  let groups: [MapGroup]
  let fitID: UUID
  var headerBottom: CGFloat = 190
  let selected: (MapGroup) -> Void
  let changed: (MapRegion) -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var camera = AtlasProjection(longitude: 70, latitude: 30, span: 220)
  @GestureState private var translation = CGSize.zero
  @GestureState private var magnification: CGFloat = 1
  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      let visible = camera.zoomed(Double(magnification)).panned(x: translation.width, y: translation.height, width: size.width)
      let top = max(190, headerBottom - geometry.frame(in: .global).minY + 8)
      let positions = labels(visible, size: size, top: top)
      ZStack {
        Palette.paper
        Canvas { context, canvasSize in
          let p = visible
          for lon in stride(from: -180.0, through: 180.0, by: 30) {
            let a = point(p, latitude: 85, longitude: lon, size: canvasSize, top: top)
            let b = point(p, latitude: -85, longitude: lon, size: canvasSize, top: top)
            var path = Path(); path.move(to: a); path.addLine(to: b)
            context.stroke(path, with: .color(Palette.ink.opacity(0.06)), style: StrokeStyle(lineWidth: 0.6, dash: [3, 5]))
          }
          for lat in stride(from: -60.0, through: 60.0, by: 30) {
            let y = point(p, latitude: lat, longitude: p.longitude, size: canvasSize, top: top).y
            var path = Path(); path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: canvasSize.width, y: y))
            context.stroke(path, with: .color(Palette.ink.opacity(0.06)), style: StrokeStyle(lineWidth: 0.6, dash: [3, 5]))
          }
          for ring in AtlasLand.rings {
            var path = Path(); var previous: CGPoint?
            for coordinate in ring where coordinate.count >= 2 {
              let next = point(p, latitude: coordinate[1], longitude: coordinate[0], size: canvasSize, top: top)
              if let previous, abs(next.x - previous.x) < canvasSize.width * 180 / p.span { path.addLine(to: next) }
              else { path.move(to: next) }
              previous = next
            }
            context.fill(path, with: .color(Palette.soft))
            context.stroke(path, with: .color(Palette.ink.opacity(0.17)), lineWidth: 0.7)
          }
        }.accessibilityHidden(true)
        ForEach(groups) { group in
          let anchor = point(visible, latitude: group.latitude, longitude: group.longitude, size: size, top: top)
          Button { selected(group) } label: {
            Circle().fill(Palette.thread).frame(width: 12, height: 12)
              .overlay(Circle().stroke(.white, lineWidth: 2))
              .background(Circle().fill(Palette.thread.opacity(0.10)).frame(width: 24, height: 24)).padding(16)
          }.position(anchor).buttonStyle(JourneyPressStyle()).accessibilityHidden(positions[group.id] != nil)
            .accessibilityLabel("\(group.label)，\(group.trips.count) 段旅程，进入")
          if let position = positions[group.id] {
          Button { selected(group) } label: {
            HStack(spacing: 7) {
              Image(systemName: "chevron.right").font(TypeStyle.caption)
              Text(group.label).font(TypeStyle.small.weight(.medium)).fixedSize()
              Text("\(group.trips.count)").font(TypeStyle.caption).foregroundStyle(Palette.muted).monospacedDigit()
            }.padding(.horizontal, 12).frame(minHeight: labelHeight).foregroundStyle(Palette.ink).nativeGlass()
          }.buttonStyle(JourneyPressStyle()).position(position)
            .accessibilityLabel("\(group.label)，\(group.trips.count) 段旅程，进入")
          }
        }
        VStack { Spacer(); HStack { Spacer(); Link("Natural Earth", destination: URL(string: "https://www.naturalearthdata.com")!).font(TypeStyle.caption).foregroundStyle(Palette.muted).padding(14) } }
      }.clipped()
        .simultaneousGesture(DragGesture(minimumDistance: 10).updating($translation) { value, state, _ in state = value.translation }.onEnded { value in
          camera = camera.panned(x: value.translation.width, y: value.translation.height, width: size.width); changed(camera.region(width: size.width, height: size.height, top: top))
        })
        .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }.onEnded { value in
          camera = camera.zoomed(value.magnification); changed(camera.region(width: size.width, height: size.height, top: top))
        })
        .onChange(of: fitID, initial: true) { _, _ in camera = .fit(trips, width: size.width, height: size.height, top: top) }
        .onChange(of: size) { _, new in camera = .fit(trips, width: new.width, height: new.height, top: top) }
        .onChange(of: top) { _, _ in camera = .fit(trips, width: size.width, height: size.height, top: top) }
        .accessibilityIdentifier("world-atlas")
    }.ignoresSafeArea(edges: .top)
  }
  private func point(_ p: AtlasProjection, latitude: Double, longitude: Double, size: CGSize, top: CGFloat) -> CGPoint {
    let value = p.point(latitude: latitude, longitude: longitude, width: size.width, height: size.height, top: top)
    return CGPoint(x: value.x, y: value.y)
  }
  private var traits: UITraitCollection {
    UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory)
  }
  private var labelHeight: CGFloat {
    max(44, UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits).lineHeight + 20)
  }
  private func labels(_ p: AtlasProjection, size: CGSize, top: CGFloat) -> [String: CGPoint] {
    let font = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits)
    let caption = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits)
    let anchors = groups.map { group in
      let anchor = point(p, latitude: group.latitude, longitude: group.longitude, size: size, top: top)
      let textWidth = (group.label as NSString).size(withAttributes: [.font: font]).width
      let countWidth = (String(group.trips.count) as NSString).size(withAttributes: [.font: caption]).width
      return AtlasLabelAnchor(id: group.id, point: AtlasPoint(x: anchor.x, y: anchor.y),
                              width: textWidth + countWidth + caption.pointSize + 42, height: labelHeight)
    }
    return AtlasLabelLayout.positions(anchors, viewport: CGRect(x: 12, y: top, width: max(0, size.width - 24), height: max(0, size.height - top - 150)))
      .mapValues { CGPoint(x: $0.x, y: $0.y) }
  }
}

private extension DynamicTypeSize {
  var uiContentSizeCategory: UIContentSizeCategory {
    switch self {
    case .xSmall: return .extraSmall
    case .small: return .small
    case .medium: return .medium
    case .large: return .large
    case .xLarge: return .extraLarge
    case .xxLarge: return .extraExtraLarge
    case .xxxLarge: return .extraExtraExtraLarge
    case .accessibility1: return .accessibilityMedium
    case .accessibility2: return .accessibilityLarge
    case .accessibility3: return .accessibilityExtraLarge
    case .accessibility4: return .accessibilityExtraExtraLarge
    case .accessibility5: return .accessibilityExtraExtraExtraLarge
    @unknown default: return .large
    }
  }
}
