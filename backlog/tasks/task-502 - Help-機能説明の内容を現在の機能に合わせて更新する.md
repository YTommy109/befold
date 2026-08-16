---
id: TASK-502
title: Help > 機能説明の内容を現在の機能に合わせて更新する
status: To Do
assignee: []
created_date: '2026-08-16 10:52'
updated_date: '2026-08-16 10:53'
labels:
  - chore
dependencies: []
priority: medium
ordinal: 111000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Help > 機能説明（BefoldApp/befold/App/FeatureOverviewView.swift:18-28）が挙げているのは livePreview / tabs / bookmarks / quickOpen / hiddenFiles / sourceToggle の 6 項目のみで、その後に入った機能が反映されていない。未掲載の例: git 差分表示、文書内検索、フォルダーサイドバー、QuickLook 拡張、befold CLI、対応フォーマット（Mermaid 以外の Markdown / SVG / HTML / CSV・TSV / 画像 / PDF / ソースコード）。

現在の機能一覧の情報源は docs/dev/native-app-design.md（単一の情報源）と CHANGELOG.md。FeatureGate で止めている機能は掲載しないこと（リリースノート生成と同じ基準）。

Help メニューの他のパネル（キーボードショートカット / AI 連携）も同時に内容が現状と合っているか確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 docs/dev/native-app-design.md と CHANGELOG.md を突き合わせ、機能説明に載せるべき項目の一覧が Implementation Notes に記録されている
- [ ] #2 FeatureOverviewView の項目が現在の機能に合わせて更新され、FeatureGate 配下の未公開機能は含まれていない
- [ ] #3 追加・変更した文言が Localizable.xcstrings に日英そろって登録されている（キー順にソートし直さない）
- [ ] #4 LocalizationTests が通り、翻訳漏れがないことを確認している
- [ ] #5 Help > キーボードショートカット / AI 連携パネルの内容も現状と一致するか確認し、ずれがあれば直すか別タスクとして起票している
- [ ] #6 実機で Help > 機能説明を開き、更新後の内容が表示されることを確認している
<!-- AC:END -->
