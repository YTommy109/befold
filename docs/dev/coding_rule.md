# befold コーディング規約

このドキュメントは befold プロジェクトのコーディング規約を一元管理する。
CLAUDE.md・スキル・コマンドはこのファイルを参照する。

**CLAUDE.md との関係**: CLAUDE.md のアーキテクチャ図・プロジェクト構成・技術スタックは
このドキュメントの同名セクションの要約版である。coding_rule.md を更新したら、
CLAUDE.md の対応セクションも同じ diff 内で同期する（権威元は coding_rule.md）。

## プロジェクト概要

macOS 向け Mermaid ダイアグラム・ビューアアプリ。
`.mmd` / `.md` ファイルを監視し、mermaid.js でリアルタイムにプレビューする。
ファイル変更は同一プロセス内伝搬で反映する。

## アーキテクチャ

```
befold.app (Swift / AppKit + SwiftUI)
  ├── AppDelegate            # ライフサイクル・各コーディネータの束ね
  │     ├── ViewerWindowManager    # ウィンドウ生成・管理とセッション記録の更新
  │     │     └─ ViewerWindowControllerDelegate  # VWC→VWM のイベント通知（close/rename/switch 等）
  │     └── SessionRestorer        # 前回セッションのタブ構成の保存/復元
  ├── ViewerWindowController # NSWindowController（1 ファイル = 1 ウィンドウ）
  │     └── SidebarNavigator       # サイドバー一覧・選択同期・戻る/進む履歴
  │           └─ SidebarNavigatorHost  # Navigator→VWC の逆方向依存を切るプロトコル
  ├── FileWatcher        # DispatchSource によるファイル監視（0.2s デバウンス）
  ├── ViewerStore        # @Observable 表示状態（content / rejectReason / isTruncated、FileReading + ChunkedTextReading で読込を抽象化）
  └── ViewerWebView      # WKWebView（NSViewRepresentable + Coordinator）
        ├── 同梱アセット（viewer.html / viewer.js / mermaid.min.js / markdown-it.min.js / style.css）
        └── JS ブリッジ: ViewerBridge 経由で evaluateJavaScript("render(content, type)")
```

ファイル変更の伝搬:
`FileWatcher → ViewerStore → ViewerWebView.updateNSView → evaluateJavaScript`

## 技術スタック

- Swift 6 / AppKit + SwiftUI（macOS 14+）
- WKWebView（mermaid.js / markdown-it.js レンダリング）
- DispatchSource（ファイル監視）
- XcodeGen（プロジェクト生成）/ Swift Package Manager（ビルド）
- SwiftLint（静的解析）/ SwiftFormat（コードフォーマット）— SPM plugin
- Jest（viewer.js のユニットテスト）

## プロジェクト構成

```
BefoldApp/
├── project.yml              # XcodeGen 定義
├── Package.swift            # SPM ビルド用
├── .swiftlint.yml           # SwiftLint 設定
├── .swiftformat             # SwiftFormat 設定
├── befold/
│   ├── App/                 # AppDelegate, ViewerWindowController, SidebarNavigator ほかウィンドウ/セッション/メニュー系
│   ├── Viewer/              # ViewerStore, ViewerWebView, FileType, FileListView, ViewerBridge ほか表示系
│   ├── FileWatching/        # FileWatcher, Debouncer
│   ├── Updates/             # UpdateChannel ほか自動更新系（Sparkle 2）
│   └── Resources/           # viewer.html, viewer.js, style.css, mermaid.min.js, markdown-it.min.js
│       └── __tests__/       # viewer.js の Jest テスト
├── BefoldKit/               # 純粋ロジックライブラリ（MarkdownImageEmbedder, PathRelativizer, ReferenceResolver, TextEncoding, LineChunkReader, ContentLoader）
└── befoldTests/            # Swift Testing テスト（TestSupport.swift = 共有ヘルパー）
```

## コマンド

```bash
cd BefoldApp
swift build                  # ビルド（SwiftLint も実行される）
swift test                   # テスト（要 Xcode.app）
xcodegen generate            # .xcodeproj を再生成
xcodebuild build -scheme befold  # Xcode ビルド（要 Xcode.app）
npx jest                     # viewer.js のテスト

# コード品質
swift package plugin swiftlint           # SwiftLint を単体実行
swift package plugin --allow-writing-to-package-directory swiftformat  # SwiftFormat 実行
```

## コード品質ツール

### SwiftLint（静的解析）

SPM Build Tool Plugin として組み込み済み。`swift build` 時に自動実行される。

| ルール | warning | error | 用途 |
|--------|---------|-------|------|
| `cyclomatic_complexity` | 10 | 20 | 循環的複雑度 |
| `function_body_length` | 50行 | 100行 | 関数の行数制限 |
| `file_length` | 400行 | 1000行 | ファイルの行数制限 |
| `type_body_length` | 250行 | 350行 | クラス/構造体の行数制限 |
| `line_length` | 120文字 | 200文字 | 行長制限 |

設定ファイル: `.swiftlint.yml`

### SwiftFormat（コードフォーマット）

SPM Command Plugin として利用する。手動実行:

```bash
swift package plugin --allow-writing-to-package-directory swiftformat
```

主な設定（`.swiftformat`）:
- インデント: 4スペース
- 行幅: 120文字
- 不要な `self.` を除去
- 引数リスト・コレクションリテラル: 長い場合は first 要素の前で改行

## Swift コーディング規約

### 言語バージョン・コンパイラ設定

- Swift 6（`swift-tools-version: 6.0`）
- Strict Concurrency: `complete`（`SWIFT_STRICT_CONCURRENCY: complete`）
- デプロイメントターゲット: macOS 14.0

### Concurrency モデル

- **`@MainActor`**: UI 状態を持つクラス（`ViewerStore`, `AppDelegate`）に付与する
- **`@Observable`**: SwiftUI のデータバインディングには `@Observable` マクロを使う（`ObservableObject` + `@Published` は使わない）
- **`@unchecked Sendable`**: GCD キューで内部的にスレッド安全性を保証するクラス（`FileWatcher`, `Debouncer`）に付与する。`NSLock` や専用 `DispatchQueue` で排他制御すること
- **`@Sendable` クロージャ**: スレッド境界を越えるクロージャには `@Sendable` を付与する
- **`nonisolated(unsafe)`**: テストコード内で並行安全でないミュータブル変数を使うときのみ許容する

### 型設計

- **`final class`**: 継承を意図しないクラスにはすべて `final` を付ける
- **`private(set)`**: 外部から読み取り可能・書き込み不可のプロパティには `private(set)` を使う
- **テスト容易性のための可視性**: SwiftUI View 等に同居する純粋ロジック（「テスト対象外」節の
  判断基準を満たすもの）をテストターゲットから直接呼びたい場合、そのメソッドは `private` を外して
  `internal`（デフォルト可視性）にする。これは「テストのために API を公開する」のではなく
  「ファイル外の唯一の正当な利用者がテストである」ことを可視性で表明する扱い。以下を守ること:
    - `internal` に上げるのは検証したい純粋ロジックだけに留める。描画・配線メソッドは `private` のまま残す
    - 型自体の外部公開（`public` / `open`）には広げない。同一モジュール内のテストから呼べれば十分
    - 単一情報源の原則（ロジックの実体は 1 箇所）は崩さない。テスト用に同じ判定を再実装しない
- **`enum`**: インスタンス化不要な型（`FileType` のような分類型）は `enum` で定義する
- **`Sendable`**: 値型の `enum` には `Sendable` 準拠を付ける。**`private` / ファイル内ローカルな
  型でも同じ**（可視性を下げても規約は緩まない。目立たない補助 enum ほど見落としやすいので
  追加時にこの節を機械的に照合する）。照合の発火条件は**型の新規追加時だけではない**。
  既存の値型を新しく `@MainActor` クロージャ境界・`WKScriptMessage` 経路・スレッド境界へ
  通し始めたとき（＝その型が Sendable 越境をするようになったとき）も、明示準拠の有無を
  再確認する。Swift 6 の暗黙合成でコンパイルは通るため、越境が増えるまで欠落が顕在化せず
  レビューをすり抜けやすい（`ViewerBridge.ViewMode` を機能拡張でクロージャ境界へ大きく
  通した際に明示 `Sendable` 欠落が露見した実例）
- **`switch` 網羅性**: `enum` の `switch` では `default` を使わず、全ケースを明示する
- **姉妹型との照合**: 命名・役割が既存型と同系列の新しい型（`〜Store` / `〜Preference` /
  `〜Coordinator` 等）を追加するときは、最も近い既存の姉妹型を 1 つ選び、その型の
  規約準拠状況を**チェック項目として機械的にコピーして照合する**。最低限:
    - クラス概要と全公開メソッドの `///`（姉妹型が完備なら同水準で付ける）
    - `final` / `private(set)` / 値型 enum の `Sendable`
    - イニシャライザの依存注入方針（共有インスタンスはデフォルトなし必須パラメータ）
  「新規型だから規約を思い出しながら書く」のではなく「姉妹型の準拠状況を写経して差分ゼロに
  する」ことで、`///` 完備の姉妹型（`SourceModeStore`）がありながら新規型（`ScrollPositionStore`）で
  `///` が丸ごと欠落する、といった逸脱を防ぐ

### 命名規約

- Swift API Design Guidelines に従う
- 型名: UpperCamelCase（`ViewerStore`, `FileWatcher`）
- メソッド・プロパティ: lowerCamelCase（`openFile`, `isRejected`）
- GCD キューラベル: リバースドメイン（`com.degino.befold.filewatcher`）
- ウィンドウ autosave 名: `Viewer-<パスベースの識別子>`
- `@available(*, unavailable)` + `fatalError()`: Interface Builder 未使用を明示する `required init?(coder:)` に付ける

### パターン

- **guard-let early return**: `guard let filePath else { return }` でオプショナルを早期アンラップする
- **`[weak self]` キャプチャ**: クロージャでの循環参照を防ぐ。`guard let self else { return }` と組み合わせる
- **`defer`**: テストでの一時ファイル削除など、スコープ終了時の後処理に使う
- **純粋関数抽出**: メソッドが「状態の計算」と「状態の適用（副作用）」を混在させている場合、
  計算部分を戻り値を返す純粋関数に切り出し、呼び出し元で結果を適用する。
  テスタビリティが向上し、同じ計算ロジックを複数の経路で再利用できる
  （例: `ContentLoader.load(from:fileType:)` → `LoadedContent` を返す純粋関数、
  `performZoom(directHTML:script:)` → 変換関数を引数で受け取り 3 アクションの重複を解消）

### 責務分離

- **1 ファイル 1 主要型**: 補助型は主要型の実装詳細である場合のみ同居可。独立して使える部品
  （`NSViewRepresentable` の UI 部品、`@Observable` モデル等）は別ファイルに置く
- **SwiftLint の行数閾値は上限であって目標ではない**: 閾値未満でも、複数の関心
  （例: ウィンドウ管理 + サイドバー + 履歴）が 1 クラスに同居し始めたら凝集単位で分割する。
  分割先は `SidebarNavigator`（ホストへの weak 参照 + プロトコル `〜Host` で逆方向依存を切る）の
  パターンに揃える
- **クロージャバンドルが 3 つを超えたら delegate プロトコルを検討する**:
  親→子へのコールバック注入がクロージャで 3 つを超えた場合、delegate プロトコルへの
  置換を検討する。特に、クロージャが値をキャプチャしており **rename / switch のたびに
  再束縛（rebind）が必要になる** 場合は、delegate への移行が強く推奨される。
  delegate メソッドは呼び出し時に対象オブジェクトを引数として受け取るため、キャプチャの
  更新が不要になり、再束縛メカニズムそのものが消える。
  - 子→親の逆方向依存: `SidebarNavigatorHost`（weak 参照 + `〜Host` プロトコル）の流儀
  - 親→子のイベント通知: `ViewerWindowControllerDelegate`（weak delegate + `〜Delegate` プロトコル）の流儀
- **ウィンドウコントローラを「何でも置き場」にしない**: メニューアクションの実装は
  対応する凝集単位（navigator / store / builder）へ委譲し、コントローラには薄い委譲メソッドだけ残す
- 並行作業でのコンフリクトを避ける観点で、「この機能を触る人が編集するファイル」が
  他機能と重ならないように切ること
- **公開イニシャライザのないフレームワーク型は、下位の値型を受け取る関数へロジックを切り出す**:
  SwiftUI の `KeyPress` はテストコードから直接構築できない（`KeyPress(characters:key:modifiers:)` の
  ようなイニシャライザは存在せず、書いてもコンパイルエラーになる）。このように「フレームワークが
  イベントとして渡してくるが、自前で組み立てられない型」が絡む場合、判断ロジックを
  構築可能な下位の値型を引数に取る関数へ分離し、フレームワーク型を受ける関数は
  その値を取り出して委譲するだけの薄い層にする。

  ```swift
  // フレームワーク型を受ける薄い層（テスト対象外）
  func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
      handleKey(keyPress.key)          // 構築可能な KeyEquivalent を取り出して委譲
  }

  // 純粋な分岐ロジック（テスト対象。KeyEquivalent はリテラルで構築できる）
  func handleKey(_ key: KeyEquivalent) -> KeyPress.Result { ... }
  ```

  同種の型（公開イニシャライザを持たない・モックしづらいイベント/入力型）に一般化して適用する。
  切り出し先の関数は前掲の可視性ルールに従い `internal` にしてテストから直接呼ぶ。

### 共通化・単一情報源・DI

同じ知識を 2 箇所に書かない。以下は既に単一情報源が決まっており、再定義・再実装は違反:

| 知識 | 単一情報源 |
|------|-----------|
| 対応拡張子の集合 | `FileType.allExtensions`（Info.plist との整合は `InfoPlistTests` が検証） |
| 拡張子が対応形式かの判定 | `FileType.isSupported(_:)`（`allExtensions.contains(url.pathExtension.lowercased())` という判定式そのものを一本化。呼び出し元で `contains` / `lowercased` を組み立て直さない） |
| パスの同一性キー（symlink 解決込み） | `URL.normalizedPathKey`。ディレクトリ同一性比較も `standardizedFileURL.path` ではなくこちらを使う |
| パスキー辞書の rename 移行 | `PathKeyedDictionary` |
| Swift → JS の関数名・メッセージハンドラ名・注入スクリプト | `ViewerBridge`（`evaluateJavaScript` への文字列リテラル直書きは違反） |
| シェルのシングルクォートエスケープ | `String.shellQuoted`（`ShellQuoting.swift`） |
| ズーム上下限・ステップ | `ZoomStore.minZoom` / `maxZoom` / `zoomStep` |
| 不可視ファイル表示の共有状態 | `HiddenFilesPreference` インスタンス（AppDelegate が生成した 1 個を全ウィンドウで共有） |
| 拡張子→FileType のマッピング | `FileType.typeByExtension`（`init(url:)` と `allExtensions` の双方がここから導出。拡張子追加は辞書への 1 行追加で完結する） |
| BOM 検出（バイトパターン→エンコーディング） | `TextEncoding.detectBOM(_:)`（`decodeText` と `isChunkableEncoding` の双方がここに委譲） |
| テキスト復号（BOM / UTF-16 / UTF-8 / レガシーエンコーディング） | `TextEncoding.decodeText(_:)`（`DefaultFileReader.readString` と `ViewerStore.decodeFullFile` の双方がここに委譲。`LineChunkReader` は `detectBOM` / `detectEncoding` / `trimIncompleteUTF8Tail` に委譲し、`decodeText` は使わない） |
| ディレクトリ列挙（ソート・フィルタ込み） | `DirectoryLister.sortedContents(in:showHiddenFiles:)`（`listFiles` / `listEntries` / `firstSupportedFile` が委譲） |
| Sparkle フィード URL | `UpdateChannel.feedURLString`（`SPUUpdaterDelegate.feedURLString(for:)` 経由で Sparkle に提供。Info.plist の `SUFeedURL` は使用しない） |

- **同一 diff 内の自己整合性**: 単一情報源テーブルへのエントリ追加・共通関数の新設を含む diff では、
  **その同じ diff 内の全コードが新設した情報源を使っているか** をセルフレビューで照合する。
  「テーブルに登録したが、同じ PR の別ファイルでは自前実装している」は、既存コードとの重複と
  同じ違反である。同様に、ある制約を表す既存の定数（`maxTextFileSizeBytes` 等）が存在するとき、
  同じ制約を意図する新規コードで別の定数（`maxFileSizeBytes` 等）を参照するのは
  「同じ知識の二重表現」であり違反とする
  （`decodeText` をテーブル登録した同じ diff で `decodeFullFile` が自前デコードしていた実例、
  テキストファイルサイズ上限に汎用の `maxFileSizeBytes` を使い `maxTextFileSizeBytes` と
  不整合を起こした実例）
- **言語をまたぐ定数**（Swift ↔ viewer.js）は避けられない場合のみ二重定義し、
  (1) 双方に対応相手を示すコメント、(2) ソースを読んで一致を検証するテスト
  （`ViewerBridgeTests.zoomRangeMatchesZoomStore` の流儀）を必ずセットで付ける
- **設定値の断片を UI 文言に埋め込むときはドリフトを前提に扱う**。メニュー項目の
  `keyEquivalent`（`MainMenuBuilder.swift`）のような「実体」を、人間可読な断片
  （`⌘B`）としてローカライズ文言（`Localizable.xcstrings` のツールチップ等）へ書き写すのは、
  上の「言語をまたぐ定数」と同種の別表現二重化であり、実体を変えたとき文言だけ取り残される。
  最低限 (1) 文言側に「どのメニュー項目のショートカットと一致させるか」を示す相互参照
  コメントを付ける（`Localizable.xcstrings` の該当エントリの `comment` フィールドに書く）。
  埋め込み箇所が増える・変更頻度が上がる場合は、さらに (2) 実体と文言の一致を検証する
  テスト（メニューの `keyEquivalent` を読む `MainMenuBuilderTests` の流儀）を追加する。
  相互参照コメントは **実装箇所が確定してから書く（または確定後に指し先を検証する）**。
  実装が固まる前に「この辺に実装するはず」という想定で指し先を書くと、実装が別の場所へ
  着地したときにコメントだけが古い想定のまま取り残される（例: Escape 処理を
  `mmd-find-input` の keydown 側に書く想定でコメントしたが、実際は IME ガード付きの
  document レベル keydown ハンドラへ実装された、という指し先ズレ）。指し先には
  「どのハンドラ・どの修飾条件（IME ガード等）か」まで具体的に書き、実装確定後に
  その記述が実物と一致しているか読み合わせる。
  グリフのコード生成のような完全な単一情報源化は viewer アプリの規模では過剰。
  なお対象は「ショートカット等の設定値の断片」に限る。ラベル文言そのものの一致
  （ツールチップとメニュータイトルが同じ意味を表すこと）は、ローカライズ上それぞれ独立に
  翻訳する対象なので二重定義違反として扱わない。
- **同型コードを 2 箇所目に書きそうになったら共通化を検討する**。ただしデータ形状・不変条件が
  異なるもの（例: 順序保持リスト / 上限付き MRU / パス辞書の永続化骨格）を無理に統合しない
  （偽の抽象）。見送る場合はその判断を PR に書く
- **値の単一情報源は、その値を使う判定・変換ロジックの単一情報源までは保証しない**。上の表は
  定数・集合そのもの（`FileType.allExtensions` 等）の一本化を定めるが、それを参照していれば
  原則を満たすわけではない。定数を使った述語や変換
  （`allExtensions.contains(url.pathExtension.lowercased())` のような「対応形式か」の判定）を
  呼び出し元ごとに個別に組み立てれば、判定式の重複という別の違反になる。定数を使う判定・変換が
  2 箇所目に現れたら、その判定自体を関数（`FileType.isSupported(_:)` の流儀）へ切り出し、
  上の表へ登録する
- **外部依存はプロトコル + デフォルト引数付きイニシャライザ注入**: ファイル読込は `FileReading`、
  監視は watcherFactory。
  新しい外部依存（ネットワーク・タイマー・Process 等)も同じ方針で注入し、メソッド内部で
  具象を直接生成しない。デフォルト引数により既存呼び出し元は変更不要に保つ
- **デフォルト引数が許されるのは「差し替え可能で状態を共有しない」依存に限る**。
  上記の `FileReading` は、
  どの具象インスタンスでも観測結果が等価な（＝呼び出し側が横断的に状態を共有しない）依存なので、
  デフォルトに具象を置いてよい
- **単一の共有インスタンスであることが不変条件の依存には、値を生成するデフォルトを付けない**。
  複数の所有者がその状態を横断的に観測する依存（例: `ZoomStore`、`HiddenFilesPreference` の
  ように「全ウィンドウが同じ 1 個を共有する」もの）は、デフォルトで `HiddenFilesPreference()` のような
  新規インスタンスを生成すると、本番で注入を書き忘れたときに「共有されていない別個体」が
  静かに生まれ、単一情報源の不変条件を破る。この種の依存は **`ZoomStore` の流儀に倣い、
  デフォルトなしの必須パラメータ**にして注入を強制するのが原則
  - NG: `hiddenFilesPreference: HiddenFilesPreference = HiddenFilesPreference()`（共有前提なのに
    新規個体を生成するデフォルト）
  - OK: `zoomStore: ZoomStore`（必須パラメータ。AppDelegate が生成した 1 個を全経路へ注入）
- テスト簡便化のためどうしても共有依存にデフォルトを残す場合は、**必須ではなく例外**と位置づけ、
  イニシャライザの `///` に「本番では必ず共有インスタンスを注入すること／このデフォルトは
  当該依存に無関心なテスト専用」を明記する（`ViewerWindowController` / `ViewerWindowManager` の
  `hiddenFilesPreference` の注記が現行の実例）。この注記は任意のドキュメントではなく**必須**とする

### AppKit / SwiftUI 混在ルール

- **ウィンドウ管理**: AppKit（`NSWindowController`）で行う
- **ビューコンテンツ**: SwiftUI（`View` プロトコル）で定義する
- **ブリッジ**: `NSHostingView` で SwiftUI View を NSWindow に埋め込む
- **WKWebView ラッパー**: `NSViewRepresentable` で SwiftUI に統合する。`Coordinator` パターンでデリゲートを処理する

### WKWebView / JavaScript ブリッジ

- HTML・CSS・JS は `Resources/` に同梱し、`Bundle.main.url(forResource:)` でロードする
- `evaluateJavaScript()` で Swift → JS の呼び出しを行う。**呼び出しスクリプトの生成は
  `ViewerBridge` に集約する**（文字列リテラルの直書きは違反。JS 側の関数名・メッセージ名の
  変更検知は `ViewerBridgeTests` のソース突き合わせテストが担う）
  - **`ViewerBridge` に新しいスクリプト定数（`currentScrollPositionScript` 等）を追加したら、
    その定数が参照する JS 側の関数名・メッセージ名を必ず `ViewerBridgeTests` のソース突き合わせ
    テストへ 1 行追加する**（例: `#expect(html.contains("function _mmdScrollTarget()"))`）。
    定数を集約しただけでは「その定数が呼ぶ JS 関数が実在するか」は保証されない。突き合わせテストの
    網羅対象は「既存スクリプト」ではなく「`ViewerBridge` が参照する全 JS シンボル」であり、
    スクリプト定数の追加とテスト行の追加をワンセットにする（新スクリプトが参照する
    `_mmdScrollTarget` の存在チェックがテストから漏れていた実例）
- JS に渡す文字列は `JSONEncoder` でエスケープする（XSS 防止）
- コンテンツ差分チェック（`lastRenderedContent`）で不要な再描画を防ぐ
- 複数のフラグを必ずセットで倒す状態遷移（例: 直接 HTML モード解除）は専用メソッドに
  集約し、不変条件を `///` に明記する（呼び出し側での部分リセットを禁じる）

## コメント・ドキュメンテーション規約

### プロダクトコード

- **`// MARK: - <セクション名>`**: ファイル内の論理セクション区切りに使う（Xcode のジャンプバーに反映される）
- **`///` ドキュメンテーションコメント**: 公開クラス・公開メソッドに日本語で付ける
- 非公開メソッド（`private` / `fileprivate`）や自明なヘルパーは省略可
- **リファクタリング・移行で型やメソッドを書き換えるとき、既存の `///` を削除しない**。
  シグネチャや責務が変わった場合は内容を更新するが、`///` 自体を落とさない。
  特に enum や公開型のクラス概要 `///` は、移行先の新コードにも引き継ぐ
  （`UpdateChannel` の `///` が Sparkle 2 移行時に失われた実例）
- コードの「なぜ（WHY）」を書く。「何を（WHAT）」は明確な命名で伝える
  - 実装の詳細（UI 部品の種類・呼び出し元・処理の中身）を言葉で説明するコメントは
    WHAT 寄りであり、命名・型・シグネチャで表現すべきことを言葉で重複させている。
    このようなコメントは実装を変更するたびに書き換えが必要になり、更新が追いつかず
    古い記述が残ったまま気づかれない（例: UI 部品を差し替えたのに、コメント内の
    部品名の説明だけ古いまま残る）
  - コメントを書く前に「この記述は実装を変更したら書き換えが必要か」を自問する。
    書き換えが必要なら WHAT を語っている可能性が高く、WHY だけを残すか、
    コメント自体を削除して命名・型で表現できないか検討する
  - **他の呼び出しとの前後関係（評価順序・呼び出し順序）を主張するコメントは特に壊れやすい**。
    「〜より前に評価される」「〜の後にリセットされる」のような順序の断定は、判定式や呼び出し順を
    少し動かしただけで実物と食い違う（結果は正しくても根拠の説明が誤りになり、将来の変更時に
    古い誤記が残る）。順序を語るなら (1) その順序が**なぜ必要か**（不変条件・副作用の依存）だけを
    書き、(2) 書いた後に実際の呼び出し箇所を読み合わせて順序主張が実物と一致するか検証する。
    単に「Xの前に呼ばれる」という事実の再記述（WHAT）は命名・コード配置で表し、コメントから外す
    （`isFileOrModeSwitch` の評価順序コメントが実際の順序と矛盾していた実例）
  - **振る舞い・状態・可視性を変えるコード変更をしたら、その挙動を説明している既存コメントと
    仕様書を同じ diff 内で読み合わせて更新する**。上の各項目が「コメントをどう書くか（執筆時）」の
    規律なのに対し、これは「コードを変えたとき（保守時）」の突き合わせ規律。変更した実体そのものだけ
    でなく、その実体の振る舞い・状態・可視性を言葉で説明している**近接コメント／設計書・仕様書
    （`docs/` 配下の spec 等）**を変更の波及範囲（blast radius）として洗い出し、記述が新しい挙動と
    一致するかを読み合わせる。コード側だけ直してコメント・仕様書を取り残すと、実装は正しいのに
    説明だけが古い誤りとして残る（CSS のホバー挙動を変えたのにコメントと仕様書が旧挙動のまま
    残っていた実例）。
  - **型・ファイルの削除・追加・リネームは、アーキテクチャ図とプロジェクト構成ツリーへの
    波及を必ず確認する**。上記の「仕様書を読み合わせて更新する」波及範囲には、
    `docs/dev/coding_rule.md` および `CLAUDE.md` のアーキテクチャ図（`## アーキテクチャ`）と
    プロジェクト構成ツリー（`## プロジェクト構成`）が含まれる。型の新設・削除・移動、
    ディレクトリの追加・廃止のいずれも、これらの図・ツリーとの突き合わせを同じ diff 内で行う。
    さらに、**プロパティ・型のリネームは、`coding_rule.md` 内のコード例・命名例・テスト例との
    突き合わせも行う**。規約ドキュメントが実在の識別子名をサンプルとして使用している場合、
    リネーム元の名前が残っていると規約とコードの乖離が生じる
    （`UpdateCheckCoordinator` を削除したがアーキテクチャ図に残っていた実例、
    `Updates/` ディレクトリを追加したが CLAUDE.md の構成ツリーに反映されていなかった実例、
    `isUnsupported` を `rejectReason` にリネームしたが命名例とテスト例に旧名が残っていた実例）
  - **「〜のみ」「常に〜」「〜のまま（変更しない）」のように現在の状態・変更有無を断定する
    コメントは、たとえ WHY 寄りであっても壊れやすい**。可視性ルール等を説明する正当なコメントでも、
    現状を事実として断定する部分（`private` → `internal` に変えたのに「internal のままにする」）は、
    コードを変えた瞬間に静かに偽になり「変更していない」という誤解を招く。状態を断定する語
    （のみ／常に／必ず／〜のまま）を含むコメントを残すなら、変更時にその断定が実物と一致するか
    を必ず読み合わせ、**なぜその状態にするか（WHY）**を主語にした記述へ寄せる
    （「internal のまま」ではなく「テストから呼ぶため internal にする」）。

```swift
/// ファイル変更を DispatchSource で監視し、変更時にコールバックを呼ぶ。
/// ファイル削除後の再作成（アトミック保存）にも対応するため、
/// ファイル本体とディレクトリの両方を監視する。
final class FileWatcher: @unchecked Sendable {
    // ...

    // MARK: - File Monitoring

    /// ファイルの書き込み・削除・リネームを監視する。
    /// 削除時はソースを解放し、ディレクトリ監視側で再作成を検知する。
    private func startFileMonitor() { ... }
}
```

- **インラインコメント**: 非自明な判断・ワークアラウンド・制約がある箇所に日本語で付ける

```swift
// WKWebView の背景を透明にする（公開 API がないため KVC を使用）
webView.setValue(false, forKey: "drawsBackground")

// JSONEncoder でエスケープし、JS インジェクションを防ぐ
guard let jsonData = try? JSONEncoder().encode(content) else { return }
```

- 書かなくてよいコメント:
  - コードをそのまま日本語に訳しただけのもの（`// ファイルを開く` → `openFile()` で自明）
  - タスク番号や変更履歴の参照（コミットメッセージに書く）

### テストコード

- **テスト関数の上**: 何を検証しているかが関数名で不十分な場合に `///` で補足する
- **テスト内のブロックコメント**: Arrange / Act / Assert や前提条件を日本語コメントで区切る

```swift
@Test(.timeLimit(.minutes(1)))
func detectsAtomicSave() async throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")

    await confirmation { confirm in
        let watcher = FileWatcher(path: file) {
            confirm()
        }

        // 初期化完了を待つ
        try? await Task.sleep(for: .seconds(0.3))

        // アトミック保存（一時ファイル → rename）をシミュレート
        let tmpFile = tmp.url.appendingPathComponent(".test.mmd.tmp")
        try? "graph TD; X-->Y".write(to: tmpFile, atomically: false, encoding: .utf8)
        _ = try? FileManager.default.replaceItemAt(file, withItemAt: tmpFile)

        // コールバック発火を待つ
        try? await Task.sleep(for: .seconds(3))
        watcher.stop()
    }
}
```

## JavaScript コーディング規約

- `viewer.js` にはテスト可能な純粋ロジックのみを置く（DOM 操作は `viewer.html` 側）
- CommonJS 互換の `module.exports` で関数をエクスポートする（Jest テスト用）
- `var` 宣言を使用する（WKWebView 内での互換性）
- **コメントは「コメント・ドキュメンテーション規約」に従う**。同節の例は Swift だが、
  規約は言語非依存であり `viewer.js` / `viewer.html` のコメントにも等しく適用される。
  特に「書かなくてよいコメント」の**タスク番号・issue 番号・変更履歴の参照は JS/HTML でも書かない**
  （`(issue #NNN)` のような記述はコミットメッセージ側に置く）。

## テスト規約

### 開発フロー（テスト先行）

- 新機能追加・仕様変更では、**先にテストを書き、そのテストを通す実装を行う**
- テストがすべてグリーンになった時点でタスク完了とみなす
- **不具合を確認したとき**: 先に落ちる回帰テストを追加してから修正する
- リファクタリングでは先に既存挙動をテストで固定してからコードを変更する

### テストフレームワーク

- **Swift**: Swift Testing（`import Testing`）を使う（XCTest は使わない）
- **JavaScript**: Jest を使う

### Swift テスト構造

- **`@Suite` + `struct`**: テストスイートは `struct` で定義し `@Suite` を付ける
- **`@Test`**: 各テスト関数に `@Test` を付ける
- **`#expect`**: アサーションには `#expect` マクロを使う（`XCTAssert` は使わない）
- **`@MainActor`**: `ViewerStore` など MainActor 隔離が必要なテストにはスイートレベルで `@MainActor` を付ける
- **`@Test(arguments:)`**: 同じアサーション構造で入力だけが異なるテストはパラメタライズする（pytest の `@pytest.mark.parametrize` に相当）
- **`confirmation`**: 非同期コールバックのテストには `confirmation { confirm in ... }` を使う
- **`.timeLimit`**: 非同期テストには `@Test(.timeLimit(.minutes(1)))` でタイムアウトを設定する

### テスト関数の命名規約

- テスト関数名は**テスト対象の振る舞いがわかる英語の lowerCamelCase** で付ける
- 形式: `func <動作説明>()` （Swift Testing では `test_` プレフィックス不要だが、慣例として付けてもよい）

```swift
// ✅ 良い例: 何をテストしているか一目でわかる
@Test func detectsFileModification() async throws { ... }
@Test func openNonexistentFileMarksDeleted() { ... }
@Test func coalescesRapidCalls() async { ... }
@Test func fileTypeDetection() { ... }

// ❌ 悪い例: 曖昧・長すぎる
@Test func test1() { ... }
@Test func testThatWhenAFileIsOpenedAndThenDeletedTheStoreMarksItAsDeleted() { ... }
```

### 共有テストヘルパー（TestSupport.swift）

以下の関心は必ず `TestSupport.swift` の共有ヘルパーで満たす。テストファイル内での自作は違反:

| 関心 | ヘルパー | 自作したら違反になるパターン |
|------|---------|------------------------------|
| 一時ディレクトリ | `TempDir` | `temporaryDirectory` + `UUID` + `defer` 削除の手組み |
| 独立した UserDefaults | `makeIsolatedDefaults(prefix:)` | `UserDefaults(suiteName:)` + `removePersistentDomain` の手書き |
| `Sendable` クロージャからの記録・カウント | `LockedBox<Value>` | `NSLock` + `@unchecked Sendable` ボックスの自作 |
| 条件成立までの待機 | `waitUntil(timeout:_:)` | 固定 `Task.sleep` の連打や独自ポーリングループ |

- **テストファイルに触れたら、変更行だけでなくファイル全体をヘルパー未使用の観点でスキャンする**。
  上表の手組みパターン（`temporaryDirectory` + `UUID` + `createDirectory` + `defer removeItem` 等）は
  「今回追加した行」に限らず、**以前から放置されていた既存の違反も同じタスク内で `TempDir` 等へ
  統一する**。差分の追加行しか見ないレビューだと、隣接する既存テストの手組みが延々と生き残る
  （新規追加でない既存 2 テストの手組み一時ディレクトリがレビューをすり抜けていた実例）
- `TempDir` は deinit で削除するため、非同期テストでは冒頭に
  `defer { withExtendedLifetime(tmp) {} }` を置いてテスト中の解放を防ぐ
- スイート固有のセットアップ定型（対象型の生成 + 依存注入）が 3 回以上繰り返されたら
  `makeController(file:)` / `makeStore(reader:)` のような `private` ファクトリ関数に抽出する

### Unit / Integration の分離

- 実ファイルシステム・実 `FileWatcher`・symlink 等の実デバイス挙動に依存するシナリオテストは
  ファイル名を `〜IntegrationTests.swift` にする
  （例外: `DirectoryLister` / `DefaultFileReader` のようにテスト対象自体がファイルシステム操作
  であるスイートは、実 FS を使っても unit 扱いでよい）
- unit テストではファイル読込を `InMemoryFileReader`、watcher をモック watcherFactory で置き換える
- **実ネットワークに到達するテストは書かない**。HTTP は `URLProtocol` スタブか
  モック Fetcher（`ReleaseFetching` 実装）を使う

### テストパターン

#### ファイルシステムテスト（FileWatcher / ViewerStore）

`TempDir` で一時ディレクトリを作る（deinit が削除を担う）:

```swift
@Test
func detectsFileModification() async throws {
    let tmp = try TempDir()
    defer { withExtendedLifetime(tmp) {} }
    let file = try tmp.file(named: "test.mmd", contents: "graph TD; A-->B")
    // ...
}
```

#### 非同期コールバックテスト

`confirmation` + `Task.sleep` で非同期イベントの発火を検証する:

```swift
@Test(.timeLimit(.minutes(1)))
func detectsFileModification() async throws {
    await confirmation { confirm in
        let watcher = FileWatcher(path: file) {
            confirm()
        }
        try? await Task.sleep(for: .seconds(0.3))
        // ファイルを変更
        try? await Task.sleep(for: .seconds(3))
        watcher.stop()
    }
}
```

- 「発火する」の検証は固定 sleep ではなく `waitUntil` で条件成立を待つ（CI の遅延に強い）
- **「発火しない」の検証は時限の境界を必ず跨ぐ**: グレース期間など「N 秒後に起きるはずの
  ことが起きない」ことを検証するときは、N より確実に長く（目安: N + 0.3 秒）待ってから
  アサートする。N 未満の待機は時限内に検証が終わり、機構が壊れていても通ってしまう。
  待機時間の根拠（どの時限に対する余裕か）をコメントに書く

#### 状態遷移テスト（ViewerStore）

同期的に操作して即座にプロパティを検証する:

```swift
@Test
func openMmdFile() throws {
    let store = ViewerStore()
    store.openFile(file)

    #expect(store.content == "graph TD; A-->B")
    #expect(store.fileType == .mmd)
    #expect(!store.isRejected)

    store.close()
}
```

### パラメタライズテスト（`@Test(arguments:)`）

同じアサーション構造で入力だけが異なるテストは個別の `#expect` を並べず `@Test(arguments:)` にまとめる。
ケースごとに独立実行され、どの入力で失敗したかが明確になる:

```swift
// ✅ 良い例: 入力と期待値のペアをパラメタライズ
@Test(arguments: [
    ("mmd", FileType.mmd),
    ("mermaid", FileType.mmd),
    ("MMD", FileType.mmd),
    ("md", FileType.markdown),
    ("markdown", FileType.markdown),
])
func fileTypeDetection(ext: String, expected: FileType) {
    let url = URL(fileURLWithPath: "/a/b.\(ext)")
    #expect(FileType(url: url) == expected)
}

// ❌ 悪い例: 同じ構造のアサーションを手動で並べる
@Test
func fileTypeDetection() {
    #expect(FileType(url: URL(fileURLWithPath: "/a/b.mmd")) == .mmd)
    #expect(FileType(url: URL(fileURLWithPath: "/a/b.mermaid")) == .mmd)
    #expect(FileType(url: URL(fileURLWithPath: "/a/b.md")) == .markdown)
    // → 最初の失敗で止まり、残りのケースが検証されない
}
```

パラメタライズを使うべき典型的なケース:
- 複数の入力に対して同じ変換結果を期待する（型判定・マッピング）
- 複数の無効入力に対して同じエラーを期待する
- 境界値テスト（最小・最大・境界+1）

#### パラメータが「値」でなく「対象プロパティ・振る舞い」のとき

「defaults 生成 → あるプロパティを true にする → 新インスタンスで true を期待」のように、
アサーション構造は同一で **対象プロパティだけが異なる** テスト群もパラメタライズ対象。
ただしパラメータに「どのプロパティを触るか」という振る舞いを載せる必要がある。

- **`ReferenceWritableKeyPath` を引数にしない**。`@Test(arguments:)` の引数は `Sendable` が要求されるが、
  `@MainActor` 隔離された型（`FindOptionsPreference` 等）のプロパティへの KeyPath は
  `@MainActor` 境界を跨げず `Sendable` 要件を満たせない。
- 代わりに、**`name` と `@MainActor @Sendable` の get/set クロージャを持つ `Sendable` な値型**で包む。
  クロージャに `@MainActor` を付けることで、隔離されたプロパティへのアクセスを型安全に閉じ込める。
- その値型に **`CustomTestStringConvertible` を実装**し、`testDescription` に `name` を返す。
  失敗時にどのプロパティのケースで落ちたかがテスト結果に表示される。

```swift
struct BoolProperty: Sendable, CustomTestStringConvertible {
    let name: String
    let get: @MainActor @Sendable (FindOptionsPreference) -> Bool
    let set: @MainActor @Sendable (FindOptionsPreference) -> Void
    var testDescription: String { name }
}

@Test("トグルした値は次のインスタンスへ引き継がれる", arguments: boolProperties)
func togglePersistsAcrossInstances(_ property: BoolProperty) {
    let defaults = makeIsolatedDefaults(prefix: "FindOptionsPreferenceTests")
    property.set(FindOptionsPreference(defaults: defaults))
    #expect(property.get(FindOptionsPreference(defaults: defaults)) == true)
}
```

#### パラメタライズ用のヘルパー型・本体関数の可視性

パラメータ型（`BoolProperty` / `FileTypeTraits` 等）と、それを引数に取るテスト本体関数の
可視性は **必ず同じレベルに揃える**。Swift のアクセス制御上、関数はその引数型より広い可視性を
持てないため、片方だけ `private` を付けると警告・エラーになる。

- `@Test` の本体関数はデフォルトで `internal`。これに合わせるなら **型も `internal`（修飾なし）**
  にする（`FindOptionsPreferenceTests.BoolProperty` の流儀）
- スイート内に閉じたいなら **関数・型の両方に `private`** を付ける
  （`FileTypeTests.FileTypeTraits` + `fileTypeTraits(_:)` の流儀）
- どちらでもよいが **同一テスト内では揃える**。片側だけ `private` を付けて可視性がちぐはぐな
  状態は違反とする

### テスト対象外

自動テスト対象外なのは「GUI 描画・フレームワーク統合に依存し、実行結果を値として
検証できない部分」であって、**型やファイル単位で免除されるわけではない**。

- WebView / GUI 層のうち、描画・レイアウト・ジェスチャ配線・WKWebView 統合など: 手動チェック
- `viewer.html` 内の DOM 操作ロジック: 手動チェック

#### SwiftUI View に純粋ロジックが同居する場合の判断基準

SwiftUI View（`FileListView` 等）でも、次の性質をすべて満たすロジックは
**GUI 免除の対象外**であり、「不具合修正時は先に回帰テストを追加する」の規定が優先される:

- 入力（引数・モデルの状態）と出力（戻り値・モデルの状態変化）が値として観測できる
- 検証に画面描画・実ウィンドウ・ユーザー操作イベントの発生を必要としない

典型例: 選択インデックスを進める / 戻す、境界で先頭を選ぶ、選択先の種別で分岐して
コールバックを呼ぶ（`selectNext` / `selectPrevious` / `handleKey` / `openIfFile`）といった
「純粋な選択・分岐ロジック」。これらはバグを確認したら先に落ちる回帰テストを書いてから修正する。

免除してよいのは、そのロジックを画面に反映する `body` / ジェスチャ / `onKeyPress` の配線部分だけ。

## エラーハンドリング規約

- ファイル読み取り失敗は `try?` で握りつぶし、空文字列にフォールバックする（ビューアアプリの特性上、致命的エラーにしない）
- ファイル削除はグレース期間(1 秒)後に `onFileGone` コールバックで通知し、ウィンドウを閉じる
- `guard` + early return で異常系を先に処理し、正常系のネストを浅く保つ

## コミット規約

Conventional Commits + 日本語:

```
<type>: <変更内容を動詞で始める日本語>

[body: 必要な場合のみ]
```

type の選択:
- `feat`: 新機能
- `fix`: バグ修正
- `chore`: ビルド・設定・依存関係
- `docs`: ドキュメントのみ
- `refactor`: 機能変更なしのコード整理
- `test`: テストの追加・修正
- `ci`: CI・リリースワークフロー

## 品質チェック手順

以下を順番に実行する:

1. **SwiftFormat**: `swift package plugin --allow-writing-to-package-directory swiftformat`
2. **Swift ビルド + SwiftLint**: `swift build`（SwiftLint はビルド時に自動実行）
3. **Swift テスト**: `swift test`
4. **JS テスト**: `npx jest`

すべてパスしたら完了。

## レビュー対応方針

- レビュー・自己チェックで指摘された内容は、同じタスク内で解消する。「次に
  触るときに」と先送りしない
- **「対応必須ではない」「任意」「現状維持でよい」は、実際に代替実装を試して
  比較した後にのみ許される結論である**。試さずに見送りを判断してはならない
- レビュー対象は差分の追加行に限定しない。**編集したファイル内の既存コードに規約違反が
  同居していたら、同じタスク内で是正する**（「今回の変更ではない」を放置の理由にしない）
- レビュー担当は、深刻度が低い指摘であっても「対応不要」の一言で済ませず、
  具体的な代替コードを示す。採用するかどうかの判断は、その代替コードを
  実際に適用・検証した結果に基づく

## 応答言語

- **会話**: ユーザーとのやりとりは基本的に**日本語**で行う
- **説明・コメント**: コード外の説明、コミットメッセージも日本語で書く
- **コード**: 変数名・関数名・ファイル名は英語（Swift API Design Guidelines 準拠）
- ユーザーが英語で質問した場合は、返答も英語で行う
