---
id: TASK-504
title: AI 連携パネルの説明を CLI 前提と対応形式に合わせる
status: To Do
assignee: []
created_date: '2026-08-16 11:42'
updated_date: '2026-08-16 11:42'
labels:
  - chore
dependencies: []
priority: low
ordinal: 121500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Help > AI コーディングエージェント連携（BefoldApp/befold/App/AIIntegrationView.swift）の説明と、同梱の skill ファイル（BefoldApp/befold/Resources/befold-review-skill.md）に、実装とずれている点が 2 つある（TASK-502 の調査で判明）。

1. skill は 'command -v befold && befold <path>' で CLI が入っていなければ黙ってスキップする作り（befold-review-skill.md:21-22）だが、画面の説明（Localizable.xcstrings の aiIntegration.detail）にも UI にも「CLI が必要」という記載が無く、App メニューの「コマンドラインツールをインストール」（MainMenuBuilder.swift:52）への導線も無い。CLI 未導入のユーザーは、skill を保存しても何も起きない理由が分からない。
2. skill の対象が .md / .mmd に限定されている（befold-review-skill.md:5,11）が、実際の befold は SVG / HTML / CSV・TSV / 画像 / PDF / ソースコードにも対応している（BefoldApp/BefoldKit/FileType.swift）。エージェントに見せられる範囲を実力より狭く書いている。

なお skill 本体を英語のまま置くのは意図的な判断（AIIntegrationView.swift:4-7）なので、これは変えない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CLI が必要であることと、未導入時の導線（App メニューのコマンドラインツールをインストール）が画面から分かる
- [ ] #2 skill ファイルの対象形式が実際の対応形式と食い違わない記述になっている
- [ ] #3 skill 本体は英語のまま（画面の説明のみ日英そろえる）
- [ ] #4 追加・変更した文言が Localizable.xcstrings に日英そろって登録され、LocalizationTests が通る
<!-- AC:END -->
