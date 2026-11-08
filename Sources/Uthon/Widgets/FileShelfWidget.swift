import SwiftUI

struct FileShelfWidget: View {
    @ObservedObject private var store = ShelfStore.shared
    @State private var targeted = false

    var body: some View {
        Card("File Shelf", symbol: "tray", trailing: {
            if !store.paths.isEmpty {
                IconButton(symbol: "trash", help: "Clear the shelf (files stay on disk)") { store.clear() }
            }
        }) {
            VStack(spacing: 2) {
                if store.paths.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 18, weight: .light))
                        Text(L("Drop files here to keep them handy"))
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    ForEach(store.paths, id: \.self) { path in
                        FileRow(url: URL(fileURLWithPath: path), onRemove: { store.remove(path) })
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        targeted ? Theme.accent : Color.primary.opacity(store.paths.isEmpty ? 0.18 : 0),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
            .onDrop(of: FileDrop.types, isTargeted: $targeted) { providers in
                FileDrop.load(providers) { store.add($0) }
                return true
            }
        }
    }
}
