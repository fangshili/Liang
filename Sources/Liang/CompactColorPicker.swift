import SwiftUI
import AppKit

/// 不依赖系统 NSColorPanel 的紧凑颜色选择器。
/// 点击色块弹出 HSB 滑块 + 十六进制输入面板，避免 macOS 15+ 的 NSSecureCoding 警告。
struct CompactColorPicker: View {
    @Binding var color: Color
    @EnvironmentObject var i18n: I18n
    @State private var isPresented = false

    var body: some View {
        let _ = i18n.currentLanguage
        HStack(spacing: 6) {
            Button(action: { isPresented.toggle() }) {
                Circle()
                    .fill(color)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Text(color.toHex())
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(minWidth: 58, alignment: .leading)
        }
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            ColorEditorPopover(color: $color)
                .frame(width: 240)
                .padding(16)
        }
    }
}

private struct ColorEditorPopover: View {
    @Binding var color: Color
    @EnvironmentObject var i18n: I18n

    @State private var hue: Double = 0
    @State private var saturation: Double = 0
    @State private var brightness: Double = 1
    @State private var hex: String = ""

    private var currentColor: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    var body: some View {
        let _ = i18n.currentLanguage
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(currentColor)
                .frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))

            VStack(spacing: 8) {
                sliderRow(I18n.shared.string(.hue), value: $hue, range: 0...1, gradient: hueGradient)
                sliderRow(I18n.shared.string(.saturation), value: $saturation, range: 0...1, color: currentColor)
                sliderRow(I18n.shared.string(.brightness), value: $brightness, range: 0...1, color: currentColor)
            }

            HStack(spacing: 6) {
                Text("#")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField("RRGGBB", text: $hex)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: hex) { _, newValue in
                        let normalized = normalize(newValue)
                        if let newColor = Color(hex: normalized) {
                            sync(from: newColor)
                        }
                    }
            }
        }
        .onAppear {
            sync(from: color)
        }
        .onChange(of: color) { _, newColor in
            sync(from: newColor)
        }
        .onChange(of: hue) { _, _ in updateColor() }
        .onChange(of: saturation) { _, _ in updateColor() }
        .onChange(of: brightness) { _, _ in updateColor() }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, gradient: LinearGradient? = nil, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                Spacer()
                Text(String(format: "%.0f%%", value.wrappedValue * 100))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            ZStack(alignment: .leading) {
                if let gradient = gradient {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(gradient)
                        .frame(height: 12)
                } else if let color = color {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color.opacity(0.5))
                        .frame(height: 12)
                }
                Slider(value: value, in: range, step: 0.01)
                    .controlSize(.small)
                    .background(Color.clear)
            }
            .frame(height: 12)
        }
    }

    private var hueGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(hue: 0.0, saturation: 1, brightness: 1),
                Color(hue: 0.17, saturation: 1, brightness: 1),
                Color(hue: 0.33, saturation: 1, brightness: 1),
                Color(hue: 0.5, saturation: 1, brightness: 1),
                Color(hue: 0.67, saturation: 1, brightness: 1),
                Color(hue: 0.83, saturation: 1, brightness: 1),
                Color(hue: 1.0, saturation: 1, brightness: 1)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func updateColor() {
        let newColor = Color(hue: hue, saturation: saturation, brightness: brightness)
        color = newColor
        hex = String(newColor.toHex().dropFirst())
    }

    private func sync(from newColor: Color) {
        guard let nsColor = NSColor(newColor).usingColorSpace(.sRGB) else { return }
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h)
        saturation = Double(s)
        brightness = Double(b)
        hex = String(newColor.toHex().dropFirst())
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
