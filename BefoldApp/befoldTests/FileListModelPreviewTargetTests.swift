@testable import befold
import Foundation
import Testing

/// FileListModel が提示対象の唯一の導出点であること(ADR 0002 段 1)を検証する。
@Suite
@MainActor
struct FileListModelPreviewTargetTests {
    private let directory = URL(fileURLWithPath: "/tmp/befold-preview-target")

    private func makeModel(selection: URL?) -> FileListModel {
        FileListModel(currentDirectory: directory, entries: [], selection: selection)
    }

    @Test("一覧を空で作った直後は未確定で、フォルダー提示にはならない")
    func startsUndeterminedBeforeFirstListing() {
        let model = makeModel(selection: directory.appendingPathComponent("opening.mmd"))
        #expect(!model.hasLoadedEntries)
        #expect(model.previewTarget == .undetermined)
        #expect(model.previewTarget.folderURL == nil)
    }

    @Test("一覧を反映すると hasLoadedEntries が立ち、選択に応じた対象になる")
    func reflectsSelectionAfterEntriesApplied() {
        let file = directory.appendingPathComponent("opening.mmd")
        let model = makeModel(selection: file)
        model.entries = [FileListEntry(url: file, kind: .file)]

        #expect(model.hasLoadedEntries)
        #expect(model.previewTarget == .file)
    }

    @Test("一覧反映後に選択が一覧から消えたら現在ディレクトリの一覧へ落ちる")
    func fallsBackToFolderWhenSelectionDisappears() {
        let file = directory.appendingPathComponent("gone.mmd")
        let model = makeModel(selection: file)
        model.entries = [FileListEntry(url: directory.appendingPathComponent("other.mmd"), kind: .file)]

        #expect(model.previewTarget == .folder(directory))
    }
}
