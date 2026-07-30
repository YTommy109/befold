---
id: TASK-189
title: 配布サイト（紹介ページ）を現状の機能・訴求ストーリーに合わせてリニューアルする
status: To Do
assignee: []
created_date: '2026-07-28 14:30'
labels: []
dependencies:
  - TASK-182
ordinal: 265000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
配布サイトの紹介ページを、初版作成時から充実した現在の befold の機能・特徴に合わせて刷新する。Cloudflare Workers 移行（TASK-182）後の新サイト基盤の上で行う。

## 背景
初版 LP の作成時点から befold の機能が大きく充実し、紹介している特徴が実態とずれている。訴求すべきユーザー像も明確になった。

## 訴求したいユーザー像とストーリー
- 大量のマークダウンファイルを行き来しているユーザー
- git worktree を使っているユーザー

ストーリーの核: Obsidian では markdown を快適に閲覧できるが、worktree をわざわざ vault に登録するのは面倒。一方 befold はコマンドラインからお手軽に表示でき、worktree 上の markdown もすぐ見られる。この「手軽さ」「worktree との相性」を軸に訴求する。

## やること（概略）
- 現在の機能棚卸しに基づいて紹介する特徴を更新する
- 上記ユーザー像に刺さるストーリー/コピーを反映する
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 紹介ページの特徴一覧が現在の befold の機能実態と一致している
- [ ] #2 「大量の markdown を行き来するユーザー」向けの訴求が含まれる
- [ ] #3 「worktree ユーザー」向けの訴求（Obsidian/vault 登録の手間との対比、CLI からの手軽表示）が含まれる
- [ ] #4 Cloudflare Workers 移行後の新サイト基盤上で公開されている
<!-- AC:END -->
