import BefoldKit
import Foundation
import Testing

/// `BookmarkLibrary` の純粋な操作。永続化を通さず値だけで不変条件を固定する。
@Suite
struct BookmarkLibraryTests {
    private let note = URL(fileURLWithPath: "/mock/docs/note.md")
    private let diagram = URL(fileURLWithPath: "/mock/docs/diagram.mmd")

    @Test("add はルート直下・別名なしで追加し、同じパスは 2 回入らない")
    func addIsIdempotentAndLandsAtRoot() {
        var library = BookmarkLibrary()

        library.add(note)
        library.add(note)

        #expect(library.entries == [BookmarkEntry(path: note.path)])
        #expect(library.entries[0].folder.isEmpty)
        #expect(library.contains(note))
    }

    @Test("表示名は別名があればそれ、無ければファイル名")
    func displayNameFallsBackToFileName() {
        var library = BookmarkLibrary()
        library.add(note)
        library.add(diagram)

        library.setAlias("Weekly notes", for: note)

        #expect(library.entry(for: note)?.displayName == "Weekly notes")
        #expect(library.entry(for: diagram)?.displayName == "diagram.mmd")
    }

    /// 空文字と nil の 2 状態を作らない。空白だけの入力も「別名なし」に畳む。
    @Test("setAlias は前後の空白を除き、空なら別名なしに戻す")
    func setAliasNormalizesEmptyToNil() {
        var library = BookmarkLibrary()
        library.add(note)

        library.setAlias("  Padded  ", for: note)
        #expect(library.entry(for: note)?.alias == "Padded")

        library.setAlias("   ", for: note)
        #expect(library.entry(for: note)?.alias == nil)
    }

    @Test("未登録のパスへの setAlias は何も足さない")
    func setAliasIgnoresUnknownPath() {
        var library = BookmarkLibrary()

        library.setAlias("Ghost", for: note)

        #expect(library.entries.isEmpty)
    }

    @Test("replace はパスだけ差し替え、別名と所属フォルダーを保つ")
    func replaceKeepsAliasAndFolder() {
        var library = BookmarkLibrary(entries: [
            BookmarkEntry(path: note.path, alias: "Weekly", folder: ["Work"]),
        ])
        let moved = URL(fileURLWithPath: "/mock/archive/note.md")

        library.replace(note, with: moved)

        #expect(library.entries == [BookmarkEntry(path: moved.path, alias: "Weekly", folder: ["Work"])])
    }

    /// 新パスが別のエントリとして既に載っていたら、置き換えた側(別名付き)を残して他方を落とす。
    @Test("replace で 1 つのパスが 2 回現れない")
    func replaceDropsOtherOccurrenceOfNewPath() {
        var library = BookmarkLibrary(entries: [
            BookmarkEntry(path: note.path, alias: "Weekly"),
            BookmarkEntry(path: diagram.path),
        ])

        library.replace(note, with: diagram)

        #expect(library.entries == [BookmarkEntry(path: diagram.path, alias: "Weekly")])
    }

    @Test("replace は未登録の旧パスでは何もしない")
    func replaceIgnoresUnknownOldPath() {
        var library = BookmarkLibrary(entries: [BookmarkEntry(path: diagram.path)])

        library.replace(note, with: URL(fileURLWithPath: "/mock/elsewhere.md"))

        #expect(library.entries == [BookmarkEntry(path: diagram.path)])
    }

    @Test("removeAll は渡した分だけを取り除く")
    func removeAllDropsOnlyGivenPaths() {
        var library = BookmarkLibrary()
        library.add(note)
        library.add(diagram)

        library.removeAll([note, URL(fileURLWithPath: "/mock/unknown.md")])

        #expect(library.urls == [diagram])
    }

    @Test("旧形式の配列からの変換は全件をルート直下・別名なしにし、重複を畳む")
    func migratedFromPathsKeepsEveryPathOnce() {
        let library = BookmarkLibrary.migrated(fromPaths: [note.path, diagram.path, note.path])

        #expect(library.entries == [BookmarkEntry(path: note.path), BookmarkEntry(path: diagram.path)])
        #expect(library.folders.isEmpty)
    }

    /// 保存形式の往復。`alias` が無いエントリは JSON にキーを持たない(旧バージョンが読めるよう
    /// optional で足す方針の実測)。
    @Test("JSON の往復で値が保たれ、別名なしのエントリは alias キーを持たない")
    func roundTripsThroughJSON() throws {
        let library = BookmarkLibrary(
            folders: [BookmarkFolder(path: ["Work"], isExpanded: false)],
            entries: [
                BookmarkEntry(path: note.path, alias: "Weekly", folder: ["Work"]),
                BookmarkEntry(path: diagram.path),
            ]
        )

        let data = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(BookmarkLibrary.self, from: data)

        #expect(decoded == library)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.components(separatedBy: "\"alias\"").count == 2)
    }
}
