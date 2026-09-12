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

    // MARK: - フォルダー

    @Test("createFolder は同じ親の下で同名を弾き、入れ子は作れる")
    func createFolderRejectsDuplicateSiblingButAllowsNesting() {
        var library = BookmarkLibrary()

        let result1 = library.createFolder(named: " Work ", in: [])
        #expect(result1)
        let result2 = library.createFolder(named: "Work", in: [])
        #expect(!result2)
        let result3 = library.createFolder(named: "Work", in: ["Work"])
        #expect(result3)
        let result4 = library.createFolder(named: "  ", in: [])
        #expect(!result4)
        let result5 = library.createFolder(named: "Orphan", in: ["Missing"])
        #expect(!result5)

        #expect(library.folders.map(\.path) == [["Work"], ["Work", "Work"]])
    }

    @Test("renameFolder は配下のサブフォルダーとエントリの所属を全件書き換える")
    func renameFolderRewritesEveryPrefix() {
        var library = BookmarkLibrary(
            folders: [
                BookmarkFolder(path: ["Work"]),
                BookmarkFolder(path: ["Work", "Specs"]),
                BookmarkFolder(path: ["Home"]),
            ],
            entries: [
                BookmarkEntry(path: note.path, folder: ["Work"]),
                BookmarkEntry(path: diagram.path, folder: ["Work", "Specs"]),
            ]
        )

        let result6 = library.renameFolder(at: ["Work"], to: "Office")
        #expect(result6)

        #expect(library.folders.map(\.path) == [["Office"], ["Office", "Specs"], ["Home"]])
        #expect(library.entries.map(\.folder) == [["Office"], ["Office", "Specs"]])
        let result7 = library.renameFolder(at: ["Office"], to: "Home")
        #expect(!result7, "同名の兄弟がいれば弾く")
        let result8 = library.renameFolder(at: ["Office"], to: "Office")
        #expect(result8, "同じ名前への改名は何もせず成功")
    }

    /// 536.4 AC #4: フォルダーを消しても配下は失われない(親へ繰り上がる)。
    @Test("deleteFolder は配下のサブフォルダーとエントリを親へ繰り上げ、件数を減らさない")
    func deleteFolderPromotesChildren() {
        var library = BookmarkLibrary(
            folders: [BookmarkFolder(path: ["Work"]), BookmarkFolder(path: ["Work", "Specs"])],
            entries: [
                BookmarkEntry(path: note.path, folder: ["Work"]),
                BookmarkEntry(path: diagram.path, folder: ["Work", "Specs"]),
            ]
        )

        let result9 = library.deleteFolder(at: ["Work"])
        #expect(result9)

        #expect(library.folders.map(\.path) == [["Specs"]])
        #expect(library.entries.count == 2)
        #expect(library.entry(for: note)?.folder == [])
        #expect(library.entry(for: diagram)?.folder == ["Specs"])
    }

    @Test("deleteFolder は繰り上げ先で名前が衝突するなら何もしない")
    func deleteFolderRejectsPromotionCollision() {
        var library = BookmarkLibrary(
            folders: [
                BookmarkFolder(path: ["Work"]),
                BookmarkFolder(path: ["Work", "Specs"]),
                BookmarkFolder(path: ["Specs"]),
            ]
        )
        let before = library

        let result10 = library.deleteFolder(at: ["Work"])
        #expect(!result10)
        #expect(library == before)
    }

    @Test("move は存在するフォルダーへだけ移せる")
    func moveRequiresExistingFolder() {
        var library = BookmarkLibrary(folders: [BookmarkFolder(path: ["Work"])])
        library.add(note)

        let result11 = library.move(note, to: ["Work"])
        #expect(result11)
        #expect(library.entry(for: note)?.folder == ["Work"])
        let result12 = library.move(note, to: ["Missing"])
        #expect(!result12)
        #expect(library.entry(for: note)?.folder == ["Work"])
        let result13 = library.move(note, to: [])
        #expect(result13)
        let result14 = library.move(diagram, to: [])
        #expect(!result14, "未登録は移せない")
    }

    /// 記録の無いフォルダーに属するエントリ(手編集・旧版)は消えて見えないよう、ルート扱いで出す。
    @Test("children はフォルダー → エントリの順で並び、所属先の無いエントリはルートに出る")
    func childrenOrdersFoldersFirstAndRescuesOrphans() {
        let library = BookmarkLibrary(
            folders: [BookmarkFolder(path: ["zeta"]), BookmarkFolder(path: ["Alpha"])],
            entries: [
                BookmarkEntry(path: note.path, alias: "b-note", folder: ["Alpha"]),
                BookmarkEntry(path: diagram.path, folder: ["Missing"]),
            ]
        )

        let root = library.children(of: [])
        #expect(root.folders.map(\.name) == ["Alpha", "zeta"])
        #expect(root.entries.map(\.path) == [diagram.path])
        #expect(library.children(of: ["Alpha"]).entries.map(\.displayName) == ["b-note"])
        #expect(library.children(of: ["zeta"]).isEmpty)
    }

    @Test("setExpanded は該当フォルダーだけを変え、JSON の往復で保たれる")
    func setExpandedPersists() throws {
        var library = BookmarkLibrary(folders: [BookmarkFolder(path: ["Work"]), BookmarkFolder(path: ["Home"])])

        library.setExpanded(false, for: ["Work"])
        library.setExpanded(false, for: ["Missing"])

        let decoded = try JSONDecoder().decode(BookmarkLibrary.self, from: JSONEncoder().encode(library))
        #expect(decoded.folders.map(\.isExpanded) == [false, true])
    }
}
