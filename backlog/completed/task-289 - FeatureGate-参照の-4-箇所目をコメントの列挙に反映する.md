---
id: TASK-289
title: FeatureGate 参照の 4 箇所目をコメントの列挙に反映する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 07:29'
updated_date: '2026-08-04 08:59'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 479000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review(high, 2026-08-04)。TASK-283 でコメントに『露出点は 3 箇所』と列挙した直後、TASK-284 で SidebarDisplayPreference.init の既定引数（isChangedFilesOnlyAvailable = FeatureGate.inProgressFeaturesEnabled）という 4 箇所目の参照を足しており、列挙が既にずれている。

放置した場合の影響: TASK-187 でコメントどおり 3 箇所の分岐を消すと、SidebarDisplayPreference 側の読み出しだけが残る。stable 昇格後も保存値 ON が OFF として読まれ続け、機能を有効化したのに絞り込みが復活しない。

同型の抜けが 2 回続いているため、コメントの追記ではなく『ゲート参照を足したら必ず列挙が更新される』仕組み（テストで参照箇所数を固定する等）も併せて検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 FeatureGate の列挙に SidebarDisplayPreference.init の参照が含まれる
- [x] #2 TASK-187 で消すべき箇所が列挙から漏れなく辿れる
- [x] #3 ゲート参照を足したときに列挙の更新漏れが検知できる手段が用意されるか、用意しない判断の理由が記録される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ゲート参照を FeatureGate 上の名前付きプロパティ isSidebarGitStatusEnabled に一本化し、4 箇所の呼び出し側をそれへ差し替える
2. FeatureGate の doc コメントの列挙を 4 箇所（SidebarDisplayPreference.init を含む）に更新する
3. 列挙の更新漏れを検知するテストを追加する: ソースを走査し、ゲートを参照する型の集合とコメントの列挙の集合が一致することを検証する（併せて inProgressFeaturesEnabled の直接参照が FeatureGate.swift 外に無いことも検証）
4. テストが修正前に落ちることを確認 → swift test / swiftformat / swiftlint 差分ゼロ
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ゲート参照を FeatureGate.isSidebarGitStatusEnabled に一本化し（呼び出し側 4 箇所すべて）、doc コメントの列挙に SidebarDisplayPreference.init を追加。検知手段として FeatureGateEnumerationTests を新設し、#filePath 起点で befold/ を走査して『ゲートを参照する型の集合』と『コメントの列挙』の一致、および inProgressFeaturesEnabled の直接参照が FeatureGate.swift 外に無いことを検証する。修正前は赤（referencing に SidebarDisplayPreference のみ差分）、列挙から 1 行消すと再度赤になることも確認済み。swift test 993 件パス、swiftformat lint 0 件、swiftlint は main ベースライン差分なし（FeatureGate 関連の新規警告なし）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FeatureGate の露出点コメントを 4 箇所（SidebarDisplayPreference.init を追加）に更新し、参照を名前付きプロパティ isSidebarGitStatusEnabled 経由に統一。列挙の更新漏れは FeatureGateEnumerationTests がソース走査で検知する（修正前に赤・修正後に緑、列挙を 1 行削ると再度赤を実測）。
<!-- SECTION:FINAL_SUMMARY:END -->
