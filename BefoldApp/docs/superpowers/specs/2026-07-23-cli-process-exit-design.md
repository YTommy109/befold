# TASK-106: CLI プロセス終了の設計

## 概要

`befold file.mmd` 実行時、CLI プロセスが終了せず GUI アプリ化してしまう問題を修正する。
`open` コマンドのように、ファイルを開いたら CLI は即座に終了する。

## 原因

`AppDelegate.launch()` の `.launchAsNewInstance` 分岐で `NSApplication.shared.run()` を呼ぶと、
CLI プロセス自体がメインループに入り GUI アプリになる。

## 設計

### 変更箇所

`AppDelegate.launch()` L134-141 の `.launchAsNewInstance` 分岐を分割する。

### 振る舞い

```
.launchAsNewInstance
  ├─ paths あり → open -a <bundle>（起動のみ）
  │                → ポーリングで起動検知
  │                → CLIInstanceRouter.forward() で転送
  │                → exit(0)
  └─ paths なし → NSApplication.run()（従来通り）
```

パスありの場合:
1. `open -a <bundlePath>`（ファイルなし）でアプリを別プロセスとして起動
2. `CLIInstanceRouter.runningInstance()` をポーリング（最大 10 秒）して起動を検知
3. 既存の `CLIInstanceRouter.forward()` でパス + 表示オプションを転送
4. `exit(0)`

この方式により、既存インスタンスへの forwarding パスと同じ経路を使うため、
`--hidden-files` 等の表示オプションも初回起動時から反映される。

### パスなし起動

`befold`（引数なし）は従来通り CLI プロセスが GUI アプリ化する。
Dock アイコンのクリックやセッション復元が必要なため、この動作は維持する。

## テスト

統合テストで `befold <path>` がタイムアウト内に終了コード 0 で終了することを検証する。
