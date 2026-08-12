@testable import befold
import Foundation
import Testing

/// withObservationTracking の onChange は Sendable なクロージャなので、
/// 発火したことをローカル変数ではなく参照で受ける。
private final class InvalidationFlag: @unchecked Sendable {
    private(set) var isRaised = false

    func raise() {
        isRaised = true
    }
}

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

    @Test("フォルダー移動の連続書き換えで、通知は提示対象が変わった回数だけになる")
    func notifiesOncePerActualTargetChange() throws {
        // SidebarNavigator.navigateToFolder と同じ順序・同じ書き換え。
        // 通知はツールバーの view ベースアイテムを再同期させるため、1 回の移動で
        // 何度も走らせない(TASK-278)。
        let file = directory.appendingPathComponent("opening.mmd")
        let model = makeModel(selection: file)
        model.entries = [FileListEntry(url: file, kind: .file)]
        try #require(model.previewTarget == .file)

        var notifications = 0
        model.onPresentationTargetChange = { notifications += 1 }

        let destination = directory.appendingPathComponent("sub")
        let destinationEntry = FileListEntry(url: destination.appendingPathComponent("a.md"), kind: .file)
        model.currentDirectory = destination
        #expect(model.previewTarget == .file) // 一覧が届くまでは開いている文書のまま
        // 一覧の反映は本番と同じ setEntries で行う。`entries` への直接代入だと
        // entriesDirectory が移動前のまま残り、「一覧がまだ追いついていない」と
        // 判定される中間状態(previewTarget == .undetermined)が本番には無い形で挟まる。
        model.setEntries([destinationEntry], for: destination, didFailEnumeration: false)
        model.selection = nil

        #expect(model.previewTarget == .folder(destination))
        #expect(notifications == 1)
    }

    @Test("提示対象が変わらない書き換えでは通知しない")
    func doesNotNotifyWhenTargetIsUnchanged() {
        let file = directory.appendingPathComponent("opening.mmd")
        let model = makeModel(selection: file)
        model.entries = [FileListEntry(url: file, kind: .file)]

        var notifications = 0
        model.onPresentationTargetChange = { notifications += 1 }
        // 同じ対象を指したまま一覧だけ取り直す(ファイル監視による再列挙)。
        model.entries = [
            FileListEntry(url: file, kind: .file),
            FileListEntry(url: directory.appendingPathComponent("added.md"), kind: .file),
        ]

        #expect(model.previewTarget == .file)
        #expect(notifications == 0)
    }

    @Test("一覧の入れ替えで提示対象が変わったら、previewTarget の観測に届く")
    func entriesChangeInvalidatesPreviewTargetObservation() {
        // previewTarget は導出値なので、View がそれを読んだときに依存として登録されるのは
        // 導出が触れた保存値だけになる。一覧側(entryIndex)を観測対象から外すと、
        // 一覧が変わって対象も変わったのに再描画されない。
        let file = directory.appendingPathComponent("opening.mmd")
        let model = makeModel(selection: file)
        model.entries = [FileListEntry(url: file, kind: .file)]

        let invalidated = InvalidationFlag()
        withObservationTracking {
            _ = model.previewTarget
        } onChange: {
            invalidated.raise()
        }
        // 選択も currentDirectory も動かさず、一覧から選択中の行だけが消える。
        model.entries = [FileListEntry(url: directory.appendingPathComponent("other.md"), kind: .file)]

        #expect(invalidated.isRaised)
        #expect(model.previewTarget == .folder(directory))
    }

    @Test("currentDirectory だけを書き換えても、対象が変われば通知する")
    func notifiesWhenOnlyCurrentDirectoryChangesTheTarget() throws {
        // 選択が無い状態では提示対象は currentDirectory の一覧そのものなので、
        // currentDirectory の書き換えだけで対象が変わる。entries / selection の
        // 書き換えと同じ通知経路を通ることを確かめる(通知の非対称を残さない)。
        let model = makeModel(selection: nil)
        model.entries = []
        try #require(model.previewTarget == .folder(directory))

        var notifications = 0
        model.onPresentationTargetChange = { notifications += 1 }
        let destination = directory.appendingPathComponent("sub")
        model.currentDirectory = destination

        #expect(model.previewTarget == .folder(destination))
        #expect(notifications == 1)
    }
}
