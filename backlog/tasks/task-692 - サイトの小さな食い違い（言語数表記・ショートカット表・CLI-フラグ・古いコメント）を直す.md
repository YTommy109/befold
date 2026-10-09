---
id: TASK-692
title: サイトの小さな食い違い（言語数表記・ショートカット表・CLI フラグ・古いコメント）を直す
status: Done
assignee:
  - '@claude'
created_date: '2026-10-09 07:33'
updated_date: '2026-10-09 07:47'
labels: []
milestone: m-12
dependencies: []
priority: low
type: chore
ordinal: 881000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
調査（2026-10-09、コード読み）で見つかった、サイト記載と実装の軽微なずれ。(1) 「ソースコード（50以上の言語）」は、FileType.swift の辞書で拡張子が 50 個、highlight.js の言語名が 30 種類で、拡張子数と言語数が混ざっている。(2) ショートカット表（site/src/views/features.tsx の SHORTCUTS）に ⇧⌘P（印刷。⌘P を Quick Open に譲って移動）と ⌘← / ⌘→（サイドバーと本文の行き来、TASK-584）が無い。⌘, は標準操作なので除外方針かもしれない。(3) CLI の記載は --sidebar / --source / --line-numbers / --check / --bookmark のみで、--sort・--hidden-files・--preview・--no-sidebar・--no-line-numbers が無い（BefoldCLI/OpenCLIOptions.swift）。(4) features.tsx の FAQ の doc コメントは「JSON-LD には英語を載せる」と書くが、実際は faqStructuredData(lang) が言語別に出す。(5) MainMenuBuilder.swift の文書内ジャンプのコメントは stable でゲート閉と読めるが、#692 でゲートは外れている（コメントが古い可能性。未確認）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 「50以上の言語」が拡張子数・言語数のどちらを指すか決め、実測値と一致する表記にしている
- [x] #2 ショートカット表の漏れ（⇧⌘P・⌘←/→）を足すか、載せない理由を決めて Notes に残している
- [x] #3 CLI フラグの記載を、載せるものと載せないものに分けて決め、載せるものは実装と一致している
- [x] #4 古い 2 つのコメント（FAQ の JSON-LD・文書内ジャンプのゲート）が実装と一致している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 言語数表記: 拡張子数（CODE_EXTENSIONS.length）を使う表記へ。数を直書きしない
2. ショートカット表へ ⇧⌘P・⌘←/→ を追加し、test/shortcuts.test.ts で実装との一致を確認
3. CLI フラグは列挙しない方針を Notes に記録
4. FAQ の doc コメントと MainMenuBuilder の文書内ジャンプのコメントを実装に合わせる
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測（2026-10-09）: site/test の shortcuts と file-types は 2 ファイル 17 件、全体は 440 件が通過。typecheck・lint・format:check も通過。

決定1（言語数）: CODE_EXTENSIONS は拡張子 50 個。言語名（highlight.js）は約 30 で、file-types.ts の doc コメントどおり読者に意味を持たないので、「50 種類の拡張子」と書き、数は CODE_EXTENSIONS.length から出す（Swift 側と集合が一致することは file-types.test.ts が見ている）。
決定2（ショートカット）: ⇧⌘P（印刷 / PDF として保存）と ⌘← / ⌘→ を追加。⌘, は macOS 標準の操作として載せない。
決定3（CLI）: サイトの 2 箇所（shared.tsx の MORE_FEATURES、features.tsx の FAQ）は「--sidebar / --source / --line-numbers など」「Display flags like」と例示の形で、実在するフラグだけを挙げているので誤りではない。--sort・--hidden-files・--preview・--no-*系は列挙しない（befold --help が一次情報で、サイトに全列挙すると実装との二重管理になる）。
古いコメント: FAQ の doc は faqStructuredData と同じ「ページの言語」に直した。MainMenuBuilder.addDocumentJumpItems のゲート記述は、呼び出し側（MainMenuBuilder.swift の Edit メニュー構築）が無条件に呼ぶことを確認した上で、ゲート撤去済み（TASK-485.16）に直した。コメントのみの変更でビルドは未実行。

気づき: この worktree には site/node_modules が無く、npx vitest が止まった原因はその可能性が高い（npm ci 後は 1 秒で通った）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイトの食い違い 5 点のうちコメント 2 点と言語数表記とショートカット表を直し、CLI フラグは列挙しない方針を記録した。言語数は CODE_EXTENSIONS.length から出す形にして直書きを無くした。site の vitest 440 件・typecheck・lint・format:check で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
