import SwiftUI
import AppKit

struct DownloadsWidget: View {
    @ObservedObject private var store = DownloadsStore.shared

    var body: some View {
        Card("Downloads", symbol: "arrow.down.circle", trailing: {
            IconButton(symbol: "folder", help: "Open the Downloads folder") {
                NSWorkspace.shared.open(store.folder)
            }
        }) {
            if store.recent.isEmpty {
                Text(L("Nothing downloaded yet"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(store.recent) { item in
                        FileRow(url: item.url, subtitle: item.date.formatted(.relative(presentation: .named)))
                    }
                }
            }
        }
        .onAppear { store.refresh() }
    }
}
