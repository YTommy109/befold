---
id: TASK-39
title: チャンク読込エラー後の再描画でエラーバナーが無効な「さらに読み込む」バナーに戻る
status: To Do
assignee: []
created_date: '2026-07-17 02:07'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerWebView.swift の TruncationState は `failed: Bool = false` のデフォルト付きで、applyRender の truncatedScript 再送(:503)は failed:false を固定で送る。チャンク読込失敗後(loadFailed=true、chunkSession=nil、isTruncated=true 維持、lastTruncation.failed=true)、行番号トグル等の任意の再描画で truncationStateChanged() が failed の差分を検知して _mmdSetTruncated(..., failed:false) を再送し、エラーバナー(TASK-25 で導入)が通常の「さらに読み込む」バナーに戻る。しかし chunkSession が nil のためボタンは永久に無反応。

修正方向: failed のデフォルト値をやめ、applyRender/truncationStateChanged に lastTruncation の failed を貫通させる(3箇所の呼び出しが揃うように)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 チャンク読込エラー後に再描画(行番号トグル等)してもエラーバナーが維持される
- [ ] #2 TruncationState の failed がデフォルト引数に依存せず全経路で明示的に渡される
- [ ] #3 クリックしても何も起きない「さらに読み込む」ボタンが表示される経路がない
<!-- AC:END -->
