import CoreAudio
import Foundation

enum CompletionSoundOutputVolume {
    struct Playback {
        let deviceIdentifier: String
        let gain: Float
    }

    static func playback(limit: Float) -> Playback? {
        guard limit > 0,
              let device = read(
                  AudioObjectID(kAudioObjectSystemObject),
                  kAudioHardwarePropertyDefaultOutputDevice,
                  scope: kAudioObjectPropertyScopeGlobal,
                  value: AudioDeviceID(0)
              ),
              device != kAudioObjectUnknown,
              !isMuted(device, element: kAudioObjectPropertyElementMain),
              let uid = read(device, kAudioDevicePropertyDeviceUID, scope: kAudioObjectPropertyScopeGlobal,
                             value: nil as Unmanaged<CFString>?) ?? nil else { return nil }
        let identifier = uid.takeRetainedValue() as String

        let main = kAudioObjectPropertyElementMain
        let channels: [(element: UInt32, scalar: Float?, muted: Bool)]
        if let scalar = volume(device, element: main) {
            channels = [(main, scalar, false)]
        } else {
            channels = outputChannels(device).map { element in
                (element, volume(device, element: element), isMuted(device, element: element))
            }
        }
        let audible = channels.filter { !$0.muted }
        guard channels.isEmpty || !audible.isEmpty else { return nil }
        let scalars = audible.compactMap(\.scalar)
        let systemVolume = scalars.count == audible.count ? scalars.max() : nil
        let gain = cappedGain(limit: limit, systemVolume: systemVolume) {
            audible.map { channel in
                guard let scalar = channel.scalar else { return 0 }
                if scalar <= limit { return 1 }
                return attenuation(device, element: channel.element, currentScalar: scalar, limit: limit) ?? 0
            }.min()
        }
        guard !identifier.isEmpty, gain > 0 else { return nil }
        return Playback(deviceIdentifier: identifier, gain: gain)
    }

    static func cappedGain(limit: Float, systemVolume: Float?, attenuation: () -> Float?) -> Float {
        guard limit > 0 else { return 0 }
        guard let systemVolume else { return limit == 1 ? 1 : 0 }
        guard systemVolume > 0 else { return 0 }
        if systemVolume <= limit { return 1 }
        return attenuation() ?? 0
    }

    private static func attenuation(
        _ device: AudioDeviceID, element: UInt32, currentScalar: Float, limit: Float
    ) -> Float? {
        guard let currentDB = read(device, kAudioDevicePropertyVolumeDecibels, element: element, value: Float(0)),
              currentDB.isFinite else { return nil }
        if let range = read(device, kAudioDevicePropertyVolumeRangeDecibels, element: element,
                            value: AudioValueRange(mMinimum: 0, mMaximum: 0)),
           let targetDB = decibelsAtLimit(limit, currentScalar: currentScalar, currentDB: currentDB,
                                         minimumDB: Float(range.mMinimum), scalarAtDecibels: {
            read(device, kAudioDevicePropertyVolumeDecibelsToScalar, element: element, value: $0)
        }) {
            return gain(targetDB: targetDB, currentDB: currentDB)
        }

        // Some drivers expose only the forward conversion. Use it if it agrees
        // with the device's live scalar and dB readings.
        guard let convertedDB = read(device, kAudioDevicePropertyVolumeScalarToDecibels,
                                     element: element, value: currentScalar),
              abs(convertedDB - currentDB) <= 0.1,
              let targetDB = read(device, kAudioDevicePropertyVolumeScalarToDecibels,
                                  element: element, value: limit),
              targetDB.isFinite, targetDB <= currentDB else { return nil }
        return gain(targetDB: targetDB, currentDB: currentDB)
    }

    static func decibelsAtLimit(
        _ limit: Float, currentScalar: Float, currentDB: Float, minimumDB: Float,
        scalarAtDecibels: (Float) -> Float?
    ) -> Float? {
        // Invert the driver curve that agrees with its current volume. On some
        // devices the forward selector reports a different, linear curve.
        guard minimumDB.isFinite, currentDB.isFinite, minimumDB <= currentDB,
              let atMinimum = scalarAtDecibels(minimumDB), (0...limit).contains(atMinimum),
              let atCurrent = scalarAtDecibels(currentDB), atCurrent > limit,
              abs(atCurrent - currentScalar) <= 0.002 else { return nil }
        var lower = minimumDB
        var upper = currentDB
        for _ in 0..<20 {
            let mid = lower + (upper - lower) / 2
            guard let scalar = scalarAtDecibels(mid), (0...1).contains(scalar) else { return nil }
            if scalar <= limit {
                lower = mid
            } else {
                upper = mid
            }
        }
        return lower
    }

    static func gain(targetDB: Float, currentDB: Float) -> Float {
        min(1, pow(10, (targetDB - currentDB) / 20))
    }

    private static func volume(_ device: AudioDeviceID, element: UInt32) -> Float? {
        guard let scalar = read(device, kAudioDevicePropertyVolumeScalar, element: element, value: Float(0)),
              (0...1).contains(scalar) else { return nil }
        return scalar
    }

    private static func isMuted(_ device: AudioDeviceID, element: UInt32) -> Bool {
        read(device, kAudioDevicePropertyMute, element: element, value: UInt32(0)) == 1
    }

    private static func outputChannels(_ device: AudioDeviceID) -> [UInt32] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return [] }
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else { return [] }
        let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
        let count = buffers.reduce(UInt32(0)) { $0 + $1.mNumberChannels }
        return count > 0 ? Array(1...count) : []
    }

    private static func read<T>(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        value initial: T
    ) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutableBytes(of: &value) { buffer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer.baseAddress!)
        }
        return status == noErr && size == MemoryLayout<T>.size ? value : nil
    }
}
