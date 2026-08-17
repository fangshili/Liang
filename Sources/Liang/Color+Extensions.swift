import SwiftUI
import AppKit

extension Color {
    func resolvedNSColor() -> NSColor {
        let resolved = self.resolve(in: EnvironmentValues())
        return NSColor(
            red: CGFloat(resolved.red),
            green: CGFloat(resolved.green),
            blue: CGFloat(resolved.blue),
            alpha: CGFloat(resolved.opacity)
        )
    }
}

extension NSColor {
    func swiftUIColor() -> Color {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard let color = self.usingColorSpace(.sRGB) else { return .cyan }
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }

    convenience init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255.0
        let g = CGFloat((int >> 8) & 0xFF) / 255.0
        let b = CGFloat(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    func toHex() -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        let srgb = usingColorSpace(.sRGB) ?? self
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
    }
}
