---
id: TASK-692
title: サイトの小さな食い違い（言語数表記・ショートカット表・CLI フラグ・古いコメント）を直す
status: To Do
assignee: []
created_date: '2026-10-09 07:33'
updated_date: '2026-10-09 07:38'
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
- [ ] #1 「50以上の言語」が拡張子数・言語数のどちらを指すか決め、実測値と一致する表記にしている
- [ ] #2 ショートカット表の漏れ（⇧⌘P・⌘←/→）を足すか、載せない理由を決めて Notes に残している
- [ ] #3 CLI フラグの記載を、載せるものと載せないものに分けて決め、載せるものは実装と一致している
- [ ] #4 古い 2 つのコメント（FAQ の JSON-LD・文書内ジャンプのゲート）が実装と一致している
<!-- AC:END -->
