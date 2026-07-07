# CLI インストールの文言変更 と 削除ファイル処理の簡略化

## 概要

2 つの独立した変更をまとめる。

1. アプリメニューの CLI インストール項目の文言を、befold 固有の表現から
   一般的な表現に変更する。
2. 「ファイルが削除された」状態をビューア内バナーで表示し続ける現行の仕組みを廃止し、
   削除されたらウィンドウを閉じる・存在しないファイルを開こうとしたらエラー表示する、
   というシンプルな挙動に置き換える。

## 変更点

### 1. CLI インストールメニューの文言変更

`befold/Resources/Localizable.xcstrings` の `menu.app.installCLI` を変更する。

- ja: `PATH に 'befold' コマンドをインストール` → `コマンドラインツールをインストール`
- en: `Install 'befold' command in PATH` → `Install Command Line Tool`

インストール結果アラート（`cli.install.success` / `cli.install.failed`）は
「'befold' コマンド」という具体表現のままで変更不要。

### 2. 削除ファイル処理の簡略化

#### 現状

- `ViewerStore.isDeleted: Bool` が「削除された」状態を保持する
- `loadContent()` が `fileReader.fileExists(at:)` の結果で `isDeleted` を同期的に切り替える
- `ViewerWebView` が `isDeleted` を見て `viewer.html` に JS 注入し、
  削除バナー（`#mmd-deleted-banner`）を表示し続ける
- `FileWatcher` は削除検知後もディレクトリ監視で再作成（アトミック保存）を検知でき、
  再作成時はバナーを消して自動復活する
- 別途、Markdown 内の参照リンククリック時のみ
  `ViewerWindowController.showFileNotFoundAlert` で「File Not Found」の
  `NSAlert` を表示する仕組みが独立して存在する

#### 変更後

**a. 削除検知 → ウィンドウを閉じる**

`ViewerStore` に `onFileGone: (@MainActor @Sendable () -> Void)?` を追加する
（既存の `onRename` と同様のコールバックパターン）。

`loadContent()` がファイル不在を検知した際、直ちに閉じるのではなく
グレース期間（約 0.3 秒、既存の 0.2 秒デバウンスに追加）を置いて再度存在確認する。

- 再確認時も不在 → `onFileGone` を発火し、`ViewerWindowController` がウィンドウを閉じる
- 再確認までにディレクトリ監視がファイルの再作成を検知した場合 →
  保留中のクローズをキャンセルし、通常のコンテンツ再読み込みに合流する
  （アトミック保存で救済されるケースを壊さない）

ゴミ箱移動・実削除・`FileWatcher` が rename を削除扱いにするケース
（トラッシュ移動など）は、すべて同じ「ファイル不在」経路に合流するため
追加の分岐は不要。

**b. 存在しないファイルを開こうとした場合 → エラー表示に統一**

「新規に開く」経路と「ウィンドウ内切替」経路の両方でファイル存在チェックを行う。

- `ViewerWindowManager.openViewer(for:)` の入り口でチェックし、存在しない場合は
  ウィンドウを一切開かず `NSAlert`「File Not Found」を表示する
  （CLI 起動・Dock ドロップ・参照リンクの新規ウィンドウ、のすべてがこの経路を通る。
  `ViewerStore` は `@Observable` な状態管理層でありアラート表示の責務を持てないため、
  チェックはウィンドウ生成の手前であるマネージャ層に置く）
- `ViewerWindowController.performFileSwitch(to:)` の入り口でもチェックし、
  存在しない場合は切替を中止して同アラートをシート表示する
  （サイドバー選択・履歴ナビゲーション・同一ウィンドウでの参照リンク切替の経路。
  ここをガードしないと、消えたファイルへの切替が a. の削除検知に流れて
  ウィンドウごと閉じてしまう）
- 対象外: セッション復元時に消えているファイルは、従来どおり黙ってセッションから除外する
  （`SessionRestorer` が `openViewer` 呼び出し前に自前でフィルタしているため、
  このアラートは発火しない）

**c. 削除するコード**

- `ViewerStore.isDeleted` フラグと `loadContent()` 内の分岐
- `ViewerWebView` の `isDeleted` パラメータ・バナー注入ロジック
  （`updateContent(...)`, `handleNavigationFailure(webView:)` 内）
- `ViewerBridge.showDeletedBannerScript`
- `viewer.html` の `#mmd-deleted-banner` 要素と `showDeletedBanner()` /
  `hideDeletedBanner()` JS 関数
- `style.css` の `.mmd-deleted-banner` / `body.mmd-deleted` スタイル
- 上記に対応するテスト

**d. 規約ドキュメントの更新**

`docs/dev/coding_rule.md` は `isDeleted` フラグによる削除伝搬を規約として記載している
（命名例・テスト例・エラーハンドリング規約「ファイル削除検出は `isDeleted` フラグで
UI に伝搬する」）。これを onFileGone 方式に合わせて更新する。
更新しないと将来の実装者が削除済みの仕組みを規約に従って再導入してしまう。

**既知の制限**

HTML 直接ロードのナビゲーション失敗時のフォールバック
（`handleNavigationFailure` → viewer.html 再ロード）は残すが、バナー表示は行わない。
削除起因の失敗は a. の `onFileGone` がウィンドウを閉じるため問題にならない。
削除以外の一時的な失敗（権限変化など）では次のファイル変更まで空表示になるが、
従来もこのケースでは「deleted」という誤ったバナーを出しており、誤表示が消える分の改善とする。

## 影響しないもの

- `ViewerStore.isUnsupported`（バイナリ/巨大ファイル）の仕組み。削除とは無関係で、
  今回のスコープ外
- セッション復元時に存在しないファイルを黙ってフィルタする挙動
- `FileWatcher` の rename 追従・アトミック保存の再作成検知そのもの
  （グレース期間の判定材料として引き続き利用する）
