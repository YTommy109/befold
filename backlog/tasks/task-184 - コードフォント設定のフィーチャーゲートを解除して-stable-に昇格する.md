---
id: TASK-184
title: コードフォント設定のフィーチャーゲートを解除して stable に昇格する
status: To Do
assignee: []
created_date: '2026-07-28 13:57'
updated_date: '2026-07-30 02:11'
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
- [ ] #1 設定メニュー・設定ウィンドウを露出する FeatureGate.inProgressFeaturesEnabled の分岐が撤去され、stable ビルドでもコードフォント設定が露出する
- [ ] #2 この機能に固有のフィーチャーゲート参照がコードベースから残らず消えている（他機能がゲートを使っていなければゲート機構自体の要否も検討する）
- [ ] #3 撤去後もフォント設定のユニットテスト・ライブ反映が従来どおり動作する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
重複タスクの整理（2026-07-30）。同内容の TASK-192 をアーカイブし本タスクへ一本化した。TASK-192 固有だった情報を以下に取り込む。

【ゲートの具体箇所】BefoldApp/befold/App/MainMenuBuilder.swift:35 の if FeatureGate.inProgressFeaturesEnabled。設定メニュー項目（About 直後の ⌘,）とセパレータを囲っている。プロダクトコードでの inProgressFeaturesEnabled の利用はこの 1 箇所のみ（FeatureGate.swift 自身の定義と FeatureGateTests を除く）。

【AC#2 の答え】FeatureGate 機構自体は撤去しない。TASK-186（サイドバー Git ステータス）が同じゲートを使う前提で、その解除タスク TASK-187 の説明にも FeatureGate 機構（TASK-180）が前提と明記されている。したがって本タスクで撤去するのは MainMenuBuilder のこの分岐だけで、FeatureGate.swift とそのテストは残す。

【TASK-193 への依存を追加した理由】codeFontSizePoints は現状ゲートなしで常時注入されており（既定 10pt≈12.3px）、stable でもソースビューのサイズがアクセシビリティ文字サイズに追従しなくなっている。本タスクで設定 UI を stable に露出させると、この追従喪失が正式な仕様として全ユーザーに影響する。TASK-193（追従を保つべきか、保つならサイズ注入をどう扱うか）の方針決定を先に済ませる必要があるため依存関係を張った。
<!-- SECTION:NOTES:END -->
