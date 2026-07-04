import Foundation

/// GitHub Releases API から最新リリースを取得する。
struct GitHubReleaseFetcher: ReleaseFetching {
    private static let endpoint =
        "https://api.github.com/repos/YTommy109/mmdview/releases/latest"

    func fetchLatest() async throws -> GitHubRelease {
        guard let url = URL(string: Self.endpoint) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try response.validateHTTPSuccess()
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}
