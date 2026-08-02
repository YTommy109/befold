# befold プロダクトコード規約

<!-- derived-from ../coding_rule.md -->

Swift プロダクトコード（`befold` / `BefoldKit` / `BefoldRenderKit` / `BefoldCLI` /
`befold-cli` 本体）と `viewer.js` 等の JavaScript コードの規約を扱う。
コメント・ドキュメンテーション規約は言語・プロダクト/テスト共通のため
[`./comments.md`](./comments.md) に独立している。全体の位置づけは
[`../coding_rule.md`](../coding_rule.md) を参照。

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
- **テスト容易性のための可視性**: SwiftUI View 等に同居する純粋ロジック（[「テスト対象外」節](./testing.md#テスト対象外)の
  判断基準——**入力と出力が値として観測でき、検証に画面描画・実ウィンドウ・ユーザー操作イベントを
  必要としない**——を満たすもの）をテストターゲットから直接呼びたい場合、そのメソッドは `private` を外して
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
- **既存経路が守っていた不変条件を跨ぐ最適化・ショートカット・強制分割を足すときは、
  その経路が保証していた不変条件を全部列挙し、新経路が全部を保存することを確認する**。
  「今回の動機になった 1 つの不変条件」だけを見て入れたショートカットが、同時に成り立って
  いた他の不変条件（文字境界・引用符などの構文状態・行境界・境界値ちょうど一致時の扱い）を
  静かに壊す。特に走査中に共有されるフラグ（`inQuotes` のような構文状態）を最適化のために
  **書き換える**と、本来の構文でその状態を戻す入力が後から来たときに以降の解釈が全て反転する。
  「本来の状態管理を書き換える」のではなく「諦めを別フラグで表現し、本来の状態は toggle だけで
  正しく保つ」設計を優先する
  （バイト上限での強制分割を入れた `StringChunkReader` が、UTF-8 継続バイトの二重カウント・
  正規クォートフィールドのクォート状態破壊・不平衡クォート後のチャンク行数超過・サイズが上限
  ちょうどのときの偽トランケーションを次々に生んだ実例。500 バイトで `inQuotes` を強制 false に
  した修正がさらに 3 つの正確性バグを生み、`hasGivenUpQuoteTracking` で「諦め」を分離し
  `inQuotes` は toggle のみで管理する設計に変えて解消した）

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
| BOM 検出（バイトパターン→エンコーディング） | `TextEncoding.detectBOM(_:)`（`decodeText` / `detectEncoding`（内部の `detectEncodingAndDecode` 経由）と `DefaultFileReader.isBinary` の双方がここに委譲） |
| テキスト復号（BOM / UTF-16 / UTF-8 / レガシーエンコーディング） | `TextEncoding.decodeText(_:)` / `detectAndDecodeText(_:)`（`DefaultFileReader.readString` と `NormalizedTextCache.init(data:)` の双方がここに委譲。行チャンク読み込みを担う `StringChunkReader` は `NormalizedTextCache` が復号済みの文字列を読むだけで、自前のエンコーディング判定は行わない） |
| ディレクトリ列挙（ソート・フィルタ込み） | `DirectoryLister.sortedContents(in:showHiddenFiles:)`（`listFiles` / `listEntries` / `firstSupportedFile` / `allEntriesSorted` が委譲） |
| ドット始まり（隠しファイル）判定 | `HiddenFileRule.isHidden(component:)` / `containsHiddenComponent(inRelativePath:)`（Quick Open の走査 `DirectoryFileScanner`・索引 `QuickOpenCandidates`・パスモード `QuickOpenModel` が委譲。`name.hasPrefix(".")` を各所で組み立て直さない。サイドバー系が使う FileManager の `.skipsHiddenFiles` は chflags hidden も隠すため定義が異なる。使い分けの理由は `HiddenFileRule` の `///` を参照） |
| Sparkle フィード URL | `UpdateChannel.feedURLString`（`SPUUpdaterDelegate.feedURLString(for:)` 経由で Sparkle に提供。Info.plist の `SUFeedURL` は使用しない） |

- **同一 diff 内の自己整合性**: 単一情報源テーブルへのエントリ追加・共通関数の新設を含む diff では、
  **その同じ diff 内の全コードが新設した情報源を使っているか** をセルフレビューで照合する。
  「テーブルに登録したが、同じ PR の別ファイルでは自前実装している」は、既存コードとの重複と
  同じ違反である。同様に、ある制約を表す既存の定数（`maxTextFileSizeBytes` 等）が存在するとき、
  同じ制約を意図する新規コードで別の定数（`maxFileSizeBytes` 等）を参照するのは
  「同じ知識の二重表現」であり違反とする
  （`decodeText` をテーブル登録した同じ diff で別の関数が自前デコードしていた実例、
  テキストファイルサイズ上限に汎用の `maxFileSizeBytes` を使い `maxTextFileSizeBytes` と
  不整合を起こした実例）
- **言語・レイヤをまたぐ定数**（Swift ↔ viewer.js、Swift ↔ ビルド設定 `project.yml`／
  Info.plist、Swift ↔ シェル等、コンパイラが同一性を保証できない境界をまたぐ定数）は
  避けられない場合のみ二重定義し、(1) **両方の定義箇所**に対応相手を示すコメント
  （viewer.js／Swift だけでなく `project.yml` 側にも相互参照コメントを書く）、
  (2) 一致を検証するテストを必ずセットで付ける。
  - **要件(2)の「ソースを読んで一致を検証」とは、テストが相手側の実ソース
    （`project.yml`／`viewer.js` 等）をその場で読み取り、自分側の定数と突き合わせることを指す。
    両辺が同じ一つの値から導出されるトートロジー（恒真）検証はこの要件を満たさない。**
    たとえば「`AppVersion.current` == `AppVersion.current`」や、Swift 側の定数同士を比較する
    テストは、相手（`project.yml` の `MARKETING_VERSION`）が食い違ってもグリーンのままで、
    ドリフトを一切検知できない。テストは**必ず相手側ファイルをパース・読み取りして比較する**
    こと（`project.yml` を読んで `MARKETING_VERSION` を抽出し `AppVersion.current` と照合する、
    `viewer.js` のソースを読んで数値リテラルを照合する `ViewerBridgeTests.zoomRangeMatchesZoomStore`
    の流儀）。
  - セルフチェック指標: 「相手側の値を書き換えたらこのテストは落ちるか？」を自問する。
    落ちないならトートロジーであり、検証になっていない。
  （`AppVersion.current` と `MARKETING_VERSION` の二重定義で、project.yml 側の相互参照コメントが
  欠落し、かつ検証テストが両辺とも `AppVersion.current` 由来でトートロジーになっていて
  ドリフトを検知できなかった実例）
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
- コンテンツ差分チェック（`lastRenderedContentRevision`）で不要な再描画を防ぐ
- 複数のフラグを必ずセットで倒す状態遷移（例: 直接 HTML モード解除）は専用メソッドに
  集約し、不変条件を `///` に明記する（呼び出し側での部分リセットを禁じる）

## JavaScript コーディング規約

- `viewer.js` にはテスト可能な純粋ロジックのみを置く（DOM 操作は `viewer.html` /
  `viewer-main.js` 側）。DOM に触れない純粋述語を `viewer-main.js` に書き足したくなったら
  `viewer.js` へ置き、`module.exports` に載せて Jest から直接テストする
- CommonJS 互換の `module.exports` で関数をエクスポートする（Jest テスト用）
- `var` 宣言を使用する。macOS 14+ の WKWebView は `const` / `let` も解釈できるため
  技術的制約ではなく、同梱 JS（`viewer.js` / `viewer-main.js`）が全面的に `var` で
  書かれているための一貫性ルールである。混在させず既存に揃える
- **コメントは [`./comments.md`](./comments.md) に従う**。同ファイルの例は Swift だが、
  規約は言語非依存であり `viewer.js` / `viewer-main.js` / `viewer.html` のコメントにも
  等しく適用される。
  特に「書かなくてよいコメント」の**タスク番号・issue 番号・変更履歴の参照は JS/HTML でも書かない**
  （`(issue #NNN)` のような記述はコミットメッセージ側に置く）。

## エラーハンドリング規約

- ファイル読み取り失敗は `try?` で握りつぶし、空文字列にフォールバックする（ビューアアプリの特性上、致命的エラーにしない）
- ファイル削除は監視デバウンス間隔の 5 倍のグレース期間(プロダクト既定 1 秒)後に
  `onFileGone` コールバックで通知し、ウィンドウを閉じる
- `guard` + early return で異常系を先に処理し、正常系のネストを浅く保つ
