import SwiftUI
import PhotosUI
import MapKit
import Observation
import ImageIO

struct DraftPhoto: Identifiable {
  let id: String
  var data: Data? = nil
  var uri: String? = nil
  var input: TripPhotoInput { if let uri { return .existing(uri) }; return .added(data ?? Data()) }
}
@MainActor @Observable final class TripDraft: Identifiable {
  let id = UUID()
  var original: Trip?
  var datesChanged = false
  init(trip: Trip? = nil) {
    original = trip
    guard let trip else { return }
    title = trip.title; note = trip.note
    place = Place(id: trip.placeId ?? trip.id, name: trip.locationTitle, city: trip.city, country: trip.country,
                  countryCode: trip.countryCode ?? "", admin1: trip.admin1 ?? "", address: trip.address ?? "",
                  source: trip.placeSource ?? "manual", latitude: trip.latitude, longitude: trip.longitude)
    query = place?.name ?? ""
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
    let normalized = VisitDate.normalized(trip.date) ?? ""
    start = formatter.date(from: normalized.count == 7 ? normalized + "-01" : normalized) ?? Date()
    end = formatter.date(from: trip.endDate ?? "") ?? start; dateRange = trip.endDate != nil
    photos = trip.photos.enumerated().map { DraftPhoto(id: "existing-\($0.offset)", uri: $0.element) }
  }
  var query = ""
  var place: Place?
  var title = ""
  var note = ""
  var start = Date()
  var end = Date()
  var dateRange = true
  var photos: [DraftPhoto] = []
  var saving = false
  var error: String?
}

struct AddJourneyView: View {
  @Environment(JourneyStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Bindable var draft: TripDraft
  let saved: (Trip) -> Void
  @State private var search = PlaceSearchModel()
  @State private var manual = false
  @State private var photoItems: [PhotosPickerItem] = []
  @State private var picking = false
  @State private var importTask: Task<Void, Never>?
  @FocusState private var field: Field?
  private enum Field: Hashable { case search, title, note }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          placeSection
          section("到访日期") {
            if let original = draft.original, !VisitDate.isDay(original.date), !draft.datesChanged {
              Text("原记录：\(original.dateLabel)。修改日期后精确到日。")
                .font(TypeStyle.caption).foregroundStyle(Palette.muted)
            }
            Picker("日期类型", selection: $draft.dateRange) { Text("时间段").tag(true); Text("单日").tag(false) }.pickerStyle(.segmented)
            DatePicker(draft.dateRange ? "开始日期" : "到访日期", selection: $draft.start, in: ...Date(), displayedComponents: .date)
              .datePickerStyle(.compact).padding(.top, 6)
            if draft.dateRange {
              DatePicker("结束日期", selection: $draft.end, in: min(draft.start, Date())...Date(), displayedComponents: .date).datePickerStyle(.compact)
            }
          }
          section("标题") {
            TextField("这段旅程的名字", text: $draft.title, prompt: Text("这段旅程的名字").foregroundStyle(Palette.muted)).focused($field, equals: .title).submitLabel(.next)
              .onSubmit { field = .note }.padding(16).background(Palette.white, in: RoundedRectangle(cornerRadius: 16))
          }
          section("回忆") {
            TextField("写下当时的心情，或一个小细节（选填）", text: $draft.note, prompt: Text("写下当时的心情，或一个小细节（选填）").foregroundStyle(Palette.muted), axis: .vertical)
              .lineLimit(4...12).focused($field, equals: .note)
              .padding(16).background(Palette.white, in: RoundedRectangle(cornerRadius: 16))
          }
          section("照片", trailing: "\(draft.photos.count) / 8") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
              ForEach(Array(draft.photos.enumerated()), id: \.element.id) { index, photo in
                ZStack(alignment: .topTrailing) {
                  GeometryReader { geometry in
                    if let uri = photo.uri { JourneyPhoto(uri: uri, fit: .fit, pixels: 700).frame(width: max(0, geometry.size.width), height: 145) }
                    else if let data = photo.data, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(width: max(0, geometry.size.width), height: 145) }
                  }.frame(height: 145)
                  Button { draft.photos.removeAll { $0.id == photo.id } } label: {
                    Image(systemName: "xmark").font(TypeStyle.small).frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
                  }.accessibilityLabel("移除第 \(index + 1) 张照片")
                  if index == 0 { Text("封面").font(TypeStyle.caption).padding(6).background(.regularMaterial, in: Capsule()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(8).allowsHitTesting(false) }
                }.clipShape(RoundedRectangle(cornerRadius: 16))
              }
              if draft.photos.count < 8 {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 8 - draft.photos.count, selectionBehavior: .ordered, matching: .images) {
                  VStack(spacing: 10) {
                    if picking { ProgressView() } else { Image(systemName: "plus").font(.system(size: 22)) }
                    Text("添加照片").font(TypeStyle.small)
                  }.frame(maxWidth: .infinity, minHeight: 145).foregroundStyle(Palette.muted)
                    .background(Palette.white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                }.disabled(picking || draft.saving).accessibilityLabel("从相册添加照片")
              }
            }
            Text("仅保存在本机").font(TypeStyle.caption).foregroundStyle(Palette.muted).padding(.top, 4)
          }
        }.padding(24).padding(.bottom, 36)
          .disabled(draft.saving)
      }
      .background(Palette.paper).scrollDismissesKeyboard(.interactively)
      .navigationTitle(draft.original == nil ? "添加旅程" : "编辑旅程").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(draft.saving || picking) }
        ToolbarItem(placement: .confirmationAction) {
          Button { Task { await save() } } label: {
            if draft.saving { HStack(spacing: 6) { ProgressView(); Text("保存中") } } else { Text("保存").fontWeight(.semibold) }
          }.disabled(!store.ready || store.busy || draft.saving || picking)
            .accessibilityLabel(draft.saving ? "正在保存旅程" : "保存")
            .accessibilityHint(saveStatus ?? "保存当前旅程")
        }
      }
      .safeAreaInset(edge: .top) {
        VStack(spacing: 8) {
          if let error = draft.error { ErrorNotice(message: error) }
          if let status = saveStatus {
            Label(status, systemImage: "hourglass").font(TypeStyle.small).foregroundStyle(Palette.muted)
              .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.updatesFrequently)
          }
        }.padding(.horizontal, 24).padding(.vertical, draft.error != nil || saveStatus != nil ? 8 : 0).background(Palette.paper)
      }
      .onChange(of: draft.error) { _, value in
        if let value { JourneyHaptics.error(); UIAccessibility.post(notification: .announcement, argument: value) }
      }
      .safeAreaInset(edge: .bottom, alignment: .trailing) {
        if field != nil { Button("完成") { field = nil }.font(TypeStyle.small).padding(.horizontal, 20).frame(height: 44).nativeGlass().padding(12) }
      }
      .interactiveDismissDisabled(draft.saving || picking)
      .sheet(isPresented: $manual) {
        ManualPlaceView(initial: draft.place) { place in draft.place = place; draft.query = place.name; search.stop(); manual = false }
          .presentationDetents([.large]).presentationDragIndicator(.visible)
      }
      .onChange(of: draft.query) { _, value in
        if value != draft.place?.name { draft.place = nil; search.search(value) }
      }
      .onChange(of: draft.start) { _, date in draft.datesChanged = true; if draft.end < date { draft.end = date } }
      .onChange(of: draft.end) { _, _ in draft.datesChanged = true }
      .onChange(of: draft.dateRange) { _, _ in draft.datesChanged = true }
      .onChange(of: draft.title) { _, value in if value.count > 48 { draft.title = String(value.prefix(48)) } }
      .onChange(of: draft.note) { _, value in if value.count > 2000 { draft.note = String(value.prefix(2000)) } }
      .onChange(of: photoItems) { _, items in importPhotos(items) }
      .onDisappear { search.stop(); importTask?.cancel() }
    }
  }
  private var saveStatus: String? {
    if draft.saving { return "正在保存旅程与照片，请稍候…" }
    if picking { return "正在读取照片，完成后即可保存。" }
    if !store.ready { return "正在读取已有旅程，完成后即可保存。" }
    if store.busy { return "正在处理旅程，请稍候再保存。" }
    return nil
  }
  private var placeSection: some View {
    section("地点") {
      HStack(spacing: 10) {
        HStack {
          Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
          TextField("搜索城市、街道或地标", text: $draft.query, prompt: Text("搜索城市、街道或地标").foregroundStyle(Palette.muted)).focused($field, equals: .search).submitLabel(.search)
            .onSubmit { field = nil; search.search(draft.query, immediately: true) }
          if !draft.query.isEmpty {
            Button { draft.query = ""; draft.place = nil; search.stop() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }.accessibilityLabel("清除地点搜索")
          }
        }.padding(14).background(Palette.white, in: RoundedRectangle(cornerRadius: 16))
        Button("自定义") { field = nil; search.stop(); manual = true }.font(TypeStyle.small).frame(minHeight: 44)
      }
      HStack {
        Button {
          field = nil
          if search.near != nil { search.near = nil; search.search(draft.query, immediately: true) }
          else { search.locate(query: draft.query) }
        } label: {
          Label(search.near == nil ? "附近优先" : "已开启附近优先", systemImage: "location").font(TypeStyle.caption)
        }.disabled(search.locating).frame(minHeight: 36)
        Spacer()
        if search.loading || search.locating { ProgressView().controlSize(.small) }
      }
      if let place = draft.place {
        HStack(spacing: 12) {
          Image(systemName: "mappin.and.ellipse")
          VStack(alignment: .leading, spacing: 5) { Text(place.name); Text(place.subtitle).font(TypeStyle.caption).foregroundStyle(Palette.muted) }
          Spacer(); Image(systemName: "checkmark.circle.fill")
        }.padding(16).background(Palette.soft, in: RoundedRectangle(cornerRadius: 16))
      } else {
        VStack(spacing: 0) {
          ForEach(Array(search.results.enumerated()), id: \.element.id) { index, place in
            Button {
              draft.place = place; draft.query = place.name; field = nil; search.stop()
            } label: {
              HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                  Text(place.name).foregroundStyle(Palette.ink)
                  Text(place.subtitle).font(TypeStyle.caption).foregroundStyle(Palette.muted)
                }
                Spacer(); Image(systemName: "chevron.right").font(TypeStyle.caption)
              }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 10)
            }.buttonStyle(JourneyPressStyle())
            if index < search.results.count - 1 { Divider().overlay(Palette.line) }
          }
        }
        if search.searched && search.results.isEmpty { Text("未找到匹配地点，可修改关键词或自定义位置。").font(TypeStyle.small).foregroundStyle(Palette.muted) }
        if search.partial { Text("部分地点服务暂时不可用，已显示可用结果。").font(TypeStyle.caption).foregroundStyle(Palette.muted) }
        if let error = search.error {
          HStack { Text(error).font(TypeStyle.small); Spacer(); Button("重试") { search.search(draft.query, immediately: true) } }.foregroundStyle(Palette.muted)
        }
        if search.results.contains(where: { $0.source == "osm" }) { OSMAttribution() }
      }
    }
  }
  private func section<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack { Text(title).font(TypeStyle.small.weight(.semibold)); Spacer(); if let trailing { Text(trailing).font(TypeStyle.caption).foregroundStyle(Palette.muted) } }
      content()
    }
  }
  private func importPhotos(_ items: [PhotosPickerItem]) {
    guard !items.isEmpty else { return }
    picking = true; draft.error = nil
    importTask = Task {
      defer { picking = false; photoItems = [] }
      for item in items {
        if Task.isCancelled { return }
        let id = item.itemIdentifier ?? UUID().uuidString
        if draft.photos.contains(where: { $0.id == id }) { continue }
        do {
          guard let raw = try await item.loadTransferable(type: Data.self) else { throw StoreError.storageUnavailable }
          let data = try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(raw as CFData, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 3000] as CFDictionary), let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.9) else { throw StoreError.invalidRecords }
            return jpeg
          }.value
          guard !Task.isCancelled else { return }
          if draft.photos.count < 8 { draft.photos.append(DraftPhoto(id: id, data: data)) }
        } catch { if !Task.isCancelled { draft.error = "部分照片未能读取，请重新选择。" } }
      }
    }
  }
  private func save() async {
    guard !draft.saving else { return }; field = nil; draft.error = nil
    guard let place = draft.place, place.valid else { draft.error = "请选择地点。"; return }
    guard let title = nonempty(draft.title) else { draft.error = "请输入标题。"; return }
    let preserveDate = draft.original != nil && !draft.datesChanged
    let start = preserveDate ? draft.original!.date : VisitDate.day(draft.start)
    let end = preserveDate ? draft.original!.endDate : (draft.dateRange ? VisitDate.day(draft.end) : nil)
    if !preserveDate, let error = VisitDate.error(start: start, end: end) { draft.error = error; return }
    guard !draft.photos.isEmpty else { draft.error = "请至少添加 1 张照片。"; return }
    draft.saving = true; defer { draft.saving = false }
    var trip = Trip(id: "local-\(UUID().uuidString.lowercased())", city: place.city, country: place.country, date: start,
                    title: title, note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines), latitude: place.latitude, longitude: place.longitude,
                    photos: [], admin1: nonempty(place.admin1), countryCode: nonempty(place.countryCode), placeName: place.name,
                    placeId: place.id, placeSource: place.source, address: nonempty(place.address), endDate: end == start ? nil : end)
    do {
      let record: Trip
      if let original = draft.original {
        trip.id = original.id; trip.extra = original.extra
        if preserveDate { trip.endDate = original.endDate }
        // Preserve legacy location metadata unless the user picked a different place.
        if place.id == (original.placeId ?? original.id) {
          trip.admin1 = original.admin1; trip.countryCode = original.countryCode; trip.placeName = original.placeName
          trip.placeId = original.placeId; trip.placeSource = original.placeSource; trip.address = original.address
        }
        record = try await store.update(trip, photos: draft.photos.map(\.input))
      } else { record = try await store.create(trip, photos: draft.photos.compactMap(\.data)) }
      JourneyHaptics.success(); saved(record)
    }
    catch { draft.error = "保存失败，草稿已保留。\n\(error.localizedDescription)" }
  }
}
