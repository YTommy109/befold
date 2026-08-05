---
id: TASK-314
title: ブランチ切り替え後の初回ビルドで appex の CFBundleVersion 不一致警告が出る
status: To Do
assignee: []
created_date: '2026-08-05 12:06'
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
- [ ] #1 警告が出る条件（どのビルドで再現し、どのビルドで消えるか）が実測で確認され、記録されている
- [ ] #2 対応する / しない の判断が根拠付きで記録されている
- [ ] #3 対応する場合、ブランチ切り替え直後の初回ビルドで警告が出ないことを実測で確認する
<!-- AC:END -->
