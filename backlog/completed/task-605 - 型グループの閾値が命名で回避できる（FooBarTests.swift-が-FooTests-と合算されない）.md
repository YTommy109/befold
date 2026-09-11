---
id: TASK-605
title: 型グループの閾値が命名で回避できる（Foo+BarTests.swift が FooTests と合算されない）
status: Done
assignee: []
created_date: '2026-09-09 00:04'
updated_date: '2026-09-09 04:37'
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
- [x] #1 (a) / (b) / (c) のどれを採るかが理由つきで記録されている
- [x] #2 (b) を採る場合、再集計した数字が Notes にある
- [x] #3 採った方針が実施され、befoldTests に + 形式のファイルが残っているならその理由が書いてある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 判断: (a) + (b) の限定版。放置(c)は採らない

(b) を「対象型名で束ねる」広い形で入れると `ViewerStore*Tests` 等の合算値が激変するが、
**穴の実体はもっと狭い**ので、そこだけを塞ぐ限定版にした。

## (b) の再集計（AC #2、実測）

判定を「`*Tests` は `Tests` を残したまま `+` を畳む」に変えた場合の再集計:

| 行数 | グループ | 変化 |
|---|---|---|
| 920 | `befold/App/ViewerWindowController` | 変化なし（恒久例外） |
| **514** | `befoldTests/DocumentCommandControllerTests` | **308 + 206 が合算され閾値超過** |
| 425 | `befold/App/SidebarNavigator` | 変化なし（恒久例外） |
| 399 | `befold/App/MainMenuBuilder` | 変化なし |
| 388 | `befold/Viewer/FileListModel` | 変化なし |

**変わるのは 1 グループだけ**。`befoldTests` に `+` を含むファイルはこの 2 本しか無く
（実測）、他の分割はすべて別名を採っているため。広い (b) が心配していた
`ViewerStore*Tests` 等は `+` を使っていないので影響を受けない。

## 実施

1. **返済**: `DocumentCommandController+JumpTests.swift` / `+OpenBarTests.swift` は
   `extension DocumentCommandControllerTests` で、doc 自身が「file_length 対策の分割」と
   書いていた。TASK-431 が「extension 方式では合算されるので返済にならない」と
   決めた形そのもの。別名の独立スイート **`DocumentJumpCommandTests`（125 行）** と
   **`OpenBarCommandTests`（88 行）** へ分け、境界を冒頭コメントに書いた。
   共有していたフェイクと組み立ては **`DocumentCommandControllerTestSupport.swift`**
   （TASK-604.2 の前例と同じ形）へ出した。本体は 308 → 158 行。
2. **塞ぐ**: `check-type-group-size.sh` の `collect()` を「基底名が `Tests` で終わるなら
   `Tests` を残したまま `+` を畳む」に変更。`Foo+BarTests.swift` はもう `FooTests` と
   合算され、命名で閾値を回避できない。
3. **明文化**: スクリプトのコメントと `docs/dev/rules/product-code.md` に、
   合算規則とテストを分けるときの作法（extension ではなく別名の独立スイート、
   共有物は `〜TestSupport.swift`）を書いた。

## 検証

- `--self-test` に新しいケース（`BazTests.swift` + `Baz+MoreTests.swift` が合算されて 3 行）を
  追加。**規則を元に戻すと落ちる**ことを確認済み（`App/BazTests` 2 行と `App/Baz` 1 行に
  分かれる形をそのまま再現して失敗する）
- `--check` 通過。`befoldTests` に `+` 形式のファイルは **0 件**（AC #3）
- `swift test` 1947 tests / 326 suites 緑。swiftlint はベースライン差分なし、
  swiftformat 変更なし、markdownlint 指摘なし
<!-- SECTION:NOTES:END -->
