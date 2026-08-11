import Foundation

/// サイドバーのツリー展開の状態。**ウィンドウごと・メモリのみ**で持つ。
///
/// 粒度は `NavigationHistory` / `SidebarNavigator.selectionMemory` と同族の
/// 「どこを見ているか」に付随するナビゲーション状態なので、アプリ全体で共有する
/// `SidebarDisplayPreference`(不可視ファイル・変更のみ表示)とは分ける。
/// 永続化する場合は `SidebarStateStore` のファイルごとのパターンに倣うこと
/// (TASK-361.4 の AC)。
///
/// `@Observable` にはしない。サイドバーの描画の真実の源は
/// `FileListModel.entries` → `visibleEntries` の 1 本で、`entries` の didSet が
/// 索引の作り直し・提示対象の通知をまとめて連動させている。ここも観測可能にすると
/// 1 回の展開で 2 系統の再描画が飛び、「visibleEntries の添字 = 行番号」の前提へ
/// 別経路から触ることになる。行を畳むのは `DirectoryListing.rows` の 1 箇所、
/// それを `FileListModel` へ反映するのは `SidebarNavigator.applyRows` の 1 箇所で、
/// どちらも `SidebarRowAssemblySingleSourceTests` がソース走査で数えている。
@MainActor
final class SidebarExpansion {
    /// フォルダの子リストの取得状態。
    ///
    /// **空配列と「まだ無い」を区別する**のが要点。`.loaded([])` は「答えが出て、
    /// 中身が空だった」であり、`.loading` や辞書に無い状態とは意味が違う。
    /// 配列が空かどうかで判定してはならない(`FileListModel.gitStatus` の
    /// 「空 != nil」と同型 / TASK-285)。
    ///
    /// 同じ理由で **`.failed` と `.loaded([])` も別**にする。読めなかったフォルダを
    /// 空として確定表示すると「中身が無い」と言い切ることになる(TASK-404)。
    enum Children: Equatable {
        /// 要求済みで、まだ結果が届いていない。
        case loading
        /// 結果が届いた。空配列は「空のフォルダ」を意味する。
        case loaded([FileListEntry])
        /// ディレクトリの列挙に失敗した(権限が無い・消えた)。
        case failed
    }

    /// 展開する意図のあるフォルダの pathKey。開閉操作が書き換える。
    /// **`children` が届いているかどうかとは別**で、意図とデータを分けて持つ。
    private(set) var expandedKeys: Set<String> = []
    private(set) var children: [String: Children] = [:]

    /// フォルダごとの列挙の世代。開始時に進めて走行中を無効化し、着地時に一致を確認する。
    /// **フォルダごとに分ける**のが要点。サイドバー全体で 1 つだと、後から始まった
    /// 展開が先行する別フォルダの列挙結果を捨ててしまう。
    private var generations: [String: Int] = [:]
    /// ルート切り替え・ウィンドウ終了・並び順の変更で進める全体の世代。
    /// フォルダごとの世代では「別のルートに対する同じパスの展開」を区別できない。
    private var epoch = 0

    /// 行の組み立て(SidebarRowBuilder)へ渡す材料。
    ///
    /// 展開集合は **`.loaded` になっているキーだけ**に絞る。こうすると「展開したが
    /// 子がまだ届いていない」間は行が増えず、読み込み中のプレースホルダ行を
    /// 設計しなくて済む(三角の見た目で表すのは TASK-361.4 の担当)。
    /// - Note: 子が未到着のキーは `loading` に入れて別に返す。行は増やせない(並べる子が
    ///   無い)が、開閉三角を「読み込み中」にする材料は要る。ここを返さないと、
    ///   展開したのに何も起きていないように見える状態と「空のフォルダ」が区別できない。
    var material: SidebarRowBuilder.Material {
        var result = SidebarRowBuilder.Material()
        for key in expandedKeys {
            // **`default` を置かない。** ここを else でまとめると、`Children` に足した
            // 状態が黙って「読み込み中」へ落ちる(`.failed` を足したときに、権限の無い
            // フォルダが永久にスピナーのままになる形で実際に起きうる)。
            switch children[key] {
            case let .loaded(entries):
                result.expanded.insert(key)
                result.childrenByPathKey[key] = entries
            case .failed:
                result.failed.insert(key)
            case .loading:
                result.loading.insert(key)
            case nil:
                // `beginExpanding` が展開の意図と同時に `.loading` を書くため到達しない。
                // 書き漏れても「答えが出ていない」側へ寄せる(空として確定表示しない)。
                result.loading.insert(key)
            }
        }
        return result
    }

    /// 展開を開始する。既に展開済みなら何もしない(再列挙しない)。
    ///
    /// 戻り値は列挙を要求すべきかどうか。true のときだけ呼び出し側が列挙を走らせ、
    /// 結果を `apply(_:for:token:)` へ渡す。「展開 1 回につき列挙 1 回」という
    /// コストの上限はここで決まる。
    ///
    /// **列挙に失敗したフォルダだけは再展開で取り直せる。** 失敗したまま
    /// `expandedKeys` に残ると、以後の展開操作が「展開済み」として弾かれ、
    /// いったん畳むまで再試行できない(TASK-404)。
    func beginExpanding(_ key: String) -> ExpansionToken? {
        guard !expandedKeys.contains(key) || children[key] == .failed else { return nil }
        expandedKeys.insert(key)
        children[key] = .loading
        return makeToken(for: key)
    }

    /// 展開したままで子リストを取り直す。ルートを取り直す契機(並び順の変更・隠しファイルの
    /// トグル・フォーカス復帰・リネーム)ごとに呼ぶ。取り直さないと、展開中のサブツリーだけが
    /// 古い規則で並び続ける。
    ///
    /// **手元の子リストは `.loading` へ戻さない。** 戻すと、新しい子が届くまでの間だけ
    /// 展開が畳まれた形になり、行がいったん減る。減った行に対して選択維持の判定が走ると、
    /// 展開したサブフォルダ内のファイルを選んでいた利用者の選択が毎回失われる。
    /// 古い子を出したまま差し替える(走行中の古い結果は世代ガードが弾く)。
    ///
    /// - Returns: 取り直しが必要なフォルダのトークン。
    func invalidateChildren() -> [ExpansionToken] {
        guard !expandedKeys.isEmpty else { return [] }
        epoch += 1
        return expandedKeys.map { makeToken(for: $0) }
    }

    /// 展開を畳む。**配下の展開も一緒に捨てる。**
    ///
    /// 残す設計にすると、畳んでいる間に走行中だった配下の列挙が着地して子リストを書き、
    /// 再展開したときに古い内容がそのまま復活する(しかも再列挙されない)。
    /// 捨てる側に倒し、再展開は必ず取り直しにする。
    func collapse(_ key: String) {
        for target in expandedKeys.filter({ $0 == key || $0.hasPrefix(key + "/") }) {
            generations[target, default: 0] += 1
            expandedKeys.remove(target)
            children[target] = nil
        }
    }

    /// 走行中の列挙をすべて無効化し、展開状態を捨てる。
    /// ルート切り替え(navigateToFolder)とウィンドウを閉じるとき(cancelPendingListing)に呼ぶ。
    /// 後者を忘れると、閉じたウィンドウのために列挙が着地して状態を書き続ける(TASK-300 と同型)。
    func invalidateAll() {
        epoch += 1
        expandedKeys.removeAll()
        children.removeAll()
        generations.removeAll()
    }

    /// 列挙結果を反映する。トークンが古ければ(別の展開・畳み・ルート切り替えが
    /// 挟まっていれば)捨てる。**着地時の一致確認**はここ 1 箇所に閉じる。
    ///
    /// `entries` が nil なら列挙失敗として `.failed` を着地させる。失敗を別の入口に
    /// 分けないのは、世代・epoch のガードを 2 箇所へ複製しないため。
    func apply(_ entries: [FileListEntry]?, for token: ExpansionToken) {
        guard generations[token.key] == token.generation, epoch == token.epoch else { return }
        children[token.key] = entries.map(Children.loaded) ?? .failed
    }

    /// 展開の列挙 1 回を識別する券。発行時点のフォルダ世代と全体世代を持ち、
    /// 着地時の一致確認に使う。呼び出し側が中身を組み立てられないよう
    /// イニシャライザは持たせない。
    struct ExpansionToken: Sendable {
        let key: String
        fileprivate let generation: Int
        fileprivate let epoch: Int
    }

    /// **開始時の無効化**。世代を進めることで、この時点で走行中の同じフォルダの
    /// 列挙結果は着地時に捨てられる。
    private func makeToken(for key: String) -> ExpansionToken {
        generations[key, default: 0] += 1
        return ExpansionToken(key: key, generation: generations[key] ?? 0, epoch: epoch)
    }
}
