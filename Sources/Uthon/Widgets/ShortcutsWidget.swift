import SwiftUI
import AppKit

struct ShortcutsWidget: View {
    @ObservedObject private var store = ShortcutsStore.shared
    @State private var targeted = false
    private let columns = Array(repeating: GridItem(.fixed(42), spacing: 8), count: 5)

    var body: some View {
        Card("Shortcuts", symbol: "square.grid.2x2", trailing: {
            IconButton(symbol: "plus", help: "Add apps, folders or files") { store.pickAndAdd() }
        }) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(store.paths, id: \.self) { path in
                    ShortcutTile(url: URL(fileURLWithPath: path)) { store.remove(path) }
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(targeted ? 0.9 : 0),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            )
            .onDrop(of: FileDrop.types, isTargeted: $targeted) { providers in
                FileDrop.load(providers) { store.add($0) }
                return true
            }
            if store.paths.isEmpty {
                Text(L("Drag apps or folders here, or press +"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}

private struct ShortcutTile: View {
    let url: URL
    let onRemove: () -> Void
    @State private var hover = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(hover ? 0.10 : 0))
                )
                .scaleEffect(hover ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .help(FileManager.default.displayName(atPath: url.path))
        .contextMenu {
            MenuButton("Open") { NSWorkspace.shared.open(url) }
            MenuButton("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            MenuButton("Remove from Shortcuts", action: onRemove)
        }
    }
}
