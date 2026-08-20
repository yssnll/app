import AVKit
import AVFoundation
import SwiftUI

struct HLSPlayerView: View {
    let url: URL
    @State private var player: AVPlayer
    @State private var isFullScreen = false
    @State private var controlsVisible = true

    init(url: URL) {
        self.url = url
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
            player.play()
            hideControlsSoon()
        }
        .onDisappear {
            player.pause()
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