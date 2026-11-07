---
paths:
  - "**/*.swift"
  - "**/*.xcstrings"
---

# Swift コーディング規約

- Swift 6 strict concurrency（`SWIFT_STRICT_CONCURRENCY: complete`）
- `@MainActor @Observable` を ViewerStore に使用
- FileWatcher は `@unchecked Sendable`（内部 GCD キューでスレッド安全性を保証）
- UI コンポーネントは SwiftUI、ウィンドウ管理は AppKit（NSWindowController）
- 複数行にまたがる `if` / `guard` の条件は、`guard ... else { return }` の 1 行化か
  ヘルパー抽出で避ける。swiftformat が `{` を独立行へ送り、swiftlint の `opening_brace` が
  新規警告になる（両者の設定が衝突する箇所であり、どちらかを直すと他方が鳴る）
- **swiftformat と swiftlint が逆を要求したら、手で整形して往復しない。**
  多行コレクションの trailing comma・brace 位置などで両者の指摘が衝突する。
  `cd BefoldApp && swift package plugin --allow-writing-to-package-directory swiftformat`
  （fix モード）を回して機械に決めさせ、その結果に対して swiftlint 差分を測る。
  それでも swiftlint が鳴る構文は、リテラル・多行条件そのものを避ける形に書き換える
  （1 行に収める / 変数へ分解する / ヘルパーへ抽出する）
  - **編集ごとの PostToolUse フックは一部ターゲットしか lint しない**（`befold` /
    `befoldTests` が含まれず、コミット時の全ターゲット実行で初めて落ちる）。
    コミット前に上記コマンドを 1 回流し、`-- --lint` でゼロ件を確認してから commit する
- swiftlint は警告の絶対数では判定できない（main 時点でも既存の警告が数十件ある）。
  変更前後で一覧を取り、**main とのベースライン差分がゼロ**であることを確認する
  - **手順は `/swiftlint-baseline` にまとめてある。まずこれを使う。**
    以下はその中身の説明であって、手で組み直すための手順書ではない
    （手で組んで 1 回目を誤った実績がある）
  - swiftlint は `Package.swift` の `SwiftLintPlugins` がビルド時に実行するもので、
    単体ではインストールされていない（`brew install` すると CI とバージョンがずれる）。
    手元で一覧を取るにはプラグイン同梱のバイナリを直接呼ぶ:
    `(cd BefoldApp && .build/artifacts/swiftlintplugins/SwiftLintBinary/SwiftLintBinary.artifactbundle/macos/swiftlint lint --quiet)`
    **必ず `BefoldApp/` を CWD にする。** swiftlint は CWD 配下を走査するため、
    リポジトリルートで実行すると `.build` の生成物まで数えて実測 15,910 件になる
    （正しくは 54 件）。件数が 2 桁違うので気づけるが、気づかなければ差分ゼロの判定が壊れる
  - **ベースライン（main 側）を取るのに `git stash` を使わない。** stash は worktree 間で
    共有されるため、作業ツリーが clean だと `git stash push -u` が何も退避せず、続く
    `git stash pop` が**別のセッション・別プロジェクトの stash** を取り出して
    コンフリクトさせる。`git archive origin/main | tar -x -C <スクラッチパッド>` で
    別ディレクトリへ展開し、そちらで測る
- **機能を足すと既存ファイルが `file_length` / `type_body_length` /
  `cyclomatic_complexity` を超えることがある。** 閾値を緩めるのではなく、
  `Type+Feature.swift` の extension へ分割する（前例: `SidebarNavigator+FolderNavigation`、
  `MainMenuBuilder+ViewMenu`、`FileListModel+Snapshot`。
  テストは `DirectoryListerAppendingOpenFileTests` が同じ理由で分かれている）
  - **Swift の `private` はファイルスコープ**なので、分割した extension からは
    参照できない。移すメソッド本体だけでなく、**それが触る stored property・
    ヘルパーも internal へ上げる**必要がある。上げたものには
    「外から呼んでよいのはどれか」を doc コメントで明示して補う
    （実測: TASK-361 の分割 6 回のうち 3 回、この取りこぼしでビルドを往復した）
  - 分割は新規ファイルの追加なので `xcodegen generate` を忘れない
- **`Localizable.xcstrings` に文字列を追加するときはキー順にソートし直さない。**
  Xcode の出力は厳密なキー順ではないため、sort すると 200 行超の無関係な並べ替え差分が出る。
  既存の並び順を保ち、近縁キー（同じ prefix のもの）の直後に挿入する
