import SwiftUI

public enum RelayAssets {
  public static func samplePhoto(_ name: String) -> Image { Image("Sample" + name, bundle: .module) }
}

public enum RelayTheme {
  public static let cardRadius: CGFloat = 16
  public static let spacing: CGFloat = 16
  public static let cardAnimation = Animation.spring(response: 0.35, dampingFraction: 0.86)
  public static func color(_ light: UInt32, _ dark: UInt32) -> Color {
    #if os(macOS)
      Color(
        nsColor: NSColor(name: nil) { appearance in
          let d = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
          return NSColor(hex: d ? dark : light)
        })
    #else
      Color(
        uiColor: UIColor { trait in UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light) }
      )
    #endif
  }
  public static let background = color(0xF6F4F1, 0x171412)
  public static let surface = color(0xFFFFFF, 0x24211E)
  public static let secondarySurface = color(0xFAF7F3, 0x2C2824)
  public static let ink = color(0x1C1A17, 0xF1ECE6)
  public static let muted = color(0x6B6259, 0xB3A99E)
  public static let line = color(0xE7E0D8, 0x3A342E)
  public static let primary = color(0x500000, 0xA33A3A)
  public static let accentText = color(0x500000, 0xF2B8BA)
  public static let selection = color(0xF1E5E5, 0x44282B)
  public static let success = color(0x166534, 0x86EFAC)
  public static let successBackground = color(0xDCFCE7, 0x0F2A18)
  public static let warning = color(0x92400E, 0xFCD34D)
  public static let warningBackground = color(0xFEF3C7, 0x3A2A0A)
  public static let danger = color(0x991B1B, 0xFCA5A5)
  public static let dangerBackground = color(0xFEE2E2, 0x3A1212)
}
#if os(macOS)
  extension NSColor {
    fileprivate convenience init(hex: UInt32) {
      self.init(
        srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
        blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
  }
#else
  extension UIColor {
    fileprivate convenience init(hex: UInt32) {
      self.init(
        red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
        blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
  }
#endif
public struct StatusChip: View {
  let title: String
  let symbol: String
  let foreground: Color
  let background: Color
  public init(
    _ title: String, symbol: String = "", foreground: Color = RelayTheme.muted,
    background: Color = RelayTheme.secondarySurface
  ) {
    self.title = title
    self.symbol = symbol
    self.foreground = foreground
    self.background = background
  }
  public var body: some View {
    HStack(spacing: 4) {
      if !symbol.isEmpty { Image(systemName: symbol) }
      Text(title)
    }.font(.caption.weight(.semibold)).foregroundStyle(foreground).padding(.horizontal, 8).padding(
      .vertical, 4
    ).background(background, in: RoundedRectangle(cornerRadius: 8)).accessibilityElement(
      children: .combine)
  }
}
public struct LifecycleChip: View {
  let lifecycle: Lifecycle
  public init(_ lifecycle: Lifecycle) { self.lifecycle = lifecycle }
  public var body: some View {
    StatusChip(lifecycle.label, symbol: symbol, foreground: fg, background: bg)
  }
  var symbol: String {
    switch lifecycle {
    case .offered: "clock"
    case .agreed: "checkmark.circle"
    case .fulfilled: "checkmark.circle.fill"
    case .cancelled: "xmark.circle"
    case .disputed: "exclamationmark.triangle"
    }
  }
  var fg: Color {
    switch lifecycle {
    case .offered: RelayTheme.warning
    case .agreed, .fulfilled: RelayTheme.success
    case .disputed: RelayTheme.danger
    case .cancelled: RelayTheme.muted
    }
  }
  var bg: Color {
    switch lifecycle {
    case .offered: RelayTheme.warningBackground
    case .agreed, .fulfilled: RelayTheme.successBackground
    case .disputed: RelayTheme.dangerBackground
    case .cancelled: RelayTheme.secondarySurface
    }
  }
}
public struct RelayPanel<Content: View>: View {
  let content: Content
  public init(@ViewBuilder content: () -> Content) { self.content = content() }
  public var body: some View {
    content.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
      RelayTheme.surface, in: RoundedRectangle(cornerRadius: RelayTheme.cardRadius)
    )
  }
}
