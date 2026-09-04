---
id: TASK-489.6
title: GitHub Releases のリリース本文に配布サイトへの導線を入れる
status: Done
assignee:
  - '@claude'
created_date: '2026-09-04 01:46'
updated_date: '2026-09-04 01:50'
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
- [x] #1 すべての新規リリースの GitHub Release 本文の末尾に、最新版は https://befold.degino.com/download から取得するよう促す案内が英語と日本語で入る
- [x] #2 案内の追記が release.yml のステップとして行われ、リリースノート生成側の手順（/release, /release-notes）の遵守に依存しない
- [x] #3 ワークフローを再実行しても案内が重複して追記されない
- [x] #4 GitHub Releases の DMG そのものは削除・添付停止しない（停止条件は TASK-489.1 が決める）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
release.yml の「GitHub Release を作成して DMG を添付する」の直後に追記ステップを足した。

- 置き場所を release.yml にした理由: リリース本文は /release コマンドの gh release create --notes が作るが、手順の申し送りは守られない。CI のステップなら毎リリース必ず通るため、書き忘れという形で破れない（CLAUDE.md「決めたことには、破れたら落ちるものを付ける」）。
- 冪等性はマーカー <!-- distribution-site-notice --> の有無で担保する。action-gh-release の append_body は実行のたびに足すため採らなかった（再実行で二重になる）。
- 実測（gh を差し替えたスタブで step の run をそのまま実行）: 1 回目で本文末尾に追記され、2 回目は「追記済みのためスキップする」を出して本文が変化しないことを確認した。YAML のパースも確認済み。
- リンクは /download?ref=gh-release にした。recordEvent は kind を問わず ?ref= を referrer として記録するため（site/src/events.ts の resolveReferrer 呼び出し）、この導線が実際に使われたかをダッシュボードの参照元で読める。ref の値は変えないこと（過去データと接続できなくなる）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
release.yml の DMG 添付ステップの直後に、GitHub Release 本文の末尾へ配布サイトへの導線（英日）を追記するステップを足した。リリースノート生成手順への申し送りではなく CI ステップに置いたので、書き忘れで破れない。マーカー <!-- distribution-site-notice --> の有無で冪等にしてある（action-gh-release の append_body は再実行で二重になるため採らなかった）。検証: gh を差し替えたスタブで step の run をそのまま 2 回実行し、1 回目で追記・2 回目はスキップして本文が不変であることを実測。YAML のパースも確認。DMG の添付・削除には手を付けていない。
<!-- SECTION:FINAL_SUMMARY:END -->
