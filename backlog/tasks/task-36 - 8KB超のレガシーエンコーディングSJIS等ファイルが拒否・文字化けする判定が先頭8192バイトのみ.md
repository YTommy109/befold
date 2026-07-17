---
id: TASK-36
title: 8KB超のレガシーエンコーディング(SJIS等)ファイルが拒否・文字化けする(判定が先頭8192バイトのみ)
status: To Do
assignee: []
created_date: '2026-07-17 02:06'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TextEncoding.swift:63 でレガシーエンコーディング判定が `data.prefix(sniffLength)`(8192バイト)に対して実行されるが、検出したエンコーディングは全データのデコードに適用される(:86)。フォールバックはない。v1.7.1-dev.5 以前は全データで判定していたため回帰。

失敗モード1: 先頭8KBが純ASCIIで後半に日本語があるSJISファイル → プレフィックスからASCII/UTF-8と誤判定 → 全データデコードがnil → NormalizedTextCache が decodeFailed を throw → 「未対応フォーマット」として拒否される。
失敗モード2: 2バイト文字がオフセット8192をまたぐ → 切断されたプレフィックスが不正SJISとなり判定が失敗/lossy → 拒否または文字化け。

修正方向: プレフィックス判定を維持しつつ (a) 不完全なマルチバイト末尾のトリム、(b) 全データデコード失敗時に全データで再判定するフォールバック、の少なくとも一方を入れる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ASCIIヘッダー8KB超+後半日本語のSJISファイルが正しくデコード・表示される(回帰テストあり)
- [ ] #2 2バイト文字が8192バイト境界をまたぐSJISファイルが正しくデコードされる(回帰テストあり)
- [ ] #3 判定の高速化(全文走査回避)の性能特性は維持される
<!-- AC:END -->
