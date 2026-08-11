# befold テスト規約

<!-- derived-from ../coding_rule.md -->

Swift Testing（`befoldTests` / `befoldCLITests`）と Jest（`BefoldApp/viewer-src/` の viewer 用 JS）のテスト規約。
コメント規約は [`./comments.md`](./comments.md) を参照（プロダクト/テスト共通）。
全体の位置づけは [`../coding_rule.md`](../coding_rule.md) を参照。

## 開発フロー（テスト先行）

- 新機能追加・仕様変更では、**先にテストを書き、そのテストを通す実装を行う**
- テストがすべてグリーンになった時点でタスク完了とみなす
- **不具合を確認したとき**: 先に落ちる回帰テストを追加してから修正する
- リファクタリングでは先に既存挙動をテストで固定してからコードを変更する

## テストフレームワーク

- **Swift**: Swift Testing（`import Testing`）を使う（XCTest は使わない）
- **JavaScript**: Jest を使う。テストは `BefoldKit/Resources/__tests__/` に置き、
  対象は成果物の `viewer-bundle.js` ではなくソースの `viewer-src/` を読む
  （純粋ロジックは `viewer-src/viewer.js` を直接 require、DOM 側は
  `__tests__/support/viewerMainHarness.js` が esbuild でバンドルして jsdom 上で評価する）

## Swift テスト構造

- **`@Suite` + `struct`**: テストスイートは `struct` で定義し `@Suite` を付ける
- **`@Test`**: 各テスト関数に `@Test` を付ける
- **`#expect`**: アサーションには `#expect` マクロを使う（`XCTAssert` は使わない）
- **`@MainActor`**: `ViewerStore` など MainActor 隔離が必要なテストにはスイートレベルで `@MainActor` を付ける
- **`@Test(arguments:)`**: 同じアサーション構造で入力だけが異なるテストはパラメタライズする（pytest の `@pytest.mark.parametrize` に相当）
- **`confirmation`**: 非同期コールバックのテストには `confirmation { confirm in ... }` を使う
- **`.timeLimit`**: 非同期テストには `@Test(.timeLimit(.minutes(1)))` でタイムアウトを設定する

## テスト関数の命名規約

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

## 共有テストヘルパー（BefoldTestSupport）

以下の関心は必ず `BefoldTestSupport` ターゲットの共有ヘルパーで満たす。テストファイル内での自作は違反:

`BefoldTestSupport` は `befoldTests` / `befoldCLITests` の双方から参照する単一情報源で、
依存は Foundation と Testing のみに保つ（GUI 本体 `befold` や `BefoldRenderKit` を
引き込まないため）。使う側のファイルには `import BefoldTestSupport` を書く。

ポーリングヘルパー（`waitUntil` 系）は、条件が成立しないままタイムアウトしたとき
**ヘルパー自身が `Issue.record` でテストを失敗させる**。呼び出し側の `#expect` に
頼らないのは、アサーションを書き忘れた箇所が「所定秒数を丸ごと浪費した上で
グリーン」になるのを防ぐため（実際にこの穴で、追い越しレースを一度も検証して
いないテストが 11 秒を浪費したままグリーンで放置されていた）。
新しい待機ヘルパーを足すときも同じ扱いにすること。

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
- **スイート内のテストヘルパー（ファクトリ・ビルダー・判定関数）の可視性は既存ヘルパーと揃える**。
  同じスイートの他のヘルパーがすべて `private` なら、新規追加分も `private` にする。
  パラメタライズ用ヘルパー型の可視性規定（[後述](#パラメタライズ用のヘルパー型本体関数の可視性)）と同じ原則——同一スイート内での一貫性——の
  適用範囲をファクトリ関数・判定ヘルパーにも広げたもの

## Unit / Integration の分離

- 実デバイス挙動・実プロセス挙動に依存するシナリオテストはファイル名を
  `〜IntegrationTests.swift` にする。対象となる「実挙動」には次を含む（これは網羅列挙ではなく
  代表例であり、**下の判定基準を満たすなら未列挙のものも Integration 扱いにする**）:
  - 実ファイルシステムへの読み書き（一時ファイル・ディレクトリ操作）
  - 実 `FileWatcher` によるファイル変更検知
  - symlink 解決・実パス正規化
  - **実行ファイルのサブプロセス起動**（`Process` でビルド済みバイナリを起動し、
      標準出力・終了コード・CLI 引数解釈を検証するテスト）
  - 判定基準: **テスト対象自体をインメモリ／モックに差し替えられず、OS・ファイルシステム・
    別プロセスの実挙動が結果を左右する**なら Integration。差し替え可能な純粋ロジックは unit。
  （例外: `DirectoryLister` / `DefaultFileReader` のようにテスト対象自体がファイルシステム操作
  であるスイートは、実 FS を使っても unit 扱いでよい）
- unit テストではファイル読込を `InMemoryFileReader`、watcher をモック watcherFactory で置き換える
- **実ネットワークに到達するテストは書かない**。HTTP は `URLProtocol` スタブか
  モック Fetcher（`ReleaseFetching` 実装）を使う
- **モデル状態しか見ないテストで `NSWindow` + `WKWebView` をフル構築しない**。検証したいのが
  値として観測できるモデル状態の変化であれば、注入シーム（ビュー生成クロージャ、
  `directoryLister` のような列挙クロージャ等）がある限りそれ経由で unit 化する。
  Integration に残すのは、実 FS・実プロセス・実 WebKit の挙動そのものが検証対象であるものだけ

## テストパターン

### ファイルシステムテスト（FileWatcher / ViewerStore）

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

### 非同期コールバックテスト

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
  **N は経路上の全時限を合算すること**。単一の時限だけを数えて過小評価すると、経路の途中に
  ある別の時限（例: rename 経由の書き込みでは `renameSettleDelay` + `debounceDelay` の 2 段）を
  見落とし、待機不足で偽陰性になる（`FileWatcher` の「発火しない」検証で `debounceDelay` だけを
  数えて `renameSettleDelay` を見落としていた実例）。
  待機時間の根拠（どの時限に対する余裕か）をコメントに書く
- **`waitUntil` でポーリング成立を確認した後に、検証対象を取り直さない**。成立後に同じ getter を
  もう一度呼ぶと、`await` の再開点を挟んだ別取得になり、その間の状態遷移（対象オブジェクトの
  再生成・再代入）と競合して CI の高負荷時に不安定に失敗する。ポーリング中に掴んだ値を箱
  （`var box`）へ退避し、その値をそのまま `#require` / `#expect` に渡す
  （`waitUntilOnMainActor` 成立後に `makeCodeButton()` を再呼び出しして検証していた
  ツールバーテストが CI で不安定に失敗した実例）

### 状態遷移テスト（ViewerStore）

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

## パラメタライズテスト（`@Test(arguments:)`）

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

### パラメータが「値」でなく「対象プロパティ・振る舞い」のとき

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

### パラメタライズ用のヘルパー型・本体関数の可視性

パラメータ型（`BoolProperty` / `FileTypeTraits` 等）と、それを引数に取るテスト本体関数の
可視性は **必ず同じレベルに揃える**。Swift のアクセス制御上、関数はその引数型より広い可視性を
持てないため、片方だけ `private` を付けると警告・エラーになる。

- `@Test` の本体関数はデフォルトで `internal`。これに合わせるなら **型も `internal`（修飾なし）**
  にする（`FindOptionsPreferenceTests.BoolProperty` の流儀）
- スイート内に閉じたいなら **関数・型の両方に `private`** を付ける
  （`FileTypeTests.FileTypeTraits` + `fileTypeTraits(_:)` の流儀）
- どちらでもよいが **同一テスト内では揃える**。片側だけ `private` を付けて可視性がちぐはぐな
  状態は違反とする

## テスト対象外

自動テスト対象外なのは「GUI 描画・フレームワーク統合に依存し、実行結果を値として
検証できない部分」であって、**型やファイル単位で免除されるわけではない**。

- WebView / GUI 層のうち、描画・レイアウト・ジェスチャ配線・WKWebView 統合など: 手動チェック
- `viewer.html` 内の DOM 操作ロジック: 手動チェック

### SwiftUI View に純粋ロジックが同居する場合の判断基準

SwiftUI View（`FileListView` 等）でも、次の性質をすべて満たすロジックは
**GUI 免除の対象外**であり、「不具合修正時は先に回帰テストを追加する」の規定が優先される:

- 入力（引数・モデルの状態）と出力（戻り値・モデルの状態変化）が値として観測できる
- 検証に画面描画・実ウィンドウ・ユーザー操作イベントの発生を必要としない

典型例: 選択インデックスを進める / 戻す、境界で先頭を選ぶ、選択先の種別で分岐して
コールバックを呼ぶ（`selectNext` / `selectPrevious` / `handleKey` / `openIfFile`）といった
「純粋な選択・分岐ロジック」。これらはバグを確認したら先に落ちる回帰テストを書いてから修正する。

免除してよいのは、そのロジックを画面に反映する `body` / ジェスチャ / `onKeyPress` の配線部分だけ。

## CI 時間・並列性に関するルール

<!-- derived-from #非同期コールバックテスト -->

テストコード全体レビュー（2026-08-01）で顕在化した、CI の実行時間・安定性に効く項目。
いずれも「テストが落ちる」方向ではなく「壊れていても通ってしまう」方向の劣化として見つかっている。

### `@Suite(.serialized)` は根拠コメント必須、直列化が必要な最小スイートに限定する

- `.serialized` を付ける理由をスイート直前にコメントで書く。「たまたま同じファイルにある」
  ではなく「プロセス全体の基準線（fd 数・スレッド数など）を汚しうるから」のように、
  何を守るための直列化かを説明する（実例: `GitCommandRunnerTests`）
- **落とし穴**: `.serialized` はそのスイート内しか直列化しない。「基準線を計測するテスト」と
  「基準線に影響する資源を生成するテスト」を別スイートへ分けると、後者は並列実行される
  ラウンドに乗り、前者が偽陰性（本来落ちるべきが通る）になる。スイートを分割するときは
  「並列側が計測対象に影響しないか」を必ず確認する
- 不変条件（何を守るための分離か）は、割った先の両方のスイート（守る側・並列化した側）に
  書く。将来テストを追加する人が読むのは追加先のスイートであり、片方にしか書かれていないと
  見落とされる

### 待機ループは必ず上限つきにし、超過時に `Issue.record` で失敗させる

- `while` + `Task.yield()` の自作 busy-yield は、対象のフラグが回帰で降りなくなったとき
  上限なしでは CI のタイムリミット（現行 120 秒）まで実行を占有し続ける
- 上限つきの待機は共有ヘルパー `waitUntil(timeout:_:)` を使う（既出、[共有テストヘルパー](#共有テストヘルパーbefoldtestsupport)節）。
  自作する場合も同じ扱い（タイムアウト時に `Issue.record` で失敗させる）にする
- 非同期スイートには `.timeLimit` を付ける（既出）

### 否定検証（発火しない・観測しない）は配送機構の差し替え優先、次に番兵、最後に固定待ち + 0.3 秒

- 固定タイムアウト待ちは「まだ来ていないだけ」と「来ない」を区別できない
- **番兵（sentinel）が使える経路では番兵を優先する**: 別の観測可能なイベントを先に肯定的に
  配送・完了させてから「対象イベントは来ていない」を検証する（実例:
  `DistributedAckWaiterIntegrationTests`）。固定待ちより短時間で、かつ「配送機構自体は動いた」
  ことを肯定的に確定できる
- **番兵方式にも限界がある**: 番兵が担保するのは「配送機構が動いた」ことだけであり、
  `DistributedNotificationCenter` のように 1 通を同一スレッドの 1 パスで全 observer に
  同期配信する仕組みでも、**同一パス内の observer 呼び出し順は規定されない**。番兵の
  observer が対象より先に呼ばれた瞬間をサンプリングすると、「対象はまだ呼ばれていないだけ」を
  「観測しなかった」と誤判定しうる——このセクション冒頭が戒めている「壊れていても通ってしまう」
  劣化を、番兵方式自身が別の形で持ち込む
- **番兵の段数を増やす前に、配送機構そのものを差し替えられないか検討する**。否定検証の対象が
  「フィルタ条件」「解除処理」のような自前ロジックであれば、通知センター等を注入シームで
  差し替え、**post が同期的に全 observer を呼び切る**ローカル実装に対して検証するのが最も確実で
  速い。この場合、番兵は不要になり順序の問題自体が消える
- 実配送のまま順序の窓を閉じたい場合、理論上は **2 回目の配送を観測**して 1 回目のディスパッチ
  パス完了を確定できる（配送は直列化されるため）。ただし**この方法は肯定待機を直列に積むため、
  負荷時のコストが跳ね上がる**。befold では実測でフル実行 6 回中 4 回失敗（単独実行では
  10/10 グリーン）し、1 段番兵へ戻した。**配送がメインランループ経由の場合、他スイートが
  メインアクターを長時間占有していると配送自体が数秒単位で止まる**ため、待機を増やすほど
  予算を超えやすくなる
- 実配送のまま 1 段番兵で運用する場合は、**「対象の observer を番兵より先に登録している」前提を
  コメントで明示する**（登録順に呼ばれる実装依存であることを残す）。残る窓はマイクロ秒オーダー
  で、赤くなるリスクとのトレードオフとして許容する（実例: `DistributedAckWaiterIntegrationTests`）
- **待機予算は共有ヘルパーの既定値を使う**。個別に短い値（5 秒等）を置くと、上記の配送停止に
  当たったときに取りこぼしと区別が付かない失敗になる
- 番兵が使えない時限系（グレース期間など「N 秒後に起きるはずのことが起きない」ことの検証）は
  [非同期コールバックテスト](#非同期コールバックテスト)節の「N + 0.3 秒」ルールをそのまま適用する。
  ここでは適用範囲の整理（番兵が使えないときのフォールバックである）だけを述べる。
  待機時間の根拠（どの時限に対する余裕か）を必ずコメントに書く

### テストの移設・統合・パラメタライズは、元の不変条件を列挙してから行う

CI 時間短縮を目的にテストを整理するときに最も繰り返し起きる事故（レビューで 4 件検出）。
いずれも「通ってしまう」方向の劣化で、後から気づけない:

- 純関数化に伴う移設で、分岐なし経路の検証が消えていた
- スタブ化に伴う書き換えで、「選択候補のファイルがあっても自動選択しない」の検証が、
  候補ファイルを置かなかったため空振りになっていた
- 競合テストの待機順序が保証されなくなり、検証対象の世代ガードを削除しても通る状態になっていた
- 実 git テストの統合で「本体が先頭に来る」の assertion が半分しか引き継がれていなかった

対策:

1. 移設・統合・パラメタライズの前に、元のテストが固定していた assertion をすべて列挙する
2. 作業後にその列挙と照合し、抜けがないか確認する
3. 可能なら変異テスト（検証対象のガード・分岐を一時的に壊してテストが落ちるか）で確認する

競合（世代ガード等）のテストを書く・移設するときの一般則: **各世代のタスクハンドルを個別に
掴み**、ゲートで「新しい方を先に確定 → 古い方を後から返す」順序を明示的に固定してから
assert する。最新のみを公開するプロパティ（`pendingListingTask` 等）を await しただけでは、
古い方の完了を待つことにならず競合の勝敗を固定できない。

### `@MainActor` スイートは隔離が必要なテストに限定する

- MainActor 隔離が必要なテスト（`ViewerStore` 等）だけを `@MainActor` スイートに置く
- static な純関数のテストは非 `@MainActor` スイートへ分離し、並列レーンで走らせる。
  `@MainActor` を付けたままにすると本来並列化できるテストが直列化され、CI 時間が伸びる
- 判断の目安: `@Observable` なモデル（`ViewerStore` 等）に触れるか、`NSWindow` 等 AppKit の型を
  構築するかのどちらかに該当すれば `@MainActor` が必要。どちらにも該当しなければ非 `@MainActor`
  スイートへ置く

### テストが依存する未文書化挙動は、API 側の `///` にも明文化する

テスト側だけが知っている前提（例: `wait(timeout: 0)` は即座に返る）は、プロダクト側の
無害に見えるリファクタで静かに壊れる。テストがある挙動に依存するなら、その挙動を保証する
関数・型の `///` ドキュメントコメントにも明文化し、テストコメントだけに留めない。

### テストが CI 実行時間に効くかは、着手前に実測で確認する

- フル実行時の「スイート別の所要時間」はそのスイートの仕事量ではなく、他スイートの完了待ちを
  含んだスケジューリングの産物であり、そのまま律速要因の特定には使えない。単独実行
  （`--filter` でそのスイートだけ実行）で計測すること
- 実例: フル実行 13 秒のうち律速は特定の 1 スイート（単独実行で 13.0 秒）であり、他のスイートを
  いくら縮めても全体時間は変わらなかった。「巨大フィクスチャを縮小すれば TSan ジョブが縮む」
  という見積もりも、対象 3 スイートを TSan 下で単独計測すると合計 1.1 秒しかなく、実測で否定された
- TSan ジョブの所要時間は計装ビルド自体が支配的で、テスト実行時間の寄与は小さい。
  CI 時間短縮に着手する前に、対象がボトルネックかどうかを実測で確認してから着手する
- **テストの安定性に関わる変更は、スイート単独実行でなくフル実行で確認する**。単独実行では
  他スイートによるメインアクター占有・スレッドプール飽和が再現せず、負荷起因の不安定さを
  見逃す（2 段番兵が単独 10/10 グリーン・フル実行 6 回中 4 回失敗だった実例）。
  グリーンの根拠を確認する手順は [品質チェック手順](./workflow.md#品質チェック手順)を参照

### テスト内のキャッシュは immutable な `static let` で持つ

- 高価な読み込み（plist・カタログ・フィクスチャ）をテスト間で使い回すときは、**起動時に一括
  ロードする `static let`** にする。以後書き換えないので並列実行下でも競合しない
- **`static var` + 遅延書き込み（初回アクセス時にキャッシュへ代入）は禁止**。swift-testing は
  既定でテストを並列実行するため、複数テストが同時に書き込み、非 Sendable な値
  （`[String: Any]` 等）ではシグナル 6 でクラッシュする
  （実例: `QuickLookInfoPlistTests` を可変 `static var` + 遅延ロードで実装して踏んだ）
- 遅延・可変がどうしても必要なら共有ヘルパーの `LockedBox`（[共有テストヘルパー](#共有テストヘルパーbefoldtestsupport)節）を使う。
  `nonisolated(unsafe)` を付けるのは「以後書き換えない」ことがコード上明らかな場合に限り、
  その理由を `///` に書く
- キャッシュ化と同時に、**読み込み失敗を空値へフォールバックさせない**。空辞書を返すと
  「型が見つからない」等の無関係な assertion 失敗に化けるため、`#require` で即座に落とす
