# ADR 0002: 「いま何を提示しているか」と「いま何ができるか」を型で持ち、ビューの生存期間に依存しない

- ステータス: Accepted
- 日付: 2026-08-04
- backlog decision: decision-2

<!-- constrained-by ./0001-keep-appkit-app-lifecycle.md -->
<!-- derived-from ../dev/native-app-design.md -->

## Context

サイドバーのパフォーマンス改善（TASK-265 / 266 / 268）を進める中で、性質の同じ回帰が 3 回続けて発生した。

1. **暗黙の無効化が消えた**: フォルダー一覧の表示中に印刷・検索・ズームが効かなかったのは、
   `WKWebView` が破棄されて `WebViewProxy.webView`（weak）が nil になるためだった。
   TASK-266 で WebView を常駐させた瞬間にこの「偶然の no-op」が消え、見えていない文書に操作が届くようになった。
2. **初期値が生成順に依存していた**: `ViewerRenderer.makeWebView` が atDocumentStart のユーザースクリプトに
   倍率を焼き込むため、`makeNSView` が `store.openFile` より前に走るようになった途端、
   ウィンドウを開いた最初のファイルの保存倍率が失われた（TASK-270）。
3. **フォーカスとアクセシビリティが生存期間で決まっていた**: WebView が破棄されることで AppKit が
   ファーストレスポンダを付け替えていた。常駐させると、不可視の文書にキー入力と VoiceOver が届く（TASK-271）。

いずれも「**ビューの生存期間を、状態・能力・初期値の代理として使っている**」という 1 つの型である。

### 実測した現状（2026-08-04 時点）

同じ概念の真実の源が複数ある。

| 概念 | 箇所数 | 実体 |
|---|---|---|
| いま表示している対象 | 5 | `ViewerStore.currentURL` / `ViewerStore.filePath` / `FileListModel.selection` / `window.representedURL` / `PreviewTargetResolver` の導出結果 |
| 倍率 | 4 | `ZoomStore`（永続） / `WKWebView.pageZoom`（直接 HTML 時） / viewer.js 内部変数 / `ViewerRenderer.initialPageZoom`・`pendingPageZoom` |
| ソース表示モード | 3 | `ViewerStore.isSourceMode`（実行時） / `SourceModeStore`（永続） / ツールバーの `selectedSegment` |

> 補記（TASK-356）: 表示モードは `ViewerStore.displayMode`（`ViewerDisplayMode` の 1 値）と
> `DisplayModeStore`（永続）に集約し、ツールバーの選択位置はそこから導出する形へ整理した。
> 差分の ON/OFF を別の Bool で持たないため、「レンダリング表示なのに差分だけ ON」という
> 不整合は状態として作れない。
| 直接 HTML モード | 2 | `ViewerRenderer.isDirectHTMLMode` / `WebViewProxy.isDirectHTMLMode` |

実行可否の判断も分散している。`ViewerWindowController.validateMenuItem` と
`WebViewCommandController` の各メソッドが同じ条件を二重に書いており、さらに
**`validateMenuItem` を通らないコマンド経路が 4 本ある**（ツールバーの view ベース項目、
オーバーフロー（»）メニュー、サイドバーの `onKeyPress`、ツールバーのフィルタ／ソート／隠しファイル）。
TASK-266 で追加した `canOperateOnVisibleDocument` は validate 側にしか無いため、この 4 本は素通りする。

「まだ分からない」を表す値が無いことによる実害も確認した。`PreviewTargetResolver.resolve` は
選択が一覧に無い場合に `.folder(currentDirectory)` を返す。ウィンドウ生成直後は `entries` が空なので、
一覧が届くまで「フォルダーを提示している」と判定され、印刷・検索・ズームがメニュー上で無効になる。
ネットワークボリューム上では体感できる長さになる。

テストの空白も同じ根に由来する。ウィンドウ系テストは `makeContentView: placeholderViewerContent`
（`AnyView(Color.clear)`）を注入するため `webViewProxy.webView` は常に nil であり、
`WebViewCommandController.evaluate` の `guard let webView else { return }` によって、
JS 契約のズレも呼び出し順の変更も「no-op が正常」として通過する。

### 外部の定石（調査結果）

- メニュー項目は validate を実装していなければ**有効**になる。無効化は明示的に書くものであり、
  「ビューが消えたから偶然無効」は Cocoa の設計意図に反する
  （[User Interface Validation](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UIValidation/UIValidation.html)）。
- `dismantleNSView` は呼ばれないことがある（[Apple Forums 724376](https://developer.apple.com/forums/thread/724376)）。
  破棄を後始末・無効化の唯一の場にしてはならない。
- `makeNSView` は一度きりのセットアップ専用で、初期値を含む設定は `updateNSView` で宣言的に流し込む
  （[Use SwiftUI with AppKit, WWDC22](https://developer.apple.com/videos/play/wwdc2022/10075/)）。
  Coordinator に representable（parent）を持たせると陳腐化する
  （[Massicotte](https://www.massicotte.org/swiftui-coordinator-parent/)）。
- SwiftUI ではビューの状態の寿命は identity によってフレームワーク側の都合で決まる
  （[Demystify SwiftUI, WWDC21](https://developer.apple.com/videos/play/wwdc2021/10022/)）。
  アプリの真実をそこに置くと、生成順や identity 変化で失われるのは仕様どおりの帰結。
- WKWebView は生成が重く、作り直すより使い回すのが定説
  （[Embrace](https://embrace.io/blog/wkwebview-memory-leaks/)）。
  可視でない間は仕事を止め、可視化時に 1 回だけ適用するのが Apple のガイドライン
  （[Work When Visible](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/WorkWhenVisible.html)）。
- 「不可能な状態を表現できなくする」型設計（bool の束を enum に畳む）が、
  能力を参照の nil 判定から導出することを構造的に防ぐ
  （[Make Impossible States Impossible](https://kentcdodds.com/blog/make-impossible-states-impossible)）。

## Decision

**「いま何を提示しているか」を 1 つの値（enum）で持ち、「いま何ができるか」をそこから導出する層を設ける。**
ビューの生存期間・weak 参照の nil・`makeNSView` の呼ばれ方に、状態・能力・初期値を委ねない。

具体的には次の 4 点を規約とする。

1. **提示状態は 1 つの値**: 表示対象は `ViewerSession`（仮称。実装では `PreviewTarget`）の enum で表し、
   「まだ分からない（一覧取得前）」を独立した case として持つ。
   `FileListModel.selection` や `window.representedURL` はその投影であり、独立した真実にしない。
2. **能力は状態から導出する**: `canPrint` / `canFind` / `canZoom` / `canToggleSource` などを
   提示状態から導出する 1 つの関数に集約し、`validateMenuItem`・ツールバー・コマンド実行の
   すべてがそこだけを見る。WebView 参照の nil 判定を能力の根拠にしない。
   `validateMenuItem` を通らない経路（ツールバー・オーバーフロー・`onKeyPress`）も同じ関数を通す。
3. **representable は投影に徹する**: `makeNSView` は器を作るだけとし、倍率・フォント等の設定は
   `updateNSView` で毎回宣言的に流し込む。`dismantleNSView` に後始末を依存させない。
4. **レンダラは port の裏に置く**: `DocumentRenderer` 相当のプロトコルを境界にし、WKWebView 実装を
   その adapter とする。WebView の寿命（作り直す／使い回す／プールする）と可視時の抑止は、
   状態の設計と切り離してこの内側で選ぶ。

**フレームワーク（TCA 等）は導入しない。** 上記 1〜4 はライブラリ無しで実現でき、
1 人開発の規模では学習・移行コストが恩恵を上回ると判断する
（[Point-Free FAQ](https://www.pointfree.co/blog/posts/141-composable-architecture-frequently-asked-questions) 自身が
「素の SwiftUI で始めて必要になったら移行してよい」としている）。
ADR 0001 の決定（AppKit がライフサイクルを所有する）は維持し、本 ADR はその内側の状態設計だけを扱う。

## 表示モードの遷移仕様

<!-- derived-from #decision -->

規約 2（能力は状態から導出する）を表示モード `ViewerDisplayMode` に適用した結果の仕様。
`feat/preview_mode` のレビュー指摘 10 件中 4 件（TASK-368〜371）は、
「モード × ファイル種別 × 入口」ごとの期待挙動が明文化されておらず、
遷移・永続化・no-op がコードの成り行きで決まっていたことに起因した。
以降の変更はこの節を基準に突き合わせる。

### 用語

- **保存値** = `ViewerStore.displayMode`（`DisplayModeStore` が永続化する値）
- **実表示** = `ViewerStore.effectiveDisplayMode`。`保存値 == .rendered && showsCodeContent`
  のときだけ `.source` を返す導出値で、保存値を書き換えない。
  `.code` ファイルは「保存値 `.rendered` / 実表示 `.source`」という状態を常に取る。

**判定はすべて実表示に対して行う。** 保存値と実表示の食い違いを無視して保存値だけで
遷移を決めると、`.code` で「既にソース表示なのに rendered→source の完全遷移が走る」
（TASK-368）。

### 選択可能なモード（ファイル種別 × 能力）

能力は `ViewerCapabilities` が状態から導出する。いずれも `onDocument`
（文書を提示中かつ拒否されていない）を前提とする。

| 種別 | `.rendered` | `.source` | `.diff` | cmd+U |
|---|---|---|---|---|
| `.markdown` / `.mmd` / `.svg` / `.html` | ○ | ○ | ○ | ○ |
| `.csv` / `.tsv` | ○ | ○ | ×（差分非対応） | ○ |
| `.code` | ×（非レンダラブル） | ○ | ○ | ×（`supportsSourceMode` = false） |
| `.image` / `.pdf` | ○ | ×（バイナリ） | × | × |

`.diff` の列は `canSelectDiffMode`（`onDocument && !isBinaryContent && supportsDiffDisplay`）
であって、フィーチャーゲートを含まない。**ゲートは能力ではなく入口（メニュー項目・
セグメント）を消すことで効かせる。** 能力側にゲートを混ぜると、能力の意味が
「この文書に対して成立するか」から「いま押せるか」へずれる。

### 遷移表

各入口が「どのモードへ遷移するか」「保存値へ書くか」。

| 入口 | 遷移先 | 永続化 | 備考 |
|---|---|---|---|
| セグメント選択 | 選択したモード | する | 選択位置は実表示から導出 |
| cmd+1 / cmd+2 / cmd+3 | `.rendered` / `.source` / `.diff` | する | cmd+3 はゲート ON のときのみ項目が存在 |
| cmd+`\` / 差分セグメントの再クリック | 遷移しない（差分レイアウト切替） | しない | ゲート ON かつ差分表示中のみ（TASK-385） |
| cmd+U（レンダリング表示から） | 直前のソース系モード、無ければ `.source` | する | 下記「cmd+U の戻り先」 |
| cmd+U（ソース系から） | `.rendered` | する | 離脱前の実表示を記憶する |
| CLI `--source` / `--preview`（新規ウィンドウ） | `.source` / `.rendered` を降格規則に通した値 | **しない** | この起動限りの上書き |
| CLI `--source` / `--preview`（指定パスが既に開いている） | 同上 | **しない** | 同上。新規ウィンドウと同じ規則（TASK-413） |
| ウィンドウ復元・起動 | 保存値（無ければ `.rendered`）を降格規則に通した値 | しない | |
| ファイル切替 | 切替先の保存値を降格規則に通した値 | しない | |
| リネーム | **いま表示中のモード**を降格規則に通した値 | しない | 保存値ではない（TASK-369） |

**降格規則**（`DisplayModeStore.supportedDisplayMode(_:for:)` の 1 箇所に置く）:
`.rendered` はそのまま、`.source` は `supportsSourceMode` でなければ `.rendered`、
`.diff` は差分対応かつゲート ON でなければ `.source`（`.code` 以外）または `.rendered`。
**降格しても保存値は書き換えない。** 対応する種別のファイルへ戻れば元のモードが復帰する。

リネームで保存値を再適用すると、永続化されていないライブなモード
（CLI 上書き）がリネームで破棄される（TASK-369）。リネームは
「別のファイルを開く」ではなく「同じ文書の名前が変わる」操作であり、
引き継ぐべきは保存値ではなく現在の表示である。

**cmd+U の戻り先**: ソース系から離れる際に「離脱直前の実表示」をファイルパスをキーに
記憶し、戻るときに使う。これが無いと `.diff` → cmd+U → cmd+U で `.source` に落ち、
保存値の `.diff` も上書きで失われる（TASK-370）。記憶はソース系モードへ入る
すべての経路で破棄する。記憶自体はウィンドウごとのライブな状態であり、
永続化も同期もしない。

### 永続化規則

**保存値へ書くのは明示的なユーザーのモード選択だけ**（`setDisplayMode` の 1 経路）。
次はいずれも書かない。

- 復元・ファイル切替・リネームに伴う適用（`applyDisplayMode`）
- CLI `--source` / `--preview` の上書き（新規ウィンドウ・既に開いているウィンドウとも
  `applyCLIDisplayMode(isSourceMode:)` の 1 経路。パスを伴わない指定は CLI が
  パース段階でエラーにするため、対象の文書が無いまま保存値へ届く経路は存在しない）
- no-op と判定された選択（次項）

### no-op 規則

`setDisplayMode` は次のいずれかで、副作用を一切起こさず早期 return する。
スクロール位置の退避・永続化・差分の再取得をまとめて行わない。

1. `canSelect(新モード)` が false（そのファイル種別で成立しないモード）
2. **新モード == 実表示**（保存値ではない）

規則 2 により、`.code` ファイルで `.source` を選ぶ操作（セグメント・cmd+2・
CLI `--source`）はすべて no-op になる。`.code` は既に実表示が `.source` であり、
遷移を走らせるとスクロール位置が別のキーへ退避されて先頭へ飛び、
意味のない `.source` が保存値に書かれる（TASK-368）。

### 複数ウィンドウでの扱い

**同一ファイルを開いている 2 つのウィンドウは、それぞれ別の表示モードを示してよい。**
表示モードは次節「状態の所在」の**文書の状態**にあたり、窓が生きている間は
その窓のライブ値が有効で、窓間の同期は行わない。

TASK-371 では逆に「すべての窓が同じ表示モードを示す」を不変条件として同期を実装したが、
TASK-382 の再検討でこの決定を差し替えた。経緯と根拠は「トリップワイヤの評価」節に記す。
**実装（`mirrorDisplayMode` とデリゲート通知の撤去）は TASK-388 で完了している。**

適用の細部:

- 保存値（`DisplayModeStore`）を読むのは、窓がその文書を提示し始めるときだけ
  （オープン・ファイル切替・モード切替）。生きている窓が保存値を読み直さないことで、
  他窓の選択が後から効くことを構造的に防ぐ。
- スクロール位置も同じ扱い。`(パス, モード)` 粒度で永続化するが、それは
  「次にその文書を開くときの既定値」であって、開いている窓へ後から効く値ではない。
  この粒度のまま、読み直しの契機を絞ることで 2 窓の競合が消える。

## 状態の所在（アプリの好み / 文書の状態 / 窓の状態）

<!-- derived-from #複数ウィンドウでの扱い -->

前節は表示モードについてのものだが、同じ問いは倍率・スクロール位置・行番号表示など、
ビューアが持つすべての状態に生じる。状態ごとに個別に決めると判断が場当たりになるため、
**新しい状態を足すとき・既存の状態の持ち方を変えるときは、まずこの 3 分類の
どれに当たるかを決める。**

### 分類を決める問い

順に問う。最初に当たったところで決める。

1. > **その値は、いま開いている「文書」に紐づくか?**
   >
   > 紐づく（別の文書へ切り替えたら別の値であってほしい）→ **文書の状態**。
   > 窓ごとのライブ値が有効で、保存値はファイル単位。

2. > **文書に紐づかないとして、それは「この窓で何をどう眺めているか」の現在値か?**
   >
   > そうである（同じ設定でも窓ごとに違ってよく、操作した窓だけが変わってほしい）
   > → **窓の状態**。窓ごとのライブ値が有効で、保存値はアプリ全体に 1 つだが
   > **新規ウィンドウの初期値としてのみ**使う。

3. > **どちらでもない = どの窓でも同じであってほしい設定か?**
   >
   > そうである（窓ごとに違うと「なぜこの窓だけ違うのか」を説明できない）
   > → **アプリの好み**。全窓で 1 インスタンス。

分類 2 は 2026-08-14（TASK-480）に追加した。それ以前は 2 分類しか無く、
サイドバーの表示設定は「ファイルに紐づかない = アプリの好み」として分類 3 へ
落ちていた。これは本 ADR の Consequences に置いたトリップワイヤ 3 の後段
（**2 分類のどちらにも収まらない状態が現れたとき**）の発火にあたる。
決定（規約 1〜4）は変えず、分類だけを 3 つに引き直す。

### 3 分類

| 分類 | 判定 | 持ち方 | 例 |
|---|---|---|---|
| **文書の状態** | その文書をどう読んでいるかの現在値。窓ごとに違ってよい | **窓が生きている間はその窓のライブ値**が有効。ファイル単位の保存値は「次にその文書を開くときの既定値」で、提示の開始時にだけ読む。窓間の同期はしない | 表示モード（`DisplayModeStore`）、ズーム倍率（`ZoomStore`）、スクロール位置（`ScrollPositionStore`）、行番号表示（`ViewerStore.showLineNumbers` + アプリ全体の既定値）、cmd+U の戻り先、戻る/進む履歴 |
| **窓の状態** | その窓で何をどう眺めているかの現在値。文書には紐づかないが、窓ごとに違ってよい | **窓が生きている間はその窓のライブ値**が有効。アプリ全体の保存値は「次に開く窓の初期値」で、窓の生成時にだけ読む。窓間の同期はしない | サイドバーの表示形式（`layoutMode`）・不可視ファイル表示（`showHiddenFiles`）・変更ファイルのみ表示（`showChangedFilesOnly`）・並び順（`sortOrder`）（`SidebarDisplayPreference`） |
| **アプリの好み** | どのファイルをどの窓で見ているかに依らない設定。窓ごとに違うと「なぜこの窓だけ違うのか」を説明できない | アプリ全体で 1 インスタンスを生成して全ウィンドウへ注入し、変更は即座に全窓へ反映する | 差分レイアウト（`DiffDisplayPreference`）、検索オプション（`FindOptionsPreference`）、コードフォント（`CodeFontPreference`） |

### 文書の状態の規則

1. **保存値を読むのは、窓がその文書を提示し始めるときだけ**（オープン・ファイル切替・
   モード切替の 3 契機）。生きている窓が保存値を読み直すと、他窓の操作が後から効いてしまう。
   窓 B のスクロール位置が窓 A の位置へ飛ぶ類の不具合は、すべてこの読み直しが原因。
   **リネームは提示の開始ではない**（同じ窓が同じ文書を提示し続けている）ため、
   ここでは読まずライブ値を引き継ぐ（TASK-369。読み直すとリネーム前の保存値へ
   巻き戻る）。モード切替はスクロール位置のキーが `(パス, モード)` 粒度である以上、
   切替先モードのキーからの読み込みが必要なので契機に含める。
2. **保存値へ書くのは明示的なユーザー操作だけ。** 後勝ちでよい。保存値の意味は
   「最後にその文書をどう読んでいたか」であり、次に開くときの出発点にすぎない。
3. **窓を閉じるとライブ値は消える。** 窓ごとの値を永続化はしない。
4. **窓間の同期はしない。** 同じファイルを 2 窓で別々の倍率・位置・モードで読むのは
   食い違いではなく正常な使い方である。

**引き受けた妥協**: アプリを終了して再起動すると、同じファイルを開いていた複数の窓は
同じ値（ファイル単位の保存値）で復元される。窓ごとの復元には窓の識別子が要るが、
`SessionLayout` は `groups: [TabGroup]`（パスの並び）しか持たず、窓の同一性を表す値が
無い。識別子の新設に見合う場面が「同一ファイルの複数窓 × アプリ再起動」に限られるため、
導入しない。**これを導入したくなったときが、この決定を見直すときである**（後述の
トリップワイヤ 3）。

### 窓の状態の規則

サイドバーの表示設定 4 値（`layoutMode` / `showHiddenFiles` / `showChangedFilesOnly` /
`sortOrder`）がこの分類にあたる。ユーザーが ⌃⌘T などで表示形式を切り替えたとき、
期待するのは「いま操作している窓の一覧が変わる」ことであって、
背後の別の窓の一覧まで作り替わることではない。

1. **ライブ値は窓ごとに持つ。** 窓のサイドバー・ツールバー・メニューは、
   その窓のライブ値だけを見る。アプリ全体に 1 つ置いた値を全窓が見る形にはしない。
   **`sortOrder` は既にこの形になっている**（真実の源は各窓の
   `FileListModel.sortOrder`、`SidebarDisplayPreference.sortOrder` は
   「次に窓を開くときの既定値」= `FileListEntry.swift` の doc コメント）。
   残る 3 値もこれに揃える。
2. **永続化された app-global の値は、新規ウィンドウの初期値としてのみ使う。**
   既存キー（`SidebarLayoutMode` / `ShowHiddenFiles` / `ShowChangedFilesOnly` /
   `SidebarSortOrder`）はそのまま残すが、意味は
   「全ウィンドウの現在値」から「次に開く窓の初期値」へ変わる。
   読むのは窓の生成時の 1 回だけで、生きている窓は読み直さない
   （読み直すと他窓の操作が後から効く。これは「文書の状態の規則 1」と同じ理由）。
3. **値の変更時に最新値を書き戻す。** 保存値の意味は「最後にどう眺めていたか」であり、
   後勝ちでよい。窓ごとの値を窓ごとに永続化はしない（窓の識別子が無い。
   「引き受けた妥協」と同じ制約）。
4. **窓間の同期はしない。** アプリ全体へ配る経路
   （`GlobalDisplayBroadcaster`）からこの 4 値を外す。同型が
   `DiffDisplayPreference` 等と混ざらないよう、**そもそもこの 4 値を
   `GlobalDisplayBroadcaster` に持たせない**（持たなければ配れない）ことで担保する。
   `GlobalDisplayBroadcaster` の doc コメントが述べる「ここから配ってよいもの」の
   定義は、この分類 3 に限る形へ書き換える。
5. **操作経路はアクティブウィンドウ 1 つへ向ける。** メニュー（`AppDelegate` の
   `@objc` アクションと `validateMenuItem` のチェック状態）、サイドバーヘッダーの
   アイコンボタン、CLI の `--hidden-files` / `--no-hidden-files` は、
   いずれも対象の窓 1 つを解決してからその窓の値を変える。

### アプリの好みの規則

- **「アプリ全体で 1 インスタンス」は、既定値のないイニシャライザで構造的に守る。**
  既定値があると渡し忘れがコンパイルエラーにならず、静かに窓ごとの別インスタンスへ落ちる
  （実際に 2 窓でトグルが同期しない不具合になった = TASK-319）。
  `DiffDisplayPreference` がこの形。
- 変更は全窓へ即座に反映する（`refreshAllToolbars` / `refreshAllSidebars` /
  `applyCodeFontToAllWindows`）。ここは「同期」ではなく、1 つの値を全員が見ている状態。

### 実装状況（2026-08-10 時点）

`ViewerStore.showLineNumbers`・ズーム倍率・スクロール位置・表示モードのいずれも
この節の形になっている（TASK-388 で完了）。保存値を読む入口は
`ViewerWindowController.beginPresentingDocument`（オープン・ファイル切替）と
`setDisplayMode`（モード切替）に閉じ、表示モードの窓間同期（`mirrorDisplayMode` と
デリゲート通知）は撤去済み。`ViewerWindowStateIndependenceTests` が、同期を戻すと
落ちるトリップワイヤになっている。

この 2 つの入口は `ViewerDocumentPresenter` にある（TASK-411 で本体ファイルから拡張へ移し、
TASK-441 で独立型へ出した）。分割前は同一ファイル内の `private` が「他から呼べないこと」を
担保していたが、型を分けた時点で internal になり構造的な担保が消えたため、
`ViewerWindowPresentationEntryPointTests` が**呼び出し元の個数をソース走査で固定**している。

サイドバー表示 4 値の「窓の状態」への移行は TASK-480 で行う。移行後は
`GlobalDisplayBroadcaster` が `SidebarDisplayPreference` を保持しないことと、
2 窓のうち一方だけを変更しても他方が変わらないことをテストで固定する。
提示開始の契機を増やす変更は、この節を先に更新しない限りテストが落ちる。

## Consequences

- 移行は段階的に行い、各段を独立してコミットする。

  | 段 | 内容 | 解消する問題 |
  |---|---|---|
  | 1 | 提示状態の enum を新設し、「現在の対象」の 5 箇所をその投影にする | 起動直後の誤無効化、切替中の倍率ズレ |
  | 2 | 能力の導出関数へ集約し、validate・ツールバー・コマンド実行を向ける | 見えない文書への操作、素通りの 4 経路（TASK-271） |
  | 3 | representable を薄くする（初期値は `updateNSView` へ） | 初回ファイルの倍率喪失（TASK-270） |
  | 4 | `DocumentRenderer` port を切り、WKWebView を adapter にする | テストが「no-op が正常」で通る空白（TASK-273 の一部） |
  | 5 | 可視性を状態に含め、不可視時の更新を抑止する | 不可視 WebView の再描画（TASK-272） |

- 段 4 まで進むと、ウィンドウ系テストが `webViewProxy.webView == nil` の世界で回っている現状が解消され、
  レンダラへの命令を検証可能な境界で確かめられるようになる。
- 既存の「真実の源を 1 つにする」規律（例: `ViewerWindowController.fileURL` は `store.currentURL` へ委譲）は
  そのまま維持する。本 ADR はそれを「提示状態」と「能力」という、まだ型を持っていなかった 2 つの概念へ広げるもの。
- パフォーマンス改善（WebView を使い回す等）は段 4 の内側の選択となり、
  UI の構造を変えずに試せるようになる。TASK-266 で行った「ビュー階層で寿命を制御する」やり方は、
  段 4 到達後に port の内側の実装へ移す。
- この決定を再検討するトリップワイヤ:
  1. 段 1〜3 を終えても同種の回帰（提示していない対象への書き込み）が再発する
  2. 状態遷移の分岐が手書きで追えない規模になり、リデューサ的な枠組みが必要になる
  3. 複数ウィンドウ間で提示状態を共有・同期する要件が生まれる

### トリップワイヤの評価（2026-08-09 / TASK-382）

<!-- derived-from #consequences -->

トリップワイヤ 3 が TASK-371（同一ファイルを複数ウィンドウで開いた際の表示モード同期）で
発火したため、3 本すべての現状を評価し決定を再検討した。**結論は「本 ADR の決定は維持する。
ただし発火の原因となった『窓間で提示状態を同期する』という要件自体を取り下げる。」**

| # | 判定 | 根拠 |
|---|---|---|
| 1 | 前提未成立（段 1・3 が未完のため、まだ問える段階にない） | 段 1: `PreviewTarget` に `.undetermined` が入り起動直後の誤無効化は解消したが、対象の格納は `ViewerStore.currentURL` / `filePath` と `FileListModel.selection` の 2 系統が残り、`window.representedURL` は手動同期。段 3: 初期値（倍率・フォント・検索オプション）が `makeNSView` → atDocumentStart のユーザースクリプトに残っている |
| 2 | 未発火 | 表示モードの遷移は `setDisplayMode` / `mirrorDisplayMode` / `applyDisplayMode` / `supportedDisplayMode` / `effectiveDisplayMode` の 5 つに閉じ、降格規則は `DisplayModeStore`（約 100 行）の 1 箇所。上記「表示モードの遷移仕様」の表で全入口を書き下せている |
| 3 | **発火済み** | `ViewerWindowController.setDisplayMode` 完了時のデリゲート通知 → `ViewerWindowManager.mirrorDisplayMode` → パスキー引き、という窓間同期の経路が実装された |

段 2・4・5 は実装済み（`ViewerCapabilities` / `DocumentRendering` port と WKWebView adapter /
可視性による更新抑止）。段 2 が名指しした「`validateMenuItem` を通らない 4 経路」は、
オーバーフローメニューの実行側自前ガードとツールバーの `capabilities` 参照で解消したか、
文書の能力を必要としない経路（サイドバーのナビゲーション、一覧のスコープ設定）として
対象外になった。

**要件を取り下げた理由**: 再検討の過程で、窓間で揃えるべき状態とそうでない状態の線引きが
表示モードについてしか書かれていないことが分かった。一般化しようとして初めて、
TASK-371 が採用した「同一ファイルの全窓は同じ表示モードを示す」という不変条件が、
比較対象を持たないまま選ばれていたことが明らかになった。

代替案は「窓が生きている間はその窓のライブ値が有効で、閉じると保存値（次に開くときの
既定値）に戻る」である。これはズーム倍率・スクロール位置にもそのまま当てはまり、
表示モードだけを特別扱いしなくてよい。**同期を足すのではなく、生きている窓が保存値を
読み直さないようにするだけで済む**ため、実装も小さい。同期の設計で必要だった配慮
（無限再帰の防止、ミラー先での永続化抑止、差分取得を合流させるための同期区間の制約）は
まとめて不要になる。

**本 ADR の決定（規約 1〜4）はこの変更の影響を受けない。** 提示状態を 1 つの値で持ち
能力をそこから導出するという設計は、その値が窓ごとであっても全窓共有であっても成立する。
リデューサ的な枠組み（トリップワイヤ 2）を必要とする分岐の増加も観測されていない。
したがってフレームワークは引き続き導入しない。

**取り下げの帰結**: TASK-371 で実装した `mirrorDisplayMode` とデリゲート通知は
TASK-388 で撤去済み。ADR 側の記述（この節と「複数ウィンドウでの扱い」「状態の所在」）と
実装は一致している。

再発火の条件を次のとおり引き直す。

1. （変更なし）段 1〜3 を終えても同種の回帰が再発する
2. （変更なし）状態遷移の分岐が手書きで追えない規模になる
3. 差し替え。**窓ごとの状態を永続化するために窓の識別子が必要になったとき**
   （「状態の所在」節で引き受けた妥協——アプリ再起動時に同一ファイルの複数窓が
   同じ値へ収束すること——を許容できなくなったとき）、または
   **2 分類のどちらにも収まらない状態が現れたとき**

**3 の後段は 2026-08-14（TASK-480）に発火した。** サイドバーの表示設定 4 値が
「ファイルには紐づかないが窓ごとに違ってよい」状態であり、当時の 2 分類の
どちらにも収まっていなかった。対処として分類へ**窓の状態**を足し、決定
（規約 1〜4）は維持した。再発火の条件は「3 分類のどれにも収まらない状態が
現れたとき」へ引き直す。
