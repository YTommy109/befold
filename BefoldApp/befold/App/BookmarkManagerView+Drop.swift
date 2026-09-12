import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Finder からのドロップでブックマークを追加する(TASK-536.3)。アプリ内で初めての D&D 実装。
///
/// `NSItemProvider` からの URL 取り出しは非同期なので、ドロップの受理(true)だけを同期で返し、
/// 追加はモデルの `addDropped` に任せる。受け入れ規則(存在・形式・重複)はモデル側にあり、
/// ここは「どこへ落とされたか」だけを渡す。
extension BookmarkManagerView {
    /// `.onDrop` で受け付ける型。ファイル URL だけ。
    static let droppableTypes: [UTType] = [.fileURL]

    /// ドロップを受理し、URL の取り出しと追加を非同期に始める。ファイル URL を 1 つも
    /// 含まないドロップは受理しない(false)。
    func handleDrop(_ providers: [NSItemProvider], into folder: [String]) -> Bool {
        let candidates = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !candidates.isEmpty else { return false }
        Task { @MainActor in
            let urls = await Self.fileURLs(from: candidates)
            await model.addDropped(urls, into: folder)
        }
        return true
    }

    /// 各 provider の URL を順に取り出す(`NSItemProvider` は Sendable でないので並列化しない。
    /// 件数は数個で、1 つあたりの取り出しは即時)。取り出せなかったものは黙って落とす
    /// (弾く理由を持たないので、結果の「弾いた件数」にも数えない)。
    static func fileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url)
                }
            }
            if let url { urls.append(url) }
        }
        return urls
    }
}
