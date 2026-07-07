import Foundation

/// GitHub Releases API から最新リリースを取得する。
struct GitHubReleaseFetcher: ReleaseFetching {
    private static let latestEndpoint =
        "https://api.github.com/repos/YTommy109/befold/releases/latest"
    private static let allEndpoint =
        "https://api.github.com/repos/YTommy109/befold/releases?per_page=10"

    func fetchLatest() async throws -> GitHubRelease {
        let data = try await fetch(Self.latestEndpoint)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    func fetchLatestIncludingPrerelease() async throws -> [GitHubRelease] {
        let data = try await fetch(Self.allEndpoint)
        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    private func fetch(_ endpoint: String) async throws -> Data {
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try response.validateHTTPSuccess()
        return data
    }
}
