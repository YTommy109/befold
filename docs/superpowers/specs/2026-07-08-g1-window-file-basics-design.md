---
title: ウィンドウ/ファイル操作の基本動作改善（G1）
date: 2026-07-08
status: approved
---

<!-- constrained-by ../plans/2026-07-08-ui-ux-improvements-roadmap.md#g1-ウィンドウファイル操作の基本動作優先度-高 -->

## 概要

`docs/superpowers/plans/2026-07-08-ui-ux-improvements-roadmap.md` の G1 グループに
含まれる3項目（#1, #2, #6）を実装する。

1. ファイルを開いた際にアプリ／ウィンドウがアクティブにならない不具合を修正する
2. cmd+o の初期ディレクトリをウィンドウ単位で記憶し、記憶が無いウィンドウではホームディレクトリを使う
3. サイドバーの「パスをコピー」を絶対パスではなく現在ディレクトリからの相対パスにする

## 1. ファイルを開いた時にアクティブウィンドウにならない

### 現状

`ViewerWindowManager.openViewer(for:forceSidebarVisible:)`
(`BefoldApp/befold/App/ViewerWindowManager.swift:20-44`) は、既存ウィンドウなら
`existing.window?.makeKeyAndOrderFront(nil)`、新規ウィンドウなら
`controller.showWindow(nil)` を呼ぶが、いずれも **アプリ自体をアクティブ化する
`NSApp.activate()` 相当の呼び出しを行わない**。

`applicationDidFinishLaunching` (`AppDelegate.swift:64`) では起動時に一度だけ
`NSApp.activate()` を呼んでいるが、`application(_:open:)`（Finder からのファイル
オープン・Dock ドロップ）や `showOpenPanel` 経由のオープンではこの呼び出しが
無いため、他アプリがアクティブな状態でファイルを開くとウィンドウが背後に
留まることがある。

### 変更方針

`ViewerWindowManager.openViewer(for:forceSidebarVisible:)` の両分岐
（既存ウィンドウ・新規ウィンドウ）の直前で `NSApp.activate()` を呼ぶ。
ここに1箇所集約することで、`application(_:open:)` / `openViewer(for:)` /
`showOpenPanel` / cmd+click によるファイル参照オープンなど、すべての
オープン経路を単一の変更でカバーする。

### テスト方針

`NSApp.activate()` は実際の `NSApplication` singleton とウィンドウサーバの
状態に依存するため、Swift Testing のユニットテストでは検証できない
（プロジェクトの既存方針: WebView/GUI 層は自動テスト対象外）。
このタスクはコードレビューでの確認とし、手動での動作確認手順を
実装計画に明記する。

## 2. cmd+o のディレクトリをウィンドウ単位で記憶

### 現状

`AppDelegate.showOpenPanel()` (`AppDelegate.swift:127-136`) は
`NSOpenPanel` の `directoryURL` を設定していない。ウィンドウ単位で
最後に使ったディレクトリを保持する仕組みも存在しない。

### 変更方針

- `ViewerWindowController` に `var lastOpenDirectory: URL?` を追加する
  （デフォルト `nil`）。
- 新規の純粋関数 `OpenPanelDirectoryResolver.resolve(lastOpenDirectory:homeDirectory:)`
  を追加し、「記憶されたディレクトリがあればそれを、無ければホーム
  ディレクトリを返す」ロジックをユニットテスト可能な形で切り出す。
- `AppDelegate.showOpenPanel()` は、`NSApp.keyWindow?.windowController as?
  ViewerWindowController` でキーウィンドウのコントローラを解決し
  （`applicationShouldTerminate` に既存の同種パターンあり:
  `AppDelegate.swift:96-98`）、`OpenPanelDirectoryResolver.resolve` の結果を
  `panel.directoryURL` に設定する。パネルでファイルが選択されたら、
  選択されたファイルの親ディレクトリを `controller.lastOpenDirectory` に
  書き戻す。
- ウィンドウが1つも開いていない（キーウィンドウが無い）場合は
  `controller` が `nil` になるため、自然にホームディレクトリへ
  フォールバックする。

### テスト方針

`OpenPanelDirectoryResolver.resolve` は純粋関数としてユニットテストする。
`showOpenPanel` 自体（`NSOpenPanel` の実表示を伴う）は自動テスト対象外。

## 3. パスコピーを相対パスに

### 現状

`FileListView.copyPath(_:)` (`FileListView.swift:183-187`) は `url.path`
（絶対パス）をそのままクリップボードへコピーする。

### 変更方針

新規の純粋関数 `PathRelativizer.relativePath(of:relativeTo:)` を追加する。

- `url` の `standardizedFileURL.pathComponents` が `base` の
  `standardizedFileURL.pathComponents` から始まっていれば、
  base 以降のコンポーネントを `/` 区切りで連結した相対パス文字列を返す。
- `base` の外にあるファイル（prefix が一致しない）の場合は、
  従来通り `url.path`（絶対パス）を返す（フォールバック）。

`FileListView.copyPath(_:)` はこの関数を使い、基準ディレクトリとして
`model.currentDirectory`（サイドバーが現在表示しているディレクトリ、
`FileListView.swift:41` で表示にも使用）を渡す。

### テスト方針

`PathRelativizer.relativePath(of:relativeTo:)` を以下のケースで
ユニットテストする: 直下のファイル、ネストしたファイル、base 自身との
比較、base の外にあるファイル（フォールバック）。

## スコープ外

- cmd+o の記憶を `UserDefaults` 等で永続化すること（今回はウィンドウの
  生存期間中のみのメモリ上の記憶。要件は「ウィンドウ単位」であり、
  アプリ再起動をまたぐ永続化は要求されていない）
- `copyFileReference`（Finder 参照のコピー）の変更（対象は `copyPath` のみ）
- ウィンドウがアクティブでない場合の視覚的フィードバック（バウンスなど）の追加
