// Records the screen (and sound) of an iPhone plugged in over USB, the way QuickTime's
// "New Movie Recording → iPhone" does: real device frames, no simulator lag.
//
//   swiftc -O ios/Tools/PhoneCapture.swift -o /tmp/phonecapture
//   /tmp/phonecapture --list
//   /tmp/phonecapture OUT.mov SECONDS        (or until OUT.mov.stop exists)
//
// The phone must be unlocked and trust this Mac; the terminal app needs the Camera permission
// (System Settings → Privacy & Security → Camera) the first time.
import AVFoundation
import CoreMediaIO

var address = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
var allow: UInt32 = 1
CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)

func phones() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified).devices
}

// the phone shows up a moment after screen capture devices are allowed
var found: [AVCaptureDevice] = []
for _ in 0..<50 {
    found = phones()
    if !found.isEmpty { break }
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}

let args = CommandLine.arguments
if args.count < 2 || args[1] == "--list" {
    for d in found { print("\(d.localizedName)  \(d.uniqueID)  \(d.modelID)") }
    if found.isEmpty { print("no iPhone screen found (plugged in over USB? unlocked? trusted?)") }
    exit(found.isEmpty ? 1 : 0)
}
guard let device = found.first else { fputs("no iPhone screen found\n", stderr); exit(1) }
let out = URL(fileURLWithPath: args[1])
let seconds = args.count > 2 ? Double(args[2]) ?? 30 : 30
try? FileManager.default.removeItem(at: out)
let stopFile = out.path + ".stop"
try? FileManager.default.removeItem(atPath: stopFile)

final class Done: NSObject, AVCaptureFileOutputRecordingDelegate {
    var finished = false
    var started = false
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        started = true
        print("recording \(fileURL.lastPathComponent)")
        fflush(stdout)
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error { fputs("recording error: \(error.localizedDescription)\n", stderr) }
        finished = true
    }
}

// the Camera permission covers screen capture devices too
let status = AVCaptureDevice.authorizationStatus(for: .video)
if status == .notDetermined {
    var answered = false
    AVCaptureDevice.requestAccess(for: .video) { _ in answered = true }
    while !answered { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
}
guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
    fputs("no Camera permission for this terminal: System Settings → Privacy & Security → Camera\n", stderr)
    exit(1)
}

let session = AVCaptureSession()
do {
    let input = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(input) else { fputs("cannot use \(device.localizedName)\n", stderr); exit(1) }
    session.addInput(input)
} catch {
    fputs("cannot open \(device.localizedName): \(error.localizedDescription)\n", stderr)
    exit(1)
}
let movie = AVCaptureMovieFileOutput()
guard session.canAddOutput(movie) else { fputs("cannot record\n", stderr); exit(1) }
session.addOutput(movie)
session.startRunning()
// the phone's stream takes a moment to start after the session runs
RunLoop.main.run(until: Date().addingTimeInterval(1.5))
let done = Done()
movie.startRecording(to: out, recordingDelegate: done)
let end = Date().addingTimeInterval(seconds + 1)
while Date() < end, !FileManager.default.fileExists(atPath: stopFile) {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
movie.stopRecording()
while !done.finished { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
session.stopRunning()
try? FileManager.default.removeItem(atPath: stopFile)
print("saved \(out.path)")
