---
id: TASK-485.13
title: isRendering の防御的クリア 3 箇所を、render 完了通知の一本化で置き換える
status: Done
assignee: []
created_date: '2026-08-17 14:05'
updated_date: '2026-08-18 04:19'
labels: []
milestone: m-6
dependencies: []
parent_task_id: TASK-485
priority: medium
type: task
ordinal: 747000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景（/code-review high の指摘、verdict: CONFIRMED）

`viewer-src/jump.ts:206` ほか、isRendering フラグが open / close / refresh の 3 つの入口で強制クリアされている。原因は `render.ts:93-94` が `_mmdJump.isOpen()` のときしかジャンプコントローラへ render 完了を通知しないこと。open() の「もう render は着地しているはず」という仮定は mermaid render 中（大きい図で数秒）には偽で、その窓で開くと DOM スワップ進行中に isRendering がクリアされ、見出しレベルのトグルが mid-render DOM に対して rebuild() を走らせうる——このフラグが守るはずのハザードそのもの（transient: バーが開いていれば `render.ts:93` の着地時 refresh が後で正すが、それは偶然）。

## 提案（レビューの指摘どおり）

`_mmdFindRefreshAfterRender` から無条件に `_mmdJump.refresh` を呼び、refresh が最初にフラグをクリアする。これで setter は invalidate の 1 箇所、clearer は refresh の 1 箇所になり、3 つの防御的リセットとそのコメントを削除できる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 isRendering の setter が invalidate、clearer が refresh の各 1 箇所になっている
- [x] #2 open / close / refresh 入口の防御的リセットと説明コメントが削除されている
- [x] #3 render 進行中にバーを開いてレベルをトグルしても mid-render DOM への rebuild が起きないことをテストで固定する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
render.ts の _mmdFindRefreshAfterRender からジャンプ側の refresh を無条件に呼ぶようにし、isRendering の下ろし口を refresh の 1 箇所へ集約した（立てるのは invalidate の 1 箇所）。open / close の防御的リセットと説明コメントは削除。

閉じている間の refresh は「フラグを下ろして即 return」にした。無条件呼び出しにすると閉じたまま列を作ってしまい、候補の下線（mmd-jump-target）が見えない状態で DOM に付くため。

テスト（viewer-main-jump.test.js）を 2 件追加。
- 描画中にバーを開いてレベルをトグルしても列は作り直されない: render() を await せずに開始 → open → toggleHeadingLevel(1) → 件数が 1/3 のまま。await 後に着地の refresh が 1/2 へ作り直す。open() の isRendering=false を戻すと 1/2 になって落ちることを実測で確認。
- バーを閉じたまま描画しても候補の印は付かない: 上記の早期 return の回帰ガード。

実測: npx jest 519 件 pass、npm run lint / format:check クリーン。docs/dev/native-app-design.md には isRendering の記述が無いため（grep で 0 件）現在仕様の更新は不要。
<!-- SECTION:NOTES:END -->
