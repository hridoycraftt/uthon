import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings → Wallpaper: live wallpapers that follow the mouse, your own video, and the
/// changing desktop picture.
struct WallpaperSettings: View {
    @ObservedObject private var library = UserLibrary.shared
    @ObservedObject private var live = LiveWallpaper.shared
    @ObservedObject private var thumbs = LiveThumbnails.shared

    private var mode: LiveMode { LiveMode(rawValue: library.liveMode) ?? .live }
    private var style: LiveStyle { LiveStyle(rawValue: library.liveStyle) ?? .aurora }

    private var status: String {
        if !library.liveEnabled { return L("Off") }
        if mode == .video && library.videoPath.isEmpty { return L("Choose a video below") }
        if !live.pauseReason.isEmpty { return L(live.pauseReason) }
        let name = mode == .video ? (library.videoPath as NSString).lastPathComponent : L(style.title)
        return L("Playing") + " · " + name
    }

    var body: some View {
        Form {
            // One switch turns it all on or off.
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        if let image = thumbs.images[style], mode == .live {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: mode == .video ? "film.fill" : "sparkles").foregroundStyle(.white)
                                .font(.system(size: 20, weight: .medium))
                        }
                    }
                    .frame(width: 74, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Live wallpaper")).font(.system(size: 15, weight: .semibold))
                        Text(status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Toggle(L("Live wallpaper"), isOn: $library.liveEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.large)
                }
                .padding(.vertical, 4)
                Picker(L("Show"), selection: $library.liveMode) {
                    Text(L("Live wallpapers")).tag(LiveMode.live.rawValue)
                    Text(L("My video")).tag(LiveMode.video.rawValue)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(L("It sits behind your desktop icons; the icons and clicks work as usual."))
            }

            if mode == .live {
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 12)], spacing: 14) {
                        ForEach(LiveStyle.allCases) { item in
                            StyleCard(style: item, image: thumbs.images[item],
                                      selected: item == style && library.liveEnabled) {
                                library.liveStyle = item.rawValue
                                library.liveMode = LiveMode.live.rawValue
                                if !library.liveEnabled { library.liveEnabled = true }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text(L("Choose a wallpaper"))
                } footer: {
                    Text(L("Move the mouse over the desktop: each one reacts to it."))
                }

                Section(L("Feel")) {
                    slider("Mouse reaction", value: $library.liveReact, range: 0...1, step: 0.05, low: "cursorarrow", high: "cursorarrow.motionlines") {
                        $0 < 0.03 ? L("Off") : "\(Int(($0 * 100).rounded()))%"
                    }
                    slider("Speed", value: $library.liveSpeed, range: 0.2...2.5, step: 0.1, low: "tortoise", high: "hare") {
                        String(format: "%.1f×", $0)
                    }
                    HStack(spacing: 8) {
                        slider("Colour", value: $library.liveHue, range: 0...1, step: 0.02, low: "paintpalette", high: "paintpalette.fill") {
                            $0 < 0.01 ? L("Original") : "\(Int(($0 * 360).rounded()))°"
                        }
                        Button(L("Reset")) { library.liveHue = 0 }
                            .disabled(library.liveHue == 0)
                    }
                }
                .disabled(!library.liveEnabled)
            } else {
                Section {
                    HStack {
                        Image(systemName: "film").foregroundStyle(.secondary)
                        Text(library.videoPath.isEmpty ? L("No video chosen") : (library.videoPath as NSString).lastPathComponent)
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(library.videoPath.isEmpty ? .secondary : .primary)
                        Spacer()
                        if !library.videoPath.isEmpty {
                            Button { library.videoPath = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary)
                                .help(L("Remove"))
                        }
                        Button(L("Choose Video…")) { chooseVideo() }
                    }
                    Picker(L("Size"), selection: $library.videoFill) {
                        Text(L("Fill the screen")).tag(true)
                        Text(L("Fit")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    Toggle(L("Play its sound"), isOn: $library.videoSound)
                    if library.videoSound {
                        slider("Volume", value: $library.videoVolume, range: 0...1, step: 0.05, low: "speaker.fill", high: "speaker.wave.3.fill") {
                            "\(Int(($0 * 100).rounded()))%"
                        }
                    }
                } header: {
                    Text(L("My video"))
                } footer: {
                    Text(L("Any MP4, MOV or M4V plays in a loop. The file stays where it is on your Mac."))
                }
            }

            Section {
                Picker(L("Quality"), selection: $library.liveQuality) {
                    Text(L("Sharp (native)")).tag("high")
                    Text(L("Balanced")).tag("balanced")
                    Text(L("Battery saver")).tag("saver")
                }
                .pickerStyle(.segmented)
                Picker(L("Smoothness"), selection: $library.liveFPS) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                Toggle(L("Pause when a window or full-screen app covers it"), isOn: $library.livePauseCovered)
                Toggle(L("Pause on battery"), isOn: $library.livePauseOnBattery)
                Toggle(L("Pause in Low Power Mode"), isOn: $library.livePauseLowPower)
                if NSScreen.screens.count > 1 {
                    Toggle(L("On every display"), isOn: $library.liveAllScreens)
                }
            } header: {
                Text(L("Performance"))
            } footer: {
                Text(L("Sharp draws every pixel of your screen. It always rests while nobody can see it, so it costs little power."))
            }

            DesktopPictureSection()
        }
        .formStyle(.grouped)
        .onAppear { thumbs.load() }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                        low: String, high: String, format: @escaping (Double) -> String) -> some View {
        HStack(spacing: 8) {
            Text(L(title)).frame(minWidth: 90, alignment: .leading)
            Image(systemName: low).foregroundStyle(.secondary).frame(width: 18)
            Slider(value: value, in: range)
            Image(systemName: high).foregroundStyle(.secondary).frame(width: 18)
            Text(format(value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary).frame(width: 58, alignment: .trailing)
        }
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            library.videoPath = url.path
            library.liveMode = LiveMode.video.rawValue
            if !library.liveEnabled { library.liveEnabled = true }
        }
    }
}

/// One wallpaper in the gallery.
private struct StyleCard: View {
    let style: LiveStyle
    let image: NSImage?
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image {
                            Image(nsImage: image).resizable().aspectRatio(16 / 10, contentMode: .fill)
                        } else {
                            Rectangle().fill(Color.primary.opacity(0.06))
                                .overlay(ProgressView().controlSize(.small))
                        }
                    }
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(hover ? 0.25 : 0.08),
                                          lineWidth: selected ? 2.5 : 1)
                    )
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .font(.system(size: 16))
                            .padding(6)
                    }
                }
                HStack(spacing: 4) {
                    Text(L(style.title)).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(L(style.kind)).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .scaleEffect(hover ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: hover)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(L(style.title))
    }
}

/// The desktop picture that changes every day (moved here from General).
struct DesktopPictureSection: View {
    @ObservedObject private var library = UserLibrary.shared

    var body: some View {
        Section {
            Picker(L("Change wallpaper"), selection: $library.wallpaperSource) {
                ForEach(WallpaperSource.allCases) { Text(L($0.title)).tag($0) }
            }
            if library.wallpaperSource == .folder {
                HStack {
                    Text(library.wallpaperFolder.isEmpty ? L("No folder chosen") : library.wallpaperFolder)
                        .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Choose…")) {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url { library.wallpaperFolder = url.path }
                    }
                }
            }
            if library.wallpaperSource != .off {
                Toggle(L("A new wallpaper every day"), isOn: $library.wallpaperDaily)
                Button(L("Change wallpaper now")) { WallpaperChanger.shared.next() }
            }
        } header: {
            Text(L("Desktop picture"))
        } footer: {
            Text(L("A still picture under the live wallpaper; it shows when the live wallpaper is off."))
        }
    }
}
