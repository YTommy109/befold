---
id: TASK-72.5
title: QLPreviewingController を実装する
status: To Do
assignee:
  - '@tokutomi'
created_date: '2026-07-19 06:44'
updated_date: '2026-07-26 06:06'
labels: []
dependencies: []
parent_task_id: TASK-72
ordinal: 215000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
View-based QLPreviewingController を実装し、preparePreviewOfFile(at:completionHandler:) 内で FileType.quickLookSupportedExtensions による対象外拡張子の早期reject、対象拡張子は RendererFeatures.quickLookRestricted を設定した ViewerRenderer.loadOneShot を呼び出し WKWebView をview階層に埋め込む。appex側にはロジックを持たせず配線のみとする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 QuickLook対象拡張子のファイルがFinderのQuickLookでレンダリング/ハイライト表示される
- [x] #2 対象外拡張子(PDF/画像等)がbefoldのQuickLook Extensionでは処理されない
- [x] #3 appex側コードがloadOneShot呼び出しと分岐のみで、レンダリングロジックを独自に持たない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerBridge.awaitRenderScript を追加(callAsyncJavaScript 用の await render(...) 本体)
2. loadOneShot を「描画完了まで待ってから返る」ようにする(TASK-72.1 の設計)
3. PreviewViewController を loadOneShot 呼び出しと分岐のみの薄いラッパーとして実装
4. swift test / xcodebuild / qlmanage による実機確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装
- ViewerBridge.awaitRenderScript: callAsyncJavaScript へ渡す `await render(...)`。
  render は async で mermaid 描画完了まで await 済みのため JS 側の改造は不要。
- loadOneShot: updateContent 経由の fire-and-forget をやめ、専用の renderOnce へ
  一本化した。viewer.html のロード完了ゲートは既存の pendingUpdate をそのまま使い、
  描画完了は callAsyncJavaScript の Promise 解決で受ける。
- ViewerRenderer.oneShotRenderTimeout(既定 3 秒)を追加。QuickLook をハングさせない
  ための打ち切りで、ホスト側から差し替えできる。
- PreviewViewController は 55 行。FileType.quickLookSupportedExtensions による
  早期 reject → loadOneShot → WebView か RejectReason メッセージの埋め込みのみで、
  レンダリングロジックを持たない。

## 設計上の修正(TASK-72.1 の設計からの変更)
当初は `await render(...)` の後に 2 段 requestAnimationFrame でペイント完了まで
待つ設計だったが、rAF はウィンドウに載っていない WebView では発火しないため、
描画完了を検知できず常にタイムアウトまで待たされることが実測で判明した
(テストで 3.4 秒 = 打ち切り時間ちょうど)。rAF を外したところ 0.46 秒で完了。
DOM 更新の完了までを描画完了とみなす方針に変更した。

## 検証
- swift test → 707 tests / 101 suites パス。
  新規テスト「loadOneShot は描画完了まで待ってから返る」で、戻り値の WebView から
  document.getElementById('diagram-wrap').innerHTML を読み、描画結果が
  入っていることを確認(予約して即 return では通らない)。
- xcodebuild build -scheme befold → BUILD SUCCEEDED。
- qlmanage -p による実機確認(appex プロセスの起動有無で判定):
    .mermaid → 起動する
    .swift   → 起動する
    .json    → 起動する
    .pdf     → 起動しない(設計どおり対象外)
    .markdown / .md → 起動しない
    .svg     → 起動しない
    .html    → 起動しない
    .csv     → 起動しない

## 未達と原因(AC#1)
md/svg/html/csv で befold の appex が選ばれないのは、同じ UTI を宣言する別の
QuickLook 拡張が既にこの実機に入っているため。QuickLook は 1 つの UTI につき
拡張を 1 つしか選ばず、優先度を指定する API はない。
- net.daringfireball.markdown / net.ia.markdown / com.unknown.md
    → org.sbarex.QLMarkdown.QLExtension (/Applications/QLMarkdown.app) が宣言
- public.html → com.apple.Safari.SafariQuickLookPreview
- public.svg-image → システム標準の画像プレビュー
これは befold 側のコードの不具合ではなく、環境側の競合。
AC#1 は mermaid/swift/json では満たせているが、md/svg/html/csv では
この実機では検証できない。またレンダリング結果の目視確認は未実施。

## 中断(2026-07-26)
実装・テスト・コミットは完了しているが、AC#1 は未達のまま中断する。
ユーザー判断により、UTI 競合の扱いを設計し直すまで先へ進めない。

再開の条件: 「同じ UTI を宣言する他の QuickLook 拡張との競合をどう扱うか」の
方針が決まること。決めるべき論点は下記の通り。
1. 競合する種別(md/svg/html/csv)を befold の QuickLook 対象から外すか、
   宣言は残したうえで「環境によっては選ばれない」と割り切るか
2. 割り切る場合、ユーザーへどう伝えるか(設定画面での競合検知・警告など)
3. .svg を public.svg-image で宣言し続けるか(TASK-72.4 で一度決めた判断の再検討。
   システム標準の画像プレビューに勝てないため実効性がない可能性がある)

方針が決まったら、TASK-72.4 の QLSupportedContentTypes と
親タスク TASK-72 の AC#1 を併せて見直すこと。
<!-- SECTION:NOTES:END -->
