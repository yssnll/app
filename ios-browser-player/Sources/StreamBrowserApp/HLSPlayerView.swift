import AVKit
import SwiftUI

struct HLSPlayerView: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        let headers: [String: String] = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 Version/16.0 Mobile/15E148 Safari/604.1",
            "Accept": "*/*"
        ]
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetHTTPHeaderFieldsKey: headers]
        )
        _player = State(initialValue: AVPlayer(playerItem: AVPlayerItem(asset: asset)))
    }

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player.play() }
            .onDisappear { player.pause() }
        .accessibilityLabel("Lecteur vidéo HLS")
    }
}