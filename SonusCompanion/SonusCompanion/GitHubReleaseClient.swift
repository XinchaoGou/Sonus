import Foundation

struct GitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let prerelease: Bool
    let body: String?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case prerelease
        case body
        case assets
    }
}

struct AvailableUpdate: Sendable {
    let version: AppVersion
    let versionString: String
    let downloadURL: URL
    let releaseNotes: String
}

enum GitHubReleaseClient {
    enum Error: LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        case missingAsset(String)
        case invalidVersion(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from GitHub."
            case .httpStatus(let code):
                return "GitHub API returned status \(code)."
            case .missingAsset(let name):
                return "Release asset not found: \(name)."
            case .invalidVersion(let tag):
                return "Invalid release version tag: \(tag)."
            }
        }
    }

    static func fetchLatestUpdate(session: URLSession = .shared) async throws -> AvailableUpdate? {
        var request = URLRequest(url: UpdateConfig.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Sonus-Updater", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Error.httpStatus(http.statusCode)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        if release.prerelease {
            return nil
        }

        guard let version = AppVersion(release.tagName) else {
            throw Error.invalidVersion(release.tagName)
        }

        guard let asset = release.assets.first(where: { $0.name == UpdateConfig.assetFileName }) else {
            throw Error.missingAsset(UpdateConfig.assetFileName)
        }

        return AvailableUpdate(
            version: version,
            versionString: version.displayString,
            downloadURL: asset.browserDownloadURL,
            releaseNotes: release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }
}
