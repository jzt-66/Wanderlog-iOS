import SwiftUI

enum Palette {
  static let paper = color("F7F5EF", "16221D")
  static let ink = color("173D35", "E2EADC")
  static let muted = color("5C6A61", "B2C0B4")
  static let soft = color("E9EEE3", "24362C")
  static let white = color("FDFCF9", "1D2D24")
  static let thread = color("BE483D", "F08072")
  static let line = color("DFE5DD", "3A4E41")
  static let gold = color("A8833A", "C8AB70")
  static func color(_ light: String, _ dark: String) -> Color {
    Color(UIColor { trait in UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light) })
  }
}
extension UIColor {
  convenience init(hex: String) {
    let v = UInt64(hex, radix: 16) ?? 0
    self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255, alpha: 1)
  }
}
enum TypeStyle {
  static func title(_ size: CGFloat = 30) -> Font { .custom("NotoSerifCJKsc-Regular", size: size, relativeTo: size >= 30 ? .largeTitle : .title2) }
  static func number(_ size: CGFloat = 22) -> Font { .custom("Georgia", size: size, relativeTo: .title2) }
  static let body: Font = .body
  static let small: Font = .subheadline
  static let caption: Font = .caption
}

extension View {
  @ViewBuilder func journeyTopBar<Header: View>(@ViewBuilder header: () -> Header) -> some View {
    if #available(iOS 26.0, *) {
      self.safeAreaBar(edge: .top, spacing: 0, content: header)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectHidden(false, for: .top)
    } else {
      self.safeAreaInset(edge: .top, spacing: 0) { header().background(.regularMaterial) }
    }
  }
  @ViewBuilder func nativeGlass() -> some View {
    if #available(iOS 26.0, *) { self.glassEffect(.regular, in: .capsule) }
    else { self.background(.regularMaterial, in: Capsule()) }
  }
}

struct OSMAttribution: View {
  var body: some View {
    Link("地点数据 © OpenStreetMap 贡献者", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
      .font(TypeStyle.caption).foregroundStyle(Palette.muted)
  }
}

struct ErrorNotice: View {
  let message: String
  var body: some View {
    Label(message, systemImage: "exclamationmark.circle")
      .font(TypeStyle.small).foregroundStyle(Palette.ink).padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.soft, in: RoundedRectangle(cornerRadius: 16))
      .accessibilityAddTraits(.updatesFrequently)
  }
}

struct JourneyPressStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reducedMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reducedMotion ? 0.97 : 1)
      .opacity(configuration.isPressed ? 0.76 : 1)
      .animation(reducedMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
  }
}

struct JourneyActionStyle: ButtonStyle {
  var destructive = false
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(TypeStyle.small.weight(.semibold))
      .foregroundStyle(destructive ? Palette.thread : Palette.ink)
      .padding(.horizontal, 22).padding(.vertical, 14)
      .frame(minHeight: 48)
      .background(destructive ? Palette.thread.opacity(0.08) : Palette.white, in: Capsule())
      .overlay(Capsule().strokeBorder(destructive ? Palette.thread.opacity(0.2) : Palette.line, lineWidth: 1))
      .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.45)
  }
}

@MainActor enum JourneyHaptics {
  static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
  static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
  static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
  static func deletion() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}
