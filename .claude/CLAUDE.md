# befold

macOS 向けのドキュメント・ダイアグラムビューアアプリ。
`.mmd` / `.md` を中心に SVG / HTML / CSV・TSV / 画像 / PDF / ソースコードを
プレビューし、ファイル変更を監視してプロセス内でリアルタイム更新する。

## アーキテクチャ

**詳細な構成図・モジュールツリー・コンポーネント一覧は
[`docs/dev/native-app-design.md`](../docs/dev/native-app-design.md) が単一の情報源。
ここには最低限の見取り図だけを置く（同じ内容を二重管理しない）。**

> このリンクは常に**現在作業中のワークツリー（worktree）内**の同名ファイルを指す。
> worktree で作業している場合、セッション起動時の「Primary working directory」
> （通常は main のパス）を起点に絶対パスを組み立てて開いてはならない。
> 必ず現在の cwd／`git rev-parse --show-toplevel` を起点に解決すること。
>
> **一般則（ドキュメントに限らない）**: このプロジェクトで作業する際、現在の
> worktree（`git rev-parse --show-toplevel` で得られるルート）の外にあるパスには、
> ファイル種別を問わず一切アクセスしない。ソースコード・設定・ドキュメントいずれも
> 同様で、別の clone や別の worktree（例: 別セッションの `.claude/worktrees/...`）に
> ある同名ファイルを開いてはならない。サブエージェントを起動する場合も、この制約を
> プロンプトで明示的に伝えること。

ソースはすべて `BefoldApp/` 配下にあり、主要ターゲットは次のとおり。

| ターゲット | 責務 |
|---|---|
| `befold/` | 本体アプリ（AppKit + SwiftUI）。`App/`（ライフサイクル・ウィンドウ管理・各種永続化ストア）、`Viewer/`（`ViewerStore` / `ViewerWebView` / サイドバー・検索）、`FileWatching/`（`FileWatcher` / `Debouncer`）、`Updates/`（`UpdateChannel`） |
| `BefoldKit/` | コアロジック＋レンダリングアセット（`ContentLoader` / `FileType` / `ViewerBridge` / `RendererFeatures` ほか、`Resources/` に viewer.html・mermaid・markdown-it 等を同梱） |
| `BefoldRenderKit/` | 描画エンジン `ViewerRenderer`（WKWebView ドライバ）。本体アプリと QuickLook 拡張で共有 |
| `BefoldQuickLook/` | QuickLook 拡張（appex）。`ViewerRenderer` を直接使い 1 回描画 |
| `BefoldCLI/` / `befold-cli/` | CLI 共有ライブラリと `befold` 実行ファイル |
| `BefoldTestSupport/` / `befoldTests/` / `befoldCLITests/` | テスト共有ヘルパーと Swift Testing テスト |

- ファイル変更は `FileWatcher → ViewerStore → ViewerRenderer(evaluateJavaScript)` の
  同一プロセス内伝搬で反映する。
- CLI 起動は `befold-cli → BefoldCLI → befold.app` で伝搬する。
- 自動アップデートは Sparkle 2（`AppDelegate` が `SPUStandardUpdaterController` を保持）。

## 技術スタック

- Swift 6 / AppKit + SwiftUI（macOS 14+）
- WKWebView（mermaid.js / markdown-it.js レンダリング）
- DispatchSource（ファイル監視）
- XcodeGen（プロジェクト生成）/ Swift Package Manager（ビルド）

## コマンド

```bash
# Swift ネイティブアプリ（BefoldApp/）
cd BefoldApp
swift build                  # ビルド
swift test                   # テスト（要 Xcode.app）
xcodegen generate            # .xcodeproj を再生成（新規ファイルの追加・削除後は必須）
xcodebuild build -scheme befold  # Xcode ビルド（要 Xcode.app）

# Markdown リンタ（リポジトリルートで実行。設定は .markdownlint-cli2.jsonc）
markdownlint-cli2          # docs 変更時に実行（--fix で自動修正）

# 規約文書が引用するシンボルの実在チェック（pre-commit フックでも自動実行）
scripts/check-doc-symbols.sh              # CLAUDE.md 内の 型.メンバ 形式の引用を検査
scripts/check-doc-symbols.sh --self-test  # 検知が働くことだけを確認
```

このチェックは 型.メンバ / 型.メンバ(ラベル:) 形式の引用だけを見る（単独の型名や
コマンドまで広げると誤検知の除外リストのほうが重くなるため）。実在しない引用を検知したら、
直すのは文書側。例示のための架空名・外部フレームワークの API に限り
`scripts/doc-symbol-allowlist.txt` へ追記する。

ファイルを新規追加したら `xcodegen generate` を忘れないこと。`swift build` は
SPM がディレクトリを走査するため通ってしまい、`.app` バンドルを作る `xcodebuild` だけが
`cannot find 'X' in scope` で落ちる（実機確認の直前に気付くことになる）。

## Swift コーディング規約

- Swift 6 strict concurrency（`SWIFT_STRICT_CONCURRENCY: complete`）
- `@MainActor @Observable` を ViewerStore に使用
- FileWatcher は `@unchecked Sendable`（内部 GCD キューでスレッド安全性を保証）
- UI コンポーネントは SwiftUI、ウィンドウ管理は AppKit（NSWindowController）
- 複数行にまたがる `if` / `guard` の条件は、`guard ... else { return }` の 1 行化か
  ヘルパー抽出で避ける。swiftformat が `{` を独立行へ送り、swiftlint の `opening_brace` が
  新規警告になる（両者の設定が衝突する箇所であり、どちらかを直すと他方が鳴る）
- **swiftformat と swiftlint が逆を要求したら、手で整形して往復しない。**
  多行コレクションの trailing comma・brace 位置などで両者の指摘が衝突する。
  `cd BefoldApp && swift package plugin --allow-writing-to-package-directory swiftformat`
  （fix モード）を回して機械に決めさせ、その結果に対して swiftlint 差分を測る。
  それでも swiftlint が鳴る構文は、リテラル・多行条件そのものを避ける形に書き換える
  （1 行に収める / 変数へ分解する / ヘルパーへ抽出する）
  - **編集ごとの PostToolUse フックは一部ターゲットしか lint しない**（`befold` /
    `befoldTests` が含まれず、コミット時の全ターゲット実行で初めて落ちる）。
    コミット前に上記コマンドを 1 回流し、`-- --lint` でゼロ件を確認してから commit する
- swiftlint は警告の絶対数では判定できない（main 時点で 80 件ほどある）。
  変更前後で一覧を取り、**main とのベースライン差分がゼロ**であることを確認する
  - swiftlint は `Package.swift` の `SwiftLintPlugins` がビルド時に実行するもので、
    単体ではインストールされていない（`brew install` すると CI とバージョンがずれる）。
    手元で一覧を取るにはプラグイン同梱のバイナリを直接呼ぶ:
    `BefoldApp/.build/artifacts/swiftlintplugins/SwiftLintBinary/SwiftLintBinary.artifactbundle/macos/swiftlint lint --quiet`
  - 比較時は行番号がずれただけの差分を除くため、`sed -E 's/:[0-9]+:[0-9]+:/:/'` で
    正規化してから diff する
  - **ベースライン（main 側）を取るのに `git stash` を使わない。** stash は worktree 間で
    共有されるため、作業ツリーが clean だと `git stash push -u` が何も退避せず、続く
    `git stash pop` が**別のセッション・別プロジェクトの stash** を取り出して
    コンフリクトさせる。`git archive origin/main | tar -x -C <スクラッチパッド>` で
    別ディレクトリへ展開し、そちらで測る（手順は `/swiftlint-baseline` にまとめてある）
- **`Localizable.xcstrings` に文字列を追加するときはキー順にソートし直さない。**
  Xcode の出力は厳密なキー順ではないため、sort すると 200 行超の無関係な並べ替え差分が出る。
  既存の並び順を保ち、近縁キー（同じ prefix のもの）の直後に挿入する

## 知識グラフ（dagayn）の Swift での限界

`refactor_tool(mode="dead_code")` はこのリポジトリでは使えない。Swift のプロトコル
準拠メソッド（NSApplicationDelegate / NSViewRepresentable / WKNavigationDelegate /
NSWindowDelegate / ArgumentParser など）は静的な呼び出し元を持たないため、実測で
1126 件中ほぼ全件が偽陽性になる。デッドコード判定は `rg` でトークン出現数を数え、
宣言 1 箇所のものだけを候補にして個別に除外条件を確認する。関係の追跡
（callers_of / tests_for など）は有効なので、そちらは従来どおり使う。

## テスト規約

- **ユニットテスト**: `befoldTests/` — Swift Testing フレームワーク
- テスト関数名は英語 camelCase（SwiftLint の `identifier_name` が非 ASCII 開始の名前を弾く）。
  日本語の説明が必要なら `@Test("日本語の説明")` の表示名で付ける
- FileWatcher: 一時ファイルによる実ファイルシステムテスト
- ViewerStore: `@MainActor` テスト（状態遷移検証）
- WebView/GUI 層: 自動テスト対象外（リリース前手動チェック）

## 設計・方針を提示するときは前提と裏付けを明示する

設計・方針・調査結論をユーザーに提示するとき、**その提案が依拠している検証可能な
前提**を明示し、前提ごとに何で裏付けたかを併記する。裏付けの種類は次の 3 つで、
どれに当たるかが読んで分かるように書く。

- **実測**: 実行したコマンドと結果（「`swift test` で 3 件失敗、テスト名は…」）
- **コード参照**: `file_path:line` の形で示す
- **ドキュメント参照**: どの文書のどの節か（spec・ADR・project.yml のコメント等）

裏付けが取れていない前提がある場合は、**その前提を落とさずに書き、未確認である
ことと確認方法を明記する**（「未確認: X は Y だと仮定している。`rg 'Z'` で
確認できる」）。黙って仮定に乗ると、承認がその仮定への同意になってしまう。

理由（TASK-305 の実測）: transcript 3,086 メッセージのうちユーザー発話の 14.1% が
承認のみで、一方でユーザーの指摘 91 件の大半は**コードの誤りではなく AI が置いた
前提の誤り**の否定だった（「タグが指すコミット数は規約ではない」「それは
フィーチャーゲートで止めている機能のはず」等）。前提を明示しない提示は、
前提が未検査のまま実装へ進む経路になる。

この規定は「提示の仕方」を定めるもので、着手前に入力ドキュメント（spec 等）の
記述が実コードとずれていないかを確かめる作業とは別物。両方必要で、順序は
「入力の前提を確かめる → 提示時に前提と裏付けを書く」。

## 実装着手前の設計レビュー

新しい状態・述語・表示設定を足す変更、値の持ち方を変える変更（computed →
キャッシュ、常駐化、正規化の位置を移す等）、既存の不変条件・共通経路に触る
変更は、**実装に着手する前に** `/review-design` を 1 回回し、結果を
backlog タスクの Implementation Plan に反映する。

根拠（TASK-306 の実測）: 実装直後にまとめて起票されたレビュー指摘 16 件を
分類したところ、約 75〜78% は実装コードを読まなくても設計文だけから導けた。
残りは「既存コードの無駄」「テストコードの書き方」「実装後の grep でしか
分からない同期漏れ」で、これらは従来どおり実装後レビューで拾う。

小さな局所修正（1 ファイル内で完結し、状態も経路も増やさないもの）には
適用しない。

**サブタスクに分割したら、サブタスクごとに回す。** 親タスクの Description に
論点を並べるのは予告であって実行ではない。実装の設計判断はサブタスク側で
下されるため、親で 1 回では届かない。

**決めたことには、破れたら落ちるものを付ける。** 設計判断（粒度・共有範囲・
不変条件）と次タスクへの申し送りは、doc コメントや Notes に書くだけでは
守られない。次のどちらかを同じタスク内で用意する。

- その判断を破ると落ちるテスト（`DiffDisplayPreference` が窓ごとに生成されたら
  落ちる、など）
- 破りようのない構造（デフォルト引数をやめて必須引数にする、appex に
  そもそもコンパイルされない場所へ置く、など）

申し送りを次のタスクへ渡すときは、Notes に書くだけで終わらせず
**受け取り側の Acceptance Criteria にする**。

根拠（TASK-326 の実測）: TASK-315（git 差分表示）の実装後レビューで確定した
bug 7 件のうち 5 件（71%）は設計文の突き合わせで導ける型だった。`/review-design`
を実際に回したのは 3 サブタスク中 315.1 のみで、回さなかった 315.2 / 315.3 から
4 件が出た。残る 3 件は「申し送りが片側だけを指示」「粒度を決めたが配線されず」
「同型の穴を予告して 1 箇所だけ直した」で、いずれも**判断は正しく記録された上で
担保が無く破れている**。

**同型のバグが 2 回目に出たら、個別修正をやめて構造で塞ぐ。** 1 回目は該当箇所を
直してよい。同じ型（同じ判定方式・同じ確定漏れ・同じ列挙漏れ）で 2 件目が起票された
時点で、3 件目を「次に気をつける」で防ごうとしない。次のいずれかへ切り替える。

- 判定の置き場所を変える（DOM や文字列の形で判定していたものを内部状態へ移す）
- 経路を一本化する（部分更新のオーバーロードを撤去し、送信と確定を同一の同期区間へ）
- 破れない形へ変える（列挙式の比較をミラー全体比較へ、デフォルト引数を必須引数へ）

ルールへの明文化は 2 回目の対処として数えない。明文化済みでも破れた実例がある
（`FeatureGate` 運用は規約にあったが TASK-333 で破れた）。

根拠（bug ラベル 25 件の分類実測）: 同型の 3 連鎖が 2 系列あった。appendChunk の
抑止判定（TASK-318 → 329 → 339）は、セレクタ一致 → 差分の有無 → DOM 判定と
移りながら毎回別の誤検知を生み、内部状態フラグへ移して終息した。描画ミラーの
確定漏れ（TASK-320 → 334 → 336）は、列挙式判定・await 前確定・中断時の記録漏れと
形を変えて再発し、部分更新オーバーロードの撤去で終息した。どちらも 2 件目の時点で
構造対策へ切り替えていれば 3 件目は生まれていない（計 2 件が防げた）。

## 完了基準

- タスク中に発見したリファクタリング課題は「次回触るときに」と後回しにせず、同じタスク内で完了する
- TDD の原則に従い、動作する状態にした後、設計のブラッシュアップまでを 1 タスクとする
- スコープが大きすぎる場合はユーザーに相談して判断を仰ぐ（勝手に先送りしない）

## コミット規約

Conventional Commits + 日本語:

```text
feat: Mermaid ビューア画面を追加する
fix: ファイル変更検知が2回通知される問題を修正する
chore: XcodeGen 設定を更新する
```

- **FeatureGate 配下のコードを変更する commit には `(gate)` スコープを付ける**
  （例: `feat(gate): 変更ファイル絞り込みのトグルボタンを追加する`）。
  `/release-notes stable` はこのスコープをコミット件名だけで機械的に判定して
  除外する。スコープを付け忘れると、stable では露出しない機能がリリースノートに
  漏れる（過去に `FeatureGate.isSidebarGitStatusEnabled` という別名のゲート関数を
  grep で見逃し、実際に混入した）。判断基準は「変更箇所が `FeatureGate.swift` の
  いずれかの `Bool` を経由してのみ有効化されるか」。

## フィーチャーゲート（開発中機能の dev 限定露出）

- 未完成機能は `FeatureGate.inProgressFeaturesEnabled` で囲い、dev/DEBUG ビルドでのみ露出する。
  判定は「バージョン文字列のプレリリース接尾辞（`-dev.N`）」由来で、`UpdateChannel`（ユーザー設定）は流用しない。
  直接 `inProgressFeaturesEnabled` を参照せず、機能ごとの別名 computed property
  （例: `isSidebarGitStatusEnabled`）を経由することがあるため、ゲート判定は
  `FeatureGate.swift` 内の宣言一覧を基準にする（コード全体を `inProgressFeaturesEnabled`
  で grep しても別名のゲートは見つからない）。
- フラグは一時的な足場。stable に載せると決めた時点で分岐を撤去しデフォルト有効化し、撤去タスクを backlog に登録する。
- 検証は「ロジックはユニットテスト、ON は dev リリースの dogfood、OFF は次回 stable リリース」で担保する。
- **OFF 側の実機確認をローカルの Release ビルドで行おうとしない。**
  `xcodebuild build -scheme befold -configuration Release` 自体は成功するが、生成された
  `.app` は同梱フレームワークと署名の Team ID が合わず起動できない
  （`Library not loaded: @rpath/BefoldKit.framework` / `different Team IDs`）。
  代わりに**ゲート値を引数で受ける純粋関数へ切り出し、ON/OFF 両方向をユニットテストで
  押さえる**。`ModeSegments.modes(isSourceDiffEnabled:)` /
  `MainMenuBuilder.addDisplayModeItems(to:isSourceDiffEnabled:)` がこの形。
  ゲート越しに参照する形だけを残すと、動いているビルドの側しか検証されない
  （AC に「stable では 2 択になること」があっても、実機で確かめる手段が無いまま
  マージされる）。
