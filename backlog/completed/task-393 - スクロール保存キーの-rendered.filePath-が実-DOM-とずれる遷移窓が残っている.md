---
id: TASK-393
title: スクロール保存キーの rendered.filePath が実 DOM とずれる遷移窓が残っている
status: Done
assignee: []
created_date: '2026-08-09 13:33'
updated_date: '2026-08-09 14:40'
labels: []
dependencies:
  - TASK-400
priority: medium
type: bug
ordinal: 648000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の指摘 2 件（CONFIRMED 1 件 + PLAUSIBLE 1 件）。どちらも TASK-400 修正（保存キーを通知の出所 = rendered.filePath から決める）の残余で、根因は共通:「rendered.filePath が実際に DOM に表示中の文書と一致しない遷移窓」がある。

1. **リネーム窓（CONFIRMED）**: リネーム時、`perFileState.migrate` は即座に新パスへ値を移すが、rendered.filePath はリネーム再描画が確定するまで旧パスのまま。その間のデバウンス済みスクロール通知（大きな文書では画像埋め込みで数秒かかりうる）が **もう存在しない旧パスのキーへ** 保存され、新パス側には移行時点の古い位置が残る。再オープン時にリネーム前の位置へ戻る（保存位置のサイレント消失）。参照: ViewerWindowController.swift:585 付近

2. **mirror 先行更新窓（PLAUSIBLE）**: applyRender は evaluateJavaScript をキューに積んだ直後（JS 実行前）に recordRendered で rendered.filePath を切替先へ進める。DOM がまだ旧文書のうちにデバウンスが発火すると、旧文書の位置が **切替先のキーへ** 保存される（TASK-400 の症状が狭い窓で残る）。参照: ViewerRenderer+MessageHandling.swift:84、ViewerRenderer+RenderHelpers.swift:140-147

個別のガードを 2 箇所に足すのではなく、「保存キーが常に実 DOM の文書と一致する」構造（mirror の filePath 更新を render 完了時へ寄せる、または JS 側に文書識別子を持たせてラウンドトリップする等）を検討すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 リネーム直後（再描画確定前）のスクロールが新パスのキーへ保存される
- [x] #2 applyRender 直後のデバウンス発火が旧文書の位置を切替先のキーへ書かない
- [x] #3 両方の窓を覆う回帰テストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
構造方針: 保存キーを「配達時に native 側で推定」から「発火時に JS 側で申告」へ移す(Description の構造案のうち後者)。
1. viewer-main.js の _createScrollSync に docPath を追加し、scrollPositionChanged payload へ path を載せる(scrollTop を読むのと同じ時点の値なので、キューやメッセージ配達の遅延と無関係に実 DOM と一致する)
2. Swift(applyRender)は render script の直前に _mmdSetRenderDocPath(path) を常時注入し、JS は beginRender で採用する(保留 debounce の破棄と同じ時点でキーが切り替わる)
3. リネームは _mmdRenameDocPath(from,to) を即時評価して差し替える(DOM は同一文書のまま名前だけ変わるため。TASK-401 のミラー差し替えと同じ同期区間)
4. handleScrollPositionChanged は rendered.filePath ではなく payload の path をキーに使う(rendered ミラーの役割は再描画キャッシュへ戻る)
5. テスト: native = payload の path を使う/欠落時は nil、JS = 採用は render 時のみ・rename は即時 flip・現 path 不一致の rename は無視
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
/review-design 実施。結論: (1) JS の rename 差し替えは current/pending が from に一致するときだけ行う(不一致=切替中に誤って付け替えるより旧キーへの短時間保存が安全)。(2) パス文字列の生成点は ViewerBridge の script 組み立てに一本化し normalizedPathKey で正規化する。(3) render 予告(_mmdSetRenderDocPath)は毎 render 常時注入(viewer.html 再ロードで JS 状態が飛んでも次の render で自己修復)。予告なしの内部再描画と区別するため JS 側は undefined 番兵で「予告なし」を表す。(4) 経路: ViewerWindowController.handleRename → WebViewCommandController.noteRename → DocumentRendering(adapter) → WebViewProxy.renderer(weak) → ViewerRenderer.handleRename。(5) 同型の兄弟 = zoom 通知(TASK-391)にも本構造(payload での出所申告)を再利用する。

実装: scrollPositionChanged の保存キーを「配達時に native が rendered.filePath から推定」から「発火時に JS が payload の path で申告」へ移した。viewer-main.js の _createScrollSync が docPath を保持し、Swift は render 直前に _mmdSetRenderDocPath を常時注入(JS は beginRender で採用 = 保留デバウンス破棄と同時)、リネームは _mmdRenameDocPath で即時差し替え(current/pending が from に一致するときのみ)。パス文字列は ViewerBridge の生成点で normalizedPathKey に正規化。検証: AC1 = jest「_mmdRenameDocPath は render を経ずに現在のパスを差し替える」+ Swift scrollPositionChangedCarriesPayloadPath + 既存 ViewerWindowScrollPositionNotificationTests の連鎖。AC2 = jest「予告は render まで採用されない」(採用前の通知は旧文書パスのまま)。AC3 = 上記 + 不一致 rename 無視・予告差し替え・null パス破棄の計 7 jest + Swift 側 3 テスト。swift test 1233 件・jest 388 件パス、swiftlint main ベースライン新規違反ゼロ(ViewerBridge の PayloadKey 宣言は file_length 対応で ViewerBridge+PayloadKeys.swift へ分離)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
スクロール保存キーを JS が位置と同じターンで payload に載せる構造へ移し、rendered.filePath と実 DOM のずれ(リネーム窓・ミラー先行更新窓)を構造ごと解消した。キューや postMessage 配達の遅延と無関係にキーが実 DOM と一致する。jest 7 件 + Swift 3 件の回帰テストで担保。
<!-- SECTION:FINAL_SUMMARY:END -->
