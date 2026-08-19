import Foundation

struct AppConfiguration: Decodable {
    let appName: String
    let searchEngineURL: String
    let supportedSchemes: [String]
    let hlsExtensions: [String]

    static let current: AppConfiguration = {
        let defaults = AppConfiguration(
            appName: "Stream Browser",
            searchEngineURL: "https://duckduckgo.com/?q=",
            supportedSchemes: ["http", "https"],
            hlsExtensions: ["m3u8"]
        )

        guard let url = Bundle.main.url(forResource: "app-config", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data)
        else {
            return defaults
        }

        return configuration
    }()
}