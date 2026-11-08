import SwiftUI

struct TodoWidget: View {
    @ObservedObject private var store = TodoStore.shared
    @State private var draft = ""

    var body: some View {
        Card("To-do", symbol: "checklist", trailing: {
            if store.items.contains(where: { $0.done }) {
                Button("Clear done") { store.clearDone() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
        }) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(store.items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { store.toggle(item.id) }
                        } label: {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13))
                                .foregroundStyle(item.done ? Theme.accent : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        Text(item.text)
                            .font(.system(size: 12))
                            .strikethrough(item.done)
                            .foregroundStyle(item.done ? Color.secondary : Color.primary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .contextMenu {
                        Button("Delete") { store.delete(item.id) }
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                    TextField("Add a task…", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit {
                            store.add(draft)
                            draft = ""
                        }
                }
            }
        }
    }
}
