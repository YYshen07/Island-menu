import Accelerate
import CoreAudio
import Foundation

/// How loud the Mac's output is right now, from a Core Audio process tap on every process's
/// output. Nothing is recorded: each buffer is reduced to one level and dropped. The tap and
/// aggregate-device setup follows Ark0N/LogoLight's `SystemAudioLevel` (MIT), which in turn follows
/// Apple's sample code. macOS asks for the "System Audio Recording Only" permission on first use.
@MainActor
final class SystemAudioMeter {
    struct Unavailable: Error {
        let status: OSStatus
    }

    private let envelope = LoudnessEnvelope()
    private let queue = DispatchQueue(label: "dev.yan.islandmenu.audio", qos: .userInteractive)
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    /// 0 in silence, 1 at the loudest the sound has been lately.
    var loudness: Double { envelope.loudness }

    func start() throws {
        guard procID == nil else { return }
        do {
            try open()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregate, procID)
            AudioDeviceDestroyIOProcID(aggregate, procID)
            self.procID = nil
        }
        if aggregate != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregate)
            aggregate = AudioObjectID(kAudioObjectUnknown)
        }
        if tap != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tap)
            tap = AudioObjectID(kAudioObjectUnknown)
        }
        envelope.reset()
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw Unavailable(status: status) }
    }

    private func open() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Island Menu"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tap))

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format))
        let isFloat = format.mFormatID == kAudioFormatLinearPCM && format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32
        guard isFloat, format.mSampleRate > 0 else { throw Unavailable(status: kAudioHardwareUnsupportedOperationError) }
        let sampleRate = format.mSampleRate

        var settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Island Menu Sound",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        if let output = Self.defaultOutputUID() {
            settings[kAudioAggregateDeviceMainSubDeviceKey] = output
            settings[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: output]]
        }
        try check(AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregate))

        let envelope = self.envelope
        var created: AudioDeviceIOProcID?
        // Runs on the audio queue, so it must not inherit this method's main-actor isolation.
        try check(AudioDeviceCreateIOProcIDWithBlock(&created, aggregate, queue) { @Sendable _, input, _, _, _ in
            envelope.add(input, sampleRate: sampleRate)
        })
        procID = created
        if let created { try check(AudioDeviceStart(aggregate, created)) }
    }

    private static func defaultOutputUID() -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != kAudioObjectUnknown else { return nil }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
}

/// Fast-attack, quick-release envelope measured against a slowly falling ceiling, so quiet music
/// uses the whole range and the volume setting does not matter. Fed from the audio thread.
private final class LoudnessEnvelope: @unchecked Sendable {
    private static let release = 0.06
    private static let ceilingDecay = 4.0
    private static let rangeDecibels = 24.0
    private static let silence = 0.001
    private static let ceilingFloor = 0.0056

    private let lock = NSLock()
    private var level = 0.0
    private var ceiling = LoudnessEnvelope.ceilingFloor

    var loudness: Double {
        lock.lock()
        defer { lock.unlock() }
        guard level > Self.silence else { return 0 }
        return min(max(1 + 20 * log10(level / ceiling) / Self.rangeDecibels, 0), 1)
    }

    func reset() {
        lock.lock()
        level = 0
        ceiling = Self.ceilingFloor
        lock.unlock()
    }

    func add(_ list: UnsafePointer<AudioBufferList>, sampleRate: Double) {
        var sumOfSquares = 0.0
        var frames = 0
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list)) {
            guard let data = buffer.mData else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            var meanSquare: Float = 0
            vDSP_measqv(data.assumingMemoryBound(to: Float.self), 1, &meanSquare, vDSP_Length(count))
            sumOfSquares += Double(meanSquare) * Double(count)
            frames += count / max(1, Int(buffer.mNumberChannels))
        }
        guard frames > 0, sampleRate > 0 else { return }
        let samples = Double(frames)
        let rms = (sumOfSquares / samples).squareRoot()
        let seconds = samples / sampleRate
        lock.lock()
        level = max(rms, level * exp(-seconds / Self.release))
        ceiling = max(level, ceiling * exp(-seconds / Self.ceilingDecay), Self.ceilingFloor)
        lock.unlock()
    }
}
