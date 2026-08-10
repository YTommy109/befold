---
id: TASK-408
title: ツリー表示の ← / h を階層移動ではなくツリー内の親行への選択移動にする
status: To Do
assignee: []
created_date: '2026-08-10 06:09'
labels:
  - bug
dependencies: []
priority: medium
ordinal: 665000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーのキー操作が list（drillDown）と tree で非対称なため整理する。

## 現状（実測）

キー対応表は `SidebarKeyAction.action(key:modifiers:target:mode:)` (Viewer/SidebarKeyAction.swift:52) に一本化されており、表示モードは引数で渡る（モードごとの別ハンドラは無い）。

| キー | drillDown | tree |
|---|---|---|
| → / l / Return | フォルダ = 中へ入る（ルート変更） | 畳 = 展開 / 展開済 = 次の行へ |
| ← / h | 常に親へ（ルート変更） | 展開済フォルダ = 畳む / それ以外 = 親へ（ルート変更） |
| delete | 親へ（ルート変更） | 同左 |
| cmd+↑ | 親へ | 同左 |

## → の差は直さない（判断）

→ の意味がモードで違うことは他アプリの慣習どおりであり、変更しない。Finder 自身が、カラム表示（階層ごとに別ペイン）では → = 降りる、リスト表示（ツリーを平坦なリストとして見る）では → = 展開、と分かれている。befold の drillDown はカラム表示の 1 カラム版、tree はリスト表示に対応する。Xcode ナビゲータ / VS Code エクスプローラ / NERDTree もツリー側は例外なく → = 展開。ここを揃えると、かえってどちらかが慣習から外れる。

## 直すのは tree の ←（本題）

tree でファイルまたは畳んだフォルダを選択中に ← を押すと、ルートごと 1 階層上へ移動する（SidebarKeyAction.swift の tree 分岐、Viewer/FileListView+Keyboard.swift:112）。問題は 3 点。

1. 往復が非対称。→ で展開して子へ降りたのに、← は展開状態の中を戻らずツリーごと別の場所へ飛ぶ
2. tree の → は一度もルートを変えないのに、← だけがルートを変える
3. Finder / Xcode / VS Code / NERDTree はいずれも「← = 畳む、畳み済みか葉なら親フォルダの行へ選択を移す」の二段構えで、ルートは動かさない

## 整理の原則

- → / ← はモード内の移動にだけ使う（tree では展開・折りたたみと選択移動、drillDown では階層の出入り）
- ルートの変更は cmd+↑ と delete に集約する（両モードで同じ意味）

変更するのは tree の ← / h のみ。

| | 現状 | 変更後 |
|---|---|---|
| tree ← / h（展開済フォルダ） | 畳む | 畳む（変更なし） |
| tree ← / h（畳んだフォルダ・ファイル） | ルートを親へ | 親フォルダの行へ選択を移す |
| tree ← / h（最上位の行） | ルートを親へ | 何もしない（cmd+↑ / delete に委ねる） |
| drillDown ← / h | ルートを親へ | 変更なし |

## 同時に片付けるリファクタリング

- `.selectNext` が文脈で意味を変える。キー経由では「次の行へ」だが、ダブルクリック経由では「畳む」と解釈される (Viewer/FileListView.swift:301)。同じ値が 2 つの意味を持つのはバグ源なのでケースを分ける
- `enterSelected()` (Viewer/FileListView+Keyboard.swift:96) は private かつ参照ゼロの未使用コード。削除する

## 未確認

`.onKeyPress` が全キーを受けるため NSTableView 標準のタイプ先行入力が効かない可能性がある（未対応キーでは `.ignored` を返すので下位へ流れる想定）。実機で確認するまで断定しない。本タスクの対象外だが、確認して問題があれば別途起票する。

## 注意

tree 表示は `FeatureGate.isSidebarTreeEnabled` 配下のため、コミット件名に `(gate)` スコープを付ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 tree で畳んだフォルダを選択中に ← / h を押すと、ルートは変わらず親フォルダの行へ選択が移る
- [ ] #2 tree でファイルを選択中に ← / h を押すと、ルートは変わらず親フォルダの行へ選択が移る
- [ ] #3 tree で展開済みフォルダを選択中の ← / h は従来どおり折りたたむ
- [ ] #4 tree で最上位の行を選択中の ← / h は何もしない（ルートが変わらない）
- [ ] #5 tree での cmd+↑ と delete は従来どおりルートを親へ移す
- [ ] #6 drillDown のキー挙動は一切変わっていない
- [ ] #7 上記すべてが SidebarKeyActionTests でモード別に検証されている
- [ ] #8 キー経由の「次の行へ」とダブルクリック経由の「畳む」が別のケースに分離され、同じ値が文脈で意味を変えない
- [ ] #9 未使用の `enterSelected()` が削除されている
- [ ] #10 着手前に `/review-design` を 1 回実行し、結果を Implementation Plan に反映している
<!-- AC:END -->
