import Foundation
import CoreGraphics
import Testing
@testable import WanderlogCore

struct AtlasProjectionTests {
  func trip(_ lon: Double, _ lat: Double = 35) -> Trip {
    Trip(id: "local-\(lon)", city: "", country: "", date: "2026.09", title: "", note: "", latitude: lat, longitude: lon, photos: ["file:///photo.jpg"])
  }
  @Test func portraitFitKeepsCrossContinentMarkersInsideUsableViewport() {
    let records = [trip(2.35, 48.8), trip(28.9, 41), trip(100.5, 13.7), trip(120.6, 28), trip(139.7, 35.6)]
    for (width, height) in [(390.0, 700.0), (320.0, 568.0), (1024.0, 700.0)] {
      let p = AtlasProjection.fit(records, width: width, height: height)
      for t in records {
        let point = p.point(latitude: t.latitude, longitude: t.longitude, width: width, height: height)
        #expect(point.x > 35 && point.x < width - 35)
        #expect(point.y > 190 && point.y < height - 150)
      }
    }
  }
  @Test func dateLineUsesShortArcAndPanningWraps() {
    let p = AtlasProjection.fit([trip(179), trip(-179)], width: 390, height: 700)
    let a = p.point(latitude: 35, longitude: 179, width: 390, height: 700)
    let b = p.point(latitude: 35, longitude: -179, width: 390, height: 700)
    #expect(abs(a.x - b.x) < 15)
    #expect(abs(p.panned(x: 800, y: 0, width: 390).longitude) <= 180)
  }
  @Test func gesturesMaintainFiniteBoundedProjection() {
    let p = AtlasProjection(longitude: 179, latitude: 30, span: 220)
    #expect(p.zoomed(2).span == 110)
    #expect(p.zoomed(0.01).span == 360)
    #expect(p.panned(x: 0, y: 10000, width: 390).latitude == 80)
  }
  @Test func denseLabelsStayNearPinsWithoutOverlap() {
    let viewport = CGRect(x: 12, y: 190, width: 366, height: 360)
    let anchors = (0..<18).map { index in
      AtlasLabelAnchor(id: "country-\(index)", point: AtlasPoint(x: 180 + Double(index % 4) * 7, y: 350 + Double(index / 4) * 6), width: 105, height: 44)
    }
    let positions = AtlasLabelLayout.positions(anchors, viewport: viewport)
    #expect(!positions.isEmpty)
    #expect(positions.count < anchors.count)
    var rects: [CGRect] = []
    for anchor in anchors {
      guard let p = positions[anchor.id] else { continue }
      #expect(hypot(p.x - anchor.point.x, p.y - anchor.point.y) <= AtlasLabelLayout.maximumDistance)
      let rect = CGRect(x: p.x - anchor.width / 2, y: p.y - anchor.height / 2, width: anchor.width, height: anchor.height)
      #expect(viewport.contains(rect))
      #expect(!rects.contains(where: { $0.intersects(rect) }))
      rects.append(rect)
    }
    #expect(positions == AtlasLabelLayout.positions(Array(anchors.reversed()), viewport: viewport))
  }
  @Test func labelsRespectViewportEdgesAndLargeText() {
    let viewport = CGRect(x: 12, y: 190, width: 296, height: 300)
    let anchors = [
      AtlasLabelAnchor(id: "left", point: AtlasPoint(x: 20, y: 300), width: 120, height: 64),
      AtlasLabelAnchor(id: "right", point: AtlasPoint(x: 300, y: 440), width: 120, height: 64),
      AtlasLabelAnchor(id: "offscreen", point: AtlasPoint(x: -20, y: 300), width: 120, height: 64),
      AtlasLabelAnchor(id: "too-wide", point: AtlasPoint(x: 180, y: 300), width: 400, height: 90)
    ]
    let positions = AtlasLabelLayout.positions(anchors, viewport: viewport)
    #expect(positions["left"] != nil && positions["right"] != nil)
    #expect(positions["offscreen"] == nil && positions["too-wide"] == nil)
    for a in anchors {
      if let p = positions[a.id] {
        #expect(viewport.contains(CGRect(x: p.x - a.width / 2, y: p.y - a.height / 2, width: a.width, height: a.height)))
      }
    }
  }
}
