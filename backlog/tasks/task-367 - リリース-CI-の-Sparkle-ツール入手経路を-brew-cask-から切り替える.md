---
id: TASK-367
title: リリース CI の Sparkle ツール入手経路を brew cask から切り替える
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-08 08:59'
updated_date: '2026-08-08 09:20'
labels: []
dependencies: []
priority: high
ordinal: 628000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
release.yml が `brew install sparkle` で generate_appcast を入手しているが、Homebrew の sparkle カスクは Gatekeeper 検証に通らないことを理由に deprecated となり、**2026-09-01 に disable される**。その時点でリリースワークフローの appcast 生成ステップが失敗し、リリースが打てなくなる。

さらに、現時点で既に実害が出ている。手元で brew install --cask sparkle を実行したところ、インストールは成功するものの bin/ には BinaryDelta と sign_update しか残らず、**generate_appcast と generate_keys が削除されている**。CI の macos-26 ランナーで同じことが起きていれば、次のリリースは 2026-09-01 を待たずに失敗する。

実測:
- brew info --cask sparkle → 'Deprecated because it does not pass the macOS Gatekeeper check! It will be disabled on 2026-09-01.'
- brew install --cask sparkle 後の /opt/homebrew/Caskroom/sparkle/2.9.5/bin/ = BinaryDelta, old_dsa_scripts, sign_update のみ（generate_appcast なし）
- 該当箇所: .github/workflows/release.yml:215-219

代替の入手経路として、Sparkle の GitHub Releases から Sparkle-X.Y.Z.tar.xz を直接取得して展開する方法がある（CI では Gatekeeper を経由しないため影響を受けない）。バージョンを固定できるので、カスク更新でツールが入れ替わる事故も同時に無くなる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 release.yml が brew cask に依存せず generate_appcast を入手する
- [ ] #2 取得する Sparkle のバージョンがワークフロー内で固定されている
- [ ] #3 dev タグでリリースワークフローを 1 回通し、appcast が生成されることを実測で確認する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. release.yml の 'Sparkle ツールをインストールする' ステップを、brew cask から Sparkle 公式リリースの tar.xz 取得へ置き換える。
   - URL: https://github.com/sparkle-project/Sparkle/releases/download/<version>/Sparkle-<version>.tar.xz
   - バージョンは env で固定する（アプリが SPM で解決している 2.9.4 に合わせる。Package.resolved で確認済み）
   - 展開先の bin/ を GITHUB_PATH へ追加する
2. brew info --json のバージョン抽出（python3 経由）が不要になるので削除する。
3. dev タグでリリースワークフローを 1 回通し、appcast が生成されることを実測する。

実測（手元、macOS 26 / Apple Silicon）:
- curl -sIL で 2.9.4 の tar.xz が 200 を返すことを確認
- 展開すると bin/ に generate_appcast / generate_keys / sign_update / BinaryDelta が揃う（brew cask では generate_appcast と generate_keys が欠落していた）
- generate_appcast --help が動作、実際に appcast 生成まで通ることを確認済み
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装と実測

release.yml:215-237 の 'Sparkle ツールをインストールする' を brew cask から公式リリースの tarball 取得へ置き換えた。SPARKLE_VERSION は 2.9.4 に固定（BefoldApp/Package.resolved の SPM 解決結果に一致）。取得先が変わってツールが欠けたまま進むと appcast が更新されないのにジョブが成功してしまうため、test -x で generate_appcast の存在を確認するステップを入れた。

実測（手元 macOS 26 / Apple Silicon、ワークフローと同じ手順を再現）:
- curl -fsSL で Sparkle-2.9.4.tar.xz を取得（HTTP 200）
- tar -xJf で展開 → bin/ に generate_appcast / generate_keys / sign_update / BinaryDelta が揃う
- test -x "$sparkle_dir/bin/generate_appcast" が通る
- generate_appcast が実際に起動し、appcast 生成まで完了することを確認

対比（問題の裏付け）:
- brew install --cask sparkle 後の /opt/homebrew/Caskroom/sparkle/2.9.5/bin/ = BinaryDelta, old_dsa_scripts, sign_update のみ。generate_appcast と generate_keys が欠落
- brew info --cask sparkle → 'Deprecated because it does not pass the macOS Gatekeeper check! It will be disabled on 2026-09-01.'

docs/superpowers/specs/2026-07-12-sparkle-migration-design.md の 'brew install sparkle' の記述にも変更を追記した。

AC#3（dev タグでの実測）は未了。リリースワークフローを 1 回通す必要があり、TASK-355 の AC#2 検証と同じ dev リリースで兼ねられる。

PR #443 を作成した（https://github.com/YTommy109/befold/pull/443）。main + 1 コミットで、R2 移行（TASK-355）とは独立してマージできる。verify チェック pass（42s）。

AC#3（dev タグでリリースワークフローを 1 回通す）はマージ後の dev リリースで実測する。TASK-355 の AC#1・#2 と同じ dev リリースで兼ねられる。
<!-- SECTION:NOTES:END -->
