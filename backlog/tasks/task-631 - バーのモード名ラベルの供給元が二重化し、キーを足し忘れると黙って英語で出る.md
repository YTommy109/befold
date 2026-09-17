---
id: TASK-631
title: バーのモード名ラベルの供給元が二重化し、キーを足し忘れると黙って英語で出る
status: Done
assignee:
  - '@claude'
created_date: '2026-09-17 04:41'
updated_date: '2026-09-17 04:58'
labels: []
dependencies:
  - TASK-630
references:
  - 'https://github.com/YTommy109/befold/pull/678'
documentation:
  - docs/dev/native-app-design.md
modified_files:
  - BefoldApp/viewer-src/bar-mode.ts
  - BefoldApp/BefoldKit/Resources/Localizable.xcstrings
  - BefoldApp/befoldTests/ViewerBridgeContractTests.swift
priority: medium
type: chore
ordinal: 828000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`viewer-src/bar-mode.ts` の冒頭には「**モードの列挙はこの配列（MODES）だけが持つ**」と明記されている。かつて currentMode() が `kind === "heading" || kind === "changeBlock"` と独立に列挙しており、Swift 側が DocumentJumpKind.allCases で自動追随するのに JS だけ取り残される形だったのを潰した結論（TASK-485.4 の設計レビュー）。

PR #678 がラベルの供給元を増やしたため、この不変条件が破れている。5 つ目のモードを足すときに触る場所が MODES / MODE_BUTTON_IDS / viewer.html のボタン / Localizable.xcstrings の viewer.mode.* / ViewerBridge.uiStringsScript の辞書 / viewer-globals.d.ts の ViewerUIStrings の 6 箇所になった。しかも `applyModeLabel` は `if (!label) return;` で早期 return するため、**キーを足し忘れると viewer.html の静的な英語ラベルのまま黙って出る**（PR #678 で静的フォールバックが日本語から英語に変わったので、日本語環境でも英語が出る）。

新設の契約テスト ViewerBridgeContractTests.uiStringsKeysAreReadInJS は「Swift が注入したキーが JS で読まれているか」の片方向しか見ておらず、この逆方向の漏れは捕まえない。CLAUDE.md の「決めたことには、破れたら落ちるものを付ける」に該当する。

あわせて Localizable.xcstrings の comment を補う。既存 22 キー中 11 件に comment があり、付与基準は (a) 他所と一致していないと壊れる契約（viewer.find.close の「Esc は viewer.html の keydown ハンドラと一致させること」など 5 件）と (b) 訳文だけでは用途が分からないもの（viewer.jump.headingLevel、viewer.pdf.pageIndicator など）の 2 種類。今回の新規キーでは viewer.mode.* が (a)（キー末尾が bar-mode.ts の BarMode と MODE_BUTTON_IDS、および Swift の DocumentJumpKind.rawValue と一対一でなければ黙って英語に落ちる）、viewer.diagram.zoomReset が (b)（"Click to Reset" だけでは何をクリックするか分からない。実体はズーム率を出す span 要素 .diagram-zoom-label の tooltip）に当たる。viewer.diagram.zoomIn / zoomOut は訳文が用途そのものなので不要。

`docs/dev/native-app-design.md` の「## 表示仕様」→「検索・文書内ジャンプの統合バー（TASK-485.19）」は「モードの列挙は bar-mode.ts の MODES だけが持つ」と書いており、実態とずれたままになっている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 MODES に新しいモードを足して xcstrings のキーを足し忘れた状態にすると、Swift のテストが落ちる
- [x] #2 ラベル適用の呼び出しが MODES の要素を個別に書き並べておらず、モードの列挙を再記述していない
- [x] #3 viewer.mode.* の 4 キーと viewer.diagram.zoomReset に、既存キーと同じ基準の comment が付いている
- [x] #4 docs/dev/native-app-design.md の統合バーの節が、モード名ラベルの供給元が Localizable.xcstrings であることに追随している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. uiStrings のモード名を modes 辞書に畳み、JS は MODES.forEach 内で strings.modes[key] を引く（列挙の再記述を消す）
2. Swift 側のモード一覧は DocumentJumpKind が BefoldKit から見えないため ViewerBridge.barModes に置き、契約テストで JS の MODES と集合一致・全モードが訳されている（キーそのものに落ちていない）ことを検査
3. xcstrings の viewer.mode.* と viewer.diagram.zoomReset に comment を付与
4. native-app-design.md の統合バーの節を追随
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
モード名ラベルを window._mmdUIStrings.modes に畳み、bar-mode.ts は既存の MODES.forEach の中で引く形にして列挙の再記述を削除。Swift 側のモード一覧は DocumentJumpKind が BefoldKit から見えないため ViewerBridge.barModes に置き、契約テスト barModesMatchJSAndAreLocalized が viewer-bundle.js の MODES との集合一致と en/ja の viewer.mode.* の訳の存在を検査する。変異確認: MODES にだけ追加→集合不一致と訳なしで失敗、両方に追加して訳なし→訳なしで失敗。xcstrings の viewer.mode.* 4 キーと viewer.diagram.zoomReset に comment を付与し、native-app-design.md の統合バーの節を追随。swiftlint の main 差分で PR 由来の type_body_length 超過（ViewerBridgeTests）が出たため、uiStrings のテストを ViewerBridgeContractTests へ移して解消。
<!-- SECTION:FINAL_SUMMARY:END -->
