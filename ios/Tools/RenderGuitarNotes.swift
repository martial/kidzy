// Renders the guitar toy's recorded notes from a SoundFont, offline (macOS AVAudioUnitSampler).
//
// The notes in ios/Toys/Resources/Guitar come from FluidR3_GM.sf2 (MIT licence, Debian package
// fluid-soundfont-gm, https://deb.debian.org/debian/pool/main/f/fluid-soundfont/), program 24
// (nylon guitar), velocity 100, one note every two semitones from MIDI 40 to 92:
//
//   swiftc -O ios/Tools/RenderGuitarNotes.swift -o /tmp/render
//   /tmp/render FluidR3_GM.sf2 24 /tmp/notes 40 92 2 100
//   for f in /tmp/notes/nylon-*.caf; do n=$(basename $f .caf | cut -d- -f2)
//     afconvert -f m4af -d aac -b 128000 -q 127 $f ios/Toys/Resources/Guitar/guitar-nylon-$n.m4a; done
//
// Each note: held 2.4 s, released, 3.2 s in all, summed to mono, faded over its last 0.25 s.
// The SoundFont itself is not in the repo.
import AVFoundation

// Renders single notes of one SF2 program offline: render SF2 PROGRAM OUTDIR FIRST LAST STEP VELOCITY
let args = CommandLine.arguments
let sf2 = URL(fileURLWithPath: args[1])
let program = UInt8(args[2])!
let outDir = URL(fileURLWithPath: args[3])
let first = Int(args[4])!, last = Int(args[5])!, step = Int(args[6])!
let velocity = UInt8(args[7])!
let sr = 44100.0
let hold = 2.4, total = 3.2

for note in stride(from: first, through: last, by: step) {
    let engine = AVAudioEngine()
    let sampler = AVAudioUnitSampler()
    engine.attach(sampler)
    let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
    engine.connect(sampler, to: engine.mainMixerNode, format: format)
    try! engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
    try! sampler.loadSoundBankInstrument(at: sf2, program: program, bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(kAUSampler_DefaultBankLSB))
    try! engine.start()
    let frames = AVAudioFrameCount(total * sr)
    let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    let chunk = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024)!
    sampler.startNote(UInt8(note), withVelocity: velocity, onChannel: 0)
    var done: AVAudioFrameCount = 0
    var released = false
    while done < frames {
        if !released, Double(done) / sr >= hold { sampler.stopNote(UInt8(note), onChannel: 0); released = true }
        let n = min(1024, frames - done)
        _ = try! engine.renderOffline(n, to: chunk)
        for c in 0..<2 { memcpy(out.floatChannelData![c] + Int(done), chunk.floatChannelData![c], Int(n) * 4) }
        done += n
    }
    out.frameLength = frames
    // mono, a 0.25 s fade at the end
    let mono = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!, frameCapacity: frames)!
    mono.frameLength = frames
    let fade = Int(0.25 * sr)
    var peak: Float = 0
    for i in 0..<Int(frames) {
        var v = 0.5 * (out.floatChannelData![0][i] + out.floatChannelData![1][i])
        if i > Int(frames) - fade { v *= Float(Int(frames) - i) / Float(fade) }
        mono.floatChannelData![0][i] = v
        peak = max(peak, abs(v))
    }
    let url = outDir.appendingPathComponent("nylon-\(note).caf")
    let file = try! AVAudioFile(forWriting: url, settings: mono.format.settings)
    try! file.write(from: mono)
    print(note, "peak", peak)
    engine.stop()
}
