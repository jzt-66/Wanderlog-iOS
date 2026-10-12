import SwiftUI
import MapKit

struct ManualPlaceView: View {
  @Environment(\.dismiss) private var dismiss
  let selected: (Place) -> Void
  @State private var name: String
  @State private var place: Place?
  @State private var coordinate: CLLocationCoordinate2D?
  @State private var position: MapCameraPosition
  @State private var loading = false
  @State private var error: String?
  @FocusState private var nameFocused: Bool
  init(initial: Place?, selected: @escaping (Place) -> Void) {
    self.selected = selected
    _name = State(initialValue: initial?.name ?? "")
    _place = State(initialValue: initial)
    let c = initial.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    _coordinate = State(initialValue: c)
    _position = State(initialValue: .region(MKCoordinateRegion(center: c ?? CLLocationCoordinate2D(latitude: 30, longitude: 120), span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2))))
  }
  private var coordinateKey: String { coordinate.map { "\($0.latitude),\($0.longitude)" } ?? "" }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          TextField("地点名称", text: $name, prompt: Text("地点名称").foregroundStyle(Palette.muted)).focused($nameFocused).submitLabel(.done).onSubmit { nameFocused = false }
            .padding(16).background(Palette.white, in: RoundedRectangle(cornerRadius: 16))
          Text("移动地图，点击你到访的位置。").font(TypeStyle.small).foregroundStyle(Palette.muted)
          MapReader { proxy in
            Map(position: $position, interactionModes: [.pan, .zoom]) {
              if let coordinate { Marker(name.isEmpty ? "所选位置" : name, coordinate: coordinate).tint(Palette.thread) }
            }.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
              .simultaneousGesture(SpatialTapGesture().onEnded { event in
                nameFocused = false
                if let c = proxy.convert(event.location, from: .local) { coordinate = c; place = nil }
              })
          }.frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityIdentifier("manual-place-map")
          if loading { ProgressView("正在查找地址…").font(TypeStyle.small) }
          if let coordinate {
            Text(place?.subtitle.isEmpty == false ? place!.subtitle : String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
              .font(TypeStyle.small).foregroundStyle(Palette.muted)
          }
          if let error { Text(error).font(TypeStyle.small).foregroundStyle(Palette.muted) }
        }.padding(24)
      }.background(Palette.paper).scrollDismissesKeyboard(.interactively)
        .navigationTitle("自定义地点").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("完成") {
              guard let coordinate, let name = nonempty(name) else { return }
              var result = place ?? Place(id: "manual:\(coordinate.latitude),\(coordinate.longitude)", name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
              result.name = name; result.source = "manual"; result.latitude = coordinate.latitude; result.longitude = coordinate.longitude
              selected(result); dismiss()
            }.disabled(nonempty(name) == nil || coordinate == nil).accessibilityIdentifier("manual-place-confirm")
          }
        }
        .onAppear { nameFocused = true }
        .task(id: coordinateKey) {
          guard let coordinate else { return }; loading = true; error = nil
          defer { loading = false }
          do { let result = try await PlaceSearchService.reverse(coordinate); if !Task.isCancelled { place = result } }
          catch { if !Task.isCancelled { self.error = "未能获取地址，仍可用所选位置保存。" } }
        }
    }
  }
}
