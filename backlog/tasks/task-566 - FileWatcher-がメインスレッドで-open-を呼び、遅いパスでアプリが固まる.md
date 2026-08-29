---
id: TASK-566
title: FileWatcher がメインスレッドで open() を呼び、遅いパスでアプリが固まる
status: To Do
assignee: []
created_date: '2026-08-29 12:43'
labels:
  - bug
dependencies: []
ordinal: 823000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 症状

セッション復元で iCloud Drive 上のファイルを開き直したとき、アプリ全体が数秒固まる。
その間はメニューも開かず、`open` で送ったファイルも処理されない（イベントが溜まる）。
ユーザーには「PDF の描画が遅い」として現れた（実際には種別に関係ない）。

## 原因（実測 / 2026-08-29）

`sample`（3 秒）を取ったところ、**2611/2611 サンプルすべてがメインスレッドの
`open()` システムコールで止まっていた**。呼び出し経路:

```
applicationDidFinishLaunching → SessionRestorer.restoreLastSession
  → ViewerWindowManager.openViewer → makeController → ViewerWindowController.init
  → ViewerWindowAssembler.openInitialDocument → ViewerStore.openFile
  → FileWatcher.init → startMonitors → startDirectoryMonitor → makeMonitor → open()
```

`FileWatcher.init` は監視対象と**その親ディレクトリ**を `open()` で開く。この呼び出しが
`_dispatch_lane_barrier_sync_invoke_and_complete` 経由でメインスレッドから同期に走るため、
対象が iCloud Drive のようにアクセスに時間のかかる場所（さらに TCC の許可ダイアログを
伴う場合）だと、その間アプリ全体が止まる。

`.claude/CLAUDE.md` の「高頻度経路のコスト」で名指ししている型（メインアクター上に
残った同期 syscall。TASK-322 と同じ形）にあたる。

## やること

`FileWatcher` の監視開始（ディスクリプタの取得）をメインスレッドから外す。
開始が非同期になる間に届く変更を取りこぼさないこと。

## 論点（実装着手前に `/review-design` で詰める）

- 監視開始を非同期にすると、「開始したつもりで開始していない」区間ができる。
  その間のファイル変更をどう扱うか（開始直後に 1 回読み直す等）。
- `FileWatcher` は `@unchecked Sendable` で内部キューを持つ。開始をそのキューへ
  移すだけで済むか、`ViewerStore` 側の期待（init 直後に監視済み）を変える必要があるか。
- 既存のテストは一時ファイルの実 FS を使う。非同期化で待ち合わせが要るなら、
  タイミング依存の flaky を作らない形にすること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 FileWatcher の監視開始がメインスレッドを塞がない
- [ ] #2 監視開始が非同期になっても、開始直後の変更を取りこぼさない
- [ ] #3 遅いパス（ネットワーク/iCloud 等）を開いてもアプリが固まらないことを確認した手順が Implementation Notes にある
- [ ] #4 既存の FileWatcher テストが通り、タイミング依存の flaky を新設していない
<!-- AC:END -->
