---
id: TASK-314
title: ブランチ切り替え後の初回ビルドで appex の CFBundleVersion 不一致警告が出る
status: Done
assignee:
  - '@claude'
created_date: '2026-08-05 12:06'
updated_date: '2026-08-05 13:50'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 512000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
共有 DerivedData を使ってローカルビルドすると、MARKETING_VERSION / CURRENT_PROJECT_VERSION が変わった直後の初回ビルドで次の警告が出る。

    warning: The CFBundleVersion of an app extension ('1210') must match that of its containing parent app ('1116').

実測（2026-08-05, fix/issue-414 ブランチ）:

- project.yml は MARKETING_VERSION / CURRENT_PROJECT_VERSION を全ターゲット共通の 1 か所でしか持っておらず、設定側にドリフトは無い。'1210' はリポジトリ内のどこにも存在しない
- 警告時に埋め込まれていた appex は CFBundleShortVersionString = 1.11.7-dev.7 / CFBundleVersion = 1210 で、以前このワークツリーで別バージョンをビルドしたときの古い成果物だった（親アプリ側は 1.11.6 / 1116 に更新済み）
- 同じコマンドをもう一度流すと appex が 1.11.6 に再ビルドされ、警告は消える

つまり ValidateEmbeddedBinary が、同じビルド内でまだ更新されていない古い appex に対して走っている一過性の事象であり、設定の不備ではない。

問題は次の 2 点。

1. 警告が常態化すると、本当にバージョンがドリフトしたときに気づけない。project.yml のコメントにあるとおり、不一致は公証で弾かれる
2. 古い appex が埋め込まれたまま起動しうるため、QuickLook 拡張の挙動を確認したいときに前のバージョンを見ている可能性がある

対応方針は未確定。想定される選択肢は、(a) 何もしない（一過性であり実害が小さいと判断する）、(b) /run のビルド手順で appex ターゲットの再ビルドを強制する、(c) バージョン変更を検知したら DerivedData の該当成果物を落とす、など。着手時に (a) を含めて再判断すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 警告が出る条件（どのビルドで再現し、どのビルドで消えるか）が実測で確認され、記録されている
- [x] #2 対応する / しない の判断が根拠付きで記録されている
- [ ] #3 対応する場合、ブランチ切り替え直後の初回ビルドで警告が出ないことを実測で確認する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測（2026-08-05, fix/appex, 共有 DerivedData = BefoldApp/.build/xcode を再利用）。いずれも `xcodegen generate && xcodebuild build -scheme befold -configuration Debug -derivedDataPath .build/xcode`（/run の手順）。

1. バージョン上げ（成果物 1.11.6/1116 が残った状態 → project.yml 1.12.0/1219）: 警告なし。ProcessInfoPlistFile(BefoldQuickLook) が ValidateEmbeddedBinary より前に走り、親・appex とも 1219 になった
2. バージョン下げ（1.12.0/1219 → 1.11.6/1116、ブランチ切り替え相当）: 警告なし。親・appex とも 1116
3. 埋め込み済み appex の Info.plist を手で 1.11.7-dev.7 / 1210 に書き換えてから無変更ビルド（「他ブランチの古い成果物が残っている」状態を人工的に再現）: 警告なし。埋め込みステップが上書きし 1116 に復旧した

結論: /run の手順（xcodegen generate → xcodebuild -scheme befold）では再現しない。ターゲット依存で appex の Info.plist 処理が ValidateEmbeddedBinary より前に必ず走り、古い appex を人工的に置いても次のビルドで自己修復する。起票時の 1 回の観測は、その手順から外れたビルド（中断・別スキーム・別 derivedDataPath 等）に起因する一過性の事象と考えられ、常態化していない。

これにより起票時の懸念 2（古い appex が埋め込まれたまま起動しうる）は実験 3 で否定された。懸念 1（常態化して本当のドリフトに気づけない）は、常態化していない以上成立しない。

検証後、project.yml は 1.12.0/1219 に戻して再ビルド済み（appex も 1219）。

方針決定（ユーザー確認済み）: (a) 対応しない。実装変更は行わない。AC #3 は「対応する場合」の条件付きのため対象外（未チェックのまま残す）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
共有 DerivedData でのバージョン変更ビルドを 3 パターン実測し、/run の手順では CFBundleVersion 不一致警告が再現しないことを確認した（上げ・下げ・古い appex を人工的に埋め込んだ無変更ビルド）。appex の Info.plist 処理は ValidateEmbeddedBinary より前に必ず走り、古い appex を置いても次のビルドで自己修復する（実験 3）。起票時の懸念「古い appex のまま起動しうる」は否定され、警告も常態化していない。よって (a) 対応しない を選択し、コード・設定の変更は行わない。
<!-- SECTION:FINAL_SUMMARY:END -->
