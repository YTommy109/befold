---
id: TASK-356
title: プレビューの表示モード切替を 3 セグメント + レイアウトトグルにし cmd+1〜4 を割り当てる
status: To Do
assignee: []
created_date: '2026-08-08 01:35'
labels: []
dependencies: []
priority: medium
ordinal: 615000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
プレビューエリアの表示モードの発見性を上げる。現在ツールバーには「レンダリング / ソース」の 2 セグメント（`ViewerToolbarController.swift:122-130`）しかなく、差分表示と差分左右分割は View メニューからしか辿れない（`MainMenuBuilder.swift:279-293`）ため、機能の存在が伝わっていない。

## 採用する UI（案 A）

第 1 階層を 3 択セグメント、第 2 階層のレイアウトを従属コントロールにする。

```
[ レンダリング | ソース | 差分 ]   [レイアウト]
      cmd+1       cmd+2    cmd+3      cmd+4
```

- 「差分」セグメントを選ぶと、内部的にソース表示 ON + 差分 ON になる
- 上下（`inline`）/ 左右（`sideBySide`）の切替は独立した小さなトグルとし、差分を選んでいない間は**無効化する**（出現・消滅させるとツールバー幅が動くため。この判断は暫定で、実装時に見直してよい）

この形を選んだ理由は、状態が対等な 4 択ではなく階層構造だから。差分はソース表示中でないと不可（`ViewerCapabilities.swift:61` `canToggleDiff`）、レイアウトは差分 ON でないと不可（`ViewerWindowController.swift:832-835`）であり、実装済みの従属関係を UI に写像する。cmd+1〜4 のフラットな 4 連セグメントはこの階層を潰すため採らない。

## 記憶の粒度をファイル単位に揃える

現状、ソース表示は**ファイルごと**（`SourceModeStore.swift:11`、キー `ViewerSourceModes`）、差分 ON/OFF と差分レイアウトは**アプリ全体**（`DiffDisplayPreference.swift:4-12`、キー `SourceDiffEnabled` / `SourceDiffLayout`）で粒度が食い違っている。差分を第 1 階層のモードに昇格させるとこの矛盾が表面化する（ファイル A で差分を選び B へ移ると、B はレンダリング表示なのに差分フラグだけ立つ）。

本タスクで**差分 ON/OFF をファイル単位の記憶に変更する**。レイアウトの粒度も揃えるかは実装時に判断してよい（レイアウトは好みの設定でありアプリ全体が自然という考え方もある）。

なお「アプリ単位でモードを固定する」機能は別タスクで扱う。

## 付随して解消できる歪み

差分表示は現在 cmd+D、差分左右分割は shift+cmd+D に割り当てられている（`MainMenuBuilder.swift:281,287`）。cmd+D はブックマークと衝突しており、dev ビルドではブックマークを cmd+B へ逃がす分岐がある（`BookmarkShortcut.swift:23`）。差分を cmd+3 / cmd+4 へ移せば cmd+D が空くため、この分岐を撤去してブックマークのキーをビルド種別によらず一本化できる。

**未決定**: 一本化後のブックマークを cmd+D と cmd+B のどちらにするか。dev ユーザーの操作感を変えない cmd+B が無難だが、stable の既存ユーザーは cmd+D に慣れている。着手時にユーザーへ確認すること。

## 制約

- 差分表示・差分左右分割は `FeatureGate.isSourceDiffEnabled` 配下（`FeatureGate.swift:61`）。**stable ビルドでは 3 つ目のセグメントとレイアウトトグルが出ず、現状どおり 2 セグメントになること。** コミットには `(gate)` スコープを付ける
- `FeatureGate.swift` の露出点 doc コメントの列挙を更新する（`befoldTests/FeatureGateEnumerationTests.swift` がソース走査で検証している）
- cmd+1〜4 は現在未使用（数字キーは `MainMenuBuilder.swift:162` の cmd+0 = 実寸のみ）。衝突はない
- ショートカットの Help 表示はメニュー定義から自動生成される（`MenuShortcutCatalog.swift:37-47`）ため個別対応は不要
- 状態の持ち方を変える変更に当たるため、実装着手前に `/review-design` を 1 回回し、結果を Implementation Plan に反映すること
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ツールバーのモードセグメントが dev ビルドで「レンダリング / ソース / 差分」の 3 択になる
- [ ] #2 stable ビルド（FeatureGate OFF）ではセグメントが従来どおり 2 択のままで、レイアウトトグルも現れない
- [ ] #3 差分レイアウトの切替コントロールが、差分を選んでいない間は無効になっている
- [ ] #4 cmd+1 / cmd+2 / cmd+3 でそれぞれレンダリング・ソース・差分に切り替わる
- [ ] #5 cmd+4 で差分レイアウトが上下と左右で切り替わる
- [ ] #6 差分の ON/OFF がファイル単位で記憶され、別ファイルへ移っても差分状態が引き継がれない
- [ ] #7 ブックマークのショートカットが dev ビルドと stable ビルドで同一になり、BookmarkShortcut のビルド種別分岐が撤去されている
- [ ] #8 FeatureGate.swift の露出点 doc コメントが更新され FeatureGateEnumerationTests が通る
<!-- AC:END -->
