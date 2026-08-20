import AVKit
import AVFoundation
import SwiftUI

struct HLSPlayerView: View {
    let url: URL
    @State private var player: AVPlayer
    @State private var isFullScreen = false

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VideoPlayer(player: player)
                .accessibilityLabel("Lecteur vidéo HLS")

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
        .onAppear {
            configureAudioSession()
            player.play()
        }
        .onDisappear {
            player.pause()
        }
        .fullScreenCover(isPresented: $isFullScreen) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()

                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .accessibilityLabel("Lecteur vidéo HLS en plein écran")
                    .onAppear {
                        configureAudioSession()
                        player.play()
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
                .padding(.top, 18)
                .padding(.trailing, 18)
                .accessibilityLabel("Quitter le plein écran")
            }
            .preferredColorScheme(.dark)
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