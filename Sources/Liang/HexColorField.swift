import SwiftUI
import AppKit

/// 替代 SwiftUI ColorPicker 的紧凑十六进制颜色编辑器。
/// 不调用系统 NSColorPanel，可避免 macOS 15+ 的 NSSecureCoding 警告。
struct HexColorField: View {
    @Binding var color: Color
    @State private var hex: String = ""

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))

            TextField("#RRGGBB", text: $hex)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 70)
                .textFieldStyle(.roundedBorder)
                .onChange(of: hex) { _, newValue in
                    let normalized = normalize(newValue)
                    if let newColor = Color(hex: normalized) {
                        color = newColor
                    }
                }
                .onChange(of: color) { _, newColor in
                    hex = newColor.toHex()
                }
                .onAppear {
                    hex = color.toHex()
                }
        }
    }

    private func normalize(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.hasPrefix("#") {
            trimmed = "#" + trimmed
        }
        return trimmed
    }
}

private extension Color {
    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let int = UInt64(trimmed, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        let nsColor = NSColor(self)
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return "#808080" }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
    }
}
