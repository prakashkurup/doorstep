import AppKit
import SwiftUI

enum Palette {
    static let blue = Color.adaptive(light: 0x0063CC, dark: 0x5AA9FF)
    static let orange = Color.adaptive(light: 0xB35900, dark: 0xFFA94D)
    static let red = Color.adaptive(light: 0xC9252D, dark: 0xFF7B72)
    static let green = Color.adaptive(light: 0x1C7A3A, dark: 0x5BD68E)
    static let gray = Color.secondary
    static let primaryButton = Color.adaptive(light: 0x0063CC, dark: 0x0A6CDB)

    static let card = Color.adaptive(light: NSColor.white.withAlphaComponent(0.78), dark: NSColor.white.withAlphaComponent(0.055))
    static let cardBorder = Color.adaptive(light: NSColor.black.withAlphaComponent(0.06), dark: NSColor.white.withAlphaComponent(0.07))
    static let track = Color.adaptive(light: NSColor.black.withAlphaComponent(0.10), dark: NSColor.white.withAlphaComponent(0.14))
    static let hairline = Color.adaptive(light: NSColor.black.withAlphaComponent(0.08), dark: NSColor.white.withAlphaComponent(0.08))

    static func color(for status: OrderStatus) -> Color {
        switch status {
        case .ordered: gray
        case .shipped: blue
        case .outForDelivery: orange
        case .delivered: green
        case .delayed: red
        }
    }

    static func symbol(for status: OrderStatus) -> String {
        switch status {
        case .ordered: "clock"
        case .shipped: "shippingbox"
        case .outForDelivery: "truck.box"
        case .delivered: "checkmark"
        case .delayed: "exclamationmark.triangle"
        }
    }
}

extension Color {
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        adaptive(light: NSColor(hex: light), dark: NSColor(hex: dark))
    }

    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]).map { [.darkAqua, .vibrantDark].contains($0) } == true ? dark : light
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// HSL in, since the tile tints were designed in HSL.
    convenience init(hue: CGFloat, saturation s: CGFloat, lightness l: CGFloat) {
        let b = l + s * min(l, 1 - l)
        let sb = b == 0 ? 0 : 2 * (1 - l / b)
        self.init(hue: hue / 360, saturation: sb, brightness: b, alpha: 1)
    }
}

/// Stable per-store tint so the same merchant always gets the same tile.
enum MerchantTint {
    static func hue(for merchant: String) -> CGFloat {
        let m = merchant.lowercased()
        if m.contains("amazon") { return 35 }
        var hash: UInt32 = 5381
        for b in m.utf8 { hash = (hash &* 33) &+ UInt32(b) }
        return CGFloat(hash % 360)
    }

    static func background(_ merchant: String) -> Color {
        let h = hue(for: merchant)
        return .adaptive(light: NSColor(hue: h, saturation: 0.55, lightness: 0.90),
                         dark: NSColor(hue: h, saturation: 0.28, lightness: 0.26))
    }

    static func foreground(_ merchant: String) -> Color {
        let h = hue(for: merchant)
        return .adaptive(light: NSColor(hue: h, saturation: 0.45, lightness: 0.30),
                         dark: NSColor(hue: h, saturation: 0.70, lightness: 0.82))
    }
}

enum DateText {
    static func weekdayDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    static func eventTime(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Today · \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday · \(time)" }
        return "\(weekdayDay(date)) · \(time)"
    }
}
