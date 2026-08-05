---
id: TASK-284
title: stable ビルドで ShowChangedFilesOnly を OFF に戻せない問題に対処する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 06:47'
updated_date: '2026-08-04 06:59'
labels: []
dependencies: []
priority: low
ordinal: 474000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-264 で追加した「変更されたファイルのみ表示」の設定は UserDefaults（キー ShowChangedFilesOnly）に永続化される。dev ビルドで ON にしたまま stable ビルドを起動すると、メニュー項目もヘッダーのアイコンボタンも FeatureGate で消えるため、ユーザーは ON を OFF に戻す手段を持たない。

現時点の実害（2026-08-04 にコードで確認）:
- FileListModel.isGitChangeFilterEffective が gitStatuses / gitFolderStatuses の空を見て縮退するため、stable では絞り込みが効かず一覧は全件表示される。一覧が空になる事故は起きない。
- 残る影響は「次に dev ビルドを起動したとき ON で始まる」ことのみ。

対処の候補（着手時に選定する。ゲート解除 TASK-187 が先に済めば本タスク自体が不要になる）:
- A: SidebarNavigator.syncDisplayPreferences で FeatureGate 無効時は false を同期する（設定値は残すが、無効ビルドでは一切効かないことを明示する）
- B: SidebarDisplayPreference 側で無効時は読み出しを false に倒す
- C: 対処せず、TASK-187 まで許容する（この場合は本タスクを Won't Do にして理由を残す）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 stable ビルドで ShowChangedFilesOnly が ON でも、モデル側の showChangedFilesOnly が ON にならない（または OFF に戻す手段がある）
- [x] #2 dev ビルドへ戻したときの挙動が意図どおりであることが説明できる（設定を保持するのか初期化するのか決めて記録する）
- [x] #3 選んだ方針の理由が Notes に残る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化の検討: 新しい状態や 4 箇所目のゲート分岐を足さず、設定を持つ SidebarDisplayPreference の読み出し 1 行で完結させる（案 B）。案 A（SidebarNavigator でゲート判定）は同期処理にゲートの知識を持ち込み、露出点が 4 箇所に増えるため採らない。案 C（放置）は縮退頼みで、FileListModel の縮退条件を将来変えたときに静かに壊れるため採らない。
2. init で isChangedFilesOnlyAvailable（既定は FeatureGate.inProgressFeaturesEnabled）と AND を取って読む。保存値は書き換えないため dev ビルドへ戻れば ON で復帰する。
3. 注入点はテストから両状態を作るためのもの。本番の呼び出しは既定引数のまま変えない。
4. TASK-187 ではこの AND とパラメータを消す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
採用: 案 B（SidebarDisplayPreference の読み出しでゲートする）。理由は上記のとおり、状態も分岐箇所も増やさずに『無効ビルドではモデルが ON にならない』を保証できるため。挙動の決定: 保存値は残す（dev で ON にした設定は dev へ戻れば ON で復帰する。不可視ファイル設定と同じく、ユーザーが自分で入れた設定を勝手に消さない）。

検証: swift test 1060 passed。AND を外す変異を入れて新規テストが落ちることを確認済み。xcodebuild build -scheme befold 成功、swiftformat 0 件、swiftlint は main とルール差分ゼロ。なお stable での見た目は変更前後とも『全件表示』で変わらない（従来は FileListModel 側の縮退で同じ結果になっていた）。今回の変更はその結果を縮退頼みにせず、設定の読み出しで保証する点が違う。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SidebarDisplayPreference の初期読み出しでフィーチャーゲートと AND を取り、機能が無効なビルドでは保存値が ON でも showChangedFilesOnly を OFF として読むようにした（保存値は書き換えないため dev ビルドへ戻れば ON で復帰する）。判定はテスト用の注入点付きで、swift test 1060 passed と『AND を外すと落ちる』変異確認で検証した。
<!-- SECTION:FINAL_SUMMARY:END -->
