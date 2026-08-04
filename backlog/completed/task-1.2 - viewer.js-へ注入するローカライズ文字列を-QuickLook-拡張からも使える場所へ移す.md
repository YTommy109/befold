---
id: TASK-1.2
title: viewer.js へ注入するローカライズ文字列を QuickLook 拡張からも使える場所へ移す
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 00:38'
updated_date: '2026-07-18 10:57'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/210
parent_task_id: TASK-1
priority: medium
ordinal: 6200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #210 から移行。Localizable.xcstrings が app ターゲット側にのみ存在し、viewer.js へ注入する検索バー・バナー文言に QuickLook 拡張から届かない。BefoldKit 側の xcstrings へ移すか、QuickLook 拡張ターゲットに必要キーのみ複製する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 viewer.js/viewer.html へ注入する文言キーが QuickLook 拡張からアクセスできる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. banner.*/viewer.find.* の計11キーを befold/Resources/Localizable.xcstrings から BefoldKit/Resources/Localizable.xcstrings へ移動する(重複させず所有権を移す)。BefoldKit は project.yml で Resources/ 配下を丸ごと resources 化しているため project.yml 変更は不要。Package.swift の BefoldKit target resources に .process("Resources/Localizable.xcstrings") を追加する。
2. BefoldKit/ViewerBridge.swift の bannerStringsScript/findStringsScript のデフォルト引数を bundle: Bundle = .main から bundle: Bundle = .befoldKitResources に変更する(BefoldKit 自身が持つ文字列を自身のバンドルから読む形にする)。
3. befold/Viewer/ViewerWebView.swift の呼び出し箇所(81-92行目)から bundle: .l10n 指定を除去し、ViewerBridge 側のデフォルト(.befoldKitResources)に委ねる。
4. befoldTests/ViewerBridgeTests.swift の bundle: .l10n 参照(3箇所)を除去しデフォルト引数を使うよう更新する。
5. befoldTests/LocalizationTests.swift の訳漏れ検証を BefoldKit 側カタログにも適用できるよう一般化する(bundle をパラメータ化)か、同等のテストを追加し、移動後も en/ja 訳の完全性を担保する。
6. swift build / swift test で回帰確認する。QuickLook 拡張は未実装のため実機確認は不要、AC は「アクセス可能な場所にある」という配置の観点で満たす。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
banner.*/viewer.find.* の計11キーを befold/Resources/Localizable.xcstrings から BefoldKit/Resources/Localizable.xcstrings へ移設(複製せず所有権移動)。ViewerBridge.bannerStringsScript/findStringsScript のデフォルト bundle を .main から .befoldKitResources に変更し、ViewerWebView.swift の呼び出し側は bundle: .l10n 指定を削除してデフォルトに委ねる形にした。BefoldKit は project.yml で Resources/ を丸ごと resources 化しているため project.yml 変更は不要、Package.swift の BefoldKit target に .process("Resources/Localizable.xcstrings") を追加した。LocalizationTests を bundle パラメータ化し、BefoldKit 側カタログの訳漏れも検証するようにした。QuickLook 拡張ターゲット自体は本タスクの範囲外(未実装)のため、実機での拡張アクセス確認はできないが、BefoldKit(拡張からもリンク可能なフレームワーク)側にキーを配置したことでアクセス可能な構造になった。検証: swift build 成功、swift test 369件全通過(LocalizationTests/ViewerBridgeTests 含む)、npx jest 193件全通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer.js/viewer.html 注入用のローカライズ文字列(banner.*/viewer.find.* 計11キー)をアプリ本体の Localizable.xcstrings から BefoldKit/Resources/Localizable.xcstrings へ移設し、ViewerBridge が自身のバンドル(.befoldKitResources)から読むよう変更した。これにより QuickLook 拡張が BefoldKit をリンクするだけでこれらの文言にアクセスできる構造になった。swift build / swift test(369件) / npx jest(193件)で回帰確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
