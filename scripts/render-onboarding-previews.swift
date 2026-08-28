// Render Liang onboarding Step 2 preview cards to PNG + animated GIF.
// Mirrors the live NotchStaticPreview / CursorStaticPreview / MenuBarStaticPreview
// views so the README images match the in-app onboarding 1:1.

import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Shapes

struct CursorArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.65))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.55))
        path.addLine(to: CGPoint(x: w * 0.85, y: h))
        path.addLine(to: CGPoint(x: w, y: h * 0.8))
        path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.4))
        path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.25))
        path.closeSubpath()
        return path
    }
}

// MARK: - Previews (hover state = glow on)

struct NotchStaticPreview: View {
    var glowColor = Color(red: 0.35, green: 0.62, blue: 0.95)

    var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.045, blue: 0.055)
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
                        .frame(height: 30)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black)
                        .frame(width: 58, height: 13)
                        .offset(y: 2)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(glowColor, lineWidth: 1.3)
                        .frame(width: 60, height: 15)
                        .offset(y: 1)
                        .shadow(color: glowColor.opacity(0.5), radius: 2.5, x: 0, y: 0)
                }
                Rectangle()
                    .fill(Color(red: 0.025, green: 0.025, blue: 0.035))
                    .overlay(
                        VStack(spacing: 8) {
                            shimmerLine(width: 110)
                            shimmerLine(width: 85)
                            shimmerLine(width: 140)
                        }
                        .padding(.top, 18)
                    )
            }
        }
    }

    private func shimmerLine(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.white.opacity(0.055))
            .frame(width: width, height: 5)
    }
}

struct CursorStaticPreview: View {
    var glowColor = Color(red: 1.0, green: 0.57, blue: 0.16)

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.035, blue: 0.045)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(0..<7, id: \.self) { i in
                    HStack(spacing: 5) {
                        if i == 4 {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color(red: 0.65, green: 0.55, blue: 0.95))
                                .frame(width: 5, height: 5)
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color.white.opacity(0.13))
                                .frame(width: CGFloat([70, 95, 60, 120, 55, 85, 105][i]), height: 4)
                        } else {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                                .frame(width: CGFloat([70, 95, 60, 120, 55, 85, 105][i]), height: 4)
                        }
                    }
                }
            }
            .padding(.leading, 14)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ZStack {
                Ellipse()
                    .fill(RadialGradient(colors: [glowColor.opacity(0.45), glowColor.opacity(0)], center: .center, startRadius: 0, endRadius: 11))
                    .frame(width: 22, height: 18)
                    .offset(x: 10, y: 14)
                    .blur(radius: 1.2)
                CursorArrowShape()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 15, height: 15)
            }
            .offset(x: 28, y: 22)
        }
    }
}

struct MenuBarStaticPreview: View {
    var orbColor = Color(red: 0.41, green: 0.84, blue: 0.42)

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.035, green: 0.035, blue: 0.045)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.65))
                        .padding(.horizontal, 6)
                    ForEach(["File", "Edit", "View"], id: \.self) { item in
                        Text(item)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.65))
                            .padding(.horizontal, 6)
                    }
                    Spacer()
                    Image(systemName: "wifi")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.55))
                    Image(systemName: "battery.75")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.55))
                        .padding(.trailing, 2)
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [orbColor.opacity(0.45), orbColor.opacity(0)], center: .center, startRadius: 0, endRadius: 8))
                            .frame(width: 16, height: 16)
                            .blur(radius: 1.2)
                        Circle()
                            .fill(RadialGradient(colors: [orbColor.opacity(0.75), orbColor.opacity(0)], center: .center, startRadius: 0, endRadius: 5))
                            .frame(width: 10, height: 10)
                    }
                    .padding(.horizontal, 6)
                }
                .frame(height: 22)
                .background(Color(red: 0.075, green: 0.075, blue: 0.085))
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
                Spacer()
            }
        }
    }
}

// MARK: - Render helpers

@MainActor
func renderFrame<V: View>(_ view: V, size: NSSize, scale: CGFloat) -> CGImage {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = scale
    renderer.isOpaque = true
    return renderer.nsImage!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}

func savePNG(_ cg: CGImage, path: String) {
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
    print("Saved \(path)")
}

func saveGIF(_ frames: [CGImage], path: String, delay: Double) {
    guard let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL,
        UTType.gif.identifier as CFString,
        frames.count, nil
    ) else { return }

    // 无限循环（0 = loop forever）
    CGImageDestinationSetProperties(dest, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
    ] as CFDictionary)

    let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
    for frame in frames {
        CGImageDestinationAddImage(dest, frame, frameProps)
    }
    CGImageDestinationFinalize(dest)
    print("Saved \(path)")
}

// MARK: - Main

@main
struct RenderPreviews {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let size = NSSize(width: 200, height: 132)
        let scale: CGFloat = 3.0
        let outDir = "/Users/fangshili/CodeBuddy/liang/assets/screenshots"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        let idle = Color(red: 1.0, green: 0.57, blue: 0.16)         // orange
        let processing = Color(red: 0.35, green: 0.62, blue: 0.95)   // blue
        let success = Color(red: 0.41, green: 0.84, blue: 0.42)      // green
        let cycle = [processing, success, idle]  // matches in-app stateCycle

        // Static PNGs (hover state)
        savePNG(renderFrame(NotchStaticPreview(glowColor: processing), size: size, scale: scale),
                path: "\(outDir)/notch-glow.png")
        savePNG(renderFrame(CursorStaticPreview(glowColor: idle), size: size, scale: scale),
                path: "\(outDir)/cursor-glow.png")
        savePNG(renderFrame(MenuBarStaticPreview(orbColor: success), size: size, scale: scale),
                path: "\(outDir)/menubar-glow.png")

        // Animated GIFs (state color cycle)
        saveGIF(cycle.map { renderFrame(NotchStaticPreview(glowColor: $0), size: size, scale: scale) },
                path: "\(outDir)/notch-glow.gif", delay: 1.2)
        saveGIF(cycle.map { renderFrame(CursorStaticPreview(glowColor: $0), size: size, scale: scale) },
                path: "\(outDir)/cursor-glow.gif", delay: 1.2)
        saveGIF(cycle.map { renderFrame(MenuBarStaticPreview(orbColor: $0), size: size, scale: scale) },
                path: "\(outDir)/menubar-glow.gif", delay: 1.2)
    }
}
