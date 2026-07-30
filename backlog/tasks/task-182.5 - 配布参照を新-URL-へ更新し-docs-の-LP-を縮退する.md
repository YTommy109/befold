---
id: TASK-182.5
title: 配布参照を新 URL へ更新し docs/ の LP を縮退する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-28 13:36'
updated_date: '2026-07-29 23:59'
labels: []
dependencies:
  - TASK-182.6
documentation:
  - >-
    docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md
parent_task_id: TASK-182
priority: low
ordinal: 262000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
README や関連ドキュメントの配布 URL を新 Worker の URL に更新する。Worker の安定稼働を確認した後、docs/ の LP 部分（index.html 等）を開発ドキュメント専用へ縮退する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 README 等の配布リンクが新 Worker URL を指す
- [x] #2 docs/ の LP 部分が縮退され役割が site/ へ移る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. docs/index.html を配布サイトへのリダイレクト 1 枚に置換する。meta refresh + JS location.replace + 手動リンクのフォールバックを併置し、遷移先は https://befold.tommy109.workers.dev/?ref=gh-pages とする（TASK-182.6 の参照元計測に載せるため）。CSS は外部ファイルを消すのでインライン最小限にする。
2. docs/style.css・docs/carousel.js・docs/images/（スクリーンショット 5 枚）を削除する。site/public/ に同一バイトサイズの資産が揃っており重複のため。docs/index.html 以外からの参照が無いことを grep で確認済み。
3. docs/adr/・docs/dev/・docs/superpowers/ は開発ドキュメントなので残す。_config.yml の exclude: [superpowers] も維持する。
4. ルート README.md:6 の紹介ページリンクを新 URL へ差し替える。
5. リダイレクトが実際に効くかを Chrome で検証する（Pages の反映後）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
docs/index.html を配布サイトへのリダイレクト 1 枚に置換した。GitHub Pages は静的ホスティングで 301 を返せないため meta refresh + JS location.replace を併置し、どちらも効かない場合の手動リンクを残した。遷移先は https://befold.tommy109.workers.dev/?ref=gh-pages で TASK-182.6 の参照元計測に載る。

docs/style.css・carousel.js・images/（5 枚）を削除した。site/public/ に同一バイトサイズの資産が揃っており、docs/index.html 以外からの参照が無いことを grep で確認済み。docs/adr/・dev/・superpowers/ の開発ドキュメントと _config.yml の exclude: [superpowers] は維持した。

README.md の紹介ページリンクを新 URL（?ref=readme）へ、インストール手順のダウンロード導線を配布サイトの /download?ref=readme へ差し替えた（GitHub Releases 直リンクも併記）。Pages 経由を通らない README からの流入も計測に載る。

発見して同タスク内で対処した件: scripts/cache-bust-docs.sh は docs/style.css / carousel.js がステージされたとき docs/index.html の ?v= ハッシュを更新するフックだが、両ファイルを削除したことで git show ":docs/style.css" が失敗し pre-commit がコミットを弾くようになった。LP 資産が無くなり ?v= 参照も消えて役目を終えたため、スクリプトを削除し setup-git-hooks.sh の pre-commit 登録から外して再インストールした。

検証: docs/ をローカル配信（python3 -m http.server）して Chrome で実際に開き、https://befold.tommy109.workers.dev/?ref=gh-pages へ遷移して LP が表示されることをスクリーンショットで確認した。本番 D1 に id 39 visit referrer=gh-pages が記録され、README 導線側も id 38 download referrer=readme を確認。/download?ref=readme は 302 で v1.10.0 の DMG へ転送されることを curl で確認済み。

未検証: GitHub Pages 上の実物（https://ytommy109.github.io/befold/）でのリダイレクトは、Pages が main の docs/ から配信されるため main へマージされるまで確認できない。マージ後に実 URL で再確認すること。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
docs/index.html を配布サイト（https://befold.tommy109.workers.dev/?ref=gh-pages）へのリダイレクト 1 枚に置換し、LP 資産（style.css・carousel.js・images/）を削除して site/ との二重管理と計測漏れを解消した。README の紹介・ダウンロード導線も新 URL（?ref=readme）へ差し替えた。LP 資産の削除で役目を終えた scripts/cache-bust-docs.sh を撤去。ローカル配信した docs/ を Chrome で開いて実リダイレクトを確認し、本番 D1 に referrer=gh-pages / readme が記録されることまで検証済み。Pages 実 URL でのリダイレクトは main マージ後に再確認が必要。
<!-- SECTION:FINAL_SUMMARY:END -->
