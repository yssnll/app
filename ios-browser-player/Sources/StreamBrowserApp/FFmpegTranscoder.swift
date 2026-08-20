import Foundation
import AVFoundation

enum FFmpegTranscoder {
    enum TranscodeError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message):
                return "La conversion vidéo a échoué\(message.isEmpty ? "." : " : \(message)")"
            }
        }
    }

    static func convertTS(at sourceURL: URL, to destinationURL: URL) async throws {
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destinationURL)

        let asset = AVURLAsset(url: sourceURL)
        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        guard let preset = presets.contains(AVAssetExportPresetHighestQuality)
            ? AVAssetExportPresetHighestQuality
            : presets.first,
              let exporter = AVAssetExportSession(asset: asset, presetName: preset),
              exporter.supportedFileTypes.contains(.mp4)
        else {
            throw TranscodeError.failed(
                "ce flux MPEG-TS n’est pas décodable par AVFoundation sur cet appareil"
            )
        }

        exporter.outputURL = destinationURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(
                        throwing: TranscodeError.failed(
                            exporter.error?.localizedDescription ?? ""
                        )
                    )
                default:
                    continuation.resume(throwing: TranscodeError.failed(""))
                }
            }
        }
    }
}