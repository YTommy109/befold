---
id: TASK-242
title: ウィンドウ系テストのフルウィンドウ+WKWebView 生成を注入シームで軽量化する
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-01 10:44'
updated_date: '2026-08-01 12:55'
labels: []
dependencies: []
priority: high
type: task
ordinal: 200000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CI レビューで、befoldTests のウィンドウ系スイート(ViewerWindowController* / ViewerWindowManager* / MockedViewerWindowManager 経由)がテストごとに実 NSWindow + NSToolbar + NSSplitViewController + NSHostingView + 実 WKWebView(viewer.html ロード、WebContent 子プロセス起動)をフル構築しており、概算 120 回・すべて @MainActor 直列で swift test(CI キャッシュ有効時 ~69s)の支配項になっていると判明した。
モデル状態しか見ないテスト(例: ViewerWindowControllerTests.swift:180-186 historyStartsEmpty)にも WebView は不要。
ViewerWindowController.init(BefoldApp/befold/App/ViewerWindowController.swift:173-227)に makeContentViewController 注入(または contentless モード)のシームを設け、WebView 検証が本質のテスト(ツールバーのライブアイテム系等)だけ既定経路を使う。
あわせて 6 スイートに散在する同型コントローラファクトリ(5 ストア構成 PerFileStateStore の全展開が ViewerWindowControllerTests.swift:231-237 / CLIOptionsTests:23-29,46-52 / SourceModeTests:33-39 / IntegrationTests:27-33 で重複)を共有フィクスチャへ集約すると、シーム導入の変更箇所が 1 箇所で済む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 モデル状態のみを検証するウィンドウ系テストが WKWebView 生成・viewer.html ロードなしで実行される
- [x] #2 WebView が本質のテストは引き続き実描画経路で検証される
- [x] #3 コントローラ生成ファクトリが共有フィクスチャへ集約される
- [ ] #4 swift test が全てグリーンで、CI の swift test ステップ時間の短縮が実測で確認できる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
設計調査完了(レビューエージェントによる全対象ファイル読み合わせ済み)。詳細はセッション成果物 task-242-brief.md。
1. シーム: makeContentView: (() -> AnyView)? = nil を ViewerWindowController.init に追加(content ペインのみ差し替え。split VC / FileListView / toolbar / SidebarNavigator は実物維持なので既存テストの依存配線は壊れない。webViewProxy.webView は nil のままだが参照するテストは無いことを確認済み)。makeSplitViewController を contentOverride 引数化。ViewerWindowManager にも貫通(プロパティ+init+openViewer)
2. 割り振り: コントローラ直生成 5 スイート+manager 系はシーム利用。ViewerRendererOneShotTests の実描画 3 本は実 WebView 維持。実経路のカナリアとして「シーム nil でウィンドウが構築できる」スモークテストを Integration に追加
3. 共有フィクスチャ: befoldTests/ViewerWindowControllerFixture.swift 新設(makeIsolatedDefaults 1 個共有、5 フィールド PerFileStateStore の組み立てを 1 箇所へ、realFileSystem フラグで InMemory/実 FS を切替、placeholderViewerContent() を Mocked 側とも共用)
4. 手順: フェーズ A(プロダクトシーム、テスト無変更でグリーン) → B(既存ファクトリへ 1 行追加で速度効果) → C(ファクトリ集約、挙動不変)。各フェーズ末に swift test 全体。コミットは A+B / C の 2 つ
5. 計測: ローカル swift test の before(全体 14.2s、ViewerWindowControllerTests 11.3s 等)/after を記録。CI 実測は PR で確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
コミット: c690096(フェーズA+B シーム導入) / 4b02124(フェーズC フィクスチャ集約) / dfb1ef6(レビュー修正)。
設計判断:
- シームは当初案の makeContentViewController(split VC ごと差し替え)ではなく makeContentView: (() -> AnyView)? = nil(content ペインのみ差し替え)を採用。split VC ごと差し替えると sidebarCollapsible が nil になり DisplayOverrides のサイドバー開閉テストが壊れるため。FileListView / split VC / toolbar / SidebarNavigator は実物のまま維持され、既存テストの依存配線は無傷
- 既定 nil が本番経路(実 WKWebView 生成)。共有依存のデフォルト禁止規約とは向きが逆のため、doc には「テスト専用シーム / 既定 nil は本番経路」を明記する形で書き分けた
- ViewerWindowControllerFixture を新設し、makeIsolatedDefaults 1 個共有・5 フィールド PerFileStateStore の組み立てをリポジトリ内 1 箇所へ集約。MockedViewerWindowManager とは統合せず役割分担(manager 経由パイプライン検証 vs コントローラ単体)
- 実経路のカナリアとして defaultContentPathBuildsWindow を Integration に追加し、既定 init で実 WKWebView 経路が組み上がることを固定
- プレースホルダ経路では webViewProxy.webView が nil のままとなり WebViewCommandController 経由(検索・印刷・ズーム)が静かに no-op になるため、対象 6 スイートのヘッダに「WebView 依存の検証をここに置かない」旨を明記
計測(レビュー担当の独立実測と一致): ViewerWindowControllerTests は --filter 単独実行で 11.3s→1.93s(約 83% 短縮)。フル swift test 内では他スイートとの並列競合に律速され 10.171s、全体は 14.2s→13.3s(全体の律速は本タスク範囲外の GitCommandRunnerTests)。
検証: swift build 警告なし、swift test 1007 tests/134 suites グリーン(実装者・レビュー担当の双方が実行)、ViewerRendererOneShotTests は差分ゼロで実 WebView 検証を維持。

AC #4 の CI 実測は未 push のため保留。PR 作成後に build-and-test の swift test ステップ時間を確認して確定する(ローカル実測は完了済み)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWindowController に makeContentView シーム(既定 nil = 本番経路)を導入し、ウィンドウ系テストのコンテンツペインをプレースホルダへ差し替えて実 WKWebView + viewer.html ロードを排除した。あわせて 6 スイートに散在していたコントローラ生成を ViewerWindowControllerFixture へ集約し、隔離 defaults の重複生成と 5 フィールド PerFileStateStore の 4 箇所重複を解消した。
効果: ViewerWindowControllerTests が単独実行で 11.3s→1.93s(約 83% 短縮)。フル実行では並列競合に律速され全体は 14.2s→13.3s。
安全策: 実描画を検証する ViewerRendererOneShotTests は無変更、実経路カナリア defaultContentPathBuildsWindow を追加、プレースホルダ経路で no-op になる WebView 依存検証を置かない旨を対象スイートのヘッダに明記。
検証: swift build 警告なし、swift test 1007 tests グリーン(実装者・レビュー担当が独立に実行)、レビュー承認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
