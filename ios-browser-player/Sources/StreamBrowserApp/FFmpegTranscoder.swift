import Foundation

#if canImport(ffmpegkit)
import ffmpegkit
#endif

enum FFmpegTranscoder {
    enum TranscodeError: LocalizedError {
        case unavailable
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "FFmpeg n’est pas disponible dans cette version de l’application."
            case .failed(let message):
                return "La conversion FFmpeg a échoué\(message.isEmpty ? "." : " : \(message)")"
            }
        }
    }

    static func convertTS(at sourceURL: URL, to destinationURL: URL) async throws {
        #if canImport(ffmpegkit)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destinationURL)

        try await Task.detached(priority: .userInitiated) {
            // Remuxer le flux évite de dépendre des encodeurs libx264/AAC,
            // absents de certaines variantes minimales de FFmpegKit.
            let command = [
                "-y",
                "-i", shellQuote(sourceURL.path),
                "-map", "0:v:0",
                "-map", "0:a?",
                "-c", "copy",
                "-bsf:a", "aac_adtstoasc",
                "-movflags", "+faststart",
                shellQuote(destinationURL.path)
            ].joined(separator: " ")

            let session = FFmpegKit.execute(command)
            guard let returnCode = session?.getReturnCode(),
                  ReturnCode.isSuccess(returnCode),
                  FileManager.default.fileExists(atPath: destinationURL.path)
            else {
                let message = session?.getFailStackTrace() ?? ""
                throw TranscodeError.failed(message)
            }
        }.value
        #else
        throw TranscodeError.unavailable
        #endif
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}