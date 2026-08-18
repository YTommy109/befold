---
id: TASK-485.16
title: 文書内ジャンプのフィーチャーゲートを外して stable に載せる
status: To Do
assignee: []
created_date: '2026-08-18 05:42'
updated_date: '2026-08-18 15:26'
labels:
  - feature-gate
milestone: m-6
dependencies:
  - TASK-485.19
parent_task_id: TASK-485
type: chore
ordinal: 755000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

文書内ジャンプ（TASK-485）は `FeatureGate.isDocumentJumpEnabled` で dev / DEBUG ビルドにだけ
露出している（`BefoldApp/befold/App/FeatureGate.swift:37`）。`FeatureGate` の doc コメント自身が
「stable 昇格時は該当機能の分岐を撤去してデフォルト有効化すること（撤去タスクを backlog 登録）」と
定めており、その撤去タスクがこれにあたる。

安定稼働を確認したうえでゲートを外し、stable ビルドでも見出し・変更ブロック・関数定義の
ジャンプが使えるようにする。

## 撤去対象（実測: `rg 'isDocumentJumpEnabled'`）

プロダクトコード 6 ファイル:

- `App/FeatureGate.swift:14-16, 37` — 名前付きプロパティと doc コメントの節
- `App/ViewerCapabilitiesFactory.swift:42`
- `App/MainMenuCoordinator.swift:71`
- `App/MainMenuBuilder.swift:23-30, 40, 125, 159` — 引数と `if isDocumentJumpEnabled` 分岐
- `App/HelpShortcutSections.swift:28-30` / `App/ViewerShortcutCatalog.swift:72-79`（`findOnlyItems` の要否も判断）
- `App/KeyboardShortcutsView.swift:7`
- `Viewer/ViewerCapabilities.swift:19, 58, 72, 80, 132`

テスト 7 ファイル（`MainMenuFixture` / `MainMenuBuilderTests` / `ViewerShortcutCatalogTests` /
`ViewerMenuValidatorTests` / `ViewerCapabilitiesTests` / `FeatureGateTests` /
`HelpShortcutSectionsTests`）。ゲート OFF を前提にしたケース（`MainMenuBuilderTests:267`、
`ViewerCapabilitiesTests:144, 171`、`ViewerShortcutCatalogTests` の closed 系）は
「ゲートが無くなった後に何を担保するか」を決めてから消す/書き換える。

## 判断が要る点（着手時に決めて Notes へ残す）

1. **`FeatureGate` 自体を残すか。** `isDocumentJumpEnabled` が唯一の名前付きプロパティのため、
   撤去すると `inProgressFeaturesEnabled` に呼び出し元が無くなる。TASK-510 で「最小構成で再導入」
   した経緯があるので、次の開発中機能のために枠だけ残すか、いったん消すかを明示的に決める。
2. **`ViewerCapabilities.swift:132` の `isDocumentJumpEnabled: false`。** ここは既定値として
   false を渡している箇所で、フラグを消すと `canJump` の値が変わる。何を意図した既定なのかを
   確認し、変わってよいのかを判断する。
3. **`ViewerShortcutCatalog.findOnlyItems`。** ゲート OFF 用の一覧なので、撤去後に使われなく
   なるなら一緒に消す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 stable ビルド（プレリリースでないバージョン）で編集メニューのジャンプ項目が表示され、実行できる
- [ ] #2 isDocumentJumpEnabled の参照がプロダクトコード・テストの両方から消えている（rg で 0 件）
- [ ] #3 上記「判断が要る点」の 3 点それぞれについて、決めた内容と理由が Implementation Notes に残っている
- [ ] #4 ゲート OFF を前提にしていたテストが、削除・書き換えのどちらであれ意図を説明するコメント付きで整理されている
- [ ] #5 ヘルプのショートカット一覧とメニューの乖離検知テストが通る（swift test）
<!-- AC:END -->
