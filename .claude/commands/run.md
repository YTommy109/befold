# /run — アプリをビルドして起動する

以下の手順を実行してください。

## 1. ビルド

`swift build` は .app バンドルを生成しないため、必ず xcodebuild を使う。
`-derivedDataPath` を固定し、worktree ごとに成果物の場所がずれないようにする。

```bash
cd MmdviewApp && xcodegen generate && \
  xcodebuild build -scheme mmdview -configuration Debug -derivedDataPath .build/xcode -quiet
```

ビルドに失敗した場合はエラーを報告して終了する。

## 2. 起動

```bash
open MmdviewApp/.build/xcode/Build/Products/Debug/mmdview.app
```

引数でファイルパスが指定された場合はそのファイルを開く:

```bash
open -a MmdviewApp/.build/xcode/Build/Products/Debug/mmdview.app <ファイルパス>
```

## 3. 完了メッセージ

アプリを起動したことを報告する。

## 補足: ログを観察したい検証時

NSLog を捕捉したい場合は `open` ではなく実行ファイルを直接起動する。
シェル終了時の SIGHUP でアプリが死ぬため **nohup + disown が必須**。

```bash
pkill -x mmdview 2>/dev/null
nohup MmdviewApp/.build/xcode/Build/Products/Debug/mmdview.app/Contents/MacOS/mmdview \
  > /tmp/mmdview.log 2>&1 &
disown
# ファイルを開く(起動済みインスタンスに open イベントが届く)
open -a MmdviewApp/.build/xcode/Build/Products/Debug/mmdview.app <ファイルパス>
# ログ確認
grep <パターン> /tmp/mmdview.log
```
