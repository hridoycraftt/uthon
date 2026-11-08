import SwiftUI
import AppKit

/// Liquid Glass surface.
/// - macOS 26+: Apple's real Liquid Glass (`glassEffect`).
/// - macOS 14/15: frosted blur of whatever is behind the window, plus a soft
///   inner sheen and a specular rim, which reads as glass in light and dark mode.
struct LiquidGlass<S: Shape>: View {
    var shape: S
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            frosted
        }
        #else
        frosted
        #endif
    }

    private var frosted: some View {
        let dark = scheme == .dark
        return ZStack {
            BehindWindowBlur(shape: shape, dark: dark)
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(dark ? 0.10 : 0.40), Color.white.opacity(dark ? 0.01 : 0.12)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            shape.stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(dark ? 0.45 : 0.95),
                        Color.white.opacity(dark ? 0.04 : 0.30),
                        Color.white.opacity(dark ? 0.20 : 0.70),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
    }
}

/// NSVisualEffectView cut to any SwiftUI shape (via maskImage, which keeps the
/// behind-window blur working, unlike a layer mask).
struct BehindWindowBlur<S: Shape>: NSViewRepresentable {
    var shape: S
    var dark: Bool

    func makeNSView(context: Context) -> ShapedEffectView {
        let view = ShapedEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        configure(view)
        return view
    }

    func updateNSView(_ view: ShapedEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: ShapedEffectView) {
        view.material = dark ? .hudWindow : .popover
        let shape = self.shape
        view.pathProvider = { rect in shape.path(in: rect).cgPath }
    }
}

final class ShapedEffectView: NSVisualEffectView {
    var pathProvider: ((CGRect) -> CGPath)? {
        didSet { updateMask() }
    }

    override func layout() {
        super.layout()
        updateMask()
    }

    private func updateMask() {
        guard let provider = pathProvider, bounds.width > 0, bounds.height > 0 else { return }
        let size = bounds.size
        let path = provider(CGRect(origin: .zero, size: size))
        maskImage = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            NSBezierPath(cgPath: path).fill()
            return true
        }
    }
}

/// A small glass tile used for cards inside the dock and the island.
struct GlassChip: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content.background(
            shape
                .fill(Color.white.opacity(dark ? 0.07 : 0.45))
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(dark ? 0.18 : 0.9), Color.white.opacity(dark ? 0.03 : 0.3)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                )
        )
    }
}

extension View {
    func glassChip(radius: CGFloat = 16) -> some View {
        modifier(GlassChip(radius: radius))
    }
}

/// The island outline: flat top that melts into the screen edge, with small
/// outward flares at the top corners (like the MacBook notch) and round bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let tr = max(0, min(topRadius, rect.width / 4, rect.height / 2))
        let br = max(0, min(bottomRadius, rect.height - tr, (rect.width - 2 * tr) / 2))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
                       control: CGPoint(x: rect.minX + tr, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr + br, y: rect.maxY),
                       control: CGPoint(x: rect.minX + tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br),
                       control: CGPoint(x: rect.maxX - tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Animated equalizer bars for "something is playing".
struct EqualizerBars: View {
    var playing: Bool
    var color: Color = Theme.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: geo.size.width * 0.14) {
                    ForEach(0..<4, id: \.self) { i in
                        let speed = 3.0 + Double(i) * 0.8
                        let level = playing ? 0.3 + 0.7 * abs(sin(t * speed + Double(i) * 1.3)) : 0.3
                        Capsule()
                            .fill(color)
                            .frame(height: geo.size.height * CGFloat(level))
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}
