---
id: TASK-393
title: スクロール保存キーの rendered.filePath が実 DOM とずれる遷移窓が残っている
status: To Do
assignee: []
created_date: '2026-08-09 13:33'
labels: []
dependencies:
  - TASK-389
priority: medium
type: bug
ordinal: 648000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の指摘 2 件（CONFIRMED 1 件 + PLAUSIBLE 1 件）。どちらも TASK-389 修正（保存キーを通知の出所 = rendered.filePath から決める）の残余で、根因は共通:「rendered.filePath が実際に DOM に表示中の文書と一致しない遷移窓」がある。

1. **リネーム窓（CONFIRMED）**: リネーム時、`perFileState.migrate` は即座に新パスへ値を移すが、rendered.filePath はリネーム再描画が確定するまで旧パスのまま。その間のデバウンス済みスクロール通知（大きな文書では画像埋め込みで数秒かかりうる）が **もう存在しない旧パスのキーへ** 保存され、新パス側には移行時点の古い位置が残る。再オープン時にリネーム前の位置へ戻る（保存位置のサイレント消失）。参照: ViewerWindowController.swift:585 付近

2. **mirror 先行更新窓（PLAUSIBLE）**: applyRender は evaluateJavaScript をキューに積んだ直後（JS 実行前）に recordRendered で rendered.filePath を切替先へ進める。DOM がまだ旧文書のうちにデバウンスが発火すると、旧文書の位置が **切替先のキーへ** 保存される（TASK-389 の症状が狭い窓で残る）。参照: ViewerRenderer+MessageHandling.swift:84、ViewerRenderer+RenderHelpers.swift:140-147

個別のガードを 2 箇所に足すのではなく、「保存キーが常に実 DOM の文書と一致する」構造（mirror の filePath 更新を render 完了時へ寄せる、または JS 側に文書識別子を持たせてラウンドトリップする等）を検討すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 リネーム直後（再描画確定前）のスクロールが新パスのキーへ保存される
- [ ] #2 applyRender 直後のデバウンス発火が旧文書の位置を切替先のキーへ書かない
- [ ] #3 両方の窓を覆う回帰テストがある
<!-- AC:END -->
