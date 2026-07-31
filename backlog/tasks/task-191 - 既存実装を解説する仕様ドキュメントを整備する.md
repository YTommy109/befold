---
id: TASK-191
title: 既存実装を解説する仕様ドキュメントを整備する
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-28 14:40'
updated_date: '2026-07-31 02:15'
labels: []
dependencies: []
ordinal: 266000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold の既存実装について、オーナー（ユーザー）が全体像を把握できる解説型の仕様ドキュメントを整備する。現状コードは把握しづらい箇所があるため、「今どう動いているか」を読んで理解できることを目的とする。

## 動機
機能が充実する一方で、実装の詳細（各サブシステムの責務・データフロー・実現方法）をオーナーが十分に把握できていない。後からの意思決定・レビュー・引き継ぎのために、現状を説明するドキュメントが欲しい。

## 期待する内容の例
- QuickLook 拡張の仕様と実現方法（appex 構成・サンドボックス制約・RendererFeatures・描画完了検知など）
- ファイルの種類ごとのビューアの違いとデータフロー（.mmd / .md / ソースコード等で、どの経路・どのレンダラ・どの資産を通るか）
- ファイル監視 → ViewerStore → WebView の伝搬、CLI 起動経路 など主要フロー

## 図の要望
必要に応じて mermaid 図（フロー図・シーケンス図・コンポーネント図）を用いて分かりやすくする。CLAUDE.md の Markdown 依存ディレクティブ方針にも従う。

## 注記
本タスクはまず「どんなドキュメントがあると良いか」の構成提案から入る（受け入れ条件参照）。提案をオーナーが確認・合意してから本文の執筆に進む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 「どんなドキュメントを用意すべきか」の構成案（ドキュメント一覧・各文書の目的と対象範囲・優先順位）を提案し、オーナーの合意を得る
- [x] #2 合意した構成に基づき、既存実装を解説するドキュメントを作成する
- [x] #3 QuickLook の仕様と実現方法が説明されている
- [x] #4 ファイルの種類ごとのビューアの違いとデータフローが説明されている
- [x] #5 必要な箇所で mermaid 図が使われ、図とテキストが整合している
- [x] #6 ドキュメント内の文書間・セクション間依存が CLAUDE.md の Markdown 依存ディレクティブで記述されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 既存 docs/dev の解説文書と実装ターゲット構成を調査し、カバー済み領域と欠落領域を洗い出す（完了）
2. 「どんな解説ドキュメントを用意すべきか」の構成案（文書一覧・目的・対象範囲・優先順位）を提案し、オーナーの合意を得る（AC#1）
3. 合意後、各文書を執筆（AC#2-#5）: QuickLook 仕様 / ファイル種別ごとのビューア差異とデータフロー / CLI 起動経路 / 監視→Store→WebView 伝搬。必要箇所に mermaid 図
4. 文書間・セクション間依存を Markdown 依存ディレクティブで記述（AC#6）
5. 既存 native-app-design.md の実装乖離（多ターゲット構成・Sparkle 整合性）を現状に合わせて更新
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証: 3新規文書(quicklook.md / viewer-rendering-dataflow.md / cli-launch.md)の型名・関数名・パス・定数・mermaid図の流れをサブエージェントが BefoldApp/ 実コードと全件照合し誤りなしを確認。dagayn build で cross-artifact 依存ディレクティブが unresolved 0 で解決することを確認(AC#6)。既存 native-app-design.md の実装乖離(旧3ターゲット構成→多ターゲット、自前アップデータ→Sparkle 2、UpdateCheckCoordinator/CLIInstaller の記述)を現状へ更新。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
既存実装を解説する開発ドキュメント群を整備。構成案を提示しオーナー合意(4文書: 総覧更新+QuickLook+ビューア描画データフロー+CLI起動経路)を得たうえで、docs/dev/ に quicklook.md・viewer-rendering-dataflow.md・cli-launch.md を新規作成し、native-app-design.md を索引ハブ兼現状反映へ更新。QuickLook拡張(appex構成/サンドボックス/ViewerRenderer共有/OneShot完了検知)、ファイル種別ごとのビューア差異とデータフロー、監視→Store→WebView→JS の一気通貫、CLI起動ワイヤプロトコルを mermaid 図付きで解説。文書間依存は Markdown 依存ディレクティブで記述。記述内容はサブエージェントが実コードと照合し誤りなし、依存ディレクティブは graph 上 unresolved 0 で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
