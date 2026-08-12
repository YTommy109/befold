@testable import befold
import BefoldKit
import Foundation

/// ファイルシステムを持たない差し替え環境。`QuickOpenModel` のテストスイート
/// (候補集合の到着 / fuzzy 絞り込み / パスモード / Tab 補完 / 選択と決定)が共有する。
final class QuickOpenStubEnvironment: QuickOpenEnvironment {
    var baseDirectory: URL?
    var includingHiddenFiles = false
    var candidates: [QuickOpenCandidate] = []
    var isTruncated = false
    /// ディレクトリ URL の正規化パス → その中身。
    var entries: [String: [URL]] = [:]
    var directories: Set<String> = []
    var resolvedFile: [String: URL] = [:]

    /// 候補集合の到着を遅らせるための関門。nil なら即時に返す。
    var candidateSetGate: (@Sendable () async -> Void)?

    func candidateSet() async -> QuickOpenCandidateSet {
        await candidateSetGate?()
        return QuickOpenCandidateSet(candidates: candidates, isTruncated: isTruncated)
    }

    func directoryEntries(in directory: URL) async -> [URL]? {
        entries[directory.normalizedPathKey] ?? []
    }

    func isDirectory(_ url: URL) async -> Bool {
        directories.contains(url.normalizedPathKey)
    }

    func resolveFileToOpen(at url: URL) async -> URL? {
        await isDirectory(url) ? resolvedFile[url.normalizedPathKey] : url
    }
}

/// `QuickOpenModel` を組み立てるテストスイートが共通で使う書き味。
/// スイートを分割しても組み立て方が 1 箇所に留まるよう、protocol extension で配る。
protocol QuickOpenModelTestCase {}

extension QuickOpenModelTestCase {
    func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    func candidate(_ path: String, _ display: String, _ origin: QuickOpenCandidate.Origin = .indexed)
        -> QuickOpenCandidate
    {
        QuickOpenCandidate(url: url(path), displayPath: display, origin: origin)
    }

    /// 候補集合の到着と絞り込みが落ち着いた状態のモデルを返す。
    @MainActor
    func makeModel(
        _ environment: QuickOpenStubEnvironment,
        onOpen: @escaping (URL) -> Void = { _ in }
    ) async -> QuickOpenModel {
        let model = QuickOpenModel(environment: environment, onOpen: onOpen)
        await model.waitForPendingWork()
        return model
    }
}
