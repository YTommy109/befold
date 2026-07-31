---
id: TASK-202
title: About 画面に OGP 画像を入れて見栄えを整える
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 02:01'
updated_date: '2026-07-31 02:47'
labels: []
dependencies: []
references:
  - public/images/ogp.png
ordinal: 285000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在の About 画面はデフォルトの簡素な表示のままで、アプリの世界観を伝えられていない。OGP 用に用意した（または用意する）画像素材を About 画面に組み込み、ブランディングとして見栄えを整える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 About 画面にアプリのビジュアル（OGP 画像相当）が表示される
- [x] #2 ライトモード・ダークモード双方で崩れずに表示される
- [x] #3 画像サイズ・レイアウトがウィンドウリサイズや高DPI環境で破綻しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. site/public/images/ogp.png を BefoldApp/befold/Resources/AboutOGP.png としてバンドルに追加する(project.yml の befold/Resources リソースフェーズは既存 excludes 以外全て拾うため追加設定不要)。
2. AboutWindowController(NSWindowController, 単一インスタンス)を新設し、CodeFontSettingsWindowController と同じ showAndActivate()/toggle() パターンで実装する。中身は SwiftUI AboutView。
3. AboutView は Image(nsImage:).resizable().aspectRatio(contentMode:.fit) で OGP 画像を表示し、下に AboutPanelCredits 相当のテキスト(アプリ名・バージョン・Copyright リンク)を配置する。画像は Material 背景付きカードに乗せてライト/ダーク双方で縁が破綻しないようにする。
4. AppDelegate.showAbout を NSApp.orderFrontStandardAboutPanel(...) から aboutWindowController.toggle() に差し替える(showSettings と同様に lazily キャッシュ)。
5. ウィンドウに minWidth/minHeight を設定し、リサイズ・Retina(1200x630 の元画像で高DPI相当の解像度は確保済み)で崩れないことを手動確認する。
6. ライトモード/ダークモードそれぞれで手動起動確認(GUI領域のため自動テスト対象外、CLAUDE.md の完了基準に従う)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
OGP 画像素材は public/images/ogp.png に配置済み。

OGP画像(site/public/images/ogp.png)を BefoldApp/befold/Resources/AboutOGP.png としてバンドルし、Package.swift の resources に追加。CodeFontSettingsWindowController と同じ単一インスタンス toggle パターンで AboutWindowController/AboutView を新設し、AppDelegate.showAbout の遷移先を標準 About パネルからこれに切替。ユーザー要望で NSApp.applicationIconImage も併記(OGPカードの下にアプリアイコン+名前+バージョン+Copyrightリンク)。旧 AboutPanelCredits.swift/テストは呼び出し元がなくなったため削除。検証: swift build / swift test (847 tests, 全 pass)。GUI手動確認: xcodebuild でビルドし About ウィンドウをスクリーンショット確認(ライトモード/ダークモード双方でレイアウト崩れなし、リサイズ耐性のある aspectRatio(.fit) レイアウト)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
About 画面に OGP 画像とアプリアイコンを組み込んだカスタム About ウィンドウを実装。標準の NSApp.orderFrontStandardAboutPanel を置き換え、CodeFontSettingsWindowController と同じ単一インスタンスウィンドウパターンで実装。ライト/ダーク双方、リサイズ耐性をスクリーンショットで確認済み。swift test 847件全て pass。
<!-- SECTION:FINAL_SUMMARY:END -->
