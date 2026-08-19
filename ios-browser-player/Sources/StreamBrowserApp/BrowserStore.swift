import Foundation
import Combine

struct HistoryItem: Codable, Identifiable, Hashable {
    let id: UUID
    let url: String
    let visitedAt: Date

    init(url: String, visitedAt: Date = Date()) {
        self.id = UUID()
        self.url = url
        self.visitedAt = visitedAt
    }
}

private struct PersistedBrowserState: Codable {
    let history: [HistoryItem]
}

@MainActor
final class BrowserStore: ObservableObject {
    @Published private(set) var history: [HistoryItem] = []

    private let configuration = AppConfiguration.current
    private let maxHistoryItems = 30
    private let fileManager = FileManager.default

    init() {
        loadState()
    }

    func resolveInput(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let url = URL(string: value), isSupported(url: url) {
            return url
        }

        if !value.contains(" ") && value.contains(".") {
            let candidate = "https://\(value)"
            if let url = URL(string: candidate), isSupported(url: url) {
                return url
            }
        }

        guard let encodedQuery = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: configuration.searchEngineURL + encodedQuery)
        else {
            return nil
        }
        return searchURL
    }

    func isHLS(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return configuration.hlsExtensions.contains(pathExtension)
    }

    func isVideo(_ url: URL) -> Bool {
        let videoExtensions = ["m3u8", "mp4", "mov", "m4v", "webm"]
        return videoExtensions.contains(url.pathExtension.lowercased())
    }

    func addToHistory(_ url: URL) {
        let item = HistoryItem(url: url.absoluteString)
        history.removeAll { $0.url == item.url }
        history.insert(item, at: 0)
        history = Array(history.prefix(maxHistoryItems))
        saveState()
    }

    func clearHistory() {
        history.removeAll()
        saveState()
    }

    private func isSupported(url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return configuration.supportedSchemes.contains(scheme)
    }

    private var stateURL: URL {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("browser-state.json")
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedBrowserState.self, from: data)
        else {
            return
        }
        history = state.history
    }

    private func saveState() {
        let state = PersistedBrowserState(history: history)
        guard let data = try? JSONEncoder().encode(state) else { return }

        do {
            let directory = stateURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            // History is a convenience feature; navigation remains usable if persistence fails.
        }
    }
}