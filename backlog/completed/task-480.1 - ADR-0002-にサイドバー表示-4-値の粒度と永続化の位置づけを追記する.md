---
id: TASK-480.1
title: ADR 0002 にサイドバー表示 4 値の粒度と永続化の位置づけを追記する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-14 08:01'
updated_date: '2026-08-14 10:52'
labels: []
dependencies: []
documentation:
  - docs/adr/0002-presentation-state-and-capabilities.md
parent_task_id: TASK-480
priority: high
type: docs
ordinal: 90100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバー表示 4 値を窓ごとのライブ値へ移すにあたり、ADR 0002 の「窓ごとのライブ値 / アプリ全体の設定」の線引きを更新する。永続化は app-global キーを新規ウィンドウの初期値として残す形とし、その位置づけ(ライブ値は窓、初期値はアプリ)を明記する。GlobalDisplayBroadcaster の doc コメントが述べる「ここから配ってよいもの」の定義も、この決定に合わせて書き換える対象として指す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ADR 0002 にサイドバー表示 4 値(layoutMode / showHiddenFiles / showChangedFilesOnly / sortOrder)が窓ごとのライブ値であることが記載されている
- [x] #2 永続化された app-global 値は新規ウィンドウの初期値としてのみ使う、と ADR に明記されている
- [x] #3 markdownlint-cli2 が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ADR 0002「状態の所在」の 2 分類を 3 分類へ引き直し、窓の状態を追加する
2. 分類を決める問いを 3 段の順序付き判定へ書き換える
3. 3 分類の表に窓の状態の行を足し、SidebarDisplayPreference をアプリの好みの例から移す
4. 窓の状態の規則（窓ごと 1 インスタンス / app-global 保存値は新規窓の初期値のみ / 書き戻し / 同期しない / 操作経路はアクティブ窓）を明記する
5. GlobalDisplayBroadcaster の doc コメント書き換えを規則 4 の中で対象として指す
6. 実装状況とトリップワイヤ 3 の評価を更新する
7. markdownlint-cli2 を通す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ADR 自身のトリップワイヤ 3 後段「2 分類のどちらにも収まらない状態が現れたとき」の発火として扱い、決定（規約 1〜4）は変えず分類だけを 3 つへ引き直した。サイドバー 4 値は「文書に紐づかない」が「窓ごとに違ってよい」ため、旧 2 分類では消去法でアプリの好みへ落ちていた。
リポジトリ内に「2 分類」を参照する他文書は無い（grep で docs/ .claude/ CLAUDE.md を確認、ヒット 0 件）。

実装手段への踏み込みを避けるため規則 1 を「ライブ値は窓ごとに持つ」へ修正した。調査で 4 値のうち sortOrder は既に窓ごとのライブ値（真実の源は各窓の FileListModel.sortOrder、SidebarDisplayPreference.sortOrder は次に窓を開くときの既定値。BefoldApp/befold/Viewer/FileListEntry.swift:7-8 の doc コメント）になっていることが分かったため、その先例を ADR に明記し、残る 3 値をそれに揃える形とした。具体的な型の配置は TASK-480.2 で決める。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ADR 0002「状態の所在」を 2 分類から 3 分類（文書の状態 / 窓の状態 / アプリの好み）へ引き直し、サイドバー表示 4 値を新設の「窓の状態」へ移した。分類を決める問いを 3 段の順序付き判定へ書き換え、窓の状態の規則 5 項（ライブ値は窓ごと / app-global 保存値は新規窓の初期値のみ・生きている窓は読み直さない / 変更時に書き戻す / GlobalDisplayBroadcaster に持たせないことで同期を構造的に禁じる / 操作経路はアクティブ窓へ）を追加。トリップワイヤ 3 後段の発火として評価を追記し、再発火条件を「3 分類のどれにも収まらないとき」へ引き直した。検証: markdownlint-cli2 で 70 ファイル 0 issues、リポジトリ内に旧「2 分類」を参照する他文書が無いことを grep で確認（ヒット 0 件）。
<!-- SECTION:FINAL_SUMMARY:END -->
