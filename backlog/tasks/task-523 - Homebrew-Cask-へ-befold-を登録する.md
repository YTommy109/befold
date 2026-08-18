---
id: TASK-523
title: Homebrew Cask へ befold を登録する
status: To Do
assignee: []
created_date: '2026-08-18 14:58'
labels: []
dependencies: []
priority: low
ordinal: 763000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
brew install --cask befold は開発者にとって最も摩擦の少ない入口であり、かつ cask 一覧自体が発見経路になる。

現状: homebrew-cask の公開要件（知名度・実績の基準）を満たしていないため着手できない。要件を満たすまで保留する。

着手可能になる条件: homebrew-cask のリポジトリが定める受け入れ基準（スター数・fork 数・その他の notability 指標）を befold が満たすこと。判断は起票時点のユーザーによるもので、具体的な閾値は未記録。着手を検討する際は、まず現行の要件を homebrew-cask のドキュメントで確認し直し、現在の befold リポジトリの数値と突き合わせる。

代替案: 要件を満たさない間は独自 tap（自前の homebrew-tap リポジトリ）という選択肢もある。本体 cask より発見性は劣るが導入の摩擦は同じだけ下がるため、着手時にどちらを取るか判断する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 homebrew-cask の現行の受け入れ要件と befold の現状を突き合わせた結果が Notes に記録されている
- [ ] #2 本体 cask と独自 tap のどちらを取るか判断され、理由が記録されている
- [ ] #3 選んだ方式で brew 経由のインストールが実際に成功する
- [ ] #4 配布サイトにインストール手順が追記されている
<!-- AC:END -->
