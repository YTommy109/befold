---
id: TASK-384
title: 紹介サイトのキーボードショートカット表示を実装と同期させる
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-08 14:09'
updated_date: '2026-08-09 01:53'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 642000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
紹介サイト（site/）は LP と TASK-376 で追加する詳細ページの双方で、キーボードショートカット（cmd+P / cmd+S / cmd+U / cmd+L / cmd+F / cmd+[ / cmd+] など）を手書きで記載している。実装側の割り当て（BefoldApp の MainMenuBuilder ほか）を変更しても site 側は落ちないため、ずれても気づけない二重管理になっている。

TASK-376 では対応ファイルタイプ表について FileType.swift を情報源としたずれ検知テストを導入した（site/test/file-types.test.ts）。同じ手口をショートカットにも適用する。

TASK-376 の /review-design で『AC は対応ファイルタイプ表のみを要求しており、Swift 側の解析対象をもう 1 系統増やすとスコープが広がる』として分離したもの。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 site 側に記載したショートカットが実装の割り当てとずれた場合に落ちるテストがある
- [x] #2 検証対象は LP と詳細ページの両方をカバーする
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. site/src/lib/shortcuts.ts を新設し、MainMenuBuilder.swift から keyEquivalent 付きの addLocalizedItem 呼び出しを総当たりで抽出するパーサと、MenuShortcutCatalog.keyDisplay と同じ ⌃⌥⇧⌘ 順の表記生成、散文からショートカット表記を拾うヘルパーを置く。
2. vitest.config.ts に MainMenuBuilder.swift / BookmarkShortcut.swift を読むバインディングを追加（file-types と同じ経路。フォールバックは置かない）。test/env.d.ts に型を追加。
3. test/shortcuts.test.ts:
   (a) 抽出結果の全件（ローカライズキー・キー等価式・修飾キー）を期待リストと toEqual で突き合わせ、実装側の増減・変更を必ず可視化する（file-types.test.ts の EXPECTED_DECLARATIONS と同じ手口）。
   (b) 詳細ページの SHORTCUTS の各キーが実装の stable 表記集合に含まれることを検証。フィーチャーゲート内の項目・表示モード（キー等価が計算値）は期待リストで分類し、site に載っていたら落とす。
   (c) LP（FEATURES / MORE_FEATURES / landing の description）と詳細ページの note 散文に現れるショートカット表記が SHORTCUTS に載っていることを検証（AC #2）。
4. file-types.ts の note にある 'cmd+L' を '⌘L' へ統一（他は全て記号表記で、この 1 箇所だけ検出漏れになるため）。
5. features.tsx の『ずれ検知は TASK-384 で入れる』コメントを実態に合わせて更新。
6. .github/workflows/site.yml の paths に情報源の Swift ファイルを追加し、Swift 側だけの変更でもずれ検知が CI で回るようにする。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
site/src/lib/shortcuts.ts に MainMenuBuilder.swift 用のパーサを追加し、test/shortcuts.test.ts で 3 層に突き合わせた。

- キー等価を持つ addLocalizedItem 呼び出しの全件（ローカライズキー・キー等価式・修飾キー）を期待表と toEqual。実装側の増減・変更は必ずここに現れる。
- サイトの表・ページ描画結果と突き合わせる集合は、期待表ではなく**パース結果**から作る。期待表から作ると実装を変えたときに全件比較だけしか落ちず、サイトとの突き合わせがすり抜ける（実測で確認して直した）。
- フィーチャーゲート内かどうかは GATED_LOCALIZATION_KEYS で分類する。ソースの if FeatureGate ブロックを解析する方式は、⌘4 が guard isSourceDiffEnabled の内側にあるなど形が一定でないため採らなかった。全件比較が更新を強制するので、分類漏れは黙って通らない。

パーサの実装上の注意（実測で 2 回踏んだ）:
- 呼び出しは 'addLocalizedItem(' の閉じ括弧までで切る。切らないと、キー等価を持たない項目（menu.app.installCLI）が後続の NSMenuItem(... keyEquivalent: "") を拾う。
- 引数の走査で文字列リテラルの中身を飛ばす。飛ばさないと "[" / "," の記号を区切りと誤認する。

判定の実測（ミューテーション）:
- MainMenuBuilder の toggleSidebar を "s"→"k": 4 件失敗
- features.tsx の SHORTCUTS を ⌘U→⌘Y: 3 件失敗
- shared.tsx の LP 訴求文を ⌘S→⌘Y: 3 件失敗（LP 経路が効いていることの確認）

付随して直したもの:
- file-types.ts の note にあった 'cmd+L' を '⌘L' へ統一（サイトで唯一の ASCII 表記で、記号ベースの検出から漏れていた）。
- .github/workflows/site.yml の paths に情報源の Swift 5 ファイルを追加。従来は site/** の変更でしか回らず、Swift 側だけを変えるとずれ検知が CI で動かなかった（TASK-376 で入れた対応ファイルタイプ表の検知も同じ穴を持っていた）。

検証: site で npx tsc --noEmit（エラーなし）、npx vitest run（8 files / 113 tests すべて成功）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
紹介サイトのキーボードショートカット表記を MainMenuBuilder.swift と突き合わせるテストを追加した。Swift のメニュー定義からキー等価付きの項目を全件パースし、(1) 項目一覧の全件比較、(2) 詳細ページの表、(3) LP と詳細ページの描画結果に現れる表記、の 3 方向で照合する。フィーチャーゲート内の項目と表示モード（キーが実行時に決まる）は分類して除外する。検証は site の vitest（113 tests 成功）と、実装・表・LP 訴求文それぞれを 1 箇所ずらすミューテーションで所定のテストが落ちることを実測。
<!-- SECTION:FINAL_SUMMARY:END -->
