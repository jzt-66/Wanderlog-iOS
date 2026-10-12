import SwiftUI

// This palette and the collage treatments belong only to the journey list.
private enum JournalStyle {
  static let paper = Color(uiColor: UIColor(hex: "F8F6F1"))
  static let ink = Color(uiColor: UIColor(hex: "2C2C2A"))
  static let muted = Color(uiColor: UIColor(hex: "73736D"))
  static let accent = Color(uiColor: UIColor(hex: "43594B"))
  static let line = ink.opacity(0.16)
  static let mono = Font.system(.caption, design: .monospaced)
  static let coordinateSpace = "journey-journal-viewport"
  static func tilt(_ index: Int) -> Double { index.isMultiple(of: 2) ? -1.5 : 1 }
}

struct JourneyListView: View {
  @Environment(JourneyStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reducedMotion
  @State private var searching = false
  @State private var filtering = false
  @State private var visibleFasteners: Set<JournalFastener.Kind> = [.tape, .clip]
  @FocusState private var searchFocused: Bool
  let open: (Trip) -> Void
  let add: () -> Void
  var body: some View {
    @Bindable var store = store
    ZStack {
      JournalStyle.paper.ignoresSafeArea()
      GeometryReader { viewport in
        ScrollViewReader { reader in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
              HStack {
                Text("\(store.visible.count) 段旅程 · \(store.visible.reduce(0) { $0 + $1.photos.count }) 张照片")
                Spacer(minLength: 12)
                if store.filter.isActive { Button("清除筛选") { store.filter = JourneyFilter() }.foregroundStyle(JournalStyle.accent) }
              }.font(JournalStyle.mono).foregroundStyle(JournalStyle.muted).id("first-journey")
              ForEach(Array(store.visible.enumerated()), id: \.element.id) { index, trip in
                Button { open(trip) } label: {
                  JourneyCard(trip: trip, index: index, showsFastener: visibleFasteners.contains(JournalFastener.Kind.at(index)))
                }
                .buttonStyle(JournalCardPressStyle(tilt: JournalStyle.tilt(index)))
                .accessibilityIdentifier("journey-card-\(trip.id)")
              }
              if store.visible.isEmpty {
                VStack(spacing: 20) {
                  Text(store.filter.isActive ? "无匹配旅程" : "旅程，从这里开始").font(TypeStyle.title(22))
                  Button(store.filter.isActive ? "清除筛选" : "添加旅程") {
                    if store.filter.isActive { store.filter = JourneyFilter() } else { add() }
                  }
                  .font(TypeStyle.small).foregroundStyle(JournalStyle.accent)
                  .padding(.horizontal, 24).frame(minHeight: 48)
                  .background(.white, in: Capsule())
                  .overlay(Capsule().strokeBorder(JournalStyle.line, lineWidth: 0.5))
                  .disabled(!store.ready)
                }.frame(maxWidth: .infinity).padding(.vertical, 48)
              } else {
                VStack(alignment: .leading, spacing: 14) {
                  Rectangle().fill(JournalStyle.line).frame(height: 0.5)
                  Text("\(store.visible.count) TRIPS / \(journalYears)")
                    .font(JournalStyle.mono).tracking(1.8).foregroundStyle(JournalStyle.muted)
                }.padding(.top, 8)
              }
              if store.visible.contains(where: { $0.placeSource == "osm" }) {
                OSMAttribution().environment(\.colorScheme, .light).tint(JournalStyle.muted)
              }
            }.padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 100)
          }
          .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 12) {
              HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                  Text("旅程").font(TypeStyle.title(30)).tracking(6).accessibilityAddTraits(.isHeader)
                  Text("TRAVEL JOURNAL").font(JournalStyle.mono).tracking(2.6).foregroundStyle(JournalStyle.muted)
                }
                Spacer(minLength: 12)
                Button {
                  withAnimation(reducedMotion ? nil : .easeInOut(duration: 0.22)) { searching.toggle() }
                  searchFocused = searching
                } label: { Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .regular)).frame(width: 44, height: 44) }
                .accessibilityLabel(searching ? "收起旅程搜索" : "搜索旅程")
                Button { searchFocused = false; filtering = true } label: {
                  Image(systemName: "line.3.horizontal.decrease").font(.system(size: 18, weight: .regular)).frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) {
                      if store.filter.isActive {
                        Circle().fill(JournalStyle.accent).frame(width: 5, height: 5).padding(6)
                      }
                    }
                }.accessibilityLabel("筛选旅程")
              }
              if searching {
                HStack(spacing: 10) {
                  Image(systemName: "magnifyingglass").foregroundStyle(JournalStyle.muted)
                  TextField("搜索地点、标题或回忆", text: $store.filter.query, prompt: Text("搜索地点、标题或回忆").foregroundStyle(JournalStyle.muted))
                    .font(TypeStyle.small).focused($searchFocused).submitLabel(.search)
                    .onSubmit { searchFocused = false }
                  Button("取消") {
                    store.filter.query = ""; searchFocused = false
                    withAnimation(reducedMotion ? nil : .easeInOut(duration: 0.22)) { searching = false }
                  }.font(TypeStyle.small).foregroundStyle(JournalStyle.accent)
                }.frame(minHeight: 44)
                  .transition(.opacity.combined(with: .move(edge: .top)))
              }
              Rectangle().fill(JournalStyle.line).frame(height: 1)
            }.padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 1)
              .background(JournalStyle.paper)
          }
          .scrollDismissesKeyboard(.interactively)
          .onChange(of: store.filter) { _, _ in reader.scrollTo("first-journey", anchor: .top) }
        }
        .onPreferenceChange(JournalFastenerFrames.self) { frames in
          // Keep the three materials in sequence, but omit the third material when
          // a tall viewport can see all three. Measuring ornaments avoids counting
          // an offscreen fastener on a partly visible photograph.
          let bounds = CGRect(origin: .zero, size: viewport.size)
          let kinds = frames.sorted { $0.key < $1.key }.compactMap { index, frame in
            frame.intersects(bounds) ? JournalFastener.Kind.at(index) : nil
          }
          var allowed: Set<JournalFastener.Kind> = []
          for kind in kinds where allowed.count < 2 { allowed.insert(kind) }
          if !allowed.isEmpty, allowed != visibleFasteners { visibleFasteners = allowed }
        }
      }.coordinateSpace(name: JournalStyle.coordinateSpace)
        .foregroundStyle(JournalStyle.ink).tint(JournalStyle.accent)
    }
    .sheet(isPresented: $filtering) { JourneyFilterSheet().presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
  }
  private var journalYears: String {
    let years = Set(store.visible.flatMap(\.years)).sorted(by: >)
    return years.isEmpty ? "—" : years.joined(separator: " · ")
  }
}

struct JourneyCard: View {
  let trip: Trip
  var index = 0
  var showsFastener = true
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      NaturalJourneyPhoto(uri: trip.photos.first ?? "", label: "\(trip.locationTitle)旅程封面")
        .environment(\.colorScheme, .light)
        .clipShape(RoundedRectangle(cornerRadius: 1))
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(trip.locationTitle).font(TypeStyle.title(20)).foregroundStyle(JournalStyle.accent)
            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          if !trip.isPersonal {
            Text("示例").font(JournalStyle.mono).foregroundStyle(JournalStyle.muted).fixedSize()
          }
        }
        Text(trip.title).font(TypeStyle.title(22)).foregroundStyle(JournalStyle.ink)
          .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        if !trip.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Text(trip.note).font(TypeStyle.small).foregroundStyle(JournalStyle.muted)
            .lineLimit(2).multilineTextAlignment(.leading).lineSpacing(4)
        }
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            dateCaption.fixedSize()
            Spacer(minLength: 0)
            numberCaption.fixedSize()
          }
          VStack(alignment: .leading, spacing: 10) {
            dateCaption
            numberCaption
          }
        }.font(JournalStyle.mono).foregroundStyle(JournalStyle.muted).padding(.top, 6)
      }.padding(.horizontal, 10).padding(.top, 20).padding(.bottom, 18)
    }
    .padding(10).background(.white, in: RoundedRectangle(cornerRadius: 3))
    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(JournalStyle.line, lineWidth: 0.5))
    .overlay(alignment: index % 3 == 1 ? .topLeading : .topTrailing) {
      JournalFastener(kind: .at(index))
        .opacity(showsFastener ? 1 : 0)
        .padding(.horizontal, 10).offset(y: -7)
        .background {
          GeometryReader { geometry in
            Color.clear.preference(key: JournalFastenerFrames.self,
                                   value: [index: geometry.frame(in: .named(JournalStyle.coordinateSpace))])
          }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
    .accessibilityElement(children: .combine)
  }
  private var dateCaption: some View { Text(trip.dateLabel).tracking(1.6) }
  private var numberCaption: some View {
    HStack(spacing: 14) {
      Text("\(trip.photos.count) 张照片")
      Text(String(format: "No.%02d", index + 1)).tracking(1)
    }
  }
}

private struct JournalCardPressStyle: ButtonStyle {
  let tilt: Double
  @Environment(\.accessibilityReduceMotion) private var reducedMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .shadow(color: JournalStyle.ink.opacity(configuration.isPressed ? 0.11 : 0.05),
              radius: configuration.isPressed ? 8 : 3, x: 0, y: configuration.isPressed ? 4 : 2)
      .rotationEffect(.degrees(configuration.isPressed && !reducedMotion ? 0 : tilt))
      .offset(y: configuration.isPressed && !reducedMotion ? -2 : 0)
      .animation(reducedMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
  }
}

private struct JournalFastenerFrames: PreferenceKey {
  static let defaultValue: [Int: CGRect] = [:]
  static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

private struct JournalFastener: View {
  enum Kind: Int, Hashable {
    case tape, clip, corner
    static func at(_ index: Int) -> Self { Self(rawValue: index % 3) ?? .tape }
  }
  let kind: Kind
  var body: some View {
    switch kind {
    case .tape:
      Rectangle().fill(Color(uiColor: UIColor(hex: "D6CBB6")).opacity(0.55))
        .frame(width: 52, height: 16).rotationEffect(.degrees(45))
    case .clip:
      PaperClip().stroke(JournalStyle.muted.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        .frame(width: 16, height: 36).rotationEffect(.degrees(12))
    case .corner:
      PhotoCorner().fill(Color(uiColor: UIColor(hex: "E4E3DF")))
        .overlay(PhotoCorner().stroke(JournalStyle.ink.opacity(0.12), lineWidth: 0.5))
        .frame(width: 24, height: 24)
    }
  }
}

private struct PaperClip: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.3))
    path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.76))
    path.addQuadCurve(to: CGPoint(x: rect.width * 0.28, y: rect.height * 0.76),
                      control: CGPoint(x: rect.width * 0.5, y: rect.height * 1.02))
    path.addLine(to: CGPoint(x: rect.width * 0.28, y: rect.height * 0.2))
    path.addCurve(to: CGPoint(x: rect.width * 0.96, y: rect.height * 0.2),
                  control1: CGPoint(x: rect.width * 0.28, y: -rect.height * 0.04),
                  control2: CGPoint(x: rect.width * 0.96, y: -rect.height * 0.04))
    path.addLine(to: CGPoint(x: rect.width * 0.96, y: rect.height * 0.78))
    path.addCurve(to: CGPoint(x: rect.width * 0.04, y: rect.height * 0.78),
                  control1: CGPoint(x: rect.width * 0.96, y: rect.height * 1.07),
                  control2: CGPoint(x: rect.width * 0.04, y: rect.height * 1.07))
    path.addLine(to: CGPoint(x: rect.width * 0.04, y: rect.height * 0.28))
    return path
  }
}

private struct PhotoCorner: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addLine(to: CGPoint(x: rect.width, y: 0))
    path.addLine(to: CGPoint(x: rect.width, y: rect.height))
    path.closeSubpath()
    return path
  }
}

struct JourneyFilterSheet: View {
  @Environment(JourneyStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var section = 0
  @State private var query = ""
  var body: some View {
    @Bindable var store = store
    NavigationStack {
      List {
        Section {
          Toggle("包含示例旅程", isOn: $store.showSamples)
            .onChange(of: store.showSamples) { _, _ in store.reconcileFilters() }
          Picker("筛选类型", selection: $section) { Text("年份").tag(0); Text("城市").tag(1) }.pickerStyle(.segmented)
        }
        if section == 0 {
          Section {
            choice("全部年份", selected: store.filter.year == "all") { store.filter.year = "all" }
            ForEach(store.years, id: \.self) { year in choice("\(year) 年", selected: store.filter.year == year) { store.filter.year = year } }
          }
        } else {
          Section {
            TextField("查找已记录城市", text: $query, prompt: Text("查找已记录城市").foregroundStyle(Palette.muted)).font(TypeStyle.small)
            choice("全部城市", selected: store.filter.cityID == nil) { store.filter.cityID = nil }
            ForEach(store.cities.filter { query.isEmpty || ($0.name + $0.detail).localizedCaseInsensitiveContains(query) }) { city in
              Button {
                store.filter.cityID = city.id
              } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 5) { Text(city.name).foregroundStyle(Palette.ink); Text(city.detail).font(TypeStyle.caption).foregroundStyle(Palette.muted) }
                  Spacer(); if store.filter.cityID == city.id { Image(systemName: "checkmark") }
                }.padding(.vertical, 4)
              }.accessibilityIdentifier("filter-city-\(city.id)")
            }
          }
        }
      }.scrollContentBackground(.hidden).background(Palette.paper)
        .navigationTitle("筛选旅程").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("清除筛选") { store.filter = JourneyFilter() }.disabled(!store.filter.isActive) }
          ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
        }
        .safeAreaInset(edge: .bottom) {
          Text([store.filter.year == "all" ? "全部年份" : "\(store.filter.year) 年", store.cities.first { $0.id == store.filter.cityID }?.name ?? "全部城市"].joined(separator: " · "))
            .font(TypeStyle.caption).padding(12).frame(maxWidth: .infinity).background(.regularMaterial)
        }
    }
  }
  private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button { action() } label: {
      HStack { Text(title).foregroundStyle(Palette.ink); Spacer(); if selected { Image(systemName: "checkmark") } }
    }
  }
}
