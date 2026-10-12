import Foundation
import CoreGraphics

public struct AtlasPoint: Equatable, Sendable { public var x, y: Double }

public struct AtlasLabelAnchor: Sendable {
  public let id: String
  public let point: AtlasPoint
  public let width, height: Double
  public init(id: String, point: AtlasPoint, width: Double, height: Double) {
    self.id = id; self.point = point; self.width = width; self.height = height
  }
}

public enum AtlasLabelLayout {
  // Keep labels near their own pins. At crowded zoom levels unplaced labels yield
  // to tappable pins; zooming in reveals them without ambiguous distant labels.
  public static let maximumDistance = 82.0
  public static func positions(_ anchors: [AtlasLabelAnchor], viewport: CGRect) -> [String: AtlasPoint] {
    var occupied: [CGRect] = []; var result: [String: AtlasPoint] = [:]
    let pins = anchors.map { CGRect(x: $0.point.x - 12, y: $0.point.y - 12, width: 24, height: 24) }
    for anchor in anchors.sorted(by: { $0.id < $1.id }) {
      guard viewport.contains(CGPoint(x: anchor.point.x, y: anchor.point.y)) else { continue }
      let vertical = anchor.height / 2 + 18
      let offsets = [(0.0, -vertical), (0.0, vertical), (-48.0, -vertical), (48.0, -vertical),
                     (-48.0, vertical), (48.0, vertical), (0.0, -72.0), (0.0, 72.0)]
      for (dx, dy) in offsets {
        let x = min(viewport.maxX - anchor.width / 2, max(viewport.minX + anchor.width / 2, anchor.point.x + dx))
        let y = anchor.point.y + dy
        guard hypot(x - anchor.point.x, y - anchor.point.y) <= maximumDistance else { continue }
        let rect = CGRect(x: x - anchor.width / 2, y: y - anchor.height / 2, width: anchor.width, height: anchor.height)
        guard viewport.contains(rect), !pins.contains(where: { $0.intersects(rect) }),
              !occupied.contains(where: { $0.intersects(rect.insetBy(dx: -4, dy: -4)) }) else { continue }
        occupied.append(rect); result[anchor.id] = AtlasPoint(x: x, y: y); break
      }
    }
    return result
  }
}

public struct AtlasProjection: Equatable, Sendable {
  public var longitude, latitude, span: Double
  public init(longitude: Double, latitude: Double, span: Double) {
    self.longitude = MapRegion.wrap(longitude); self.latitude = min(80, max(-80, latitude)); self.span = min(360, max(4, span))
  }
  public static func fit(_ trips: [Trip], width: Double, height: Double, top: Double = 190, bottom: Double = 150) -> Self {
    let region = MapRegion.frame(trips, minimum: 100)
    let usable = max(100, height - top - bottom)
    let verticalSpan = (trips.map(\.latitude).max() ?? 45) - (trips.map(\.latitude).min() ?? 15)
    return Self(longitude: region.longitude, latitude: region.latitude, span: max(region.longitudeDelta, verticalSpan * 1.8 * max(1, width) / usable))
  }
  public func point(latitude lat: Double, longitude lon: Double, width: Double, height: Double, top: Double = 190, bottom: Double = 150) -> AtlasPoint {
    let scale = max(1, width) / span
    return AtlasPoint(x: width / 2 + MapRegion.wrap(lon - longitude) * scale,
                      y: top + max(100, height - top - bottom) / 2 + (latitude - lat) * scale)
  }
  public func panned(x: Double, y: Double, width: Double) -> Self {
    Self(longitude: longitude - x * span / max(1, width), latitude: latitude + y * span / max(1, width), span: span)
  }
  public func zoomed(_ magnification: Double) -> Self {
    Self(longitude: longitude, latitude: latitude, span: span / max(0.1, magnification))
  }
  public func region(width: Double, height: Double, top: Double = 190, bottom: Double = 150) -> MapRegion {
    MapRegion(latitude: latitude, longitude: longitude, latitudeDelta: span * max(100, height - top - bottom) / max(1, width), longitudeDelta: span)
  }
}
