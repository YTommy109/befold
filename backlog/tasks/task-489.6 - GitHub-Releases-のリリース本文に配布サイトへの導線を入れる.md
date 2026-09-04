---
id: TASK-489.6
title: GitHub Releases のリリース本文に配布サイトへの導線を入れる
status: To Do
assignee: []
created_date: '2026-09-04 01:46'
labels: []
dependencies: []
parent_task_id: TASK-489
ordinal: 849000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
手動ダウンロードは befold.degino.com を経由させたい。GitHub Releases に DMG を置き続けているのは出荷済みバージョンの自動アップデート互換のためであり（TASK-489.1 の停止条件が定まるまで削除できない）、人に直接落としてもらう場所ではない。

README・アプリ内 Help の導線はすでに配布サイト向きだが（README の Download/Website リンク、AppLinks.help）、GitHub Releases ページ自体には配布サイトへの案内が一切なく、リリース本文はリリースノート本文だけで終わっている。

実測（2026-09-04）: GitHub Releases のアセット download_count の合計は 81 件で、サイト移行後に出した v1.14.1 / v1.15.1 / v1.15.2 にも各 1 件ある。ただしこの数字は Worker の /dl/ フォールバック（R2 に無いとき GitHub アセットへ 302）による分と混ざっており、直接アクセス分だけを取り出すことはできない。

導線は release.yml 側に置く（リリースノート生成手順の申し送りにしない）。/release コマンドが gh release create --notes で本文を作り、release.yml の action-gh-release が DMG を添付する順序なので、添付ステップの後に本文へ追記する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 すべての新規リリースの GitHub Release 本文の末尾に、最新版は https://befold.degino.com/download から取得するよう促す案内が英語と日本語で入る
- [ ] #2 案内の追記が release.yml のステップとして行われ、リリースノート生成側の手順（/release, /release-notes）の遵守に依存しない
- [ ] #3 ワークフローを再実行しても案内が重複して追記されない
- [ ] #4 GitHub Releases の DMG そのものは削除・添付停止しない（停止条件は TASK-489.1 が決める）
<!-- AC:END -->
