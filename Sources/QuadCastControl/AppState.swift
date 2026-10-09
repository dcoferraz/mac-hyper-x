import CoreAudio
import ServiceManagement
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var lighting: LightingConfig {
        didSet { pushLighting(); persist() }
    }
    @Published var presets: [Preset] {
        didSet { persist() }
    }
    @Published var lightsOff = false {
        didSet { pushLighting() }
    }
    @Published private(set) var connected = false
    /// Nil until the mic reports a mute state, which it only does on a tap.
    @Published private(set) var muted: Bool?
    /// Nil until the pattern dial is turned. The mic won't say where it starts.
    @Published private(set) var polarPattern: PolarPattern?
    @Published private(set) var inputGain: Double?
    @Published private(set) var headphoneVolume: Double?
    @Published private(set) var launchAtLogin: Bool

    private let device = QuadCastDevice()
    private let status = StatusMonitor()
    private let audio = AudioControl()
    private var inputDevice: AudioDeviceID?
    private var outputDevice: AudioDeviceID?

    init() {
        let saved = SavedState.load()
        lighting = saved.lighting
        presets = saved.presets
        launchAtLogin = SMAppService.mainApp.status == .enabled

        device.onConnectionChange = { [weak self] isConnected in
            Task { @MainActor in
                self?.connected = isConnected
                if isConnected { self?.refreshAudio() }
            }
        }
        status.onMuteChange = { [weak self] isMuted in
            Task { @MainActor in self?.muted = isMuted }
        }
        status.onPatternChange = { [weak self] pattern in
            Task { @MainActor in self?.polarPattern = pattern }
        }

        device.update(lighting)
        device.start()
        status.start()
        refreshAudio()
    }

    // MARK: - Lighting

    func setLinked(_ linked: Bool) {
        var updated = lighting
        if !linked { updated.lower = updated.upper }  // start the lower ring from the current look
        updated.linked = linked
        lighting = updated
    }

    func apply(_ preset: Preset) {
        lightsOff = false
        lighting = preset.lighting
    }

    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let index = presets.firstIndex(where: { $0.name == trimmed }) {
            presets[index].lighting = lighting
        } else {
            presets.append(Preset(name: trimmed, lighting: lighting))
        }
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
    }

    private func pushLighting() {
        device.update(lightsOff ? .allOff : lighting)
    }

    private func persist() {
        SavedState(lighting: lighting, presets: presets).save()
    }

    // MARK: - Audio

    func refreshAudio() {
        inputDevice = audio.findHyperXDevice(.input)
        outputDevice = audio.findHyperXDevice(.output)
        inputGain = inputDevice.flatMap { audio.volume(of: $0, .input) }
        headphoneVolume = outputDevice.flatMap { audio.volume(of: $0, .output) }
    }

    func setInputGain(_ value: Double) {
        guard let inputDevice else { return }
        inputGain = value
        audio.setVolume(of: inputDevice, .input, to: value)
    }

    func setHeadphoneVolume(_ value: Double) {
        guard let outputDevice else { return }
        headphoneVolume = value
        audio.setVolume(of: outputDevice, .output, to: value)
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("QuadCastControl: launch at login change failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
