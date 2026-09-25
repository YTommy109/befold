---
id: TASK-485.29
title: cmd+F のトグル化がゲート外で stable に効き、開いている検索欄へ戻る操作と PDF の検索語が失われる
status: Done
assignee:
  - '@claude'
created_date: '2026-09-25 09:10'
updated_date: '2026-09-25 09:27'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/DocumentCommandController.swift
  - BefoldApp/befold/App/PDFDocumentRenderer.swift
  - BefoldApp/befold/App/PDFFindModel.swift
  - BefoldApp/viewer-src/find.ts
parent_task_id: TASK-485
priority: medium
type: bug
ordinal: 830000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-485.28 のコードレビュー(2026-09-25)で検出。cmd+F の入口 `DocumentCommandController.toggleFind()` はフィーチャーゲート(`FeatureGate.isDocumentJumpEnabled`)を見ないため、文書内ジャンプを出していない stable ビルドでも cmd+F の意味が「開く」から「トグル」に変わる。
以前は検索バーが開いている状態で cmd+F を押すと `find.ts` の `open()` が入力欄へフォーカスして語を全選択していた(Safari 等と同じ慣習)。今は同じ操作でバーが閉じ、ハイライトも消える。例: 検索後に本文をクリックして読み、語を変えようと cmd+F を押すとバーが閉じてしまい、もう一度押す必要がある。
PDF 面では `PDFDocumentRenderer.toggleFind()` が `PDFFindModel.close()` を呼び、`close()` は `query = ""` で検索語を捨てる。web 面は閉じても語を保つので、cmd+F を 2 回押したときの結果が面によって食い違う。`PDFFindModel.close()` の doc の「呼び出し元は検索バーの × と Esc だけ」も実態と合わなくなった。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 cmd+F のトグル化を stable に出すかどうかを決め、出さないならゲート閉では従来どおり「開く(開いていれば入力欄へフォーカスして全選択)」になる
- [x] #2 検索バーが開いているがフォーカスが本文にあるとき cmd+F で何が起きるか(閉じるか、入力欄へ戻るか)を決め、web 面と PDF 面で同じ振る舞いになる
- [x] #3 cmd+F で閉じてから開き直したときに検索語が残るかどうかが web 面と PDF 面で一致し、テストで固定されている
- [x] #4 `PDFFindModel.close()` の doc が実際の呼び出し元と一致している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. cmd+F の閉じる条件を「検索欄が開いていて、かつ入力欄にフォーカスがある」に絞る(web: bar-mode.ts + find.ts の isFindInputFocused / PDF: 窓の first responder が PDFFindOverlay.inputIdentifier の欄か)
2. PDF の close() で検索語を捨てず、open() で残った語で探し直す(web と揃える)
3. 本文にフォーカスがある状態の cmd+F は入力欄へ戻して全選択(PDF は focusRequest の変化で FocusClaimingTextField が取り直す)
4. テストと viewer-ui.md を更新
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針決定(AC#1/#2): ゲートで cmd+F の振る舞いを 2 本持つ案は採らず、閉じるのを入力欄に居るときだけに絞った。stable の従来動作(本文から cmd+F で入力欄へ戻り全選択)はそのまま残り、トグルも入力欄に居るときは効く。stable で変わるのは「入力欄に居るときの cmd+F」が全選択し直しから閉じるになる点だけ。ジャンプバーは入力欄を持たないので単純なトグルのまま。
新しい状態は持たない: web は document.hasFocus() && activeElement(サイドバーへ移っても activeElement は残るため hasFocus も見る)、PDF は窓の first responder(フィールドエディタの delegate の identifier)をその都度訊く。
検証: npx jest viewer-test 665 件通過(新規: 本文フォーカス時に入力欄へ戻り全選択 / 閉じて開き直しても語が残る)、swift test 1992 件 + 72 件通過(新規: PDFSurfaceTextFieldTests の cmd+F 2 件、PDFFindModelTests の閉じても語が残り開き直すと再検索)、swiftlint は main との差分ゼロ。アプリ上での cmd+F の操作確認はしていない(System Events から窓を取得できなかった)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
cmd+F は、検索欄の入力欄にフォーカスがあるときだけ閉じ、本文を読んでいるときは入力欄へ戻して語を全選択するようにした(web と PDF で同じ規則)。stable の従来の慣習を保つためゲートは使わない。PDF でも閉じたときに検索語を残し、開き直すとその語で探し直す(web と一致)。PDFFindModel.close() の doc の呼び出し元を実態に合わせ、viewer-ui.md を更新した。jest / swift test / swiftlint ベースラインで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
