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

1. **提示状態は 1 つの値**: 表示対象は `ViewerSession`（仮称）の enum で表し、
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
