import CoreAudio
import Foundation

final class SystemOutputDuckingCoordinator {
    private var restoration: DuckingRestoration?

    func duckForRecording(level: Float) {
        guard restoration == nil,
              let deviceID = Self.defaultOutputDeviceID() else {
            return
        }

        let clampedLevel = max(0, min(1, level))
        let volumes = Self.captureVolumes(for: deviceID)
        guard !volumes.isEmpty else {
            return
        }

        var state = DuckingRestoration(deviceID: deviceID)

        for volume in volumes {
            guard volume.value > clampedLevel else {
                continue
            }

            state.previousVolumes.append(volume)
            Self.setVolume(clampedLevel, for: deviceID, channel: volume.channel)
        }

        guard !state.previousVolumes.isEmpty else {
            return
        }

        restoration = state
    }

    func restoreAfterRecording() {
        guard let state = restoration else {
            return
        }

        restoration = nil

        for volume in state.previousVolumes {
            Self.setVolume(volume.value, for: state.deviceID, channel: volume.channel)
        }
    }

    private static func defaultOutputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }

        return deviceID
    }

    private static func captureVolumes(for deviceID: AudioObjectID) -> [OutputVolume] {
        [UInt32(kAudioObjectPropertyElementMain), 1, 2].compactMap { channel in
            guard let value = getVolume(for: deviceID, channel: channel) else {
                return nil
            }
            return OutputVolume(channel: channel, value: value)
        }
    }

    private static func getVolume(for deviceID: AudioObjectID, channel: UInt32) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }

        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func setVolume(_ volume: Float32, for deviceID: AudioObjectID, channel: UInt32) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )

        guard AudioObjectHasProperty(deviceID, &address),
              isSettable(deviceID: deviceID, address: &address) else {
            return
        }

        var value = volume
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
    }

    private static func isSettable(deviceID: AudioObjectID, address: inout AudioObjectPropertyAddress) -> Bool {
        var isSettable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        return status == noErr && isSettable.boolValue
    }
}

private struct DuckingRestoration {
    let deviceID: AudioObjectID
    var previousVolumes: [OutputVolume] = []
}

private struct OutputVolume {
    let channel: UInt32
    let value: Float32
}
