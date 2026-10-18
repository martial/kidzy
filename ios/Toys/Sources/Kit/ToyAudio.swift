@preconcurrency import AudioKit
@preconcurrency import AudioKitEX
import AVFoundation
import os
@preconcurrency import SoundpipeAudioKit

/// The one audio engine every toy plays through (AudioKit).
///
/// ```
/// instruments ─▶ bus ─┬──────────────────────────▶ master ─▶ compressor ─▶ limiter ─▶ clipper ─▶ fade ─▶ out
///                     └─▶ reverb (wet) ─▶ send ───┘
/// ```
/// Each instrument plugs its own `Fader` into `bus` with `attach`, and leaves with
/// `detach`, which fades it out before unplugging it, so nothing is ever cut dead.
/// `acquire`/`release` count the toys using the engine: the session is set once
/// (ambient, or play-and-record while the parrot listens), switched only with
/// the engine stopped, and the engine fades in and out instead of starting cold.
@MainActor
final class ToyAudio {
    static let shared = ToyAudio()

    /// How much room a toy plays in.
    enum Room {
        case dry, small, hall

        var send: AUValue {
            switch self {
            case .dry: 0.05
            case .small: 0.14
            case .hall: 0.3
            }
        }
    }

    let engine = AudioEngine()
    /// Instruments connect here.
    let bus = Mixer(name: "toys")
    private let reverb: ZitaReverb
    private let send: Fader
    private let master: Mixer
    private let compressor: DynamicRangeCompressor
    private let limiter: PeakLimiter
    private let clipper: Clipper
    private let fade: Fader

    /// True in tests: the engine renders offline, no session, no fades in time.
    let offline: Bool
    private var users = 0
    private var micUsers = 0
    private var sessionHasMic: Bool?
    private var stopTask: Task<Void, Never>?
    /// Instruments fading out before they are unplugged: plugging one in again cancels it.
    private var leaving: Set<ObjectIdentifier> = []
    private var observers: [NSObjectProtocol] = []
    let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.screenclub", category: "audio")

    init(offline: Bool = false) {
        self.offline = offline
        reverb = ZitaReverb(bus, predelay: 22, crossoverFrequency: 220, lowReleaseTime: 2.2, midReleaseTime: 1.7, dampingFrequency: 7000, equalizerFrequency1: 315, equalizerLevel1: -2, equalizerFrequency2: 2200, equalizerLevel2: -3, dryWetMix: 1)
        send = Fader(reverb, gain: Room.small.send)
        master = Mixer(bus, send, name: "master")
        // gentle glue, then a hard ceiling: many fingers or a full strum never clip
        compressor = DynamicRangeCompressor(master, ratio: 3, threshold: -12, attackDuration: 0.004, releaseDuration: 0.15, gain: 1, dryWetMix: 1)
        limiter = PeakLimiter(compressor, attackTime: 0.002, decayTime: 0.04, preGain: 0)
        clipper = Clipper(limiter, limit: 0.97)
        fade = Fader(clipper, gain: offline ? 1 : 0)
        engine.output = fade
        _ = bus.resizeInputBussesArray(requiredSize: 16)
        if !offline { observe() }
    }

    // MARK: - instruments

    /// Plugs an instrument in. The engine is briefly paused if it runs, since a
    /// running mixer cannot grow its inputs safely.
    func attach(_ node: Node) {
        // back within the fade-out (the scene went inactive for a moment): keep it plugged in
        if leaving.remove(ObjectIdentifier(node)) != nil { return }
        guard !bus.hasInput(node) else { return }
        let wasRunning = engine.avEngine.isRunning
        if wasRunning, !offline { engine.stop() }
        bus.addInput(node)
        if wasRunning, !offline { startEngine() }
    }

    /// Fades an instrument out, then unplugs it.
    func detach(_ node: Fader) {
        guard bus.hasInput(node) else { return }
        if offline || !engine.avEngine.isRunning {
            bus.removeInput(node)
            return
        }
        node.$leftGain.ramp(to: 0, duration: 0.05)
        node.$rightGain.ramp(to: 0, duration: 0.05)
        let id = ObjectIdentifier(node)
        leaving.insert(id)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard let self, self.leaving.remove(id) != nil else { return }
            self.bus.removeInput(node)
        }
    }

    func setRoom(_ room: Room) {
        if offline {
            send.gain = room.send
        } else {
            send.$leftGain.ramp(to: room.send, duration: 0.2)
            send.$rightGain.ramp(to: room.send, duration: 0.2)
        }
    }

    // MARK: - lifetime

    /// A toy starts using sound; `mic` while it listens.
    func acquire(mic: Bool = false) {
        users += 1
        if mic { micUsers += 1 }
        stopTask?.cancel()
        stopTask = nil
        guard !offline else { return }
        if mic {
            // the parrot installs its tap right after: session and input now
            reconfigure()
        } else {
            // started on the next turn, so every instrument a toy opens in one go
            // is plugged in before the engine runs
            Task { @MainActor [weak self] in self?.reconfigure() }
        }
    }

    func release(mic: Bool = false) {
        users = max(0, users - 1)
        if mic { micUsers = max(0, micUsers - 1) }
        guard !offline else { return }
        if users == 0 {
            fadeOut()
            stopTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, !Task.isCancelled, self.users == 0 else { return }
                self.engine.stop()
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                self.sessionHasMic = nil
            }
        } else {
            reconfigure()
        }
    }

    var isRunning: Bool { engine.avEngine.isRunning }

    private func reconfigure() {
        guard users > 0 else { return }
        let wantMic = micUsers > 0
        if engine.avEngine.isRunning, sessionHasMic == wantMic {
            fadeIn()
            return
        }
        if engine.avEngine.isRunning {
            // the category changes only with the engine stopped
            fade.gain = 0
            engine.stop()
        }
        configureSession(mic: wantMic)
        if wantMic {
            // create the input before starting: a running engine does not take a new input
            _ = engine.avEngine.inputNode
        }
        startEngine()
    }

    private func configureSession(mic: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if mic {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothA2DP])
            } else {
                // toys follow the silent switch and mix with whatever else plays
                try session.setCategory(.ambient, mode: .default)
            }
            try session.setActive(true)
            sessionHasMic = mic
        } catch {
            log.error("session: \(error.localizedDescription)")
        }
    }

    private func startEngine() {
        guard !engine.avEngine.isRunning else { return }
        fade.gain = 0
        do {
            try engine.start()
            fadeIn()
        } catch {
            log.error("engine: \(error.localizedDescription)")
        }
    }

    private func fadeIn() {
        fade.$leftGain.ramp(to: 1, duration: 0.06)
        fade.$rightGain.ramp(to: 1, duration: 0.06)
    }

    private func fadeOut() {
        guard engine.avEngine.isRunning else { return }
        fade.$leftGain.ramp(to: 0, duration: 0.06)
        fade.$rightGain.ramp(to: 0, duration: 0.06)
    }

    /// A phone call or another app stops the engine; a route or format change
    /// reconfigures it: start again when it is over, if a toy still plays.
    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init) == .ended
            MainActor.assumeIsolated {
                guard let self, ended, self.users > 0 else { return }
                self.sessionHasMic = nil
                self.reconfigure()
            }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine.avEngine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.users > 0 else { return }
                self.log.notice("engine configuration changed: restarting")
                self.sessionHasMic = nil
                self.reconfigure()
            }
        })
    }
}
