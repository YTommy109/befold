---
id: decision-10
title: 新しいウィンドウの寸法はアプリ全体で 1 個にし、窓ごとの寸法はセッションに持たせる
date: '2026-09-01 04:32'
status: proposed
---
## Context

本文は ADR に置く（`docs/adr/0010-window-frame-app-wide-default.md`）。

実測（2026-09-01）: ファイル単位の記憶 `WindowFrames` が 104 件あり、最後に調整した寸法
（`WindowFrameLastUserAdjusted`）と一致するのは 1 件だけだった。窓を開くたびに解決結果を
そのファイルへ書き戻していたため、一度開いたファイルは古い寸法に固定されていた。

## Decision

新しい窓の出発点になる寸法は**アプリ全体で 1 個**（`WindowFrameStore`）にし、
ファイル単位の記憶をやめる。再起動時に各窓を戻す寸法は「窓の状態」として
`SessionLayout.TabGroup.frame` が持つ。グローバル値を書く契機はリサイズの確定のみ
（閉じたときの順序は AppKit 任せで制御できないため）。

**TASK-74 の判断（app-global 単一キーを廃止してファイル単位にする）を上書きする。**

## Consequences

ファイルごとに違う寸法を覚える性質は失われる。位置だけを動かして閉じた場合、その位置は
次に開く窓へは引き継がれない（再起動時の復元では戻る）。`WindowFrames` は移行せず
`AppStores.retiredDisplayStateKeys` で削除する。
