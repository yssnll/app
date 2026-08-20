import AVKit
import SwiftUI

struct HLSPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var errorMessage: String?

    init(url: URL) {
        self.url = url
    }

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                    Text("Impossible de lire cette vidéo")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            } else {
                ProgressView("Préparation du flux…")
            }
        }
        .task(id: url) {
            await preparePlayer()
        }
        .onDisappear {
            player?.pause()
        }
        .accessibilityLabel("Lecteur vidéo HLS")
    }

    @MainActor
    private func preparePlayer() async {
        player?.pause()
        player = nil
        errorMessage = nil

        do {
            let qualities = try await VideoQualityResolver.resolve(for: url)
            let playableURL = qualities.first?.url ?? url
            let headers: [String: String] = [
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 Version/16.0 Mobile/15E148 Safari/604.1",
                "Accept": "*/*"
            ]
            let asset = AVURLAsset(
                url: playableURL,
                options: [AVURLAssetHTTPHeaderFieldsKey: headers]
            )
            let newPlayer = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            player = newPlayer
            newPlayer.play()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}