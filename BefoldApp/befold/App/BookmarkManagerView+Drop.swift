import AppKit
import BefoldKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// 管理パネル内でブックマーク行をドラッグするときの型(TASK-620.3)。自プロセス内だけで使い、
    /// `.fileURL` は載せない——載せると Finder からのドロップ(追加)と同じ受け口に拾われ、
    /// 並び替えのつもりが「登録済みなので何もしない」追加として消える。
    static let bookmarkEntry = UTType(exportedAs: "com.degino.befold.bookmark-entry")
}

/// 管理パネルの D&D。受け口は 2 種類で、**型で取り違えない**。
/// - Finder からのドロップ(`.fileURL`)でブックマークを追加する(TASK-536.3)
/// - パネル内の行ドラッグ(`.bookmarkEntry`)で並び替え・フォルダーへの格納をする(TASK-620.3)
///
/// `NSItemProvider` からの取り出しは非同期なので、ドロップの受理(true)だけを同期で返し、
/// 反映はモデルに任せる。受け入れ規則(存在・形式・重複・並びの規則)はモデル側にあり、
/// ここは「どこへ落とされたか」だけを渡す。
extension BookmarkManagerView {
    /// `.onDrop` で受け付ける型。Finder からのファイル URL と、パネル内の行。
    static let droppableTypes: [UTType] = [.fileURL, .bookmarkEntry]

    /// ドロップを受理し、取り出しと反映を非同期に始める。パネル内の行なら `folder` の末尾へ移し、
    /// そうでなければファイル URL として追加する。どちらも含まないドロップは受理しない(false)。
    func handleDrop(_ providers: [NSItemProvider], into folder: [String]) -> Bool {
        if handleReorder(providers, into: folder, before: nil) { return true }
        let candidates = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !candidates.isEmpty else { return false }
        Task { @MainActor in
            let urls = await Self.fileURLs(from: candidates)
            await model.addDropped(urls, into: folder)
        }
        return true
    }

    /// 行間へのドロップ(`ForEach.onInsert`)。`index` はその段のエントリの並びでの挿入位置で、
    /// 兄弟(直後に来るエントリ)へ直してから `handleReorder` へ渡す。末尾なら兄弟なし。
    func handleInsert(at index: Int, _ providers: [NSItemProvider], into parent: [String], entries: [BookmarkEntry]) {
        _ = handleReorder(providers, into: parent, before: Self.sibling(at: index, in: entries))
    }

    /// 挿入位置 `index` の直後に来るエントリ(ドロップの瞬間に同期で決める。`handleReorder` の doc)。
    static func sibling(at index: Int, in entries: [BookmarkEntry]) -> URL? {
        entries.indices.contains(index) ? entries[index].url : nil
    }

    /// パネル内の行のドロップなら受理し、`folder` の中の `sibling` の直前へ移す(nil なら末尾)。
    /// 挿入先は兄弟の URL で持つ——取り出しを待つあいだに一覧が変わっても、index のずれで
    /// 別の位置へ入らない(兄弟や行き先が消えていれば、規則どおり末尾か何もしない)。
    func handleReorder(_ providers: [NSItemProvider], into folder: [String], before sibling: URL?) -> Bool {
        let identifier = UTType.bookmarkEntry.identifier
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(identifier) }) else {
            return false
        }
        Task { @MainActor in
            guard let path = await Self.draggedPath(from: provider) else { return }
            model.move(URL(filePath: path), to: folder, before: sibling)
        }
        return true
    }

    /// 行のドラッグで運ぶ値(正規化パス)。自プロセスにだけ見せる。
    static func dragProvider(for entry: BookmarkEntry) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = Data(entry.path.utf8)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.bookmarkEntry.identifier, visibility: .ownProcess
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    private static func draggedPath(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.bookmarkEntry.identifier) { data, _ in
                continuation.resume(returning: data.flatMap { String(data: $0, encoding: .utf8) })
            }
        }
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
