---
id: TASK-334
title: applyRender が await 前に diffState を記録し描画がスキップされ得る問題を修正する
status: Done
assignee: []
created_date: '2026-08-06 01:48'
updated_date: '2026-08-06 03:45'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 509400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerRenderer+RenderHelpers.swift:109 の applyRender は await embeddedContent(...) の中断より前に rendered.diffState = diffState を記録する。中断中に SwiftUI が updateNSView を再入すると、updateContent は他の入力が同一なら incoming == rendered と判定して描画をスキップし、同時に contentUpdateGeneration を進めるため中断から復帰した applyRender も generation ガードで抜ける。結果として差分テキストは JS 側に入っているのに render() が走らず、他の状態変化があるまでプレーンなソースのままになる。レビューの評定は PLAUSIBLE（再現手順は理屈上のもので実測されていない）。着手時はまず再現可否を確認すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 再現可否を実測して Notes に記録する（再現しない場合はその根拠を残して見送り可）
- [x] #2 再現する場合、rendered の更新が実際の描画完了後に行われる（もしくは同等の方法で取りこぼしが起きない）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
再現: 再現した（実測）。ViewerRendererContentUpdateIntegrationTests に回帰テストを追加し、修正を戻すと 3/3 で落ちることを確認。

再現の作り方で 1 度失敗している。最初は Task.yield() 後に再入させ DOM に .diff-table が出るかで判定したが、未修正でも 3 回中 1 回通った（中断窓を外す）。中断の発生を画像埋め込みのゲート（SlowFileReader + セマフォ）で制御する形に作り直して決定的にした。ゲートを効かせられるのは画像埋め込みを通る markdown のレンダリング表示だけで、差分の DOM は source 表示でしか出ないため、判定は DOM ではなく『握り潰しの原因になるミラーの先行確定』に置いている。

原因と修正: applyRender は showLineNumbers / isSourceMode / diffState / truncation を await 前にミラーへ確定していた。await 中に同じ入力の updateContent が再入すると incoming == rendered と判定して描画をスキップしつつ世代を進めるため、戻ってきた applyRender も世代ガードで抜け、render() が一度も走らない。ミラーの確定を render 評価後の recordRendered へ移し、ミラーを丸ごと差し替える recordRendered(_:) を追加した（フィールド追加時の確定漏れを防ぐため）。applyAppend の truncation も同じ形だったので併せて移した。JS 送信自体は冪等なので確定前の再送は無害。

swift test 1160 件通過（--skip FileWatcherTests）。swiftlint はベースライン差分なし（RenderHelpers の opening_brace は HEAD 時点から同一構文で存在）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
applyRender/applyAppend が await 前に描画ミラーを先行確定していたため、再入した更新に描画を握り潰される問題を修正。確定を render 評価後へ移し、ゲート制御で決定的な回帰テストを追加（修正を戻すと 3/3 で落ちる）。swift test 1160 件通過。
<!-- SECTION:FINAL_SUMMARY:END -->
