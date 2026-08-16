---
id: TASK-506
title: 配布サイトに旧バージョン（stable）のダウンロードページを用意する
status: To Do
assignee: []
created_date: '2026-08-16 13:46'
labels: []
dependencies: []
ordinal: 737000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
最新版に不具合があったとき、利用者が一つ前の stable に戻せるようにする。現在 befold.degino.com は LP の /download が stable 最新の DMG を R2 から返すだけで、過去バージョンへ辿る導線が無い。

過去の stable リリース一覧（バージョン・公開日・リリースノートへのリンク・DMG のダウンロードリンク）を並べたページを追加する。dev（develop チャンネル）のリリースは対象外で、一覧にも出さない。

ダウンロード実績は既存の download イベントと同じ枠組みで記録し、どのバージョンが旧版として落とされたかがダッシュボードから分かる状態にする。一覧の取得元（R2 のポインタ/オブジェクト列挙か GitHub Releases か）と、LP からの導線の置き場所は着手時に決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 befold.degino.com に過去の stable バージョンを一覧するページがあり、各行からその版の DMG をダウンロードできる
- [ ] #2 一覧に develop チャンネル（プレリリースタグ）のリリースが含まれない
- [ ] #3 各行にバージョン・公開日・リリースノートへのリンクが表示される
- [ ] #4 LP から旧バージョンページへ辿れる導線がある
- [ ] #5 旧バージョンのダウンロードが download イベントとして版ごとに記録され、ダッシュボードで確認できる
- [ ] #6 ページが LP と同じ意匠・多言語対応で表示される
- [ ] #7 一覧の取得元が利用できない場合でもページがエラー表示にならず、状況が利用者に伝わる
<!-- AC:END -->
