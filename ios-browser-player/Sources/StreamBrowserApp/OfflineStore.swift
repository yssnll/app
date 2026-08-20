import AVFoundation
import Combine
import Foundation

struct OfflineVideo: Codable, Identifiable, Hashable {
    enum Status: String, Codable {
        case downloading
        case converting
        case completed
        case failed
    }

    let id: UUID
    let title: String
    let sourceURL: String
    let localPath: String?
    let qualityLabel: String
    let downloadedAt: Date
    let status: Status
    let errorMessage: String?
    let taskIdentifier: Int?

    init(
        id: UUID = UUID(),
        title: String,
        sourceURL: String,
        localPath: String? = nil,
        qualityLabel: String,
        downloadedAt: Date = Date(),
        status: Status = .downloading,
        errorMessage: String? = nil,
        taskIdentifier: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.localPath = localPath
        self.qualityLabel = qualityLabel
        self.downloadedAt = downloadedAt
        self.status = status
        self.errorMessage = errorMessage
        self.taskIdentifier = taskIdentifier
    }
}

@MainActor
final class OfflineStore: NSObject, ObservableObject {
    private static let backgroundSessionIdentifier = "com.example.StreamBrowser.offline-assets"
    private static let fileBackgroundSessionIdentifier = "com.example.StreamBrowser.file-downloads"
    static weak var shared: OfflineStore?
    private static var pendingBackgroundCompletionHandlers: [
        String: () -> Void
    ] = [:]

    private enum DownloadError: LocalizedError {
        case unsupportedVideoFormat
        case mp4ExportUnavailable
        case exportFailed
        case hlsTaskCreationFailed
        case interrupted
        case invalidHLSPlaylist
        case encryptedHLSUnsupported
        case hlsSegmentFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedVideoFormat:
                return "Ce format vidéo n’est pas compatible avec la conversion MP4 sur cet iPhone."
            case .mp4ExportUnavailable:
                return "La conversion MP4 n’est pas disponible pour cette vidéo."
            case .exportFailed:
                return "La conversion de la vidéo en MP4 a échoué."
            case .hlsTaskCreationFailed:
                return "Le téléchargement HLS n’a pas pu démarrer. Vérifiez que le lien est encore valide."
            case .interrupted:
                return "Le téléchargement a été interrompu avant sa finalisation."
            case .invalidHLSPlaylist:
                return "La playlist HLS est invalide ou ne contient aucun segment vidéo."
            case .encryptedHLSUnsupported:
                return "Cette vidéo HLS est chiffrée et ne peut pas être enregistrée hors ligne."
            case .hlsSegmentFailed:
                return "Un segment vidéo n’a pas pu être téléchargé. Le lien a peut-être expiré."
            }
        }
    }

    @Published private(set) var videos: [OfflineVideo] = []
    @Published private(set) var progress: [UUID: Double] = [:]

    private let fileManager = FileManager.default
    private let stateFileName = "offline-videos.json"
    private let networkHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 Version/16.0 Mobile/15E148 Safari/604.1",
        "Accept": "*/*"
    ]
    // Keep the CDN busy without creating an excessive number of requests.
    // HLS segments are independent, so a moderate amount of parallelism
    // noticeably reduces the total download time without changing quality.
    private let maxConcurrentHLSSegmentDownloads = 16
    private lazy var hlsSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.httpMaximumConnectionsPerHost = 16
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
    private var assetTasks: [Int: UUID] = [:]
    private var fileTasks: [Int: UUID] = [:]
    private var backgroundCompletionHandler: (() -> Void)?

    override init() {
        super.init()
        Self.shared = self
        prepareDocumentsStorage()
        loadState()
        restoreBackgroundTasks()
        resumePendingConversions()
        for identifier in [
            Self.backgroundSessionIdentifier,
            Self.fileBackgroundSessionIdentifier
        ] {
            if let completionHandler = Self.pendingBackgroundCompletionHandlers
                .removeValue(forKey: identifier) {
                handleBackgroundEvents(
                    for: identifier,
                    completionHandler: completionHandler
                )
            }
        }
    }

    private lazy var configuredAssetSession: AVAssetDownloadURLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.backgroundSessionIdentifier
        )
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.httpAdditionalHeaders = networkHeaders
        return AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: self,
            delegateQueue: OperationQueue.main
        )
    }()

    private lazy var fileBackgroundSession: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.fileBackgroundSessionIdentifier
        )
        // The system URLSession daemon owns this transfer, so it continues
        // while the app is suspended or the phone is locked.
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.httpAdditionalHeaders = networkHeaders
        return URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: OperationQueue.main
        )
    }()

    func startDownload(_ quality: VideoQuality, title: String? = nil) {
        let displayTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = OfflineVideo(
            title: displayTitle?.isEmpty == false ? displayTitle! : "Vidéo téléchargée",
            sourceURL: quality.url.absoluteString,
            qualityLabel: quality.label
        )
        videos.insert(item, at: 0)
        progress[item.id] = 0
        saveState()

        if quality.isHLS || quality.url.pathExtension.lowercased() == "m3u8" {
            startHLSDownload(item: item, url: quality.url)
        } else {
            startFileDownload(item: item, url: quality.url)
        }
    }

    func localURL(for video: OfflineVideo) -> URL? {
        guard video.status == .completed || video.status == .converting,
              let localPath = video.localPath,
              fileManager.fileExists(atPath: localPath)
        else {
            return nil
        }
        return URL(fileURLWithPath: localPath)
    }

    static func receiveBackgroundEvents(
        for identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == backgroundSessionIdentifier
                || identifier == fileBackgroundSessionIdentifier
        else {
            completionHandler()
            return
        }

        if let store = shared {
            store.handleBackgroundEvents(
                for: identifier,
                completionHandler: completionHandler
            )
        } else {
            pendingBackgroundCompletionHandlers[identifier] = completionHandler
        }
    }

    func handleBackgroundEvents(
        for identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == Self.backgroundSessionIdentifier
                || identifier == Self.fileBackgroundSessionIdentifier
        else {
            completionHandler()
            return
        }

        backgroundCompletionHandler = completionHandler
        if identifier == Self.backgroundSessionIdentifier {
            _ = configuredAssetSession
        } else {
            _ = fileBackgroundSession
        }
    }

    func remove(_ video: OfflineVideo) {
        if let localPath = video.localPath {
            try? fileManager.removeItem(atPath: localPath)
        }
        videos.removeAll { $0.id == video.id }
        progress[video.id] = nil
        saveState()
    }

    func rename(_ video: OfflineVideo, to title: String) {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty,
              let index = videos.firstIndex(where: { $0.id == video.id })
        else {
            return
        }

        let current = videos[index]
        videos[index] = OfflineVideo(
            id: current.id,
            title: cleanedTitle,
            sourceURL: current.sourceURL,
            localPath: current.localPath,
            qualityLabel: current.qualityLabel,
            downloadedAt: current.downloadedAt,
            status: current.status,
            errorMessage: current.errorMessage,
            taskIdentifier: current.taskIdentifier
        )
        saveState()
    }

    private func startFileDownload(item: OfflineVideo, url: URL) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60 * 60
        request.allHTTPHeaderFields = networkHeaders
        let task = fileBackgroundSession.downloadTask(with: request)
        task.taskDescription = item.id.uuidString
        fileTasks[task.taskIdentifier] = item.id
        attachTask(task.taskIdentifier, to: item)
        progress[item.id] = 0
        task.resume()
    }

    private func processFileDownload(
        item: OfflineVideo,
        temporaryURL: URL,
        response: URLResponse?
    ) async {
        do {
            try fileManager.createDirectory(
                at: offlineDirectory,
                withIntermediateDirectories: true
            )

            let destination = mp4URL(for: item.id)
            let mimeType = response?.mimeType
                .map { value in
                    String(value.split(
                        separator: ";",
                        maxSplits: 1,
                        omittingEmptySubsequences: true
                    ).first ?? "")
                }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let sourceIsAlreadyMP4 = URL(string: item.sourceURL)?
                .pathExtension.lowercased() == "mp4"
                || mimeType == "video/mp4"

            progress[item.id] = 0.55
            if sourceIsAlreadyMP4 {
                try? fileManager.removeItem(at: destination)
                try fileManager.moveItem(at: temporaryURL, to: destination)
            } else {
                // Passthrough remuxing preserves every byte of the encoded
                // audio/video and avoids a slow re-encode.
                do {
                    try await exportToMP4(
                        sourceURL: temporaryURL,
                        destinationURL: destination,
                        preferPassthrough: true
                    )
                    try? fileManager.removeItem(at: temporaryURL)
                } catch {
                    // Keep the conversion fallback for formats that cannot
                    // be remuxed directly into an MP4 container.
                    try await exportToMP4(
                        sourceURL: temporaryURL,
                        destinationURL: destination
                    )
                    try? fileManager.removeItem(at: temporaryURL)
                }
            }
            finish(item: item, localURL: destination)
        } catch {
            fail(item: item, error: error)
        }
    }

    private func startHLSDownload(item: OfflineVideo, url: URL) {
        // AVAssetDownloadURLSession is convenient but unreliable with signed
        // CDNs: query parameters are often lost when resolving segment URLs.
        // Download the playlist ourselves and write a local HLS playlist so
        // every segment receives the original signed query.
        Task { @MainActor in
            await self.downloadHLSPlaylist(item: item, url: url)
        }
    }

    private struct HLSSegment {
        let duration: String
        let url: URL
    }

    private func downloadHLSPlaylist(item: OfflineVideo, url: URL) async {
        let temporaryDirectory = offlineDirectory
            .appendingPathComponent("\(item.id.uuidString).hls.tmp", isDirectory: true)
        let finalDirectory = offlineDirectory
            .appendingPathComponent("\(item.id.uuidString).hls", isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )
            try? fileManager.removeItem(at: finalDirectory)

            let playlist = try await requestText(url: url)
            guard !playlist.contains("#EXT-X-KEY:METHOD=AES-128")
                    && !playlist.contains("#EXT-X-KEY:METHOD=SAMPLE-AES")
            else {
                throw DownloadError.encryptedHLSUnsupported
            }

            let parsed = try parseMediaPlaylist(playlist, baseURL: url)
            guard !parsed.segments.isEmpty else {
                throw DownloadError.invalidHLSPlaylist
            }

            var initializationData: Data?
            if let mapURL = parsed.mapURL {
                let (data, _) = try await requestData(url: mapURL)
                initializationData = data
                try data.write(
                    to: temporaryDirectory.appendingPathComponent("init.mp4"),
                    options: .atomic
                )
            }

            let segmentURLs = try await downloadHLSSegments(
                parsed.segments,
                item: item,
                in: temporaryDirectory,
                extensionName: parsed.mapURL == nil ? "ts" : "m4s"
            )

            // Build one local media file before asking AVFoundation to export.
            // This is more reliable than exporting a file:// HLS playlist,
            // especially for MPEG-TS streams.
            let combinedExtension = parsed.mapURL == nil ? "ts" : "mp4"
            let combinedURL = temporaryDirectory
                .appendingPathComponent("combined")
                .appendingPathExtension(combinedExtension)
            fileManager.createFile(atPath: combinedURL.path, contents: nil)
            do {
                let combinedHandle = try FileHandle(forWritingTo: combinedURL)
                if let initializationData {
                    try combinedHandle.write(contentsOf: initializationData)
                }
                for segmentURL in segmentURLs {
                    try combinedHandle.write(contentsOf: Data(contentsOf: segmentURL))
                }
                try combinedHandle.close()
            }

            // A downloaded HLS stream without an EXT-X-MAP is normally an
            // MPEG-TS stream. Do not expose that .ts file as the completed
            // download: it is not consistently playable by AVPlayer when
            // opened as a standalone local file. Export it to a real MP4
            // container first, just like direct video downloads.
            if parsed.mapURL == nil {
                let destination = mp4URL(for: item.id)
                markConverting(item: item, packageURL: combinedURL)
                do {
                    try await FFmpegTranscoder.convertTS(
                        at: combinedURL,
                        to: destination
                    )

                    try? fileManager.removeItem(at: temporaryDirectory)
                    finish(
                        item: item,
                        localURL: destination,
                        note: "Vidéo convertie en MP4 et disponible hors ligne."
                    )
                } catch {
                    // Certains flux MPEG-TS ne peuvent pas être remuxés par
                    // FFmpegKit minimal. Garder le TS téléchargé est préférable
                    // à perdre tout le téléchargement : AVPlayer peut souvent
                    // encore le lire localement.
                    try? fileManager.removeItem(at: destination)
                    finish(
                        item: item,
                        localURL: combinedURL,
                        note: "Téléchargée hors ligne (format TS)."
                    )
                }
                return
            }

            let localPlaylist = makeLocalPlaylist(
                parsed: parsed,
                hasInitializationMap: parsed.mapURL != nil
            )
            try localPlaylist.write(
                to: temporaryDirectory.appendingPathComponent("offline.m3u8"),
                atomically: true,
                encoding: .utf8
            )
            try fileManager.moveItem(at: temporaryDirectory, to: finalDirectory)

            let combinedFinalURL = finalDirectory
                .appendingPathComponent("combined")
                .appendingPathExtension(combinedExtension)
            let destination = offlineDirectory
                .appendingPathComponent(item.id.uuidString)
                .appendingPathExtension(combinedExtension)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: combinedFinalURL, to: destination)
            try? fileManager.removeItem(at: finalDirectory)

            finish(
                item: item,
                localURL: destination,
                note: "Vidéo disponible hors ligne."
            )
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            try? fileManager.removeItem(at: finalDirectory)
            fail(item: item, error: error)
        }
    }

    private func downloadHLSSegments(
        _ segments: [HLSSegment],
        item: OfflineVideo,
        in directory: URL,
        extensionName: String
    ) async throws -> [URL] {
        var segmentURLs = [URL?](repeating: nil, count: segments.count)
        var nextIndex = 0
        var completedCount = 0

        try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            let initialCount = min(
                maxConcurrentHLSSegmentDownloads,
                segments.count
            )

            for _ in 0..<initialCount {
                let index = nextIndex
                nextIndex += 1
                let segment = segments[index]
                let segmentURL = directory
                    .appendingPathComponent(String(format: "segment-%05d", index))
                    .appendingPathExtension(extensionName)

                group.addTask {
                    let (data, _) = try await self.requestData(url: segment.url)
                    try data.write(to: segmentURL, options: .atomic)
                    return (index, segmentURL)
                }
            }

            while let (index, segmentURL) = try await group.next() {
                segmentURLs[index] = segmentURL
                completedCount += 1
                progress[item.id] = min(
                    0.95,
                    Double(completedCount) / Double(segments.count)
                )

                guard nextIndex < segments.count else { continue }
                let currentIndex = nextIndex
                let segment = segments[currentIndex]
                nextIndex += 1
                let nextSegmentURL = directory
                    .appendingPathComponent(
                        String(format: "segment-%05d", currentIndex)
                    )
                    .appendingPathExtension(extensionName)

                group.addTask {
                    let (data, _) = try await self.requestData(url: segment.url)
                    try data.write(to: nextSegmentURL, options: .atomic)
                    return (currentIndex, nextSegmentURL)
                }
            }
        }

        return segmentURLs.compactMap { $0 }
    }

    private struct ParsedHLSPlaylist {
        let targetDuration: String
        let mapURL: URL?
        let segments: [HLSSegment]
    }

    private func parseMediaPlaylist(
        _ playlist: String,
        baseURL: URL
    ) throws -> ParsedHLSPlaylist {
        let lines = playlist.components(separatedBy: .newlines)
        var targetDuration = "10"
        var mapURL: URL?
        var segments: [HLSSegment] = []
        var pendingDuration: String?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                targetDuration = String(line.dropFirst("#EXT-X-TARGETDURATION:".count))
            } else if line.hasPrefix("#EXT-X-MAP:") {
                guard let value = attribute(named: "URI", in: line),
                      let resolved = signedURL(value, relativeTo: baseURL)
                else {
                    throw DownloadError.invalidHLSPlaylist
                }
                mapURL = resolved
            } else if line.hasPrefix("#EXTINF:") {
                pendingDuration = String(
                    line.dropFirst("#EXTINF:".count)
                ).split(separator: ",", maxSplits: 1).first.map(String.init)
            } else if !line.hasPrefix("#"), let duration = pendingDuration,
                      let segmentURL = signedURL(line, relativeTo: baseURL) {
                segments.append(HLSSegment(duration: duration, url: segmentURL))
                pendingDuration = nil
            }
        }

        guard playlist.hasPrefix("#EXTM3U"), !segments.isEmpty else {
            throw DownloadError.invalidHLSPlaylist
        }
        return ParsedHLSPlaylist(
            targetDuration: targetDuration,
            mapURL: mapURL,
            segments: segments
        )
    }

    private func makeLocalPlaylist(
        parsed: ParsedHLSPlaylist,
        hasInitializationMap: Bool
    ) -> String {
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            "#EXT-X-TARGETDURATION:\(parsed.targetDuration)",
            "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PLAYLIST-TYPE:VOD"
        ]
        if hasInitializationMap {
            lines.append("#EXT-X-MAP:URI=\"init.mp4\"")
        }
        for (index, segment) in parsed.segments.enumerated() {
            let extensionName = hasInitializationMap ? "m4s" : "ts"
            lines.append("#EXTINF:\(segment.duration),")
            lines.append("segment-\(String(format: "%05d", index)).\(extensionName)")
        }
        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n") + "\n"
    }

    private func requestText(url: URL) async throws -> String {
        let (data, _) = try await requestData(url: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DownloadError.invalidHLSPlaylist
        }
        return text
    }

    private func requestData(url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.allHTTPHeaderFields = networkHeaders
        let (data, response) = try await hlsSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw DownloadError.hlsSegmentFailed
        }
        return (data, httpResponse)
    }

    private func signedURL(_ value: String, relativeTo baseURL: URL) -> URL? {
        guard let resolved = URL(string: value, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }
        guard resolved.query == nil,
              let inheritedQuery = baseURL.query,
              var components = URLComponents(
                url: resolved,
                resolvingAgainstBaseURL: false
              )
        else {
            return resolved
        }
        components.query = inheritedQuery
        return components.url ?? resolved
    }

    private func attribute(named name: String, in line: String) -> String? {
        let prefix = "\(name)=\""
        guard let start = line.range(of: prefix)?.upperBound,
              let end = line[start...].firstIndex(of: "\"")
        else {
            return nil
        }
        return String(line[start..<end])
    }

    private func resumePendingConversions() {
        for video in videos where video.status == .converting {
            guard let localPath = video.localPath else { continue }
            let packageURL = URL(fileURLWithPath: localPath)
            guard fileManager.fileExists(atPath: localPath) else { continue }

            Task { @MainActor in
                await convertPackage(item: video, packageURL: packageURL)
            }
        }
    }

    private func attachTask(_ taskIdentifier: Int, to item: OfflineVideo) {
        guard let index = videos.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        videos[index] = OfflineVideo(
            id: item.id,
            title: item.title,
            sourceURL: item.sourceURL,
            localPath: item.localPath,
            qualityLabel: item.qualityLabel,
            downloadedAt: item.downloadedAt,
            status: item.status,
            errorMessage: item.errorMessage,
            taskIdentifier: taskIdentifier
        )
        saveState()
    }

    private func exportToMP4(
        sourceURL: URL,
        destinationURL: URL,
        preferPassthrough: Bool = false
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        try await exportToMP4(
            asset: asset,
            destinationURL: destinationURL,
            preferPassthrough: preferPassthrough
        )
    }

    private func exportToMP4(
        asset: AVAsset,
        destinationURL: URL,
        preferPassthrough: Bool = false
    ) async throws {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: destinationURL)

        let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let preset: String
        if preferPassthrough,
           compatiblePresets.contains(AVAssetExportPresetPassthrough) {
            preset = AVAssetExportPresetPassthrough
        } else {
            // Passthrough frequently fails for MPEG-TS -> MP4. Force a real
            // transcode for those streams instead of returning a broken
            // or empty container.
            preset = compatiblePresets.contains(AVAssetExportPresetHighestQuality)
                ? AVAssetExportPresetHighestQuality
                : compatiblePresets.first ?? AVAssetExportPresetHighestQuality
        }

        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset),
              exporter.supportedFileTypes.contains(.mp4)
        else {
            throw DownloadError.mp4ExportUnavailable
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
                    let message = exporter.error?.localizedDescription
                        ?? DownloadError.exportFailed.localizedDescription
                    continuation.resume(
                        throwing: NSError(
                            domain: "StreamBrowser.Download",
                            code: 1,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Conversion MP4 échouée : \(message)"
                            ]
                        )
                    )
                default:
                    continuation.resume(throwing: DownloadError.exportFailed)
                }
            }
        }
    }

    private func finish(
        item: OfflineVideo,
        localURL: URL,
        note: String? = nil
    ) {
        update(
            item: item,
            status: .completed,
            localPath: localURL.path,
            errorMessage: note,
            taskIdentifier: nil
        )
        progress[item.id] = 1
    }

    private func markConverting(item: OfflineVideo, packageURL: URL) {
        update(
            item: item,
            status: .converting,
            localPath: packageURL.path,
            taskIdentifier: nil
        )
        progress[item.id] = 0.98
    }

    private func convertPackage(item: OfflineVideo, packageURL: URL) async {
        do {
            let destination = mp4URL(for: item.id)
            try await exportToMP4(
                sourceURL: packageURL,
                destinationURL: destination
            )
            try? fileManager.removeItem(at: packageURL)
            finish(item: item, localURL: destination)
        } catch {
            // The package itself remains playable with AVPlayer. Conversion is
            // optional and must not make an otherwise complete download fail.
            finish(
                item: item,
                localURL: packageURL,
                note: "Vidéo disponible hors ligne (format HLS local)."
            )
        }
    }

    private func fail(item: OfflineVideo, error: Error? = nil) {
        update(
            item: item,
            status: .failed,
            localPath: nil,
            errorMessage: error?.localizedDescription,
            taskIdentifier: nil
        )
        progress[item.id] = nil
    }

    private func update(
        item: OfflineVideo,
        status: OfflineVideo.Status,
        localPath: String?,
        errorMessage: String? = nil,
        taskIdentifier: Int? = nil
    ) {
        guard let index = videos.firstIndex(where: { $0.id == item.id }) else { return }
        videos[index] = OfflineVideo(
            id: item.id,
            title: item.title,
            sourceURL: item.sourceURL,
            localPath: localPath,
            qualityLabel: item.qualityLabel,
            downloadedAt: item.downloadedAt,
            status: status,
            errorMessage: errorMessage,
            taskIdentifier: taskIdentifier
        )
        saveState()
    }

    private var applicationSupportDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var legacyOfflineDirectory: URL {
        applicationSupportDirectory.appendingPathComponent(
            "OfflineVideos",
            isDirectory: true
        )
    }

    private var offlineDirectory: URL {
        documentsDirectory.appendingPathComponent(
            "Stream Browser Downloads",
            isDirectory: true
        )
    }

    private func hlsPackageURL(for id: UUID) -> URL {
        offlineDirectory
            .appendingPathComponent(id.uuidString)
            .appendingPathExtension("movpkg")
    }

    private func mp4URL(for id: UUID) -> URL {
        offlineDirectory
            .appendingPathComponent(id.uuidString)
            .appendingPathExtension("mp4")
    }

    private var stateURL: URL {
        applicationSupportDirectory.appendingPathComponent(stateFileName)
    }

    private func prepareDocumentsStorage() {
        do {
            try fileManager.createDirectory(
                at: offlineDirectory,
                withIntermediateDirectories: true
            )
            migrateLegacyDownloads()
        } catch {
            // A later download reports the visible error if Documents is
            // unavailable. The directory is retried when that download starts.
        }
    }

    private func migrateLegacyDownloads() {
        guard fileManager.fileExists(atPath: legacyOfflineDirectory.path),
              let entries = try? fileManager.contentsOfDirectory(
                  at: legacyOfflineDirectory,
                  includingPropertiesForKeys: nil
              )
        else {
            return
        }

        for entry in entries {
            let destination = offlineDirectory.appendingPathComponent(entry.lastPathComponent)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            try? fileManager.moveItem(at: entry, to: destination)
        }
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL),
              let savedVideos = try? JSONDecoder().decode([OfflineVideo].self, from: data)
        else {
            return
        }

        var stateWasMigrated = false
        videos = savedVideos.compactMap { video in
            let normalizedLocalPath = normalizedLocalPath(for: video.localPath)
            stateWasMigrated = stateWasMigrated || normalizedLocalPath != video.localPath
            switch video.status {
            case .completed, .converting:
                guard let localPath = normalizedLocalPath,
                      fileManager.fileExists(atPath: localPath)
                else {
                    return nil
                }
            case .downloading, .failed:
                break
            }
            guard normalizedLocalPath != video.localPath else {
                return video
            }
            return OfflineVideo(
                id: video.id,
                title: video.title,
                sourceURL: video.sourceURL,
                localPath: normalizedLocalPath,
                qualityLabel: video.qualityLabel,
                downloadedAt: video.downloadedAt,
                status: video.status,
                errorMessage: video.errorMessage,
                taskIdentifier: video.taskIdentifier
            )
        }
        if stateWasMigrated {
            saveState()
        }

        for video in videos {
            switch video.status {
            case .downloading:
                progress[video.id] = 0
            case .converting:
                progress[video.id] = 0.98
            case .completed, .failed:
                break
            }
        }
    }

    private func normalizedLocalPath(for path: String?) -> String? {
        guard let path else { return nil }
        guard path.hasPrefix(legacyOfflineDirectory.path) else { return path }

        let relativePath = String(
            path.dropFirst(legacyOfflineDirectory.path.count)
        ).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty else { return path }

        let newURL = offlineDirectory.appendingPathComponent(relativePath)
        return fileManager.fileExists(atPath: newURL.path) ? newURL.path : path
    }

    private func restoreBackgroundTasks() {
        // The task description is not guaranteed to survive an iOS wake-up.
        // Keep the mapping from the identifier persisted with each item.
        assetTasks = videos.reduce(into: [:]) { result, video in
            guard let taskIdentifier = video.taskIdentifier else { return }
            result[taskIdentifier] = video.id
        }
        let persistedTaskIDs = assetTasks

        configuredAssetSession.getAllTasks { tasks in
            let taskIDs = tasks.reduce(into: [Int: UUID]()) { result, task in
                guard let assetTask = task as? AVAssetDownloadTask,
                      let id = assetTask.taskDescription.flatMap(UUID.init(uuidString:))
                          ?? persistedTaskIDs[assetTask.taskIdentifier]
                else {
                    return
                }
                result[assetTask.taskIdentifier] = id
            }

            Task { @MainActor in
                self.assetTasks.merge(taskIDs) { _, latest in latest }
                for video in self.videos where video.status == .downloading {
                    self.progress[video.id] = 0
                }
            }
        }

        fileBackgroundSession.getAllTasks { tasks in
            let taskIDs = tasks.reduce(into: [Int: UUID]()) { result, task in
                guard let id = task.taskDescription.flatMap(UUID.init(uuidString:))
                    ?? self.fileTasks[task.taskIdentifier]
                else {
                    return
                }
                result[task.taskIdentifier] = id
            }

            Task { @MainActor in
                self.fileTasks.merge(taskIDs) { _, latest in latest }
                for video in self.videos where video.status == .downloading {
                    self.progress[video.id] = 0
                }
            }
        }
    }

    private func saveState() {
        guard let data = try? JSONEncoder().encode(videos) else { return }
        do {
            try fileManager.createDirectory(
                at: applicationSupportDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: stateURL, options: .atomic)
        } catch {
            // The current download remains usable when persistence is unavailable.
        }
    }

    private func fileExtension(for mimeType: String) -> String? {
        switch mimeType.lowercased() {
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "video/x-m4v": return "m4v"
        case "video/webm": return "webm"
        default: return nil
        }
    }
}

extension OfflineStore: AVAssetDownloadDelegate, URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard session.configuration.identifier
                == Self.fileBackgroundSessionIdentifier,
              totalBytesExpectedToWrite > 0
        else {
            return
        }

        let nextProgress = min(
            max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0),
            0.99
        )
        let taskIdentifier = downloadTask.taskIdentifier
        let taskDescription = downloadTask.taskDescription
        Task { @MainActor in
            guard let id = self.fileID(
                from: taskDescription,
                taskIdentifier: taskIdentifier
            )
            else {
                return
            }
            self.progress[id] = nextProgress
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard session.configuration.identifier
                == Self.fileBackgroundSessionIdentifier
        else {
            return
        }

        let taskIdentifier = downloadTask.taskIdentifier
        let taskDescription = downloadTask.taskDescription
        let response = downloadTask.response
        Task { @MainActor in
            guard let id = self.fileID(
                from: taskDescription,
                taskIdentifier: taskIdentifier
            ),
            let item = self.videos.first(where: { $0.id == id })
            else {
                return
            }

            self.fileTasks[taskIdentifier] = nil
            await self.processFileDownload(
                item: item,
                temporaryURL: location,
                response: response
            )
        }
    }

    nonisolated func urlSession(
        _ session: AVAssetDownloadURLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskIdentifier = assetDownloadTask.taskIdentifier
        let taskDescription = assetDownloadTask.taskDescription

        Task { @MainActor in
            guard let id = self.id(
                from: taskDescription,
                taskIdentifier: taskIdentifier
            ),
            let item = self.videos.first(where: { $0.id == id })
            else {
                return
            }

            do {
                // AVAssetDownloadURLSession gives us a temporary .movpkg
                // directory. It must be moved before the delegate returns or
                // iOS may remove it after the background task completes.
                let packageURL = self.hlsPackageURL(for: id)
                try self.fileManager.createDirectory(
                    at: self.offlineDirectory,
                    withIntermediateDirectories: true
                )
                try? self.fileManager.removeItem(at: packageURL)
                do {
                    try self.fileManager.moveItem(at: location, to: packageURL)
                } catch {
                    // A copy fallback is useful when iOS places the temporary
                    // package on a different volume during a background wake.
                    try self.fileManager.copyItem(at: location, to: packageURL)
                    try? self.fileManager.removeItem(at: location)
                }

                // .movpkg is Apple's native offline HLS format. It is already
                // playable by AVPlayer, so do not block visibility on an
                // optional MP4 export (which can hang or be unsupported for
                // encrypted/segmented streams).
                self.finish(
                    item: item,
                    localURL: packageURL,
                    note: "Disponible hors ligne (HLS local)."
                )
                self.assetTasks[taskIdentifier] = nil
            } catch {
                self.fail(item: item, error: error)
            }
        }
    }

    nonisolated func urlSession(
        _ session: AVAssetDownloadURLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didLoad timeRange: CMTimeRange,
        totalTimeRangesLoaded loadedTimeRanges: [NSValue],
        timeRangeExpectedToLoad: CMTimeRange
    ) {
        let taskIdentifier = assetDownloadTask.taskIdentifier
        let taskDescription = assetDownloadTask.taskDescription
        guard timeRangeExpectedToLoad.duration.seconds > 0 else {
            return
        }

        let loaded = loadedTimeRanges.reduce(0.0) { partialResult, value in
            partialResult + value.timeRangeValue.duration.seconds
        }
        let expected = timeRangeExpectedToLoad.duration.seconds
        let nextProgress = min(max(loaded / expected, 0), 0.99)

        Task { @MainActor in
            if let id = self.id(
                from: taskDescription,
                taskIdentifier: taskIdentifier
            ) {
                self.progress[id] = nextProgress
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else {
            return
        }
        let taskIdentifier = task.taskIdentifier
        let taskDescription = task.taskDescription

        Task { @MainActor in
            if session.configuration.identifier
                    == Self.fileBackgroundSessionIdentifier {
                guard let id = self.fileID(
                    from: taskDescription,
                    taskIdentifier: taskIdentifier
                ),
                let item = self.videos.first(where: { $0.id == id })
                else {
                    return
                }

                // Background URLSession normally waits for connectivity
                // itself. If iOS reports a transient disconnect, recreate
                // the task with resume data and keep the item in "downloading"
                // instead of showing a failure to the user.
                guard self.isTemporaryNetworkError(error) else {
                    self.fileTasks[taskIdentifier] = nil
                    self.fail(item: item, error: error)
                    return
                }

                let replacement: URLSessionDownloadTask
                if let resumeData = (error as NSError).userInfo[
                    NSURLSessionDownloadTaskResumeData
                ] as? Data {
                    replacement = self.fileBackgroundSession
                        .downloadTask(withResumeData: resumeData)
                } else {
                    guard let sourceURL = URL(string: item.sourceURL) else {
                        self.fileTasks[taskIdentifier] = nil
                        self.fail(item: item, error: error)
                        return
                    }
                    var request = URLRequest(url: sourceURL)
                    request.timeoutInterval = 60 * 60
                    request.allHTTPHeaderFields = self.networkHeaders
                    replacement = self.fileBackgroundSession
                        .downloadTask(with: request)
                }
                replacement.taskDescription = item.id.uuidString
                self.fileTasks[replacement.taskIdentifier] = id
                self.attachTask(replacement.taskIdentifier, to: item)
                self.progress[id] = self.progress[id] ?? 0
                replacement.resume()
                return
            }

            guard let id = self.id(
                from: taskDescription,
                taskIdentifier: taskIdentifier
            ),
            let item = self.videos.first(where: { $0.id == id }),
            item.status != .completed
            else {
                return
            }

            self.fail(item: item, error: error)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            let completionHandler = self.backgroundCompletionHandler
            self.backgroundCompletionHandler = nil
            completionHandler?()
        }
    }

    private func id(from taskDescription: String?, taskIdentifier: Int) -> UUID? {
        if let taskDescription,
           let id = UUID(uuidString: taskDescription) {
            return id
        }
        return assetTasks[taskIdentifier]
    }

    private func fileID(
        from taskDescription: String?,
        taskIdentifier: Int
    ) -> UUID? {
        if let taskDescription,
           let id = UUID(uuidString: taskDescription) {
            return id
        }
        return fileTasks[taskIdentifier]
    }

    private func isTemporaryNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }
        return [
            .notConnectedToInternet,
            .networkConnectionLost,
            .timedOut,
            .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed,
            .resourceUnavailable
        ].contains(urlError.code)
    }
}