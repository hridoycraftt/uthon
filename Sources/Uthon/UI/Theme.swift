import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Design tokens: one warm accent, soft glass, generous rounding.
enum Theme {
    static let accent = Color(red: 0.89, green: 0.48, blue: 0.36)   // warm terracotta
    static let panelRadius: CGFloat = 20
    static let cardRadius: CGFloat = 14
}

/// Frosted glass that blurs whatever is behind the dock window.
struct GlassBackground: NSViewRepresentable {
    var radius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(radius: radius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.maskImage = Self.mask(radius: radius)
    }

    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// The card every widget sits in: small caps title, optional trailing control.
struct Card<Content: View, Trailing: View>: View {
    let title: String
    let symbol: String
    let trailing: Trailing
    let content: Content

    init(_ title: String, symbol: String,
         @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.secondary)
                Spacer(minLength: 0)
                trailing
            }
            .frame(height: 22)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

extension Card where Trailing == EmptyView {
    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.init(title, symbol: symbol, trailing: { EmptyView() }, content: content)
    }
}

/// A small round icon button that lights up on hover.
struct IconButton: View {
    let symbol: String
    var help: String = ""
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.secondary)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Filled accent pill button.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.accent.opacity(configuration.isPressed ? 0.75 : 1)))
    }
}

/// A file or folder row: double-click opens it, drag it anywhere.
struct FileRow: View {
    let url: URL
    var subtitle: String? = nil
    var onRemove: (() -> Void)? = nil
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
            }
            Spacer(minLength: 0)
            if hover, let onRemove {
                IconButton(symbol: "xmark", help: "Remove", action: onRemove)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hover ? 0.07 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            if let onRemove {
                Divider()
                Button("Remove", action: onRemove)
            }
        }
        .help("Double-click to open, or drag it where you need it")
    }
}

/// Reads file URLs out of a drag-and-drop.
enum FileDrop {
    private final class Box { var urls: [URL] = [] }

    static func load(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let box = Box()
        let lock = NSLock()
        for provider in providers where provider.canLoadObject(ofClass: NSURL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                if let url = object as? NSURL {
                    lock.lock()
                    box.urls.append(url as URL)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(box.urls) }
    }

    static let types: [UTType] = [.fileURL]
}
