import SwiftUI
import ImageIO

@MainActor @Observable final class PhotoLoader {
  static let cache = NSCache<NSString, UIImage>()
  var image: UIImage?
  var failed = false
  func load(_ value: String, pixels: Int, repository: TripRepository?) async {
    let cacheKey = "\(value)|\(pixels)" as NSString
    if let cached = Self.cache.object(forKey: cacheKey) { image = cached; return }
    guard let repository, let url = repository.photoURL(value) else { failed = true; return }
    do {
      let data: Data
      if url.isFileURL { data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value }
      else {
        let response = try await URLSession.shared.data(from: url)
        guard (response.1 as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true else { throw URLError(.badServerResponse) }
        data = response.0
      }
      try Task.checkCancellation()
      guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: pixels
      ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
      let decoded = UIImage(cgImage: cg)
      Self.cache.totalCostLimit = 80 * 1024 * 1024
      Self.cache.setObject(decoded, forKey: cacheKey, cost: cg.bytesPerRow * cg.height)
      image = decoded; failed = false
    } catch is CancellationError { } catch { if !Task.isCancelled { failed = true } }
  }
}

struct JourneyPhoto: View {
  @Environment(JourneyStore.self) private var store
  let uri: String
  var fit: ContentMode = .fill
  var pixels = 1400
  var label = "旅程照片"
  @State private var loader = PhotoLoader()
  var body: some View {
    GeometryReader { geometry in
      Group {
        if let image = loader.image {
          Image(uiImage: image).resizable().aspectRatio(contentMode: fit)
            .frame(width: max(0, geometry.size.width), height: max(0, geometry.size.height))
        } else {
          ZStack {
            Palette.soft
            if loader.failed { Image(systemName: "photo").foregroundStyle(Palette.muted) }
            else { ProgressView().tint(Palette.muted) }
          }
        }
      }
    }
    .clipped().accessibilityLabel(label)
    .task(id: uri) { loader.image = nil; loader.failed = false; await loader.load(uri, pixels: pixels, repository: store.repository) }
  }
}

struct PrintedPhoto: View {
  let uri: String
  var tilt: Double = -1.2
  var label = "旅程照片"
  var body: some View {
    NaturalJourneyPhoto(uri: uri, label: label)
      .padding(4).background(Palette.white)
      .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 3)
      .rotationEffect(.degrees(tilt))
  }
}

// The transformed thumbnail has the original's displayed orientation (including EXIF).
// Its intrinsic ratio drives every full photograph rather than a shared crop box.
struct NaturalJourneyPhoto: View {
  @Environment(JourneyStore.self) private var store
  let uri: String
  var pixels = 1400
  var label = "旅程照片"
  @State private var loader = PhotoLoader()
  var body: some View {
    Group {
      if let image = loader.image {
        Image(uiImage: image).resizable().scaledToFit()
      } else {
        ZStack {
          Palette.soft
          if loader.failed { Image(systemName: "photo").foregroundStyle(Palette.muted) }
          else { ProgressView().tint(Palette.muted) }
        }.aspectRatio(1, contentMode: .fit)
      }
    }.accessibilityLabel(label)
      .task(id: uri) {
        loader.image = nil; loader.failed = false
        await loader.load(uri, pixels: pixels, repository: store.repository)
      }
  }
}

struct PhotoMasonryLayout: Layout {
  var spacing: CGFloat = 16
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    arrangement(width: proposal.width ?? 320, subviews: subviews).size
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let layout = arrangement(width: bounds.width, subviews: subviews)
    for (index, origin) in layout.origins.enumerated() {
      subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                            anchor: .topLeading, proposal: ProposedViewSize(width: layout.columnWidth, height: nil))
    }
  }
  private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, columnWidth: CGFloat, origins: [CGPoint]) {
    let columnWidth = max(1, (width - spacing) / 2)
    var heights: [CGFloat] = [0, 0]; var origins: [CGPoint] = []
    for subview in subviews {
      let column = heights[0] <= heights[1] ? 0 : 1
      origins.append(CGPoint(x: CGFloat(column) * (columnWidth + spacing), y: heights[column]))
      let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
      heights[column] += size.height + spacing
    }
    return (CGSize(width: width, height: max(0, (heights.max() ?? 0) - spacing)), columnWidth, origins)
  }
}
