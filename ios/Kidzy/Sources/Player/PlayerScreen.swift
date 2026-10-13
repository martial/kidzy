import SwiftUI
import AVFoundation

/// Full-screen video. No control at all: a tap does nothing, four taps in the
/// top-left corner leave. At the end, the next episode after a short ring.
struct PlayerScreen: View {
    let item: Item
    @Environment(AppModel.self) private var model
    @State private var player = AVPlayer()
    @State private var ended = false
    @State private var countdownStart: Date?
    @State private var reporter = TimelineReporter()
    @State private var observers: [Any] = []
    @State private var failed = false

    private var next: Item? { model.next(after: item) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerLayerView(player: player).ignoresSafeArea()
            if ended, let next {
                NextOverlay(next: next, start: countdownStart ?? Date(), duration: AutoplayQueue(items: []).countdown, playNow: { model.play(next) }, imageURL: model.mediaURL(next.thumbUrl))
            }
            if failed {
                VStack(spacing: 12) {
                    SunMascot()
                    Text("Cette vidéo ne veut pas se lancer").font(Theme.rounded(20)).foregroundStyle(.white)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { /* no pause: a tap does nothing */ }
        .overlay(alignment: .topLeading) {
            SecretCorner { model.exitPlayer() }
        }
        .onAppear { start() }
        .onDisappear { stop() }
        .task(id: item.id) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !ended, !failed, player.timeControlStatus == .playing else { continue }
                model.tickPlaying()
                let position = player.currentTime().seconds
                if let e = reporter.event(itemId: item.id, state: .playing, position: position.isFinite ? position : 0) {
                    await model.report(e)
                }
            }
        }
    }

    private func start() {
        Orientation.set(.landscape)
        UIApplication.shared.isIdleTimerDisabled = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let url = model.mediaURL(item.videoUrl) else {
            failed = true
            return
        }
        reporter.startSession()
        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)
        player.automaticallyWaitsToMinimizeStalling = true
        player.play()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { _ in
            MainActor.assumeIsolated { finished() }
        })
        observers.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: playerItem, queue: .main) { _ in
            MainActor.assumeIsolated { fail() }
        })
        observers.append(playerItem.observe(\.status, options: [.new]) { pi, _ in
            if pi.status == .failed {
                Task { @MainActor in fail() }
            }
        })
        if let e = reporter.event(itemId: item.id, state: .playing, position: 0) {
            Task { await model.report(e) }
        }
    }

    private func finished() {
        ended = true
        countdownStart = Date()
        if let e = reporter.event(itemId: item.id, state: .ended, position: item.duration) {
            Task { await model.report(e) }
        }
        if next == nil {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                model.exitPlayer()
            }
        } else {
            Task {
                try? await Task.sleep(for: .seconds(AutoplayQueue(items: []).countdown))
                if ended, let next { model.play(next) }
            }
        }
    }

    private func fail() {
        guard !failed else { return }
        failed = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            model.exitPlayer()
        }
    }

    private func stop() {
        if !ended, let e = reporter.event(itemId: item.id, state: .stopped, position: player.currentTime().seconds) {
            Task { await model.report(e) }
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        for o in observers {
            if let token = o as? NSObjectProtocol, !(o is NSKeyValueObservation) { NotificationCenter.default.removeObserver(token) }
            (o as? NSKeyValueObservation)?.invalidate()
        }
        observers.removeAll()
        UIApplication.shared.isIdleTimerDisabled = false
        Orientation.set(.portrait)
    }
}

/// The next episode's tile with a filling ring; a tap plays it right away.
struct NextOverlay: View {
    let next: Item
    let start: Date
    let duration: TimeInterval
    let playNow: () -> Void
    let imageURL: URL?

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            TimelineView(.animation) { ctx in
                let progress = min(1, max(0, ctx.date.timeIntervalSince(start) / duration))
                Button(action: playNow) {
                    StickerTile(color: Color(hex: next.color), tilt: -2, radius: 28, innerRadius: 16) {
                        RemoteImage(url: imageURL, maxPixel: 500)
                            .frame(width: 228, height: 142)
                    }
                    .overlay(alignment: .topTrailing) {
                        ZStack {
                            Circle().fill(Theme.ink).offset(x: 4, y: 4)
                            Circle().fill(Theme.paper).overlay(Circle().stroke(Theme.ink, lineWidth: 5))
                            Circle().stroke(Theme.starOff, lineWidth: 8).padding(12)
                            Circle().trim(from: 0, to: progress).stroke(Theme.lemon, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90)).padding(12)
                            Image(systemName: "play.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.ink)
                        }
                        .frame(width: 76, height: 76)
                        .offset(x: 30, y: -30)
                    }
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("\(next.title), démarre dans quelques secondes")
            }
        }
    }
}
