import AVKit
import AVFoundation
import SwiftUI

struct HLSPlayerView: View {
    let url: URL
    @State private var player: AVPlayer
    @State private var isFullScreen = false
    @State private var controlsVisible = true
    @State private var playerViewController: AVPlayerViewController?

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PlayerViewControllerRepresentable(
                player: player,
                onReady: { controller in
                    playerViewController = controller
                }
            )
                .accessibilityLabel("Lecteur vidéo HLS")

            if controlsVisible {
                HStack(spacing: 10) {
                    if AVPictureInPictureController.isPictureInPictureSupported() {
                        Button {
                            playerViewController?.startPictureInPicture()
                        } label: {
                            Image(systemName: "pip.enter")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.black.opacity(0.65), in: Circle())
                        }
                        .accessibilityLabel("Regarder en incrustation")
                    }

                    Button {
                        isFullScreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.65), in: Circle())
                    }
                    .accessibilityLabel("Plein écran")
                }
                .padding(12)
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
                    player: player,
                    onReady: { controller in
                        playerViewController = controller
                    }
                )
                    .ignoresSafeArea()
                    .accessibilityLabel("Lecteur vidéo HLS en plein écran")
                    .onAppear {
                        configureAudioSession()
                        player.play()
                    }

                if controlsVisible {
                    HStack(spacing: 10) {
                        if AVPictureInPictureController.isPictureInPictureSupported() {
                            Button {
                                playerViewController?.startPictureInPicture()
                            } label: {
                                Image(systemName: "pip.enter")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(.black.opacity(0.7), in: Circle())
                            }
                            .accessibilityLabel("Regarder en incrustation")
                        }

                        Button {
                            isFullScreen = false
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.black.opacity(0.7), in: Circle())
                        }
                        .accessibilityLabel("Quitter le plein écran")
                    }
                    .padding(.top, 18)
                    .padding(.trailing, 18)
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
            try? await Task.sleep(for: .seconds(3))
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
    let onReady: (AVPlayerViewController) -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.showsPlaybackControls = true
        onReady(controller)
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