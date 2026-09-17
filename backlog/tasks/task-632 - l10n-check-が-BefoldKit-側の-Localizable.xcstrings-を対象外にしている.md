---
id: TASK-632
title: /l10n-check が BefoldKit 側の Localizable.xcstrings を対象外にしている
status: Done
assignee:
  - '@claude'
created_date: '2026-09-17 04:42'
updated_date: '2026-09-17 04:50'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/pull/678'
documentation:
  - .claude/skills/l10n-check.md
priority: low
type: chore
ordinal: 829000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
カタログは 2 つある。`BefoldApp/befold/Resources/Localizable.xcstrings`（244 キー、アプリ本体のメニュー等）と `BefoldApp/BefoldKit/Resources/Localizable.xcstrings`（22 キー、ビューアーへ注入する文言）。`.claude/skills/l10n-check.md` の手順は前者だけを見ており、後者を一度も検査していない。

PR #678 が BefoldKit 側へ 7 キー（viewer.diagram.zoomIn / zoomOut / zoomReset、viewer.mode.search / heading / changeBlock / functionDefinition）を追加したが、/l10n-check の対象外だったため翻訳漏れの検査が働かなかった。今回は手動確認で en / ja とも state: translated、プレースホルダ無しで問題なしだったが、検査が空振りしている状態自体は残る。

ビューアーの文言は WKWebView へ注入されて画面に出るものなので、アプリ本体のメニュー文言と同じだけ翻訳漏れの実害がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 /l10n-check が BefoldApp/BefoldKit/Resources/Localizable.xcstrings も検査対象にしている
- [x] #2 検出結果にどちらのカタログのキーかが示される
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
/l10n-check の対象に BefoldApp/BefoldKit/Resources/Localizable.xcstrings を加え、出力の各行に [befold | BefoldKit] でカタログを示すようにした。手順どおりの検査を両カタログへ実行し、befold 244 キー / BefoldKit 22 キーとも翻訳漏れ・未対応状態なしを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
