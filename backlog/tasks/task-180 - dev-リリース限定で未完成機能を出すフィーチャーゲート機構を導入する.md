---
id: TASK-180
title: dev リリース限定で未完成機能を出すフィーチャーゲート機構を導入する
status: To Do
assignee: []
created_date: '2026-07-28 12:22'
updated_date: '2026-07-28 12:22'
labels: []
dependencies: []
priority: medium
ordinal: 255000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
トランクベース開発で、頻繁マージ + dev リリースで機能を試しつつ、納得したら patch/minor リリースを行う運用をしている。この運用で「未完成機能は stable リリースには載せたくないが、バグ修正は随時リリースしたい」を両立させるため、ビルド由来の signal（バージョン文字列のプレリリース接尾辞）で機能をゲートする仕組みを導入する。

release.yml がタグ名から MARKETING_VERSION を注入するため、dev タグ v X.Y.Z-dev.N でビルドしたアプリは CFBundleShortVersionString に -dev.N を持ち、AppVersion.current から実行時に判別できる。これを使って「dev/DEBUG ビルドでのみ有効な機能フラグ」を 1 箇所（FeatureGate）に集約する。UpdateChannel はユーザー設定であり dev ビルド判定には使わない。

フラグは一時的な足場とし、stable 昇格時に撤去する運用（撤去タスク登録）も README/開発ドキュメントに明記する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 AppVersion にプレリリース判定 isPrerelease（バージョン文字列に - を含むか）が追加され、純粋関数として単体テストがある
- [ ] #2 dev/DEBUG ビルドでのみ true になる FeatureGate.inProgressFeaturesEnabled が用意され、stable ビルド（接尾辞なしバージョン）では false になる
- [ ] #3 FeatureGate は機能フラグを集約する単一の窓口であり、呼び出し側は if FeatureGate.xxx で分岐する形になっている
- [ ] #4 フラグの目的と「stable 昇格時に撤去する」運用が開発者向けドキュメント（CLAUDE.md か docs/dev）に記載されている
- [ ] #5 UpdateChannel（ユーザー設定）を機能ゲートの判定に流用していない
<!-- AC:END -->
