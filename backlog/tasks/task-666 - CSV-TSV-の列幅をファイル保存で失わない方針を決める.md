---
id: TASK-666
title: CSV/TSV の列幅をファイル保存で失わない方針を決める
status: To Do
assignee: []
created_date: '2026-10-05 22:50'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/pull/708'
documentation:
  - docs/dev/file-type-display.md
priority: medium
ordinal: 851000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #708（rianjs、CSV/TSV の列幅ドラッグ・自動フィット）では、同じパスでも内容が変わると列幅を捨てる（`viewer-src/render.ts` の `prepareCsvResize` 呼び出し）。befold は FileWatcher で自動更新するため、手で調整した幅がエディタでの保存のたびに消える。仕様書 `docs/dev/file-type-display.md` には「内容の変更ではリセット」と明記されており意図した挙動ではあるが、利用者体験として妥当かは未判断。未確認: 判定時点で `_mmdDocument.content()` が前回の記録のままであること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 パス同一での内容変更時に列幅を保持するか捨てるかの方針が決まり、Notes に理由が残っている
- [ ] #2 保持に決めた場合、列数が変わったときの扱い（捨てる / 末尾列のみ初期幅）がテストで固定されている
- [ ] #3 方針に合わせて docs/dev/file-type-display.md の「寿命」の記述が更新されている
<!-- AC:END -->
