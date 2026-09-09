---
id: TASK-605
title: 型グループの閾値が命名で回避できる（Foo+BarTests.swift が FooTests と合算されない）
status: To Do
assignee: []
created_date: '2026-09-09 00:04'
labels:
  - refactor
dependencies: []
priority: medium
ordinal: 885000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 実測

`scripts/check-type-group-size.sh` の `collect()` は `base="\${base%%+*}"` で最初の `+` の手前までをグループキーにする。そのため `Foo+BarTests.swift` はキーが `Foo` になり、`FooTests.swift`（キー `FooTests`）と**合算されない**。

```
308  BefoldApp/befoldTests/DocumentCommandControllerTests   ← 本体
206  BefoldApp/befoldTests/DocumentCommandController        ← +JumpTests / +OpenBarTests の合算
227  BefoldApp/befold/App/DocumentCommandController         ← プロダクト側（別ディレクトリ）
```

同一対象・同一ヘルパー・同一 fake を共有する **514 行**が、命名の形だけで 2 グループに分かれて閾値を通っている。合算されていれば CI が落ちる。

`befoldTests/` で `+` を含むファイルはこの 2 本だけ（実測）。他の分割はすべて別名を採っている（`DirectoryLister*Tests` / TASK-431 の 14 スイート）。TASK-431 の Implementation Notes は「extension 方式では check-type-group-size.sh が合算するため負債返済にならない」と明示しており、`+` を避けたのは意図的。今回の 2 本はその方針が固まる前のもの、と見られる。

## 論点

これは**意図した抜け道ではなく、`Type+Feature.swift` 規約をテスト名にそのまま当てた副作用**と見られる。一方でスクリプトの `--check` メッセージは「責務を分けて別の型へ切り出すか」と書いており、**別型名への切り出しは回避ではなく望ましい返済手段**として位置づけられている。つまり「`FooMoreTests` を作る」のは意図どおりで、「`Foo+BarTests` を作る」だけが宙に浮いている。

## 決めること（いずれか）

- **(a) 明文化する**: 判定ロジックは変えず、`check-type-group-size.sh` のコメントと `docs/dev/rules/product-code.md` へ「`Foo+BarTests.swift` は `FooTests` と合算されない」ことと、それを意図とするか否かを書く。あわせて既存 2 本を別名へ改名して `+` 形式のテストを 0 件にする（最小）
- **(b) 塞ぐ**: テストの判定を「対象型名で束ねる」形へ変える。ただし `ViewerStore*Tests`（11 ファイル）・`ViewerWindowController*Tests` 等の合算値が激変する可能性が高く、**先に (b) の判定で再集計した数字を取らないと議論できない**
- **(c) 放置**

同じことはプロダクトコードにも成り立つ（`ViewerWindowController+Assembly.swift` を `ViewerWindowAssembly.swift` に改名すれば別グループ）。ただしプロダクトでは新型が依存グラフに現れて意味を問われるのに対し、テストは誰にも呼ばれないため「意味のない機械分割」が差分レビューでしか止まらない、という非対称がある。

## 経緯

TASK-604 の棚卸しで発見。同タスクは「テストも本番と同じ 400 行で縛る」を据え置く結論を出しており、その据え置きに伴って残る宿題として切り出した。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 (a) / (b) / (c) のどれを採るかが理由つきで記録されている
- [ ] #2 (b) を採る場合、再集計した数字が Notes にある
- [ ] #3 採った方針が実施され、befoldTests に + 形式のファイルが残っているならその理由が書いてある
<!-- AC:END -->
