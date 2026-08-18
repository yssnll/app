import Foundation

struct AppConfiguration: Decodable {
    let appName: String
    let searchEngineURL: String
    let supportedSchemes: [String]
    let hlsExtensions: [String]

    static let current: AppConfiguration = {
        guard let url = Bundle.main.url(forResource: "app-config", withExtension: "json") else {
            fatalError("The bundled app-config.json file is missing.")
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AppConfiguration.self, from: data)
        } catch {
            fatalError("The bundled app-config.json file is invalid: \(error.localizedDescription)")
        }
    }()
}