import Foundation

struct VideoQuality: Identifiable, Hashable {
    let id: String
    let label: String
    let url: URL
    let bitrate: Int?
    let resolution: String?

    var detail: String {
        var parts: [String] = []

        if let resolution {
            parts.append(resolution)
        }

        if let bitrate {
            parts.append(Self.formatBitrate(bitrate))
        }

        return parts.isEmpty ? "Qualité disponible" : parts.joined(separator: " · ")
    }

    static func original(url: URL) -> VideoQuality {
        VideoQuality(
            id: url.absoluteString,
            label: "Qualité d’origine",
            url: url,
            bitrate: nil,
            resolution: nil
        )
    }

    private static func formatBitrate(_ bitrate: Int) -> String {
        if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
        }
        return "\(Int(round(Double(bitrate) / 1_000))) Kbps"
    }
}

enum VideoQualityResolver {
    enum ResolverError: LocalizedError {
        case invalidPlaylist
        case requestFailed

        var errorDescription: String? {
            switch self {
            case .invalidPlaylist:
                return "La playlist vidéo n’est pas lisible."
            case .requestFailed:
                return "Impossible de récupérer les qualités disponibles."
            }
        }
    }

    static func resolve(for url: URL) async throws -> [VideoQuality] {
        guard url.pathExtension.lowercased() == "m3u8" else {
            return [.original(url: url)]
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let playlist = String(data: data, encoding: .utf8)
        else {
            throw ResolverError.requestFailed
        }

        let lines = playlist.components(separatedBy: .newlines)
        var qualities: [VideoQuality] = []

        for index in lines.indices {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("#EXT-X-STREAM-INF:") else { continue }
            guard index + 1 < lines.count else { continue }

            let attributes = parseAttributes(
                line.replacingOccurrences(of: "#EXT-X-STREAM-INF:", with: "")
            )
            guard let variantLine = lines[(index + 1)...].first(where: {
                let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                return !value.isEmpty && !value.hasPrefix("#")
            }),
            let variantURL = URL(string: variantLine.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: url)?.absoluteURL
            else {
                continue
            }

            let resolution = attributes["RESOLUTION"]
            let bitrate = Int(attributes["BANDWIDTH"] ?? attributes["AVERAGE-BANDWIDTH"] ?? "")
            let label = qualityLabel(resolution: resolution, attributes: attributes, bitrate: bitrate)

            qualities.append(
                VideoQuality(
                    id: variantURL.absoluteString,
                    label: label,
                    url: variantURL,
                    bitrate: bitrate,
                    resolution: resolution
                )
            )
        }

        if qualities.isEmpty {
            guard playlist.contains("#EXTINF:") || playlist.contains("#EXT-X-TARGETDURATION:") else {
                throw ResolverError.invalidPlaylist
            }
            return [.original(url: url)]
        }

        return qualities.sorted {
            let lhsHeight = height(from: $0.resolution)
            let rhsHeight = height(from: $1.resolution)

            if lhsHeight != rhsHeight {
                return lhsHeight > rhsHeight
            }

            return ($0.bitrate ?? 0) > ($1.bitrate ?? 0)
        }
    }

    private static func parseAttributes(_ value: String) -> [String: String] {
        value.split(separator: ",").reduce(into: [:]) { result, component in
            let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return }
            result[pair[0]] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
    }

    private static func qualityLabel(
        resolution: String?,
        attributes: [String: String],
        bitrate: Int?
    ) -> String {
        if let resolution, let height = height(from: resolution), height > 0 {
            return "\(height)p"
        }

        if let name = attributes["NAME"], !name.isEmpty {
            return name
        }

        if let bitrate {
            if bitrate >= 1_000_000 {
                return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
            }
            return "\(Int(round(Double(bitrate) / 1_000))) Kbps"
        }

        return "Qualité disponible"
    }

    private static func height(from resolution: String?) -> Int? {
        guard let resolution,
              let heightString = resolution.split(separator: "x").last,
              let height = Int(heightString)
        else {
            return nil
        }
        return height
    }
}