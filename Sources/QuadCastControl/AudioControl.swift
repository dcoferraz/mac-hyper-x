import CoreAudio
import Foundation

enum AudioDirection {
    case input, output

    var scope: AudioObjectPropertyScope {
        self == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
    }
}

/// Reads and sets the mic's input gain and headphone-jack volume through
/// macOS's audio system (the same sliders as System Settings › Sound).
struct AudioControl {
    /// Finds the HyperX audio device that has streams in the given direction.
    func findHyperXDevice(_ direction: AudioDirection) -> AudioDeviceID? {
        allDevices().first { id in
            let name = deviceName(id).lowercased()
            let isHyperX = name.contains("quadcast") || name.contains("duocast") || name.contains("hyperx")
            return isHyperX && hasStreams(id, direction)
        }
    }

    func volume(of device: AudioDeviceID, _ direction: AudioDirection) -> Double? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: direction.scope,
                mElement: element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                return Double(value)
            }
        }
        return nil
    }

    /// Sets the main volume if the device has one, otherwise each channel.
    func setVolume(of device: AudioDeviceID, _ direction: AudioDirection, to level: Double) {
        var value = Float32(max(0, min(1, level)))
        let size = UInt32(MemoryLayout<Float32>.size)

        if isSettable(device, direction, element: kAudioObjectPropertyElementMain) {
            var address = volumeAddress(direction, element: kAudioObjectPropertyElementMain)
            AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
            return
        }
        for channel: AudioObjectPropertyElement in [1, 2] where isSettable(device, direction, element: channel) {
            var address = volumeAddress(direction, element: channel)
            AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        }
    }

    // MARK: - Helpers

    private func volumeAddress(_ direction: AudioDirection,
                               element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                   mScope: direction.scope,
                                   mElement: element)
    }

    private func isSettable(_ device: AudioDeviceID, _ direction: AudioDirection,
                            element: AudioObjectPropertyElement) -> Bool {
        var address = volumeAddress(direction, element: element)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private func allDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private func deviceName(_ id: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value = name?.takeRetainedValue() else { return "" }
        return value as String
    }

    private func hasStreams(_ id: AudioDeviceID, _ direction: AudioDirection) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: direction.scope,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }
}
