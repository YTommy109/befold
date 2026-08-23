---
id: TASK-485.22
title: シンボルジャンプの装飾を変更箇所ジャンプと同じ行番号エリアの色分けに揃える
status: To Do
assignee: []
created_date: '2026-08-23 07:26'
labels: []
milestone: m-6
dependencies: []
parent_task_id: TASK-485
type: enhancement
ordinal: 790000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景（ユーザー要望・2026-08-23）

文書内ジャンプ（TASK-485）には見た目の系統が 2 つあり、**変更箇所へのジャンプの方が好ましい**というのがユーザーの判断。シンボル（見出し）ジャンプの見た目をそちらへ揃える。

具体的には次の 2 点。

1. **現在アクティブな箇所を枠線で囲むのをやめる。** 見出しの周りに枠が出るのは画面がうるさい
2. **候補（該当箇所）は行番号エリアを少し薄く、アクティブ箇所ははっきりと**という色分けにする。装飾を行番号エリア（ガター）へ寄せて、変更箇所ジャンプと同じ読み方にする

## 現状（実測: `BefoldApp/BefoldKit/Resources/style.css`）

| | 候補 `.mmd-jump-target` | アクティブ `.mmd-jump-current` |
|---|---|---|
| 既定（見出し等） | 文字幅のアクセント下線（`style.css:692-697`） | `outline: 2px solid var(--accent)` の枠線（`style.css:705-709`） |
| 差分表示 | 装飾なし（`style.css:724-728` で下線を打ち消し。地色で見えているため） | 左端セルへ `box-shadow: inset 3px 0 0 var(--accent)` の縦帯（`style.css:718-721`） |

クラスを付けるのは `BefoldApp/viewer-src/jump.ts:70,73`（`CURRENT_CLASS` / `TARGET_CLASS`）、対象の列挙と highlight 要素の決定は `BefoldApp/viewer-src/jump-providers.ts`（見出し :69-135 / 変更ブロック :156-193）。**装飾は JS/CSS 側だけにあり、Swift は「ジャンプを開けるか」しか持たない**（`ViewerCapabilities.swift:80,98`）。

差分側のアクティブが「行番号エリアの縦帯」に見えるのは、`leadingCell`（`jump-providers.ts:181-185`）が行の先頭セルを取り、行番号表示 ON ならそれが `td.line-number` になるため。

## 着手前に決めること（この設計判断が実装内容を分ける）

**行番号ガター `td.line-number` はコード系テーブルにしか存在しない。** 生成箇所は `code-html.ts:167` / `diff-html.ts:288-290,402,411` / `csv-html.ts:214-220` で、いずれも行番号表示 ON のときだけ。

見出しジャンプの対象は 2 系統に分かれる。

- **Markdown レンダリング表示**（見出しジャンプの主用途）… 対象は `h1/h2/h3` 要素そのもの（`jump-providers.ts:98-110`）。テーブル構造も行番号ガターも無く、行番号トグル自体が無効（`ViewerCapabilities.swift:85` の `canToggleLineNumbers` は `showsCodeContent` 前提）
- **Markdown ソース表示**… code-table なのでガターは存在しうるが、行番号表示は既定 OFF（`viewer-src/view-options.ts:26`）で、現在の highlight 対象も `td.line-content`（`jump-providers.ts:91-94`）

つまり「行番号エリアの色分けへ揃える」は、**レンダリング表示の見出しジャンプにはそのままでは成立しない**。次のどちらを採るかを着手前にユーザーへ確認すること。

- (a) レンダリング表示にも**擬似ガター**（左マージンの帯）を新設し、行番号の有無に依らず同じ位置に色を出す
- (b) 行番号エリアの色分けはガターがある表示に限り、レンダリング表示は「枠線をやめる」だけを満たす別の控えめな装飾にする

## 関連

- **TASK-485.4**（ソースコード表示で関数定義へジャンプ）… こちらは code-table なのでガターと素直に噛み合う。装飾の決め方をこのタスクで固めておくと、実装時に迷わない
- **TASK-485.16**… フィーチャーゲート撤去。見た目が定まってから stable に載せる方が望ましい
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 見出しジャンプのアクティブ箇所が枠線（outline）で囲まれなくなっている
- [ ] #2 候補とアクティブが「薄い／はっきり」の濃淡で区別でき、変更箇所ジャンプと同じ読み方になっている
- [ ] #3 行番号ガターが無い表示（Markdown レンダリング表示）でも候補とアクティブが判別でき、どう扱うかの判断が Notes に記録されている
- [ ] #4 差分表示の変更箇所ジャンプの見た目は現状から変わっていない
- [ ] #5 ライト／ダーク両方で候補とアクティブのコントラストを確認した記録がある
<!-- AC:END -->
