import SwiftUI

// MARK: - Building blocks

/// A titled panel. The window is a stack of these rather than a Form, which
/// gives the layout room to breathe and keeps the controls full width.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Label {
                    Text(title.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(0.6)
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.07)))
    }
}

/// A slider with a leading icon, a name and a live percentage.
struct LabeledSlider: View {
    let title: String
    var systemImage: String?
    let value: Double
    let set: (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            Text(title)
                .frame(width: 86, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: 0...1)
            Text("\(Int((value * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

// MARK: - Status header

struct StatusHeader: View {
    @EnvironmentObject private var state: AppState

    private var statusText: String {
        guard state.connected else { return "Not found" }
        switch state.muted {
        case .none: return "Connected"   // the mic hasn't said whether it's muted
        case .some(true): return "Muted"
        case .some(false): return "Live"
        }
    }

    private var statusColor: Color {
        if !state.connected { return .orange }
        return state.muted == true ? .red : .green
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            MicIllustration(lighting: state.lightsOff ? .allOff : state.lighting,
                            muted: state.muted)

            VStack(alignment: .leading, spacing: 8) {
                Text("QuadCast S")
                    .font(.title2.weight(.semibold))

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)

                PatternRow(pattern: state.polarPattern)

                Text(muteHint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Lights", isOn: Binding(get: { !state.lightsOff },
                                               set: { state.lightsOff = !$0 }))
                    .toggleStyle(.switch)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }

    private var muteHint: String {
        guard state.connected else { return "Plug the mic in. It's picked up automatically." }
        switch state.muted {
        case .none: return "Tap the top of the mic to mute. The state shows here once you do."
        case .some(true): return "Tap the top of the mic again to unmute."
        case .some(false): return "Lighting stays applied while this app runs."
        }
    }
}

/// The pickup pattern the dial on the back is set to. Both the dial and the
/// mute sensor are hardware, so this is a readout, not a control.
struct PatternRow: View {
    let pattern: PolarPattern?

    var body: some View {
        HStack(spacing: 6) {
            if let pattern {
                PolarPatternIcon(pattern: pattern, size: 15)
                Text(pattern.title)
                Text("·").foregroundStyle(.tertiary)
                Text(pattern.detail).foregroundStyle(.tertiary)
            } else {
                Image(systemName: "dial.min")
                    .foregroundStyle(.tertiary)
                Text("Pattern unknown").foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Main window

struct ControlsView: View {
    @EnvironmentObject private var state: AppState
    @State private var editingLower = false
    @State private var presetName = ""
    @State private var showingSave = false

    private var linkedBinding: Binding<Bool> {
        Binding(get: { state.lighting.linked }, set: { state.setLinked($0) })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card { StatusHeader() }

                Card(title: "Lighting", systemImage: "paintpalette") {
                    Picker("", selection: linkedBinding) {
                        Text("Both rings").tag(true)
                        Text("Separate").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if !state.lighting.linked {
                        Picker("", selection: $editingLower) {
                            Text("Upper").tag(false)
                            Text("Lower").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    ZoneEditor(zone: (editingLower && !state.lighting.linked)
                               ? $state.lighting.lower
                               : $state.lighting.upper)
                }
                .disabled(state.lightsOff)
                .opacity(state.lightsOff ? 0.5 : 1)

                Card(title: "Audio", systemImage: "slider.horizontal.3") {
                    if let gain = state.inputGain {
                        LabeledSlider(title: "Mic gain", systemImage: "mic",
                                      value: gain, set: { state.setInputGain($0) })
                    } else {
                        Text("macOS exposes no software gain for this mic. Use the dial underneath it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let volume = state.headphoneVolume {
                        LabeledSlider(title: "Headphones", systemImage: "headphones",
                                      value: volume, set: { state.setHeadphoneVolume($0) })
                    }
                }

                Card(title: "Presets", systemImage: "square.stack") {
                    PresetPicker(showingSave: $showingSave, presetName: $presetName)
                }

                Card {
                    Toggle("Open at login", isOn: Binding(
                        get: { state.launchAtLogin },
                        set: { state.setLaunchAtLogin($0) }))
                        .toggleStyle(.switch)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 430, idealWidth: 470, maxWidth: .infinity,
               minHeight: 440, idealHeight: 720, maxHeight: .infinity)
        .background(.background)
        .onAppear { state.refreshAudio() }
    }
}

// MARK: - Presets

/// Presets as one popup button plus save and delete, rather than a list of rows.
struct PresetPicker: View {
    @EnvironmentObject private var state: AppState
    @Binding var showingSave: Bool
    @Binding var presetName: String

    /// Which preset the current lighting matches, if any.
    private var currentID: UUID? {
        state.presets.first { $0.lighting == state.lighting }?.id
    }

    private var selection: Binding<UUID?> {
        Binding(get: { currentID }, set: { id in
            guard let id, let preset = state.presets.first(where: { $0.id == id }) else { return }
            state.apply(preset)
        })
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: selection) {
                if currentID == nil {
                    Text(state.presets.isEmpty ? "No presets saved" : "Custom").tag(UUID?.none)
                }
                ForEach(state.presets) { preset in
                    Text(preset.name).tag(UUID?.some(preset.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(state.presets.isEmpty)

            Button {
                showingSave = true
            } label: {
                Image(systemName: "plus")
            }
            .help("Save the current lighting as a preset")

            Button {
                if let id = currentID, let preset = state.presets.first(where: { $0.id == id }) {
                    state.deletePreset(preset)
                }
            } label: {
                Image(systemName: "trash")
            }
            .disabled(currentID == nil)
            .help("Delete the selected preset")
        }
        .popover(isPresented: $showingSave, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Name this preset").font(.headline)
                TextField("Preset name", text: $presetName)
                    .frame(width: 200)
                    .onSubmit(save)
                HStack {
                    Spacer()
                    Button("Cancel") { showingSave = false }
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(16)
        }
    }

    private func save() {
        state.savePreset(named: presetName)
        presetName = ""
        showingSave = false
    }
}

// MARK: - Zone editor

struct ZoneEditor: View {
    @Binding var zone: ZoneConfig

    private var modeBinding: Binding<LightMode> {
        Binding(get: { zone.mode }, set: { mode in
            zone.mode = mode
            if mode.wantsPalette && zone.colors.count < 2 { zone.colors = RGB.rainbow }
        })
    }

    private var visibleColorCount: Int {
        zone.mode.allowsMultipleColors ? zone.colors.count : min(1, zone.colors.count)
    }

    var body: some View {
        HStack {
            Text("Effect").frame(width: 86, alignment: .leading)
            Picker("", selection: modeBinding) {
                ForEach(LightMode.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
        }

        if zone.mode != .off {
            HStack(spacing: 8) {
                Text(zone.mode.allowsMultipleColors ? "Colors" : "Color")
                    .frame(width: 86, alignment: .leading)
                ForEach(0..<visibleColorCount, id: \.self) { index in
                    ColorWell(color: colorBinding(index))
                }
                if zone.mode.allowsMultipleColors {
                    Button { zone.colors.removeLast() } label: { Image(systemName: "minus") }
                        .disabled(zone.colors.count <= 1)
                        .help("Remove the last color")
                    Button { zone.colors.append(zone.colors.last ?? .red) } label: { Image(systemName: "plus") }
                        .disabled(zone.colors.count >= 8)
                        .help("Add a color")
                }
                Spacer(minLength: 0)
            }
            .buttonStyle(.borderless)

            LabeledSlider(title: "Brightness", systemImage: "sun.max",
                          value: zone.brightness / 100) { zone.brightness = $0 * 100 }

            if zone.mode.isAnimated {
                LabeledSlider(title: "Speed", systemImage: "metronome",
                              value: zone.speed / 100) { zone.speed = $0 * 100 }
            }
        }
    }

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { index < zone.colors.count ? zone.colors[index].color : .black },
            set: { if index < zone.colors.count { zone.colors[index] = RGB($0) } })
    }
}

// MARK: - Menu bar

/// The panel behind the menu bar icon: enough to change the levels and swap
/// presets without opening the window.
struct MenuBarContent: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var showingSave = false
    @State private var presetName = ""

    private var statusText: String {
        guard state.connected else { return "QuadCast S not found" }
        switch state.muted {
        case .none: return "QuadCast S connected"
        case .some(true): return "QuadCast S muted"
        case .some(false): return "QuadCast S live"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MicIllustration(lighting: state.lightsOff ? .allOff : state.lighting,
                                muted: state.muted, height: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text(statusText)
                        .font(.headline)
                        .foregroundStyle(state.connected ? .primary : .secondary)
                    PatternRow(pattern: state.polarPattern)
                        .font(.caption)
                    Toggle("Lights", isOn: Binding(get: { !state.lightsOff },
                                                   set: { state.lightsOff = !$0 }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
            }

            Divider()

            if let gain = state.inputGain {
                LabeledSlider(title: "Mic gain", systemImage: "mic",
                              value: gain, set: { state.setInputGain($0) })
            } else {
                Text("No software gain for this mic. Use the dial underneath it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let volume = state.headphoneVolume {
                LabeledSlider(title: "Headphones", systemImage: "headphones",
                              value: volume, set: { state.setHeadphoneVolume($0) })
            }

            Divider()
            PresetPicker(showingSave: $showingSave, presetName: $presetName)
            Divider()

            HStack {
                Button("Open Controls…") {
                    openWindow(id: "controls")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 330)
        // The levels can be changed elsewhere, so re-read them when this opens.
        .onAppear { state.refreshAudio() }
    }
}
