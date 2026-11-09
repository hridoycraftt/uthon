import SwiftUI
import AppKit

/// Liquid Glass surface.
/// - Automatic (default): exactly what this macOS uses. macOS 26+ gets Apple's real
///   Liquid Glass; macOS 14/15 get the native frosted HUD material, like Control Center.
/// - Clear / Frosted: manual overrides for people who want more or less see-through.
struct LiquidGlass<S: Shape>: View {
    var shape: S
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            switch settings.glassClarity {
            case .automatic:
                automatic(dark: dark)
            case .clear:
                manual(clear: true, dark: dark)
            case .frosted:
                manual(clear: false, dark: dark)
            }
            if settings.tintGlass {
                shape.fill(Theme.accent.opacity(dark ? 0.16 : 0.12)).allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func automatic(dark: Bool) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            native(dark: dark)
        }
        #else
        native(dark: dark)
        #endif
    }

    @ViewBuilder
    private func manual(clear: Bool, dark: Bool) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            ZStack {
                Color.clear.glassEffect(clear ? .clear : .regular, in: shape)
                if clear {
                    shape.fill(dark ? Color.black.opacity(0.2) : Color.white.opacity(0.1))
                }
            }
        } else {
            frosted(clear: clear, dark: dark)
        }
        #else
        frosted(clear: clear, dark: dark)
        #endif
    }

    /// The system's own translucent material plus a hairline rim, nothing invented.
    private func native(dark: Bool) -> some View {
        ZStack {
            BehindWindowBlur(shape: shape, material: dark ? .hudWindow : .popover)
            shape.stroke(
                LinearGradient(
                    colors: [Color.white.opacity(dark ? 0.35 : 0.9), Color.white.opacity(dark ? 0.08 : 0.4)],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 1
            )
        }
    }

    private func frosted(clear: Bool, dark: Bool) -> some View {
        ZStack {
            BehindWindowBlur(shape: shape, material: clear ? .fullScreenUI : (dark ? .hudWindow : .popover))
            // Body: barely tinted so the background shows through.
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(dark ? 0.07 : 0.28), Color.white.opacity(dark ? 0.0 : 0.05)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            // Light bending along the inside of the edge.
            shape
                .stroke(Color.white.opacity(dark ? 0.20 : 0.55), lineWidth: 10)
                .blur(radius: 9)
                .clipShape(shape)
            // Soft caustic glow near the bottom.
            shape
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(dark ? 0.10 : 0.22), Color.clear],
                        center: .bottom, startRadius: 0, endRadius: 260
                    )
                )
            // Specular rim: bright top-left, fading, bright again bottom-right.
            shape.stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(dark ? 0.75 : 1.0),
                        Color.white.opacity(dark ? 0.06 : 0.35),
                        Color.white.opacity(dark ? 0.04 : 0.25),
                        Color.white.opacity(dark ? 0.40 : 0.85),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 1.3
            )
            // Hairline outline so the glass has an edge on busy wallpapers.
            shape.stroke(Color.black.opacity(dark ? 0.45 : 0.10), lineWidth: 0.5)
        }
    }
}

/// NSVisualEffectView cut to any SwiftUI shape (via maskImage, which keeps the
/// behind-window blur working, unlike a layer mask).
struct BehindWindowBlur<S: Shape>: NSViewRepresentable {
    var shape: S
    var material: NSVisualEffectView.Material

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
        view.material = material
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
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(dark ? 0.11 : 0.55), Color.white.opacity(dark ? 0.04 : 0.30)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
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

// MARK: Content inside the system glass

extension View {
    /// Puts this view *inside* the system's Liquid Glass (macOS 26), the way the Dock is
    /// built: macOS then picks the glass, its light/dark look and the colour of the text
    /// and icons on it from what is behind, live. On macOS 14/15 the native material sits
    /// behind the view instead.
    func nookGlass<S: Shape>(_ shape: S) -> some View {
        modifier(NookGlass(shape: shape))
    }
}

struct NookGlass<S: Shape>: ViewModifier {
    var shape: S
    @ObservedObject private var settings = AppSettings.shared

    /// True where Apple's Liquid Glass is available to this build and this Mac.
    static var isSystemGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content
                .background {
                    if settings.tintGlass { shape.fill(Theme.accent.opacity(0.12)) }
                }
                .glassEffect(settings.glassClarity == .clear ? .clear : .regular, in: shape)
        } else {
            content.background(LiquidGlass(shape: shape))
        }
        #else
        content.background(LiquidGlass(shape: shape))
        #endif
    }
}
