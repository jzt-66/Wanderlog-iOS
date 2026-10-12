import SwiftUI

enum JourneyTab: Hashable { case map, memories }
struct MapFocusRequest: Identifiable { let id = UUID(); let trip: Trip }

struct JourneyRootView: View {
  @Environment(JourneyStore.self) private var store
  @Environment(\.scenePhase) private var scenePhase
  @State private var tab: JourneyTab = .map
  @State private var selected: Trip?
  @State private var detailOrigin: JourneyTab = .map
  @State private var detailMapRequest: Trip?
  @State private var adding = false
  @State private var focus: MapFocusRequest?
  @State private var draft = TripDraft()
  @State private var notice: String?
  var body: some View {
    tabs
      .buttonStyle(JourneyPressStyle())
      .font(TypeStyle.body).foregroundStyle(Palette.ink)
      .background(Palette.paper)
      .sheet(isPresented: $adding) {
        AddJourneyView(draft: draft) { trip in
          draft = TripDraft(); adding = false; tab = .map
          focus = MapFocusRequest(trip: trip); notice = "已保存"
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
      }
      .fullScreenCover(item: $selected, onDismiss: {
        if let trip = detailMapRequest { tab = .map; focus = MapFocusRequest(trip: trip) }
        else { tab = detailOrigin }
        detailMapRequest = nil
      }) { trip in
        JourneyDetailView(trip: trip) { current in
          detailMapRequest = current; selected = nil
        }
      }
      .safeAreaInset(edge: .top, spacing: 0) {
        VStack(spacing: 8) {
          if let error = store.error {
            ErrorNotice(message: error)
            Button("重新读取") { Task { await store.load() } }
              .buttonStyle(JourneyActionStyle()).disabled(store.busy)
          } else if !store.ready {
            ProgressView("正在读取旅程…").font(TypeStyle.small).padding(12)
          }
          if let notice {
            Label(notice, systemImage: "checkmark").font(TypeStyle.small)
              .padding(14).nativeGlass().allowsHitTesting(false)
          }
        }.padding(.horizontal, 20)
          .padding(.vertical, store.error != nil || !store.ready || notice != nil ? 8 : 0)
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if let pending = store.pendingDeletion {
          VStack(spacing: 8) {
            HStack {
              Text("已删除「\(pending.trip.title)」").font(TypeStyle.small).lineLimit(2)
              Spacer()
              Button("撤销") {
                Task {
                  await store.undoDelete()
                  if store.undoError == nil { JourneyHaptics.success() } else { JourneyHaptics.error() }
                }
              }.fontWeight(.semibold).frame(minHeight: 44).disabled(store.busy)
            }
            if let error = store.undoError { Text(error).font(TypeStyle.caption) }
          }.padding(.horizontal, 18).padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 20).padding(.vertical, 8).id(pending.id)
        }
      }
      .task(id: "\(store.pendingDeletion?.id ?? "")-\(scenePhase == .active)-\(store.busy)-\(store.undoError == nil)") {
        guard scenePhase == .active, !store.busy, store.undoError == nil, let pending = store.pendingDeletion else { return }
        do { try await Task.sleep(for: .seconds(8)) } catch { return }
        await store.finalizeDelete(id: pending.id)
      }
      .task { await store.load() }
      .task(id: notice) {
        guard notice != nil else { return }
        try? await Task.sleep(for: .seconds(2.4)); if !Task.isCancelled { notice = nil }
      }
      .onChange(of: store.showSamples) { _, _ in store.reconcileFilters() }
  }
  private func openDetail(_ trip: Trip, from origin: JourneyTab) {
    detailOrigin = origin; detailMapRequest = nil; selected = trip
  }
  private var baseTabs: some View {
    TabView(selection: $tab) {
      JourneyMapView(focus: focus, open: { openDetail($0, from: .map) }, add: { adding = true })
        .tabItem { Label("地图", systemImage: "map") }.tag(JourneyTab.map)
      JourneyListView(open: { openDetail($0, from: .memories) }, add: { adding = true })
        .tabItem { Label("旅程", systemImage: "photo.on.rectangle.angled") }.tag(JourneyTab.memories)
    }
  }
  @ViewBuilder private var tabs: some View {
    if #available(iOS 26.0, *) {
      baseTabs.tabViewBottomAccessory {
        Button { adding = true } label: {
          Label("添加旅程", systemImage: "plus").font(TypeStyle.small.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }.disabled(!store.ready || store.busy)
      }
    } else {
      baseTabs.overlay(alignment: .bottom) {
        Button { adding = true } label: {
          Label("添加旅程", systemImage: "plus").font(TypeStyle.small.weight(.semibold)).padding(.horizontal, 22).padding(.vertical, 14)
        }.nativeGlass().disabled(!store.ready || store.busy).padding(.bottom, 66)
      }
    }
  }
}
