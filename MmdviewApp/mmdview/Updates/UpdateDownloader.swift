import Foundation

/// DMG を指定先へストリーミングダウンロードする。
struct UpdateDownloader: Sendable {
    /// - Parameter progress: 0.0–1.0 の進捗(コンテンツ長が不明な場合は完了時のみ)。
    func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let expected = response.expectedContentLength
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var written: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 {
                    progress(Double(written) / Double(expected))
                }
            }
        }
        try handle.write(contentsOf: buffer)
        progress(1.0)
    }
}
