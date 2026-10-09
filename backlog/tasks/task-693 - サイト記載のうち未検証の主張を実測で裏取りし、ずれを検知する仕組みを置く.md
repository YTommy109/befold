---
id: TASK-693
title: サイト記載のうち未検証の主張を実測で裏取りし、ずれを検知する仕組みを置く
status: To Do
assignee: []
created_date: '2026-10-09 07:33'
updated_date: '2026-10-09 07:38'
labels: []
milestone: m-12
dependencies: []
priority: low
type: task
ordinal: 882000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
調査（2026-10-09）はコード読みだけで、次は未検証: ライブリロード 0.2 秒、通信はアップデート確認のみ、HTML 内スクリプトは実行しない、git を知っているリンク解決と worktree 追従、Quick Open の空欄時の最近/ブックマーク表示、「さらに読み込む」の文言、サイドバーバッジの色分け。site 側の既存テスト（test/shortcuts.test.ts・test/file-types.test.ts）は npx vitest が止まり、実行できていない。記事 Markdown は ja/en のサイズ差が約 1.4 倍（ai-code-review は 3.5K と 2.5K）で、段落対応は未検証。今回の食い違いは、今のところ人が読み比べないと見つからない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 上記の未検証の主張それぞれについて、実測またはコード参照で 一致／食い違い を Notes に記録している
- [ ] #2 site の vitest が止まる原因を特定し、test/shortcuts.test.ts と test/file-types.test.ts の合否を実測で示している
- [ ] #3 記事 Markdown の ja/en で段落が対応しているかを確認し、ずれがあれば直している
- [ ] #4 サイトの SHORTCUTS が実装のメニュー定義とずれたら落ちるテスト、またはそれが成立しない理由と代替の運用を残している
<!-- AC:END -->
