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
| `BefoldPDFProbe/` | PDF の解釈（`PDFDocument` の生成）だけを持つ最小の層。PDFKit を要する判定を `BefoldKit` から隔離する（TASK-598） |
| `BefoldRenderKit/` | 描画エンジン `ViewerRenderer`（WKWebView ドライバ）。本体アプリと QuickLook 拡張で共有 |
| `BefoldQuickLook/` | QuickLook 拡張（appex）。`ViewerRenderer` を直接使い 1 回描画 |
| `BefoldCLI/` / `befold-cli/` | CLI のコマンド定義（ArgumentParser）と `befold` 実行ファイル。本体は依存しない（本体と共有する型は `BefoldKit`、`CLIInstaller` は本体側） |
| `BefoldTestSupport/` / `befoldTests/` / `befoldCLITests/` | テスト共有ヘルパーと Swift Testing テスト |

- ファイル変更は `FileWatcher → ViewerStore → ViewerRenderer(evaluateJavaScript)` の
  同一プロセス内伝搬で反映する。
- CLI 起動は `befold-cli → BefoldCLI → befold.app` で伝搬する。依存は `befold-cli → BefoldCLI → BefoldKit` の一方向で、本体（`befold`）は `BefoldCLI` / ArgumentParser を import しない（`scripts/check-app-no-cli-dependency.sh` が検査）。
- 自動アップデートは Sparkle 2（`AppDelegate` が保持する `AppUpdaterController` が `SPUStandardUpdaterController` を持つ）。

## 技術スタック

- Swift 6 / AppKit + SwiftUI（macOS 14.2+）
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

# JS/TS の lint とフォーマッタ（site/ と BefoldApp/ のそれぞれで実行）
npm run lint               # Oxlint（--report-unused-disable-directives 付き）
npm run lint:fix           # 自動修正できる指摘だけ直す
npm run format             # Oxfmt で整形
npm run format:check       # 整形ずれの検査（CI と pre-commit が使う）

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

### ビルドが反映されているか確かめる

`.app` フォルダの**作成日は最初に作られた日のまま**で、`xcodebuild` は中身だけを
差し替える（実測: bundle 2026-08-17 / 実行体 2026-09-06）。Finder の「作成日」が古くても
ビルドされていないとは限らない。反映を確かめるなら
`Contents/MacOS/befold` と `Contents/Frameworks/*.framework` の**更新時刻**を見る。

**`strings` で確認するときはメイン実行体だけを見ない。** BefoldRenderKit / BefoldKit の
コードは `Contents/Frameworks/<名前>.framework` 側に入るため、メイン実行体を探して
「入っていない」と誤結論する（実測で 1 回やった。診断ログは framework 側にあった）。

`/run` は `-derivedDataPath .build/xcode` を固定する。`~/Library/Developer/Xcode/DerivedData`
配下の別バンドルと**混在させない**——同一セッションで両方を起動すると、どちらを見て
いるのか分からなくなる。

## パス別の規約（`.claude/rules/`）

次の節は `.claude/rules/` へ移した。該当するファイルを Read / Edit すると自動で読み込まれる。
ファイルに触る前に方針を決めるとき（設計・レビュー）は、先に該当するルールを読むこと。

| 節 | 置き場 | 読み込まれる条件 |
|---|---|---|
| JS/TS コーディング規約（Oxlint / Oxfmt） | `.claude/rules/js-ts.md` | JS/TS・oxlint/oxfmt の設定ファイル |
| Swift コーディング規約 | `.claude/rules/swift.md` | `.swift` / `.xcstrings` |
| UserDefaults キーの廃止・改名 | `.claude/rules/userdefaults.md` | `.swift` |

理由: 3 節で本ファイルの約 3 分の 1 を占め、サイトだけ・文書だけの作業でも毎回読み込まれていた。

サブエージェントを worktree で動かす場合など、パス条件が効くかが不確かなときは、
プロンプトで該当するルールファイルを読むよう指示する。

## 知識グラフ（dagayn）の Swift での限界

`refactor_tool(mode="dead_code")` はこのリポジトリでは使えない。Swift のプロトコル
準拠メソッド（NSApplicationDelegate / NSViewRepresentable / WKNavigationDelegate /
NSWindowDelegate / ArgumentParser など）は静的な呼び出し元を持たないため、実測で
1126 件中ほぼ全件が偽陽性になる。デッドコード判定は `rg` でトークン出現数を数え、
宣言 1 箇所のものだけを候補にして個別に除外条件を確認する。関係の追跡
（callers_of / tests_for など）は有効なので、そちらは従来どおり使う。

## テスト規約

- **ユニットテスト**: `befoldTests/` — Swift Testing フレームワーク
- **CI は PDF のテストを別プロセスで回す**（`--skip PDF` と `--filter PDF`）。PDFView の Vision 解析が、
  キャッシュの無い環境で libdispatch のワーカーを使い切り、同じプロセスの実 WKWebView のロードを
  止めるため（TASK-907）。PDFView を作るテストは名前に PDF を含める（`PDFTestIsolationGuardTests` が見る）。
  手元の `swift test` が固まったら、`scripts/test-watchdog.sh` を通すと止まった場所が分かる
- テスト関数名は英語 camelCase（SwiftLint の `identifier_name` が非 ASCII 開始の名前を弾く）。
  日本語の説明が必要なら `@Test("日本語の説明")` の表示名で付ける
- FileWatcher: 一時ファイルによる実ファイルシステムテスト
- ViewerStore: `@MainActor` テスト（状態遷移検証）
- WebView/GUI 層: 自動テスト対象外（リリース前手動チェック）
- **環境に依存する実測値をアサートしない。** 窓の寸法・画面サイズ・レイアウト結果は
  AppKit がディスプレイに合わせて切り詰めるため、手元で通っても CI の仮想ディスプレイで
  落ちる。守りたい値そのもの（定数・純粋関数の戻り値）を測ること。
  実測（TASK-593.5）: スライド窓の既定サイズが 16:9 であることを
  `window.contentView.frame.size` の比で測ったテストが、手元では通り GitHub Actions の
  macOS ランナーで比 1.52 になって落ちた。`ViewerWindowKind.slide.defaultContentSize` を
  直接測る形へ移して解消した（実現された寸法は AppKit の都合であって、守りたい値ではない）

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
（かつての `FeatureGate` 運用は規約にあったが TASK-333 で破れた）。

根拠（bug ラベル 25 件の分類実測）: 同型の 3 連鎖が 2 系列あった。appendChunk の
抑止判定（TASK-318 → 329 → 339）は、セレクタ一致 → 差分の有無 → DOM 判定と
移りながら毎回別の誤検知を生み、内部状態フラグへ移して終息した。描画ミラーの
確定漏れ（TASK-320 → 334 → 336）は、列挙式判定・await 前確定・中断時の記録漏れと
形を変えて再発し、部分更新オーバーロードの撤去で終息した。どちらも 2 件目の時点で
構造対策へ切り替えていれば 3 件目は生まれていない（計 2 件が防げた）。

## 設計文書の三層構造と、現在仕様の集約

このプロジェクトの設計情報は三層に分かれている。**どの層に書くかを取り違えない。**

| 層 | 置き場 | 性質 | 更新のタイミング |
|---|---|---|---|
| 現在の仕様 | `docs/dev/native-app-design.md` と、その索引から辿る文書（表示仕様は `file-type-display.md` / `viewer-ui.md`） | 常に「今」を表す単一の情報源。入口は native-app-design.md | 実装完了時に**必ず**追随させる |
| 設計スナップショット | `docs/superpowers/specs/*-design.md` | 書かれた時点の意図と検討経緯。追記も修正もしない | 起票・設計時に 1 回書くだけ |
| 不可逆な設計判断 | `backlog/decisions/`（ADR） | 他の選択肢を潰した判断とその理由 | 判断を下した時点 |

**スナップショット層を「現在の仕様」として読まない。** spec は日付順に並んでいるが、
どれも当時の設計であり、実装と食い違っていることがある。着手前に spec の記述を
コードで裏取りする（メモリ `verify-spec-premises-before-starting` の実例がある）。

新しく `docs/superpowers/specs/*-design.md` を作ったら、H1（と `derived-from` 等の
ディレクティブ）の直後に次のバナーを置く。既存の spec はすべて付与済み。

```markdown
> **これは YYYY-MM-DD 時点の設計スナップショットです。**
> 現在の仕様は [`docs/dev/native-app-design.md`](../../dev/native-app-design.md)
> が単一の情報源。この文書は当時の意図と検討経緯を残すためのもので、
> 現在の実装と食い違っていることがある。着手前に必ずコードで裏を取ること。
```

**スナップショットを現在仕様へ吸収する動作は `/finish-task` の手順 5 で行う。**
spec を書きっぱなしにすると、設計文書が増えるほど「今どうなっているか」が
コードにしか無い状態になる。実装が終わった時点で `native-app-design.md`（表示仕様なら `file-type-display.md` / `viewer-ui.md`）を更新し、
更新不要と判断したならその理由を Notes に 1 行残す。

なお OpenSpec のような外部の spec 管理ツールは導入しない。上の三層で同じ役割を
既に担っており、後から重ねると設計文書の置き場が二重化する。

### 文書からコードを引用するときは行番号を書かない

`docs/adr/**` と `docs/dev/**` は「今のコード」を語る層なので、コードを指すときは
**パスとシンボル名**で示し、`path:12` のような行番号引用は使わない。
`scripts/check-doc-citations.sh` が pre-commit で落とす。

```markdown
NG: `DOWNLOAD_URL`（`site/src/views/shared.tsx:13`）
OK: `DOWNLOAD_PATH`（`site/src/views/shared.tsx`）
```

理由（TASK-550 の実測）: 行番号はコードを 1 行足すだけで無音でずれ、名前と違って
grep でも lint でも見つからない。ADR 0007 の `DOWNLOAD_URL`（`shared.tsx:13`）は
定数名も位置も実態と違っていたが、誰も気づかないまま「そこにその名前がある」という
前提を配り続けていた。同じスクリプトが引用パスの実在も見るので、ファイルの移動や
拡張子の変更（`viewer-src/*.js` → `*.ts`）でずれた引用もそこで落ちる。

**シンボル名そのものの実在は検査しない。** ADR は「採らなかった案」「存在しないもの」
を論じる文書で、実測では ADR 内の識別子 79 件中 9 件が「実在しない」と出て、うち
8 件はそう書くのが正しい記述だった（偽陽性 89%）。検査を足すと除外リストが本体になる。

**ADR の Context が現状調査を含むなら、見出しに調査日を書く**（「### 現状（実測 /
2026-08-14 時点）」）。決定の実装そのものが調査結果を古くするため、日付が無いと
読み手は決定前の記述を現在仕様として読む。

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
