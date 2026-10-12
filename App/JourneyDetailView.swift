import SwiftUI

private struct PhotoSelection: Identifiable { let id = UUID(); let index: Int }

struct JourneyDetailView: View {
  @Environment(JourneyStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let original: Trip
  private var trip: Trip { store.personal.first { $0.id == original.id } ?? original }
  init(trip: Trip, locate: @escaping (Trip) -> Void) { original = trip; self.locate = locate }
  let locate: (Trip) -> Void
  @State private var editing: TripDraft?
  @State private var photo: PhotoSelection?
  @State private var deleting = false
  @State private var busy = false
  @State private var error: String?
  var body: some View {
    GeometryReader { _ in
      ZStack(alignment: .topTrailing) {
        Palette.paper.ignoresSafeArea()
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            hero
            VStack(alignment: .leading, spacing: 24) {
              if nonempty(trip.note) != nil { Text(trip.note).font(TypeStyle.body).lineSpacing(9).foregroundStyle(Palette.muted).textSelection(.enabled).accessibilityIdentifier("detail-note") }
              Text("照片").font(TypeStyle.title(22)).accessibilityAddTraits(.isHeader)
              PhotoMasonryLayout(spacing: 16) {
                ForEach(Array(trip.photos.enumerated()), id: \.offset) { index, uri in
                  Button { photo = PhotoSelection(index: index) } label: {
                    NaturalJourneyPhoto(uri: uri, pixels: 1000, label: "\(trip.city)第 \(index + 1) 张照片")
                      .padding(4).background(Palette.white)
                      .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                  }.buttonStyle(JourneyPressStyle()).accessibilityIdentifier("detail-photo-\(index)")
                }
              }
              Button { JourneyHaptics.selection(); locate(trip) } label: {
                HStack(spacing: 14) {
                  Image(systemName: "mappin.and.ellipse").font(.system(size: 22))
                  VStack(alignment: .leading, spacing: 6) {
                    Text(trip.locationTitle).font(TypeStyle.small.weight(.medium))
                    if let address = nonempty(trip.address) { Text(address).font(TypeStyle.caption).foregroundStyle(Palette.muted) }
                    Text("在地图上查看").font(TypeStyle.caption).foregroundStyle(Palette.muted)
                  }.frame(maxWidth: .infinity, alignment: .leading)
                  Image(systemName: "arrow.up.right")
                }.padding(18).background(Palette.white, in: RoundedRectangle(cornerRadius: 18))
              }.buttonStyle(JourneyPressStyle())
              if trip.placeSource == "osm" { OSMAttribution() }
              if store.personal.contains(where: { $0.id == trip.id }) {
                Button { editing = TripDraft(trip: trip) } label: { Label("编辑旅程", systemImage: "pencil").frame(maxWidth: .infinity, minHeight: 48) }
                  .buttonStyle(JourneyActionStyle()).disabled(busy || store.busy)
                Button(role: .destructive) { deleting = true } label: { Label("删除旅程", systemImage: "trash").frame(maxWidth: .infinity) }
                  .buttonStyle(JourneyActionStyle(destructive: true)).disabled(busy || store.busy)
              }
              if let error { ErrorNotice(message: error) }
            }.padding(24).padding(.bottom, 32)
          }
        }.clipped()
        Button { dismiss() } label: { Image(systemName: "xmark").font(TypeStyle.small.weight(.semibold)).frame(width: 44, height: 44) }
          .nativeGlass().padding(.horizontal, 22).padding(.top, 6).accessibilityLabel("关闭旅程详情").disabled(busy)
      }
    }
    .confirmationDialog("删除旅程？", isPresented: $deleting, titleVisibility: .visible) {
      Button("删除旅程及应用内照片", role: .destructive) {
        Task {
          busy = true; defer { busy = false }
          do { try await store.delete(trip); JourneyHaptics.deletion(); dismiss() }
          catch { JourneyHaptics.error(); self.error = "未能删除，记录已保留。\n\(error.localizedDescription)" }
        }
      }
      Button("取消", role: .cancel) {}
    } message: { Text("将删除“\(trip.title)”及应用内照片副本。系统相册原照片不受影响。删除后可在提示中撤销。") }
    .sheet(item: $editing) { draft in
      AddJourneyView(draft: draft) { _ in editing = nil }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    .fullScreenCover(item: $photo) { selected in PhotoViewerView(trip: trip, initial: selected.index) }
  }
  private var hero: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button { photo = PhotoSelection(index: 0) } label: {
        NaturalJourneyPhoto(uri: trip.photos.first ?? "", pixels: 2200, label: "查看原照片")
      }.buttonStyle(JourneyPressStyle()).accessibilityIdentifier("detail-hero-photo")
      VStack(alignment: .leading, spacing: 12) {
        Text([trip.country, trip.city, trip.placeName ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
          .font(TypeStyle.caption).foregroundStyle(Palette.muted).accessibilityIdentifier("detail-location")
        Text(trip.title).font(TypeStyle.title()).foregroundStyle(Palette.ink)
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 10) { heroMetadata }
          VStack(alignment: .leading, spacing: 8) { heroMetadata }
        }.font(TypeStyle.caption).foregroundStyle(Palette.muted)
      }.padding(24).padding(.bottom, 0)
    }
  }
  @ViewBuilder private var heroMetadata: some View {
    Text(trip.dateLabel).monospacedDigit()
    Label("\(trip.photos.count) 张照片", systemImage: "photo")
    if !trip.isPersonal { Text("示例").foregroundStyle(Palette.gold) }
  }
}

struct PhotoViewerView: View {
  @Environment(\.dismiss) private var dismiss
  let trip: Trip
  @State private var index: Int
  init(trip: Trip, initial: Int) { self.trip = trip; _index = State(initialValue: initial) }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("\(index + 1) / \(trip.photos.count) · \(trip.cityLabel)").font(TypeStyle.small).monospacedDigit()
        Spacer()
        Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.nativeGlass().accessibilityLabel("关闭照片")
      }.padding(.horizontal, 20).padding(.vertical, 10)
      TabView(selection: $index) {
        ForEach(Array(trip.photos.enumerated()), id: \.offset) { index, uri in
          ZoomableJourneyPhoto(uri: uri, label: "\(trip.cityLabel)第 \(index + 1) 张照片", dismissPhoto: { dismiss() }).tag(index)
        }
      }.tabViewStyle(.page(indexDisplayMode: .never))
      HStack(spacing: 30) {
        Button { index -= 1 } label: { Image(systemName: "chevron.left").frame(width: 50, height: 50) }.nativeGlass().disabled(index == 0).accessibilityLabel("上一张照片")
        Button { index += 1 } label: { Image(systemName: "chevron.right").frame(width: 50, height: 50) }.nativeGlass().disabled(index == trip.photos.count - 1).accessibilityLabel("下一张照片")
      }.padding(20)
    }.background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
      .accessibilityAction(.escape) { dismiss() }
  }
}

private struct ZoomableJourneyPhoto: View {
  @Environment(JourneyStore.self) private var store
  let uri, label: String
  let dismissPhoto: () -> Void
  @State private var loader = PhotoLoader()
  var body: some View {
    Group {
      if let image = loader.image { NativeZoomPhoto(image: image, label: label, dismissPhoto: dismissPhoto) }
      else if loader.failed { ContentUnavailableView("照片未能读取", systemImage: "photo", description: Text("原文件未改动，可稍后重试。")) }
      else { ProgressView().tint(.white) }
    }.task(id: uri) { await loader.load(uri, pixels: 3600, repository: store.repository) }
  }
}

private struct NativeZoomPhoto: UIViewRepresentable {
  let image: UIImage
  let label: String
  let dismissPhoto: () -> Void
  func makeUIView(context: Context) -> ZoomPhotoScrollView {
    let view = ZoomPhotoScrollView(); view.dismissPhoto = dismissPhoto; view.imageView.image = image; view.imageView.accessibilityLabel = label; return view
  }
  func updateUIView(_ view: ZoomPhotoScrollView, context: Context) {
    view.dismissPhoto = dismissPhoto
    if view.imageView.image !== image { view.imageView.image = image; view.zoomScale = 1; view.setNeedsLayout() }
  }
}

private final class ZoomPhotoScrollView: UIScrollView, UIScrollViewDelegate {
  var dismissPhoto: (() -> Void)?
  private var dismissalPan: UIPanGestureRecognizer!
  let imageView = UIImageView()
  private var lastSize = CGSize.zero
  override init(frame: CGRect) {
    super.init(frame: frame); delegate = self; minimumZoomScale = 1; maximumZoomScale = 4
    showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
    imageView.contentMode = .scaleAspectFit; imageView.isAccessibilityElement = true; addSubview(imageView)
    dismissalPan = UIPanGestureRecognizer(target: self, action: #selector(pullDown(_:)))
    dismissalPan.maximumNumberOfTouches = 1; dismissalPan.delegate = self; addGestureRecognizer(dismissalPan)
    panGestureRecognizer.require(toFail: dismissalPan)
    let tap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:))); tap.numberOfTapsRequired = 2; addGestureRecognizer(tap)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  override func layoutSubviews() {
    super.layoutSubviews()
    if bounds.size != lastSize, !bounds.isEmpty {
      lastSize = bounds.size; zoomScale = 1; imageView.frame = CGRect(origin: .zero, size: bounds.size); contentSize = bounds.size
    }
    centerPhoto()
  }
  func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
  func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPhoto() }
  private func centerPhoto() { imageView.center = CGPoint(x: max(bounds.width, contentSize.width) / 2, y: max(bounds.height, contentSize.height) / 2) }
  @objc private func doubleTap(_ recognizer: UITapGestureRecognizer) {
    if zoomScale > 1.1 { setZoomScale(1, animated: !UIAccessibility.isReduceMotionEnabled) }
    else {
      let point = recognizer.location(in: imageView), scale: CGFloat = 2.5
      zoom(to: CGRect(x: point.x - bounds.width / scale / 2, y: point.y - bounds.height / scale / 2, width: bounds.width / scale, height: bounds.height / scale), animated: !UIAccessibility.isReduceMotionEnabled)
    }
  }
}

extension ZoomPhotoScrollView: UIGestureRecognizerDelegate {
  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard gestureRecognizer === dismissalPan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
    let velocity = dismissalPan.velocity(in: self)
    return zoomScale <= minimumZoomScale + 0.01 && velocity.y > 0 && velocity.y > abs(velocity.x) * 1.3
  }
  @objc private func pullDown(_ gesture: UIPanGestureRecognizer) {
    let distance = max(0, gesture.translation(in: self).y)
    switch gesture.state {
    case .changed:
      if !UIAccessibility.isReduceMotionEnabled { imageView.transform = CGAffineTransform(translationX: 0, y: distance * 0.7) }
      imageView.alpha = max(0.5, 1 - distance / 700)
    case .ended:
      if distance > 100 || (distance > 35 && gesture.velocity(in: self).y > 800) { dismissPhoto?() }
      resetPullDown()
    case .cancelled, .failed: resetPullDown()
    default: break
    }
  }
  private func resetPullDown() {
    UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2) { self.imageView.transform = .identity; self.imageView.alpha = 1 }
  }
}
