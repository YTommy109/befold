---
id: TASK-564.7
title: PDF ウィンドウで WKWebView を作らないようにする（初回表示の遅さ）
status: Done
assignee:
  - '@claude'
created_date: '2026-08-29 12:42'
updated_date: '2026-08-29 13:07'
labels:
  - performance
dependencies: []
parent_task_id: TASK-564
ordinal: 822000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 目的

PDF を開いたときの初回表示が体感で遅い（ユーザー報告: 約 1 秒）。実測すると、時間の大半は
**PDF とは無関係な WKWebView の生成と viewer.html の読み込み**に食われている。
PDF は `PDFView` で描くようになった（TASK-564.1 / ADR 0009）のに、同じ窓に
描画面がもう 1 枚作られ、viewer.html + バンドル（816KB）を読み込んでいる。

## 実測（2026-08-29 / Debug ビルド / 一時的な NSLog 計測）

窓が 2 つ復元される起動での内訳（`openViewer` を 0ms とした相対時刻）:

| 経過 | 出来事 |
| --- | --- |
| 0.0ms | `openViewer` 開始 |
| 51.4ms | `ViewerWebView.makeNSView`（**WKWebView の生成**） |
| 121.7ms | `loadContent` 開始 |
| 293.5ms | 読み込みパイプラインが実際に走り始める（**この間 172ms、メインスレッドが窓の組み立てで詰まっている**） |
| 294.9ms | ファイル読み込み + PDF の検証まで完了（**1.4ms**） |
| 313.2ms | 表示状態の確定 |
| 323.3ms | `PDFView` へ文書を設定し終わる |
| +約 180ms | `PDFView` の初回描画（画素が出るまで） |

PDF 自体の処理は速い。別プロセスでの計測では 1.2MB / 231 ページの PDF でも
読み込み 0.2ms・SHA256 0.4ms・`PDFDocument(data:)` 0.1ms（遅延パースのため）で、
初回の描画だけが約 115ms。**既に開いている窓でファイルを PDF へ切り替える場合は
読み込みから描画設定まで 26ms** で終わる。つまり遅いのは窓を新しく作る経路。

## やること

PDF を表示する窓では WKWebView を作らない（遅延生成にする）。

## 論点（実装着手前に `/review-design` で詰める）

- **TASK-266 との整合**: 「描画面は破棄・再生成しない」は白フラッシュと stale な初期倍率を
  避けるための決定で、**まだ作っていないものを作らない**こととは別。ただし PDF → md の
  切替時に生成コストを払うことになるので、その瞬間の見え方を確認すること。
- **どこで判断するか**: 種別による分岐は `DocumentSurfaces` / `DocumentSurfaceStack` に
  閉じている（ADR 0009）。生成の遅延もそこへ閉じられるか。
- **`WebViewProxy` の nil 期間**: 面がまだ無い間に届く設定反映（`applyCodeFont` 等）は
  現在も no-op で耐える設計だが、遅延生成すると「まだ作っていない面へ配った値」を
  生成時に適用し直す必要が出る。取り残しの事故（TASK-401）を再発させないこと。
- **測り方**: 改善の確認は上と同じ NSLog 計測でよい。数値を Implementation Notes に残す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PDF だけを開いた窓で WKWebView が生成されない
- [x] #2 PDF → 他種別への切替で描画面が生成され、白フラッシュや倍率の取り残しが起きない
- [x] #3 初回表示までの時間を改善前後で実測し、数値が Implementation Notes に記録されている
- [x] #4 設定反映（フォント・CSV 数値表示・ジャンプ可否）が遅延生成した面にも取り残しなく入る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
/review-design の結論。

## A. 判断

A1. **生成の遅延であって、破棄ではない。** TASK-266 の「描画面は破棄・再生成しない」は
    白フラッシュと stale な初期倍率を避けるための決定で、**まだ作っていないものを
    作らない**こととは別。一度作った面は以後ずっと残す（PDF へ戻っても壊さない）。

A2. **「作ったかどうか」の記憶を新設しない。** `webViewProxy.webView != nil` が
    そのまま「もう作ってある」を表す（`makeNSView` で入り、View が生きている限り残る）。
    `@State` を足すと、SwiftUI の再評価 1 回分だけ生成が遅れる経路ができる。

A3. **初回の判断は「開こうとしている種別」（`ViewerStore.pendingFileType`）で行う。**
    内容が着地するまで `contentState.fileType` は既定（.mmd）のままなので、それで
    判断すると必ず WKWebView を作ってしまい、目的を果たさない。
    宛先の決定（`DocumentSurfaces.operating(on:)`）が pendingURL を**使わない**のとは
    逆の判断で、意図的に揃えていない——あちらは fail-silent（命令が無言で捨てられる）、
    こちらは fail-safe（判断を外しても、面が少し遅れて作られるだけ）。

## B. チェックリストで拾ったもの

B1. 項目 3（消費経路）: 面が無い間に届く設定反映は現在も no-op で耐える。**取り残しに
    ならないのは、生成時に現在値を渡しているから**（`ViewerWebView` は
    codeFont / csv / findOptions / headingJump / initialZoom を props から受ける）。
    ここが「生成時に渡す」形でなくなったら取り残しが復活するので、テストで固定する。

B2. 項目 4（新しい状態）: 「まだ面が無い」状態は画面上は PDF の面が覆っているので、
    ユーザーに見える新しい状態は増えない。

B3. 項目 5（順序）: `WebViewProxy.renderer` も生成時にしか入らないため、PDF だけの窓では
    `noteRename` が web 側へ届かない。届く相手が居ないので実害は無いが、**面が
    生成された後は従来どおり届く**ことを確認する。

B4. 項目 9（担保）: 「PDF だけの窓では作らない」は破れても静かに元へ戻る（速いか遅いかの
    差でしかない）。**破れたら落ちるテスト**を置く: PDF を出している状態の
    `DocumentSurfaceStack` に WKWebView が現れないこと、非 PDF へ切り替えると現れること。

## C. 実装順序

1. `DocumentSurfaceStack` に生成条件（`webViewProxy.webView != nil || !isOpeningPDF`）を入れる
2. `ViewerStore.pendingFileType` を読む経路をこの 1 箇所に閉じる
3. テスト（窓を作って WKWebView の有無を数える）
4. 起動から初回描画までを NSLog で改善前後に実測し、数値を Notes へ残す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-29）

`DocumentSurfaceStack` が `needsWebSurface`（`webViewProxy.webView != nil || !isOpeningPDF`）
で WKWebView を階層へ入れるかを決める。**生成の遅延であって破棄ではない**——一度作った面は
以後ずっと残るので、TASK-266（行を通過するたびに作り直さない）はそのまま守られる。
「作ってあるか」は proxy の参照がそのまま表すので、別の記憶を新設していない。

### 着地前の判断に何を見るか（実装中に判明）

当初は `ViewerStore.pendingFileType` を見る設計だったが、**それでは効かなかった**。
`ViewerWindowController.init` は分割ビューの構築（`makeSplitViewController`、
この View の最初の評価）を `openInitialDocument`（`pendingFileType` を設定する）より
**先**に行うため、判断の時点ではまだ既定値のままになる。実測でも PDF を開いた窓で
`makeNSView` が呼ばれていた。窓が開く対象の種別（`FileType(url: controller.fileURL)`）を
`openingFileType` として明示的に渡す形へ変更した。着地後は `contentState.fileType` が
唯一の情報源になるので、この値が古くなっても影響しない。

### 実測（Debug ビルド / NSLog / 同一マシン）

**単一ウィンドウを新しく開く**（アプリ起動済み、iCloud 上の 1.4MB / 1 ページ PDF）:

| | openViewer → PDF 表示可 |
| --- | --- |
| 改善前 | 147ms（うち WKWebView 生成が 19ms） |
| 改善後 | **124ms**（`makeNSView` は呼ばれない） |

**窓 4 つのセッション復元**（差が大きく出るのはこちら。メインスレッドの取り合いが減る）:

| | 最初の窓が表示可 | 4 窓すべて表示可 |
| --- | --- | --- |
| 改善前 | 543ms | 2388ms（後続の窓が 1.7〜2.4 秒まで待たされる） |
| 改善後 | **336ms** | **525ms** |

改善前は、復元した窓が 4 つとも viewer.html + バンドル（816KB）を読み込むため、
PDF の面がその後ろで待たされていた。ユーザー報告の「最初に開いた PDF は遅い」はこれ。

### 検証

- `swift test` 1787 件すべて成功。`DocumentSurfaceLazyWebViewTests` が
  「PDF を開く窓では WKWebView が 0 個」「他種別では 1 個」「PDF → 他種別 → PDF の
  往復で作られた面が壊れない」を階層を数えて固定する（AC #1 / #2）。
- 設定反映の取り残しが起きないのは、面の生成時に現在値（フォント・CSV 表示・検索
  オプション・見出しジャンプ・初期倍率）を props から渡しているため（AC #4）。
  この形が崩れると取り残しが復活するので、`ViewerWebView` の引数を減らすときは注意。
- swiftlint の main とのベースライン差分ゼロ、型グループの行数も上限内。
<!-- SECTION:NOTES:END -->
