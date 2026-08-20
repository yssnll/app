import AVKit
import AVFoundation
import SwiftUI
import UIKit

struct HLSPlayerView: View {
    let url: URL
    let initialPosition: Double
    let onPositionChanged: (Double) -> Void
    let onPlaybackStarted: () -> Void
    @State private var player: AVPlayer
    @State private var isFullScreen = false
    @State private var controlsVisible = true
    @State private var timeObserver: Any?

    init(
        url: URL,
        initialPosition: Double = 0,
        onPositionChanged: @escaping (Double) -> Void = { _ in },
        onPlaybackStarted: @escaping () -> Void = {}
    ) {
        self.url = url
        self.initialPosition = initialPosition
        self.onPositionChanged = onPositionChanged
        self.onPlaybackStarted = onPlaybackStarted
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PlayerViewControllerRepresentable(
                player: player
            )
                .accessibilityLabel("Lecteur vidéo HLS")

            if controlsVisible {
                Button {
                    isFullScreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.65), in: Circle())
                }
                .padding(12)
                .accessibilityLabel("Plein écran")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsVisible.toggle()
            }
            if controlsVisible {
                hideControlsSoon()
            }
        }
        .onAppear {
            configureAudioSession()
            if initialPosition > 0 {
                player.seek(
                    to: CMTime(seconds: initialPosition, preferredTimescale: 600)
                )
            }
            installTimeObserver()
            player.play()
            onPlaybackStarted()
            hideControlsSoon()
        }
        .onDisappear {
            saveCurrentPosition()
            removeTimeObserver()
            player.pause()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didEnterBackgroundNotification
            )
        ) { _ in
            saveCurrentPosition()
        }
        .fullScreenCover(isPresented: $isFullScreen) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()

                PlayerViewControllerRepresentable(
                    player: player
                )
                    .ignoresSafeArea()
                    .accessibilityLabel("Lecteur vidéo HLS en plein écran")
                    .onAppear {
                        configureAudioSession()
                        player.play()
                    }

                if controlsVisible {
                    Button {
                        isFullScreen = false
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.7), in: Circle())
                    }
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                    .accessibilityLabel("Quitter le plein écran")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    controlsVisible.toggle()
                }
                if controlsVisible {
                    hideControlsSoon()
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func hideControlsSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsVisible = false
            }
        }
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            )
            try audioSession.setActive(true)
        } catch {
            // La vidéo reste lisible même si iOS refuse l'activation audio.
        }
    }

    private func installTimeObserver() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 2, preferredTimescale: 600),
            queue: .main
        ) { time in
            guard time.isNumeric else { return }
            onPositionChanged(max(0, time.seconds))
        }
    }

    private func saveCurrentPosition() {
        let time = player.currentTime()
        guard time.isNumeric else { return }
        onPositionChanged(max(0, time.seconds))
    }

    private func removeTimeObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }
}

private struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.showsPlaybackControls = true
        return controller
    }

    func updateUIViewController(
        _ controller: AVPlayerViewController,
        context: Context
    ) {
        if controller.player !== player {
            controller.player = player
        }
    }
}