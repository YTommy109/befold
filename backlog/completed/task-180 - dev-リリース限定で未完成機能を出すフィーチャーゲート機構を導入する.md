---
id: TASK-180
title: dev リリース限定で未完成機能を出すフィーチャーゲート機構を導入する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-28 12:22'
updated_date: '2026-07-28 15:49'
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
- [x] #1 AppVersion にプレリリース判定 isPrerelease（バージョン文字列に - を含むか）が追加され、純粋関数として単体テストがある
- [x] #2 dev/DEBUG ビルドでのみ true になる FeatureGate.inProgressFeaturesEnabled が用意され、stable ビルド（接尾辞なしバージョン）では false になる
- [x] #3 FeatureGate は機能フラグを集約する単一の窓口であり、呼び出し側は if FeatureGate.xxx で分岐する形になっている
- [x] #4 フラグの目的と「stable 昇格時に撤去する」運用が開発者向けドキュメント（CLAUDE.md か docs/dev）に記載されている
- [x] #5 UpdateChannel（ユーザー設定）を機能ゲートの判定に流用していない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了。AppVersion.isPrerelease(純関数, 3 単体テスト), FeatureGate.inProgressFeaturesEnabled(version:isDebugBuild:)(dev/DEBUG のみ true, 3 テスト), 運用/撤去ルールを .claude/CLAUDE.md に追記。UpdateChannel は不使用。swift test 838/838 PASS, opus 最終レビュー clean。commits 8a8e713..f9bc6b8
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AppVersion.isPrerelease とバージョン接尾辞由来の FeatureGate を追加し、開発中機能を dev/DEBUG 限定で露出する窓口を一元化。UpdateChannel は非流用。運用・撤去ルールを .claude/CLAUDE.md に明記。単体テスト(AppVersionTests/FeatureGateTests)と opus 最終レビューで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
