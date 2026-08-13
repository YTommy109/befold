# Quick Open Design

> **これは 2026-07-26 時点の設計スナップショットです。**
> 現在の仕様は [`docs/dev/native-app-design.md`](../../dev/native-app-design.md)
> が単一の情報源。この文書は当時の意図と検討経緯を残すためのもので、
> 現在の実装と食い違っていることがある。着手前に必ずコードで裏を取ること。

## Summary

VSCode の `Cmd+P` に相当する Quick Open を befold に導入する。開発者がパスや断片的なファイル名をキーボードだけで打ち込み、現在のウィンドウを目的のファイルに切り替えられるようにする。

befold は開発者向けツールであり、扱う対象の多くは Git リポジトリ内のドキュメントである。現在ファイルを開く手段は `Cmd+O`（NSOpenPanel）、Finder からの起動、CLI、サイドバー、文書内リンクに限られ、いずれも「パスを知っている状態から最短で開く」用途には遠回りになっている。

### NSOpenPanel 拡張を採らない理由

<!-- derived-from #summary -->

`NSOpenPanel` には `accessoryView` があり、パス入力欄を差し込むことは可能である。しかし次の理由で採用しない。

- パネル本体のキー入力とリスト描画には介入できず、fuzzy 検索して候補を絞り込むという Quick Open の中核部分をパネル内に構築できない。
- macOS の Open ダイアログには既に `Cmd+Shift+G`（フォルダへ移動）があり、`~` 展開と Tab 補完つきで unix パスを受け付ける。`accessoryView` にパス入力欄を足すと標準機能とほぼ重複する。

したがって、独立した Spotlight 風のフローティングパネルとして実装する。macOS らしさは標準の外観・キーバインド・パネル挙動で担保する。

## Requirements

- `Cmd+P` で Spotlight 風のフローティングパネルを表示する。`Esc` とフォーカス喪失で閉じる。
- 入力が `/` `~` `.` で始まる場合はパスモード、それ以外は fuzzy 検索モード、空文字なら履歴表示として振る舞う。
- fuzzy 検索の候補は、Git 管理下なら追跡ファイル、非 Git ならファイルのあるディレクトリの再帰走査から集める。
- 候補は拡張子で区別しない（全ファイルを対象とする）。`Cmd+O` が全ファイルを許す現行挙動と揃える。
- 履歴（最近開いたファイル）とブックマークも候補に混ぜる。
- 決定時は現在のウィンドウでファイルを切り替える。ウィンドウが 1 枚も無い場合のみ新規ウィンドウを開く。
- `Cmd+P` を Quick Open に割り当てる。Print はメニュー項目としては残し、キーを `Shift+Cmd+P` へ移す。
- 判断ロジックはすべて BefoldKit 側の純粋ロジックに置き、AppKit / SwiftUI 層は表示とキー配線のみを担う。

## Architecture

<!-- constrained-by ./2026-07-11-path-link-navigation-design.md -->

```
Cmd+P
  └── QuickOpenPanelController (AppKit / NSPanel)
        └── QuickOpenView (SwiftUI: TextField + 候補リスト)
              └── QuickOpenModel (@MainActor @Observable)
                    ├── QuickOpenQuery        … 入力の分類
                    ├── QuickOpenCandidates   … 候補のマージ・順位付け
                    │     ├── GitCommandFileIndex (既存, GitFileIndexing)
                    │     ├── DirectoryFileScanner (新規)
                    │     ├── RecentDocumentsStore (既存)
                    │     └── BookmarkStore (既存)
                    ├── FuzzyMatcher          … 順位付き複数件マッチ
                    └── TrackedPathResolver (既存) … パスモードの解決
  決定 → ViewerWindowController.switchFile(to:)
        （ウィンドウが無い場合のみ ViewerWindowManager.openViewer(for:)）
```

### 新規コンポーネント（BefoldKit）

| 型 | 責務 |
| --- | --- |
| `QuickOpenQuery` | 入力文字列を `.path(String)` / `.fuzzy(String)` / `.empty` に分類する純粋関数 |
| `FuzzyMatcher` | 部分列マッチとスコアリングを行い、順位付きの複数候補を返す |
| `DirectoryFileScanner` | 非 Git 時の再帰走査。深さ・件数の上限と除外ディレクトリを持つ |
| `QuickOpenCandidates` | 索引・走査・履歴・ブックマークをマージし、重複除去して順位付けする |

### 新規コンポーネント（App）

| 型 | 責務 |
| --- | --- |
| `QuickOpenPanelController` | `NSPanel` のライフサイクル。表示・非表示とキーイベントの配線のみ |
| `QuickOpenModel` | `@MainActor @Observable`。入力の変化から候補配列を導き、決定を注入されたクロージャへ渡す |
| `QuickOpenView` | SwiftUI。`TextField` と候補リスト。上下キーで選択移動、Enter で決定 |

`QuickOpenPanelController` と `QuickOpenView` は判断ロジックを持たない。候補の決定も開く先の決定もすべて `QuickOpenModel` より下の層で完結させる。

### 既存コンポーネントへの接続

- **候補源**: `GitCommandFileIndex`（`GitFileIndexing` 実装、`git ls-files` を 1 回実行して全ウィンドウで索引を共有）をそのまま利用する。プロトコル越しのためテストでは差し替えられる。
- **パス解決**: `TrackedPathResolver.resolve(href:baseURL:)` を流用する。ディレクトリが指された場合は `SupportedFileResolver.resolveFileToOpen(at:)` に渡す。
- **表示ラベル**: `PathRelativizer.relativePath(of:relativeTo:)` で相対パスを生成する。
- **重複除去キー**: `URL+NormalizedPathKey` の `normalizedPathKey` を使う。
- **メニュー**: `MainMenuBuilder.build(...)` に Quick Open 項目を追加し、Print の `keyEquivalent` を `p` から `P`（`Shift+Cmd+P`）へ変更する。

既存の `SuffixPathMatcher` / `SuffixPathIndex` は最良 1 件のみを返す設計であり、候補リスト表示には使えない。既存の文書内リンク解決の挙動を変えないため、照合規則には手を入れず `FuzzyMatcher` を別に設ける。

ただし `GitFileIndexing.trackedFileIndex(forFileAt:)` は `SuffixPathIndex` を返すだけで、取り込んだ候補 URL を読み出す口を持たない。そのため `SuffixPathIndex` に読み取り専用の `allCandidates: [URL]` を 1 つ追加する。照合には使わず、既存の解決挙動は変わらない。

## Behavior

### パスモード（先頭が `/` `~` `.`）

- `~` は展開する。`./` `../` は現在開いているファイルのディレクトリを基準に解決する。
- 入力を「確定した親ディレクトリ」と「未確定の末尾断片」に分解する。`~/dev/be` なら親が `~/dev/`、断片が `be`。親ディレクトリの中身を列挙し、断片で前方一致（大文字小文字を無視）して絞り込む。末尾が `/` なら断片は空とみなし中身を全件表示する。
- `Tab` は候補の共通接頭辞まで補完する。候補が 1 件だけでそれがディレクトリなら、末尾に `/` を付けて次の階層へ進む。
- 親ディレクトリが存在しない場合は「該当なし」を表示し、`Enter` は何もしない。
- 決定した対象がディレクトリなら `SupportedFileResolver.resolveFileToOpen(at:)` に渡して中の 1 ファイルを開く（`Cmd+O` の既存挙動と揃える）。

### fuzzy 検索モード

- 候補全件に `FuzzyMatcher` をかけ、スコア降順で表示する。表示上限は 50 件。
- スコアは、連続一致・単語境界（`/` `_` `-` `.` の直後、およびキャメルケース境界）での一致・ファイル名部分での一致を加点する。
- 同点時は正規化パスの昇順で並べ、結果を決定論的にする（既存 `SuffixPathMatcher` の決定論方針に揃える）。
- 入力に `/` が含まれる場合はパス全体に対して照合し、含まれない場合はファイル名部分を優先して照合する。

### 空入力時

- 最近開いたファイル（`RecentDocumentsStore`）を上位に、続けてブックマーク（`BookmarkStore`）を並べる。合計 20 件を上限とする。
- 履歴とブックマークは fuzzy 検索モードでも候補に混ぜる。同一ファイルが Git 索引にも存在する場合は `normalizedPathKey` で重複除去し、履歴側の加点を反映する。

### 候補の取得タイミングと上限

- パネルを開いた時点で `GitCommandFileIndex.warm(forFileAt:)` を呼び、初回入力までに索引の準備を進める。
- 非 Git のディレクトリ走査は深さ上限 8、件数上限 10,000 とする。`.git` `node_modules` `.build` を除外する。
- 隠しファイルの扱いは既存の `HiddenFilesPreference.showHiddenFiles`（`Ctrl+Cmd+H` で切り替わる値）に従い、独自のフィルタ設定を持たない。
- 上限に達して打ち切った場合は、その旨をリスト末尾に表示する。黙って切り捨てない。
- 索引取得とディレクトリ走査はバックグラウンドで行い、結果を `@MainActor` に戻して反映する。入力ごとの絞り込みは同期で行う。候補は 10,000 件で上限が掛かっており、メモリ内の照合はデバウンスを挟むまでもなく収まる。実測でもたつく場合にのみ後からデバウンスを導入する。

### エラーと空結果

- 候補ゼロは正常な状態として扱い、リストに「一致なし」を表示するだけとする。アラートは出さない。
- 選択後にファイルが消えていた場合は、既存の `ViewerWindowManager` のガードから `FileNotFoundUI.present(url:over:)` に落ちる。Quick Open 側では独自のエラー表示を持たない。

## Testing

TDD で進める。各ステップで `swift test` が通る状態を保つ。

### 自動テスト（BefoldKit）

- `QuickOpenQuery`: `/` `~` `.` 始まり、空文字、空白のみ、`~` 単独などの境界での分類。
- `FuzzyMatcher`: 「連続一致が飛び飛びより上位」「ファイル名一致がディレクトリ名一致より上位」「同点は path 昇順で安定」を、期待順序の配列と比較して検証する。スコアの絶対値は assert しない（チューニングのたびにテストが壊れるため、検証対象は順序とする）。
- `DirectoryFileScanner`: 深さ上限・件数上限・除外ディレクトリ・隠しファイル設定。`BefoldTestSupport/TempDir` で実ファイルツリーを作って検証する。上限到達時に打ち切りフラグが立つことも検証する。
- `QuickOpenCandidates`: 履歴・ブックマーク・索引のマージ、`normalizedPathKey` での重複除去、履歴加点。`GitFileIndexing` はテスト用スタブを注入する。

### 自動テスト（App）

- `QuickOpenModel`: 候補源をプロトコル越しに受け取る形にし、「入力を与えると期待した候補配列になる」「決定時に注入したクロージャが正しい URL で呼ばれる」を検証する。ウィンドウやパネルには依存させない。
- `MainMenuBuilder`: Quick Open 項目が `Cmd+P`、Print 項目が `Shift+Cmd+P` に割り当てられていることを検証する。

### 手動チェック（リリース前）

既存規約どおり、`QuickOpenPanelController` と `QuickOpenView` は自動テスト対象外とする。

- `Cmd+P` でパネルが表示され、`Esc` とフォーカス喪失で閉じる
- 上下キーで選択が移動し、`Enter` で現在のウィンドウが切り替わる
- 大きな非 Git ディレクトリで入力がもたつかない
- ウィンドウが 1 枚も無い状態で `Cmd+P` を押したときの挙動
- `Shift+Cmd+P` で印刷ダイアログが表示される

## Out of Scope

- 新しいタブでの表示（`addTabbedWindow` の明示的な利用）。macOS の自動タブ化に任せる現行方針を変えない。
- ファイル内容の全文検索。候補はパスとファイル名のみを対象とする。
- コマンドパレット（ファイル以外のアクション実行）への拡張。
- `SuffixPathMatcher` / `SuffixPathIndex` の照合規則の変更。文書内リンク解決の挙動は現状を維持する（`allCandidates` の追加は読み取り専用で挙動を変えないため対象外）。
