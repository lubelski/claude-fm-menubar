import CoreAudio
import Foundation

// Not in a public header, but exported by libSystem. Returns the process that macOS holds
// responsible for `pid`, such as the app that owns an XPC helper.
@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsiblePID(_ pid: pid_t) -> pid_t

/// Watches Core Audio's per-process list and reports when another app starts playing audio.
///
/// Our own audio comes out of a WebKit GPU helper process, not this one. Helpers count as
/// ours when macOS holds the same process responsible for them as for us.
@MainActor
final class OtherAudioMonitor {
    /// Called once another app has been playing for about 2 seconds, so alert sounds don't count.
    var onOtherAudioStarted: (() -> Void)?

    private var timer: Timer?
    /// Apps already playing when monitoring started. They are ignored until they go quiet.
    private var baseline: Set<pid_t> = []
    private var streaks: [pid_t: Int] = [:]
    private let ownResponsiblePID = responsiblePID(getpid())
    private let requiredStreak = 2

    func start() {
        guard timer == nil else { return }
        baseline = Self.otherPlayingPIDs(excluding: ownResponsiblePID)
        streaks = [:]
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let playing = Self.otherPlayingPIDs(excluding: ownResponsiblePID)
        baseline.formIntersection(playing)
        for pid in playing.subtracting(baseline) {
            streaks[pid, default: 0] += 1
        }
        streaks = streaks.filter { playing.contains($0.key) }
        if streaks.values.contains(where: { $0 >= requiredStreak }) {
            stop()
            onOtherAudioStarted?()
        }
    }

    /// PIDs of processes outside this app that are currently sending audio to an output.
    private static func otherPlayingPIDs(excluding ownResponsible: pid_t) -> Set<pid_t> {
        var result: Set<pid_t> = []
        for object in processObjects() {
            guard read(object, kAudioProcessPropertyIsRunningOutput, UInt32(0)) == 1,
                  let pid = read(object, kAudioProcessPropertyPID, pid_t(0)), pid > 0,
                  responsiblePID(pid) != ownResponsible
            else { continue }
            result.insert(pid)
        }
        return result
    }

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
}
