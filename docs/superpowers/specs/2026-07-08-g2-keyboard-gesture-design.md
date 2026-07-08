---
title: キーボード/ジェスチャー操作の改善（G2）
date: 2026-07-08
status: approved
---

<!-- constrained-by ../plans/2026-07-08-ui-ux-improvements-roadmap.md#g2-キーボードジェスチャー操作優先度-高 -->
<!-- constrained-by ./2026-07-04-diagram-zoom-design.md -->

## 概要

`docs/superpowers/plans/2026-07-08-ui-ux-improvements-roadmap.md` の G2 グループに
含まれる4項目（#3, #4, #10, #11）を実装する。

## 1. スペースキー/矢印/vim jk でスクロール（#3, #4）

### 現状

`BefoldApp/befold/Resources/viewer.html:99-109` に既存の `keydown` リスナーがあり、
⌘+/⌘- のズームショートカットを処理している（`_mmdZoomIn()` / `_mmdZoomOut()` を
JS内で直接呼ぶ）。スクロール用のキーボードショートカットは未実装。

キーボード処理は Swift 側（`WKWebView` の keyDown オーバーライドなど）ではなく、
既存の `viewer.html` 内 `document.addEventListener('keydown', ...)` が主体であり、
ズーム機能もこの1箇所に集約されている。新しいスクロールショートカットも同じ
リスナーに追加するのが既存構造と一貫する。

スクロール対象のDOM要素は `style.css` で `overflow: auto` が設定されている
`.viewer`（メインのスクロールコンテナ、ページ全体のMarkdown/コード表示時に
縦スクロールを担う）。ダイアグラム個別ズーム時の `.diagram-zoom-scroll` は
本タスクのスコープ外とする（ダイアグラム表示中の全体スクロールは通常
発生しないため）。

### 変更方針

`viewer.html` の `keydown` リスナーに以下の分岐を追加する:

- `key === ' '`（スペース）: `shiftKey` が false なら下スクロール、true なら
  上スクロール
- `key === 'ArrowDown'` または `key === 'j'`: 下スクロール
- `key === 'ArrowUp'` または `key === 'k'`: 上スクロール
- `shiftKey` が true の場合はスクロール量を大きくする（ページ送り相当）

スクロール量の計算を純粋関数として切り出す（`viewer.js` に追加）。DOM操作
（`.viewer` への `scrollBy` 呼び出し）はJS側のイベントハンドラで行うが、
「どちら向きに・どれだけスクロールするか」の計算はDOMに依存しない純粋
ロジックとして切り出し、Node.js 経由でユニットテスト可能にする
（本プロジェクトには現状JSのテストランナーが無いため、新規に軽量な
Node実行によるアサーションスクリプトを追加する。既存の `swift test` の
対象外であり、`npm test` 等の別コマンドとして追加する）。

```js
// viewer.js に追加するイメージ（実装計画で詳細化）
const SCROLL_STEP = 80;       // 通常スクロール量(px)
const SCROLL_STEP_LARGE = 400; // 大スクロール量(px、shift併用時)

function scrollKeyDelta(key, shiftKey) {
  const step = shiftKey ? SCROLL_STEP_LARGE : SCROLL_STEP;
  if (key === ' ') return shiftKey && key === ' ' ? -step : step;
  // ArrowDown/j は常に下、ArrowUp/k は常に上（shiftは量のみ変える）
  if (key === 'ArrowDown' || key === 'j') return step;
  if (key === 'ArrowUp' || key === 'k') return -step;
  return null; // 対象外のキー
}
```

上記は概念のみ。実装計画では、スペースキーだけ「shiftKey が逆転条件」に
なる点（要件: 「スペースで下、shift+スペースで上」）と、矢印/jkは
「キー自体が方向を決め、shiftは量だけ変える」点を区別して実装する。

### テスト方針

**重要（既存パターンの確認結果）**: 本プロジェクトには JS を実行して検証する
テストランナー（Node.js等）は存在しない。`viewer.js` 冒頭のコメント
「テスト可能な純粋ロジック」は、実際には Swift Testing 側から JS の
**ソーステキストを文字列として読み込み、関数定義や定数値の存在を
アサーションする「ドリフト検知」テスト**（`ViewerBridgeTests.swift:87-100`
の `zoomRangeMatchesZoomStore` 等）を指しており、JS を実際に実行して
戻り値を検証するものではない。新規に Node.js 等のテストランナーを
導入するのはこのプロジェクトの既存パターールールに反するため行わない。

本タスクでは `scrollKeyDelta` 相当のロジックを `viewer.js` に定数
（`SCROLL_STEP` / `SCROLL_STEP_LARGE`）付きの純粋関数として切り出すが、
実行結果の自動検証はせず、実際のDOMスクロール・キーイベント発火と
合わせて手動確認する（プロジェクトの既存方針「WebView/GUI層は自動
テスト対象外」に従う）。

## 2. ズームジェスチャー対応（#10）

### 現状（重要な発見）

`viewer.html:198-207` に既存の `wheel` イベントリスナーがあり、
`e.ctrlKey` が true の場合にホイールイベントを「ズーム操作」として扱っている
（イベントのターゲットが `.diagram-zoom-wrap` 内かどうかでダイアグラム個別
ズームと全体ズーム(`_mmdWheelZoom`)を振り分ける、`viewer.html:94-97,198-207`）。

**macOS の WebKit/Chromium 系ブラウザエンジンは、トラックパッドのピンチ
（マグニフィケーション）ジェスチャーを Web コンテンツ内では
`ctrlKey: true` の `wheel` イベントとして配信する**（Safari/Chrome共通の
挙動）。つまり `viewer.html` 経由でレンダリングされる Markdown / Mermaid /
コード表示など（`isDirectHTMLMode` でない全ての形式）は、**既にトラック
パッドのピンチジェスチャーでズームできている可能性が高い**。

一方、`.html` ファイルを直接ロードする `isDirectHTMLMode`（`ViewerWebView.swift`
参照、`WKWebView.pageZoom` を直接操作するモード）は `viewer.html` を経由
しないため、この `wheel` リスナーの恩恵を受けない。`WKWebView` には
`allowsMagnification: Bool`（macOS, デフォルト `false`）というプロパティが
あり、これを `true` にするとトラックパッドのピンチで `WKWebView` の
`magnification`（表示スケール）が変化する（`pageZoom` とは別の変倍機構）。

### 変更方針

1. **確認タスク**: 既存の `viewer.html` 経由のピンチズームが実際に機能する
   ことを手動確認する（既に実装済みの可能性が高いため、新規実装ではなく
   確認作業として扱う）。
2. **direct HTML mode 対応**: `ViewerWebView.swift` の `WKWebView` 生成箇所で
   `webView.allowsMagnification = true` を設定する。これにより isDirectHTMLMode
   のファイルでもトラックパッドピンチでズームできるようになる。

### スコープ外

- `allowsMagnification` による変倍（`WKWebView.magnification`）と
  `ZoomStore` が管理する `pageZoom` ベースのズーム値との同期・永続化
  （要望は「ジェスチャーでズームできること」であり、値の永続化は
  `pageZoom` ベースのメニュー操作に閉じたままでよい）
- ダイアグラム個別ズームの新規変更（既存のCtrl+ホイール振り分けロジックは
  そのまま）

### テスト方針

`allowsMagnification = true` の設定は1行のプロパティ設定であり、
ユニットテスト化の対象にならない。手動確認手順（トラックパッドで実際に
ピンチしてズームすることを確認）を明記する。

## 3. 二本指スワイプで履歴を遡る（#11）

### 現状（調査済み）

戻る/進む履歴機能自体は `NavigationHistory` / `SidebarNavigator` /
`FileListModel` / `HistoryNavigationButton` として既に完成しており、
`ViewerWindowController.navigateHistory(by offset:)`
（`ViewerWindowController.swift:254-256`、負=戻る/正=進む）という
呼び出し口も既に存在する（`FileListView` の `onNavigateHistory` から
使われている）。不足しているのは「二本指スワイプ」を検知してこの
メソッドを呼ぶ配線のみ。

`WKWebView` は `scrollWheel` イベントを内部で消費するため、AppKit の
`NSView.scrollWheel(with:)` をオーバーライドする通常の方法では
確実に検知できない。また `WKWebView` はデフォルトで
`allowsBackForwardNavigationGestures`（ページ内の戻る/進むナビゲーション
ジェスチャー）を持つ可能性があり、本アプリはページ履歴を使っていないため
明示的に無効化しておく必要がある。

### 変更方針

- `ViewerWindowController` の `WKWebView` 設定箇所で
  `webView.allowsBackForwardNavigationGestures = false` を設定し、
  WebKit標準のページ履歴スワイプと衝突しないようにする。
- `ViewerWindowController` に `NSEvent.addLocalMonitorForEvents(matching:
  .scrollWheel, handler:)` でウィンドウ単位のイベント監視を追加する
  （`init` 内、`window.delegate = self` 設定以降で登録し、`windowWillClose`
  で `NSEvent.removeMonitor` により解除する）。
- 監視ハンドラは、水平方向のトラックパッドジェスチャーの完了
  （`event.phase == .ended` かつ `momentumPhase` が入る前、または
  `momentumPhase == .began` の最初の1回）を捉え、`scrollingDeltaX` の
  符号としきい値からスワイプ方向を判定し、
  `navigateHistory(by:)` を呼ぶ。
- スワイプ方向 → `navigateHistory` の offset への変換ロジック
  （しきい値判定、符号→オフセットのマッピング）を純粋関数として
  切り出しユニットテスト可能にする:

```swift
enum SwipeHistoryNavigation {
    /// トラックパッドの水平スクロールデルタから履歴ナビゲーションの
    /// offset を決める。しきい値未満は nil（ナビゲーションしない）。
    static func offset(forHorizontalDelta deltaX: CGFloat, threshold: CGFloat) -> Int? {
        guard abs(deltaX) >= threshold else { return nil }
        // 右向き(正のdeltaX)スワイプ=戻る(-1)、左向き=進む(+1)
        // (トラックパッドの自然なスクロール方向に合わせる)
        return deltaX > 0 ? -1 : 1
    }
}
```

### テスト方針

`SwipeHistoryNavigation.offset(forHorizontalDelta:threshold:)` はユニット
テストする。実際の `NSEvent.addLocalMonitorForEvents` の登録・発火・
`WKWebView` との競合有無は自動テスト対象外とし、手動確認手順を明記する。

## スコープ外（全体）

- スクロール量・スワイプしきい値の具体的なピクセル値のUI設定機能
  （固定値のハードコードでよい）
- ダイアグラム個別ズーム機能自体の変更（既存のまま）
- JS を実行するテストランナー（Node.js等）の新規導入（本プロジェクトの
  既存パターンに存在しないため導入しない。JS変更は手動確認に委ねる）
