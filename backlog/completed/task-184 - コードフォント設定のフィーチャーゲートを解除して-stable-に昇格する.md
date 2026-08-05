---
id: TASK-184
title: コードフォント設定のフィーチャーゲートを解除して stable に昇格する
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-28 13:57'
updated_date: '2026-07-30 05:21'
labels: []
dependencies:
  - TASK-193
ordinal: 264000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-181 で実装したソースコードビューのフォント設定は、開発中は FeatureGate.inProgressFeaturesEnabled で囲われ dev/DEBUG ビルドのみに露出している（TASK-180 のゲート機構）。機能が安定したと判断した時点で、このゲート分岐を撤去し stable ビルドでも露出させる。フィーチャーゲートは一時的な足場であり撤去し忘れると stable に機能が出ないままになるため、解除忘れ防止として本タスクを登録する。着手条件: TASK-181 が完了し、フォント設定機能を stable リリースに載せてよいと判断できること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 設定メニュー・設定ウィンドウを露出する FeatureGate.inProgressFeaturesEnabled の分岐が撤去され、stable ビルドでもコードフォント設定が露出する
- [x] #2 この機能に固有のフィーチャーゲート参照がコードベースから残らず消えている（他機能がゲートを使っていなければゲート機構自体の要否も検討する）
- [x] #3 撤去後もフォント設定のユニットテスト・ライブ反映が従来どおり動作する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. MainMenuBuilder.swift:35 の if FeatureGate.inProgressFeaturesEnabled 分岐を撤去し、設定メニュー項目とセパレータを無条件に追加する
2. AppDelegate.swift:308 の「FeatureGate 有効時のみメニューに現れる」コメントを実態に合わせて修正する
3. FeatureGate.swift とそのテストは TASK-186/187 の前提として残す（AC#2 の方針は Implementation Notes 済み）
4. swift build / swift test --skip Integration --skip FileWatcherTests で確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
重複タスクの整理（2026-07-30）。同内容の TASK-192 をアーカイブし本タスクへ一本化した。TASK-192 固有だった情報を以下に取り込む。

【ゲートの具体箇所】BefoldApp/befold/App/MainMenuBuilder.swift:35 の if FeatureGate.inProgressFeaturesEnabled。設定メニュー項目（About 直後の ⌘,）とセパレータを囲っている。プロダクトコードでの inProgressFeaturesEnabled の利用はこの 1 箇所のみ（FeatureGate.swift 自身の定義と FeatureGateTests を除く）。

【AC#2 の答え】FeatureGate 機構自体は撤去しない。TASK-186（サイドバー Git ステータス）が同じゲートを使う前提で、その解除タスク TASK-187 の説明にも FeatureGate 機構（TASK-180）が前提と明記されている。したがって本タスクで撤去するのは MainMenuBuilder のこの分岐だけで、FeatureGate.swift とそのテストは残す。

【TASK-193 への依存を追加した理由】codeFontSizePoints は現状ゲートなしで常時注入されており（既定 10pt≈12.3px）、stable でもソースビューのサイズがアクセシビリティ文字サイズに追従しなくなっている。本タスクで設定 UI を stable に露出させると、この追従喪失が正式な仕様として全ユーザーに影響する。TASK-193（追従を保つべきか、保つならサイズ注入をどう扱うか）の方針決定を先に済ませる必要があるため依存関係を張った。

MainMenuBuilder.swift の if FeatureGate.inProgressFeaturesEnabled 分岐を撤去し、Settings…(⌘,)とセパレータを無条件追加に変更。AppDelegate.showSettings のドキュメントコメントから「FeatureGate 有効時のみ」の記述を削除。回帰防止として MainMenuBuilderTests に appMenuHasSettingsItem を追加（ゲートに依存せず ⌘, とセレクタを検証）。FeatureGate.swift とそのテストは TASK-186/187 の前提として意図的に残す（プロダクトコードでの参照は 0 箇所になった）。検証: swift build 成功、swift test --skip Integration --skip FileWatcherTests で 787 tests / 105 suites 全pass、swift test --filter CodeFont で 8 tests pass。ライブ反映（設定変更→全ウィンドウ反映）の GUI 手動確認は未実施（showSettings/onChange の経路は無変更）。

GUI 実機確認(Debug ビルド, xcodebuild -configuration Debug): (1) 起動中プロセスの App メニューを System Events でダンプし「設定…」の存在を確認。(2) メニューから設定を開きサイズ Stepper を 11→12→11 と操作、一時 NSLog で applyCodeFontToAllWindows windows=2 / applyCodeFont family=HackGen points=12.0 webView=yes ×2 を確認（開いていた 2 ウィンドウ両方の生存 WebView へ即時注入）。一時 NSLog は撤去済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
設定メニュー項目(⌘,)を囲っていた FeatureGate.inProgressFeaturesEnabled の分岐を MainMenuBuilder から撤去し、コードフォント設定を stable ビルドでも露出させた。FeatureGate 機構自体は TASK-186/187 の前提として残置（プロダクトコードでの参照は 0 箇所）。回帰防止に MainMenuBuilderTests.appMenuHasSettingsItem を追加。検証: swift test --skip Integration --skip FileWatcherTests で 787 tests / 105 suites 全pass、Debug 実機で「設定…」のメニュー露出と 2 ウィンドウへのフォント即時反映を NSLog で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
