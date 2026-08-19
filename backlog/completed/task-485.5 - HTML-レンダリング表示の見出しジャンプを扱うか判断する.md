---
id: TASK-485.5
title: HTML レンダリング表示の見出しジャンプを扱うか判断する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-14 13:18'
updated_date: '2026-08-18 11:40'
labels: []
milestone: m-6
dependencies:
  - TASK-485.2
parent_task_id: TASK-485
priority: low
type: task
ordinal: 750000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

HTML の描画は `viewer-src/renderers.js:78 _renderHtml()` が
`&lt;iframe sandbox="allow-same-origin" srcdoc=…&gt;` へ流し込む形で、親文書からは
DOM が隔離されている。既存の検索窓も `#diagram-wrap` 配下しか走査しないため
（`find.js:101 collectScopes`）、**HTML では検索自体が効いていない**
（`ViewerCapabilities` の `canFind` が直接 HTML モードを除外している、
`befold/Viewer/ViewerCapabilities.swift:59`）。

同一オリジンなので `iframe.contentDocument` へは理屈上アクセスでき、
実際に `renderers.js:90` で触っている前例がある。

## このタスクで決めること

1. HTML レンダリングでも見出しジャンプを提供するか、ソース表示に限定するか
2. 提供するなら、iframe 越しに目印を列挙・ハイライト・スクロールする経路を
   新設することの妥当性（sandbox 属性・セキュリティ上の含意を含む）
3. ついでに検索窓も HTML で使えるようにするか（同じ経路を共有できる可能性がある）

判断だけを行うタスクで、実装する結論になった場合は別タスクを起票する。
見送る結論の場合も、理由を残して閉じる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 HTML レンダリングで見出しジャンプを提供するか否かの結論が理由付きで記録されている
- [ ] #2 提供する結論なら実装タスクが起票されている
- [x] #3 iframe 越しにアクセスする場合のセキュリティ上の含意が検討されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. HTML レンダリング表示が実際に通る描画経路をコードで確定させる（起票時の前提「iframe srcdoc」が現在の実装と合っているかを裏取りする）
2. iframe srcdoc 経路が到達する実行環境を洗い出し、そこにジャンプ UI が存在するかを確認する
3. 上記の結果から「提供する / ソース表示に限定する」を判断し、理由と裏付け（file:line）を Notes に残す
4. 提供しない結論なら実装タスクは起票せず、iframe 越しアクセスのセキュリティ含意だけ検討結果として記録して閉じる
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 結論: 提供しない（ソース表示に限定する）

理由は「iframe 越しに触るのが危ういから」ではなく、**ビューア窓の HTML レンダリング表示は
そもそも iframe 経路を通らない**ため。起票時（2026-08-14）の Description が置いていた
「HTML の描画は renderers の iframe srcdoc」という前提が、ビューア窓については成り立たない。

### 裏付け（コード参照）

1. ビューア窓の HTML レンダリング表示は必ず**直接ロード経路**に入る。
   - 分岐: `BefoldApp/BefoldRenderKit/ContentUpdatePlanner.swift:74-78` が
     `DirectHTMLModeController.shouldEnter` 真なら `.directHTMLLoad` を返す
   - 条件: `DirectHTMLModeController.swift:41-45`
     `fileType == .html && !isSourceMode && filePath != nil && features.allowDirectHTML`
   - 本体アプリは `features = .allEnabled`（`befold/Viewer/ViewerContentView.swift:96`、
     `BefoldKit/RendererFeatures.swift:39` で `allowDirectHTML: true`）。ビューア窓は
     開いたファイルの URL を持つので `filePath` は非 nil
   - この経路は viewer.html 自体をロードしない（`loadFileURL` で文書を直接表示し、
     `DirectHTMLModeController.swift:76` で `allowsContentJavaScript = false`）。
     つまり iframe を覗く以前に、**ジャンプバーの DOM も jump.ts も存在しない**
   - 既存の `canFind` / `canJump` が `!isDirectHTMLMode` を条件に持つのはこの理由
     （`befold/Viewer/ViewerCapabilities.swift:15-20, 76, 80`）

2. iframe srcdoc 経路（`BefoldApp/viewer-src/renderers.ts:111-134`）が実際に動くのは
   `.quickLookRestricted` を渡す 2 箇所だけ。
   - QuickLook 拡張: `BefoldQuickLook/PreviewViewController.swift:11`
   - 謝辞などのヘルプパネル: `befold/App/RenderedMarkdownView.swift:37`
   どちらも `OneShotRenderer` による 1 回描画の静的プレビューで、メニュー・検索バー・
   ジャンプバーを持たない（`RenderedMarkdownView.swift:8-10` に「検索といったビューア本体の
   機能は持たない」と明記）。`ViewerCapabilities` も QuickLook 側では参照されていない。
   **列挙経路を新設しても、それを開く UI がある実行環境が存在しない。**

3. `shape === "html"` になるのは `type === "html" && mode === "rendered"` のときだけ
   （`viewer-src/render.ts:48-62` `renderShape`、ソース表示では `"code"` に落ちる）。
   Markdown 内の HTML は markdown-it が親 DOM へ展開するので iframe にはならない。

### 実測

`(cd BefoldApp && swift test --filter "ViewerWebViewCoordinatorTests|ViewerCapabilitiesTests")`
→ 2 suite / 22 test すべて成功。うち
「直接HTMLモードへの遷移可否はallowDirectHTMLフラグとファイル種別/表示モードで決まる」（5 ケース）、
「HTML 直接ロード中は検索だけを止め、他は止めない」、
「文書内ジャンプは検索と同じく HTML 直接ロード中と非提示中は不可」が上記 1 を固定している。

### 提供する場合に必要になること（採らない理由）

提供するには直接ロードをやめて viewer.html 経由（iframe）へ寄せるしかないが、それは
「外部 HTML は文書が canvas ごと所有する」「相対リソースを解決して素の HTML として見せる」
という直接ロードの存在理由（`docs/dev/native-app-design.md:217-223`）を捨てることになる。
見出しジャンプ 1 機能と釣り合わない。

### セキュリティ上の含意（AC #3）

仮に iframe 越しに列挙する場合を検討した結果、実装しない判断とは独立に次が問題になる。

- `renderers.ts:116` の sandbox は `allow-same-origin` 単独指定。`allow-scripts` が無いので
  子文書のスクリプトは走らないが、`allow-same-origin` がある以上、親からは
  `contentDocument` を読める（実際 `:125` が高さ計測で読んでいる）。**読むだけなら追加の
  権限緩和は不要**で、ここは危険の所在ではない
- 危険が増えるのは**書き込み側**。ジャンプはハイライト（`jump.ts:68-74` の
  `mmd-jump-target` 付与）を伴うため、親のコードが任意のユーザー HTML 由来 DOM を
  書き換えることになる。親の CSS クラスが子文書へ効くわけではない
  （`viewer.html` の style.css は子には適用されない）ので、ハイライト用スタイルの注入も
  必要になり、子文書へ親由来の style/class を差し込む経路が新設される
- タイミングの穴もある。`_renderHtml` は `load` を待たずに返る（`render.ts:144` は同期呼び出し）。
  現状 `contentDocument` を触る唯一の前例は `load` リスナーの中（`renderers.ts:121-130`）で
  この問題を避けている。列挙を足すなら「iframe の load 完了を外へ通知する口」を新設する
  必要があり、`_mmdJump.refresh` の呼び出しタイミング（`render.ts:96`）との同期が新しい
  不変条件になる

いずれも越えられない壁ではないが、上記 2 のとおり**使う場所が無い**ため踏み込まない。

### 付随して確認したこと（本タスクでは扱わない）

`canJump`（見出しジャンプ）は表示モードを見ていないため、HTML の**ソース表示**中は
メニューが有効のまま 0/0 になる。これは `ViewerCapabilities.swift:20-24` の
「目印 0 個かでは判定せず、0/0 表示で伝える」という既存の設計方針どおりで、穴ではない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
判断のみのタスク。結論は「HTML レンダリング表示では見出しジャンプを提供しない（ソース表示に限定する）」。

理由は起票時の前提が実装とずれていたこと。ビューア窓の HTML レンダリング表示は
ContentUpdatePlanner.swift:74-78 → DirectHTMLModeController.shouldEnter（:41-45）で必ず
直接ロード経路に入り、viewer.html 自体がロードされないため、iframe を覗く以前にジャンプの
DOM も JS も存在しない。iframe srcdoc 経路（renderers.ts:111-134）が動くのは
.quickLookRestricted を渡す QuickLook 拡張とヘルプパネルの 2 箇所だけで、どちらも 1 回描画の
静的プレビューでありジャンプ UI を持たない。よって列挙経路を新設しても使う場所が無い。

検証: (cd BefoldApp && swift test --filter "ViewerWebViewCoordinatorTests|ViewerCapabilitiesTests")
で 22 test 成功。うち 3 テストが上記の前提（直接ロードへの遷移条件、直接ロード中は
canFind / canJump が落ちること）を固定している。

AC #2 は「提供する結論なら実装タスクを起票」なので、見送り結論により該当しない（未チェック）。
AC #3 のセキュリティ含意は Notes に検討結果を記録（読み取りは追加権限不要、危険はハイライト
書き込み側と load 完了待ちの新設不変条件にある）。コード変更なしのため
native-app-design.md の更新も不要。
<!-- SECTION:FINAL_SUMMARY:END -->
