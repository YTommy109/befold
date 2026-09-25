---
id: TASK-485.29
title: cmd+F のトグル化がゲート外で stable に効き、開いている検索欄へ戻る操作と PDF の検索語が失われる
status: To Do
assignee: []
created_date: '2026-09-25 09:10'
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
- [ ] #1 cmd+F のトグル化を stable に出すかどうかを決め、出さないならゲート閉では従来どおり「開く(開いていれば入力欄へフォーカスして全選択)」になる
- [ ] #2 検索バーが開いているがフォーカスが本文にあるとき cmd+F で何が起きるか(閉じるか、入力欄へ戻るか)を決め、web 面と PDF 面で同じ振る舞いになる
- [ ] #3 cmd+F で閉じてから開き直したときに検索語が残るかどうかが web 面と PDF 面で一致し、テストで固定されている
- [ ] #4 `PDFFindModel.close()` の doc が実際の呼び出し元と一致している
<!-- AC:END -->
