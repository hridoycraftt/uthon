import SwiftUI
import UniformTypeIdentifiers

/// A row of tiles that can be edited in place, like Control Center on iPhone:
/// in edit mode tiles jiggle, show a remove (−) badge, can be dragged to reorder,
/// and a gallery underneath adds new ones (+).
struct EditableRow<Item: CustomizableItem, Tile: View>: View {
    let items: [Item]
    let allItems: [Item]
    let maxSlots: Int
    let editing: Bool
    let canAdd: (Item) -> Bool
    let setEnabled: (Item, Bool) -> Void
    let place: (Item, Item) -> Void
    /// When set, edit mode shows a big "+ Add Widget" button (opens a full gallery)
    /// instead of the small chip list.
    var onAdd: (() -> Void)? = nil
    var addTitle = "Add Widget"
    /// Optional "Presets" button shown next to "+ Add Widget".
    var onPresets: (() -> Void)? = nil
    @ViewBuilder let tile: (Item) -> Tile

    @State private var dragging: Item?
    private let spacing: CGFloat = 10

    private var usedSlots: Int { items.reduce(0) { $0 + $1.slots } }
    private var available: [Item] { allItems.filter { !items.contains($0) } }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                // In edit mode keep room for the full row so you can see what still fits.
                let slots = max(1, editing ? max(usedSlots, min(maxSlots, usedSlots + 1)) : usedSlots)
                let unit = (geo.size.width - spacing * CGFloat(slots - 1)) / CGFloat(slots)
                HStack(spacing: spacing) {
                    ForEach(items) { item in
                        tile(item)
                            .allowsHitTesting(!editing)
                            .frame(width: unit * CGFloat(item.slots) + spacing * CGFloat(item.slots - 1))
                            .frame(maxHeight: .infinity)
                            .overlay(alignment: .topLeading) {
                                if editing {
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { setEnabled(item, false) }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 20))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(Color.white, Color.red)
                                            .background(Circle().fill(Color.white).padding(3))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: -6, y: -6)
                                    .transition(.scale.combined(with: .opacity))
                                    .help("Remove \(item.title)")
                                }
                            }
                            .modifier(Jiggle(active: editing, seed: item.rawValue.count))
                            .opacity(dragging == item ? 0.4 : 1)
                            .modifier(ReorderModifier(enabled: editing, item: item, dragging: $dragging, place: place))
                    }
                    if editing && usedSlots < maxSlots {
                        Button {
                            onAdd?()
                        } label: {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                                .overlay(
                                    VStack(spacing: 4) {
                                        Image(systemName: "plus.circle.fill").font(.system(size: 22))
                                        Text(onAdd == nil ? "Add from below" : addTitle).font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundStyle(Color.secondary)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: unit)
                        .transition(.opacity)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: items)
            }
            if editing {
                Group {
                    if let onAdd {
                        HStack(spacing: 8) {
                            Button(action: onAdd) {
                                Label(L(addTitle), systemImage: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Theme.accent))
                                    .foregroundStyle(Color.white)
                                    .fixedSize()
                            }
                            .buttonStyle(.plain)
                            .help(L("Open the full widget gallery"))
                            if let onPresets {
                                Button(action: onPresets) {
                                    Label(L("Presets"), systemImage: "square.grid.3x2.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Theme.accent.opacity(0.16)))
                                        .foregroundStyle(Theme.accent)
                                        .fixedSize()
                                }
                                .buttonStyle(.plain)
                                .help(L("Ready-made Home layouts"))
                            }
                            // Quick suggestions right next to it: tap one to add it.
                            gallery
                        }
                        .frame(height: 30)
                    } else {
                        gallery
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: editing)
    }

    private var gallery: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if available.isEmpty {
                    Text(L("Everything is already added"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                } else if usedSlots >= maxSlots {
                    Text(L("Page full: remove one to add more"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.orange)
                        .fixedSize()
                }
                ForEach(available) { item in
                    let fits = canAdd(item)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { setEnabled(item, true) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: item.symbol).font(.system(size: 11, weight: .semibold))
                            Text(L(item.title)).font(.system(size: 11, weight: .medium)).fixedSize()
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(fits ? Color.green : Color.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.primary.opacity(0.09)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!fits)
                    .opacity(fits ? 1 : 0.45)
                    .help(fits ? "Add \(item.title)" : "No room: remove something first")
                }
            }
        }
        .frame(height: 30)
    }
}

/// Gentle wobble while editing.
struct Jiggle: ViewModifier {
    let active: Bool
    let seed: Int
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(active ? (on ? 0.9 : -0.9) : 0))
            .animation(active ? .easeInOut(duration: 0.12 + Double(seed % 3) * 0.015).repeatForever(autoreverses: true) : .default,
                       value: on)
            .onAppear { if active { on = true } }
            .onChange(of: active) { _, isActive in on = isActive }
    }
}

/// Drag a tile onto another tile to swap their places (only while editing).
private struct ReorderModifier<Item: CustomizableItem>: ViewModifier {
    let enabled: Bool
    let item: Item
    @Binding var dragging: Item?
    let place: (Item, Item) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    dragging = item
                    return NSItemProvider(object: item.rawValue as NSString)
                }
                .onDrop(of: [UTType.text], delegate: ReorderDropDelegate(target: item, dragging: $dragging, place: place))
        } else {
            content
        }
    }
}

private struct ReorderDropDelegate<Item: CustomizableItem>: DropDelegate {
    let target: Item
    @Binding var dragging: Item?
    let place: (Item, Item) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { place(dragging, target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
