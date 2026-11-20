---
id: TASK-911
title: 空タブからの Quick Open などでも空タブを置き換える
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T06:38:00Z'
updated_date: '2026-11-07T07:56:00Z'
labels:
  - tabs
  - ui
dependencies:
  - TASK-910
references:
  - BefoldApp/befold/App/QuickOpenCoordinator.swift
  - BefoldApp/befold/App/ActiveViewerProvider.swift
priority: medium
ordinal: 877000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
空タブで ⌘P からファイルを開くと、空タブが残ったまま別の窓が開く（2026-11-07 実機確認）。⌘O とドロップは空タブを置き換えるので、⌘T → ⌘P という自然な操作だけ結果が違う。`ActiveViewerProvider.fromMainWindow` が `ViewerWindowController` へキャストするため、空タブでは操作対象の窓が無い扱いになることが原因。Open Recent とブックマークも同様と思われるが未確認。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 空タブで Quick Open からファイルを開くと、その空タブが置き換わる
- [x] #2 Open Recent とブックマークの空タブでの動作を確認し、置き換えるか現状のままかを決めて docs/dev/viewer-ui.md に記載している
- [x] #3 空タブの ⌘O と Quick Open が候補や初期ディレクトリの基準にする文書が、タブグループの文書との関係も含めて決まっている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
方針: UI から開く経路（Quick Open / Open Recent / ブックマーク）は DocumentOpener.openViewer(for:focusesContent:) に集まっているので、そこで手前の空タブを起点にして置き換える。Finder / CLI（openSequentially）は外部からの要求なので変えない。
1. ActiveViewerProvider に手前の空タブを引く blankTabFromMainWindow を足し、DocumentOpener と QuickOpenCoordinator へ注入する
2. presentOpenPanel の keyWindow 判定もこの入口へ揃える
3. ⌘O の初期ディレクトリと Quick Open の候補の起点は、空タブのサイドバーのフォルダ。サイドバーが無ければ従来どおり（ホーム / 履歴とブックマークだけ）
設計レビュー: 新しい経路は増やさず既存の 1 点へ寄せる。AppDelegate のサイドバー表示メニューは文書タブ用で、空タブでは無効のまま。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
決定: Quick Open・Open Recent・ブックマーク（UI から開く経路）は手前の空タブを置き換える。Finder と CLI は外部からの要求なので置き換えない。⌘O の初期フォルダと Quick Open の候補の起点は空タブのサイドバーのフォルダで、不可視ファイルの設定も空タブの現在値を読む。サイドバーが無ければ従来どおり。Open Recent とブックマークは DocumentOpener.openViewer(for:) を共有するのでコードで確認した（実機未確認）。
責務レビュー: quickOpenAnchor の存在しないファイル名は全読み手が親フォルダとして読むので問題なし。指摘のとおり不可視ファイルの読み先を直し、openInNewWindow を openWithoutViewer へ改名した。
実測: 置き換えを外すと uiRouteReplacesActiveBlank が落ちる。swift test 1984 件 + PDF 103 件成功、xcodebuild 成功、swiftlint 新規 0 件。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Quick Open・Open Recent・ブックマークから開くと手前の空タブを置き換えるようにした。Finder と CLI は置き換えない。⌘O と Quick Open の起点は空タブのサイドバーのフォルダ。実機確認は未実施。
<!-- SECTION:FINAL_SUMMARY:END -->
