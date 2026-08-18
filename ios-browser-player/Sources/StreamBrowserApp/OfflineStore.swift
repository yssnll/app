import AVFoundation
import Combine
import Foundation

struct OfflineVideo: Codable, Identifiable, Hashable {
    enum Status: String, Codable {
        case downloading
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

    init(
        id: UUID = UUID(),
        title: String,
        sourceURL: String,
        localPath: String? = nil,
        qualityLabel: String,
        downloadedAt: Date = Date(),
        status: Status = .downloading
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.localPath = localPath
        self.qualityLabel = qualityLabel
        self.downloadedAt = downloadedAt
        self.status = status
    }
}

@MainActor
final class OfflineStore: NSObject, ObservableObject {
    @Published private(set) var videos: [OfflineVideo] = []
    @Published private(set) var progress: [UUID: Double] = [:]

    private let fileManager = FileManager.default
    private let stateFileName = "offline-videos.json"
    private var assetTasks: [Int: UUID] = [:]

    override init() {
        super.init()
        loadState()
    }

    private lazy var configuredAssetSession: AVAssetDownloadURLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: "com.example.StreamBrowser.offline-assets"
        )
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        return AVAssetDownloadURLSession(
            configuration: configuration,
            assetDownloadDelegate: self,
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

        if quality.url.pathExtension.lowercased() == "m3u8" {
            startHLSDownload(item: item, url: quality.url)
        } else {
            startFileDownload(item: item, url: quality.url)
        }
    }

    func localURL(for video: OfflineVideo) -> URL? {
        guard video.status == .completed,
              let localPath = video.localPath
        else {
            return nil
        }
        return URL(fileURLWithPath: localPath)
    }

    func remove(_ video: OfflineVideo) {
        if let localPath = video.localPath {
            try? fileManager.removeItem(atPath: localPath)
        }
        videos.removeAll { $0.id == video.id }
        progress[video.id] = nil
        saveState()
    }

    private func startFileDownload(item: OfflineVideo, url: URL) {
        Task {
            do {
                let (temporaryURL, response) = try await URLSession.shared.download(from: url)
                let extensionName = response.mimeType.flatMap { self.fileExtension(for: $0) } ?? url.pathExtension
                let destination = offlineDirectory
                    .appendingPathComponent(item.id.uuidString)
                    .appendingPathExtension(extensionName.isEmpty ? "mp4" : extensionName)

                try fileManager.createDirectory(
                    at: offlineDirectory,
                    withIntermediateDirectories: true
                )
                try? fileManager.removeItem(at: destination)
                try fileManager.moveItem(at: temporaryURL, to: destination)
                finish(item: item, localURL: destination)
            } catch {
                fail(item: item)
            }
        }
    }

    private func startHLSDownload(item: OfflineVideo, url: URL) {
        let asset = AVURLAsset(url: url)
        guard let task = configuredAssetSession.makeAssetDownloadTask(
            asset: asset,
            assetTitle: item.title,
            assetArtworkData: nil,
            options: nil
        ) else {
            fail(item: item)
            return
        }

        task.taskDescription = item.id.uuidString
        assetTasks[task.taskIdentifier] = item.id
        task.resume()
    }

    private func finish(item: OfflineVideo, localURL: URL) {
        update(item: item, status: .completed, localPath: localURL.path)
        progress[item.id] = 1
    }

    private func fail(item: OfflineVideo) {
        update(item: item, status: .failed, localPath: nil)
        progress[item.id] = nil
    }

    private func update(item: OfflineVideo, status: OfflineVideo.Status, localPath: String?) {
        guard let index = videos.firstIndex(where: { $0.id == item.id }) else { return }
        videos[index] = OfflineVideo(
            id: item.id,
            title: item.title,
            sourceURL: item.sourceURL,
            localPath: localPath,
            qualityLabel: item.qualityLabel,
            downloadedAt: item.downloadedAt,
            status: status
        )
        saveState()
    }

    private var applicationSupportDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private var offlineDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("OfflineVideos", isDirectory: true)
    }

    private var stateURL: URL {
        applicationSupportDirectory.appendingPathComponent(stateFileName)
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL),
              let savedVideos = try? JSONDecoder().decode([OfflineVideo].self, from: data)
        else {
            return
        }

        videos = savedVideos.compactMap { video in
            guard video.status == .completed,
                  let localPath = video.localPath,
                  fileManager.fileExists(atPath: localPath)
            else {
                return nil
            }
            return video
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

extension OfflineStore: AVAssetDownloadDelegate {
    nonisolated func urlSession(
        _ session: AVAssetDownloadURLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = assetDownloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        Task { @MainActor in
            do {
                let destination = self.offlineDirectory.appendingPathComponent("\(id.uuidString).movpkg")
                try self.fileManager.createDirectory(
                    at: self.offlineDirectory,
                    withIntermediateDirectories: true
                )
                try? self.fileManager.removeItem(at: destination)
                try self.fileManager.copyItem(at: location, to: destination)

                guard let item = self.videos.first(where: { $0.id == id }) else { return }
                self.finish(item: item, localURL: destination)
                self.assetTasks[assetDownloadTask.taskIdentifier] = nil
            } catch {
                if let item = self.videos.first(where: { $0.id == id }) {
                    self.fail(item: item)
                }
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
        guard let id = assetDownloadTask.taskDescription.flatMap(UUID.init(uuidString:)),
              timeRangeExpectedToLoad.duration.seconds > 0
        else {
            return
        }

        let loaded = loadedTimeRanges.reduce(0.0) { partialResult, value in
            partialResult + value.timeRangeValue.duration.seconds
        }
        let expected = timeRangeExpectedToLoad.duration.seconds
        let nextProgress = min(max(loaded / expected, 0), 0.99)

        Task { @MainActor in
            self.progress[id] = nextProgress
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let id = task.taskDescription.flatMap(UUID.init(uuidString:)),
              let error
        else {
            return
        }

        Task { @MainActor in
            if let item = self.videos.first(where: { $0.id == id }) {
                self.fail(item: item)
            }
        }
        _ = error
    }
}