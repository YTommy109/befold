@testable import befold
import BefoldKit
import Foundation

/// `FileListViewDelegate` のテスト用スパイ。
///
/// `FileListView.delegate` は弱参照なので、テスト側がこのインスタンスを保持し続ける
/// 必要がある(`FileListViewDelegateStore` がその役)。
@MainActor
final class FileListViewDelegateSpy: FileListViewDelegate {
    var onSelect: (URL) -> Void = { _ in }
    var onNavigate: (URL) -> Void = { _ in }

    private(set) var selectedFiles: [URL] = []
    private(set) var navigatedFolders: [URL] = []
    private(set) var openedElsewhere: [(url: URL, disposition: OpenDisposition)] = []
    private(set) var expandedEntries: [FileListEntry] = []
    private(set) var collapsedEntries: [FileListEntry] = []

    func fileListDidSelectFile(_ url: URL) {
        selectedFiles.append(url)
        onSelect(url)
    }

    func fileListDidRequestNavigation(to url: URL) {
        navigatedFolders.append(url)
        onNavigate(url)
    }

    func fileListDidRequestOpenElsewhere(_ url: URL, disposition: OpenDisposition) {
        openedElsewhere.append((url, disposition))
    }

    func fileListDidRequestExpand(_ entry: FileListEntry) {
        expandedEntries.append(entry)
    }

    func fileListDidRequestCollapse(_ entry: FileListEntry) {
        collapsedEntries.append(entry)
    }
}

/// スパイを生存させておく入れ物。テスト構造体が値型でも参照を持ち回せるようにする。
@MainActor
final class FileListViewDelegateStore {
    private var spies: [FileListViewDelegateSpy] = []

    /// スパイを 1 つ作り、保持したうえで返す。
    func makeSpy(
        onSelect: @escaping (URL) -> Void = { _ in }, onNavigate: @escaping (URL) -> Void = { _ in }
    ) -> FileListViewDelegateSpy {
        let spy = FileListViewDelegateSpy()
        spy.onSelect = onSelect
        spy.onNavigate = onNavigate
        spies.append(spy)
        return spy
    }
}
