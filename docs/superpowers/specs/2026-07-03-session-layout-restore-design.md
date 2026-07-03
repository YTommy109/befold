# セッションレイアウト復元（アクティブファイル + タブ順序）設計

## 背景

mmdview は起動時に前回開いていたファイル群を再オープンする（`SessionStore` が
`"SessionOpenFilePaths"` キーに開いた順の `[String]` を保存し、`AppDelegate.restoreLastSession()`
がその順に開く）。しかし以下は記憶していない:

- **終了時にアクティブ（キーウィンドウ）だったファイル** — 復元後は配列末尾のファイルが
  成り行きでキーになる
- **タブの実際の並び順** — ドラッグで並べ替えても「開いた順」のまま
- **タブグループ構成** — 複数ウィンドウに分かれていた場合のグループ分け

## 要求

1. 終了時にアクティブだったファイルが、復元後もアクティブ（キーウィンドウ）である
2. タブの並び順は終了時の実際の並び（ドラッグ並べ替え結果を含む）を復元する
3. 複数のタブグループに分かれていた場合、グループ構成・各グループ内のタブ順・
   各グループの選択タブも復元する

## 採用アプローチ

**終了時スナップショット + ライブ追跡の併用**（検討した代替案: 完全ライブ追跡は
タブ並べ替えの通知 API が存在せず完全性を保証できない。OS 標準の
NSWindowRestoration はシステム設定に挙動が左右され既存 SessionStore と二重管理になる）。

## 保存データ構造

`SessionStore` に構造化レイアウトを追加する。UserDefaults キー `"SessionLayout"` に
JSON（Codable）で保存する:

```swift
struct SessionLayout: Codable {
    struct TabGroup: Codable {
        var paths: [String]        // タブの並び順（normalizedPathKey）
        var selectedPath: String?  // このグループで選択中だったタブ
    }
    var groups: [TabGroup]         // ウィンドウ（タブグループ）の並び
}
```

**アクティブファイルは別キー `"SessionActiveFilePath"`（`String?`）に分離する。**
`SessionLayout` 内に持たせない理由: アクティブファイルはキーウィンドウ変更のたびに
ライブ更新するため、単一文字列キーなら JSON 全体の再シリアライズが不要で、
レイアウト JSON が壊れた場合のフォールバック時にもアクティブファイルが生き残る。

既存の `"SessionOpenFilePaths"`（開いた順のフラット配列）は**そのまま維持**し、
`SessionLayout` が無い・パース不能・中身が空のときのフォールバックとする。
旧バージョンからのアップデート直後も自然にフォールバック側が使われる。

## 保存タイミング

- **タブ構成スナップショット**: `applicationShouldTerminate` で `NSApp.windows` の各
  `tabGroup` を走査し、グループごとの `windows` の並びと `selectedWindow` から
  レイアウトを構築して保存する。同時に `NSApp.keyWindow` から
  `"SessionActiveFilePath"` も確定値で上書きする（既存の `freeze()` 呼び出しと
  同じ場所）
- **アクティブファイルのライブ更新**: `ViewerWindowController` に `windowDidBecomeKey`
  デリゲートを実装し、`onBecomeKey` コールバックで AppDelegate 経由
  `sessionStore.noteActivated(url)` を呼ぶ。クラッシュ時もアクティブファイルは最新が残る
- **リネーム追従**: 既存の `onRename` フローで `SessionLayout` 内のパスも書き換える

クラッシュ時のトレードオフ: タブ並び順は「最後の正常終了時点」に戻る可能性があるが、
ファイル一覧（ライブ追跡済み）とアクティブファイル（ライブ追跡）は守られる。

## 復元処理（`AppDelegate.restoreLastSession()`）

1. `SessionLayout` を読む。無ければ従来どおりフラット配列を順に開く（この場合も
   `"SessionActiveFilePath"` が有効ならそれをキーにし、無ければ現状挙動 = 末尾がキー）
2. グループごとに: 先頭ファイルのウィンドウを `openViewer` で作り、残りは作成後に
   `window.addTabbedWindow(_:ordered: .above)` で末尾に連結する（システムの
   「タブ優先」設定に依存せず明示的にタブ化する）
3. 各グループの `selectedPath` のウィンドウを `tabGroup.selectedWindow` に設定する
4. 最後に `"SessionActiveFilePath"` のウィンドウを `makeKeyAndOrderFront` する
5. 存在しないファイルは現状同様スキップして記録から除去する。グループ内の全ファイルが
   消えていたらそのグループ自体をスキップする

## エラー処理・エッジケース

- レイアウト JSON が壊れていたらフォールバック配列で復元する（クラッシュさせない）
- `activePath` / `selectedPath` が開けなかった場合は、そのグループの先頭タブ /
  最後に開いたウィンドウで代替する
- ウィンドウ位置・サイズは既存のファイル毎フレーム autosave（#70）がそのまま効く
  （タブ化されたウィンドウはグループのフレームに従うので干渉しない）

## テスト

- `SessionStoreTests` に追加: レイアウトの保存/読込ラウンドトリップ、`noteActivated` の
  永続化、壊れた JSON でのフォールバック、リネーム時のレイアウト書き換え
- タブ化・キーウィンドウの実挙動（AppKit 層）は既存方針どおり手動チェック対象。
  複数ファイルを開く → タブを並べ替える → アクティブタブを変える → 再起動、で
  並び順・選択タブ・キーウィンドウの再現を確認する

## 変更対象ファイル

- `MmdviewApp/mmdview/App/SessionStore.swift` — `SessionLayout` 型、
  `noteActivated(_:)`、`saveLayout(_:)` / `savedLayout()`、リネーム時の書き換え
- `MmdviewApp/mmdview/App/AppDelegate.swift` — 終了時スナップショット構築、
  復元処理のグループ対応、`onBecomeKey` 配線
- `MmdviewApp/mmdview/App/ViewerWindowController.swift` — `windowDidBecomeKey`
  実装と `onBecomeKey` コールバック追加
- `MmdviewApp/mmdviewTests/SessionStoreTests.swift` — テスト追加
