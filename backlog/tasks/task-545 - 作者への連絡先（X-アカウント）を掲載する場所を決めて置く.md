---
id: TASK-545
title: 作者への連絡先（X アカウント）を掲載する場所を決めて置く
status: To Do
assignee: []
created_date: '2026-08-23 07:58'
updated_date: '2026-08-23 08:33'
labels: []
milestone: m-10
dependencies: []
type: feature
ordinal: 794000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
利用者とのコミュニケーション経路として `https://x.com/tommy1969` を掲載したい。**まず置き場所を決めるところから。**

## 現状の受け口（実測、2026-08-23）

- GitHub Issues: アプリの Help メニューから（`AppLinks.issues`）と、GitHub リボン経由
- それ以外の連絡先は、サイトにもアプリにも無い

不具合・要望は GitHub Issues が受け口として機能しているが、GitHub アカウントを持たない利用者には届く経路が無い。

## 調べること

同種のプロダクト（個人・小規模チームの macOS 向けユーティリティ）が、作者への連絡先をどこに置いているかを実例で確認する。少なくとも次の観点で:

- サイトのフッターか、専用の連絡先セクションか、About パネルか
- X 単体か、他の経路（メール・Mastodon・Discord）と併記か
- 「不具合は Issues、それ以外は X」のように用途を分けて書いているか

その結果を踏まえて置き場所を決める。**調査結果を Notes に残してから実装に入る**（掲載場所は後から動かしにくいため）。

## 決めること

- 置き場所（サイトのフッター / 各ページ / About パネル / その組み合わせ）
- GitHub Issues との使い分けを文言で示すか
- アプリ側にも置くなら、URL リテラルは `AppLinks` に集約する（`siteOrigin` の規約と同じ）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 同種プロダクトの掲載場所を 3 件以上調べ、出典つきで Notes に記録している
- [ ] #2 調査結果を踏まえた掲載場所の判断と理由が Notes に残っている
- [ ] #3 決めた場所に https://x.com/tommy1969 が掲載され、ja / en の両方で出る
- [ ] #4 アプリ側にも置く場合、URL リテラルが AppLinks に集約されている
<!-- AC:END -->
