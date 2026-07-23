# CLIサブコマンド廃止・フラット化 設計

## 背景・課題

<!-- derived-from ./2026-07-06-cli-install.md -->

befold CLI は現在 `open`(既定)/`bookmark`/`check` の3サブコマンドを持つ
(`BefoldRootCommand.swift`)。TASK-94.4 でトップレベル `--help` に
`open` のオプション(`--hidden-files`/`--sort`/`--line-numbers`/`--source`/`--preview`)
を表示するため、root に `@OptionGroup var openOptions: OpenCLIOptions` を追加したが、
これにより「`befold --hidden-files check path` のようにサブコマンド名の前に
`open` 専用フラグを置くと root がフラグを黙って消費し、`check`/`bookmark` へ
渡らず警告もエラーも出ない」というバグ(TASK-97)が発生し、`@OptionGroup` を
root から削除して巻き戻した。

結果として「`open` のオプションをトップレベル `--help` にも表示する」という
要求と「サブコマンド前の `open` 専用フラグを黙殺しない」という要求が、
`@OptionGroup` 共有という実装手段のもとでは両立しない状態になっている。

## 根本原因

サブコマンド分割そのものが、この2つの要求の対立を生んでいる。
swift-argument-parser はサブコマンドをargv位置で振り分けるため、
「オプションがどのコマンドに属するか」がトークンの並び順に依存し、
親子でオプションを共有すると親側が先に消費してしまう。

## 方針: サブコマンドを廃止し、単一コマンド + フラグに統合する

`open`/`bookmark`/`check` という3つの `ParsableCommand` をやめ、
`BefoldRootCommand` 1つに統合する。`bookmark`/`check` は
値を取らないブールフラグ `--bookmark`/`--check` とし、位置引数 `paths` を
共通の対象パスリストとして扱う。

単一コマンドになるため、ArgumentParser の標準 `--help` 生成が
全オプション(`--check`/`--bookmark`/`--hidden-files`/`--sort`/`--line-numbers`/
`--source`/`--preview`)を自動的に1画面へ列挙する。サブコマンドという
「位置による振り分け」が存在しないため、TASK-97 のようなフラグ黙殺は
構造的に発生しない。

## コマンド仕様

```
struct BefoldRootCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "befold",
        abstract: "Mermaid/Markdown viewer.",
        usage: "befold [options] [file/folder...]",
        version: AppVersion.current
    )

    @Flag(name: .customLong("check"), help: "Check whether the given paths can be opened, instead of opening them.")
    var check = false

    @Flag(name: .customLong("bookmark"), help: "Bookmark the given paths, instead of opening them.")
    var bookmark = false

    @OptionGroup var openOptions: OpenCLIOptions

    @Argument(help: "Paths of files/folders to open (or check/bookmark with --check/--bookmark).")
    var paths: [String] = []

    func validate() throws {
        try openOptions.validate()
        if (check || bookmark) && paths.isEmpty {
            throw ValidationError("At least one path is required with --check/--bookmark.")
        }
    }

    func run() throws {
        if check || bookmark {
            var anyFailed = false
            if check {
                for path in paths {
                    let result = CLICheckCommand.run(path)
                    print/stderr(result.message)
                    if result.exitCode != 0 { anyFailed = true }
                }
            }
            if bookmark {
                for path in paths {
                    let result = CLIBookmarkCommand.run(path)
                    print/stderr(result.message)
                    if result.exitCode != 0 { anyFailed = true }
                }
            }
            exit(anyFailed ? 1 : 0)
        }
        AppDelegate.launch(withInitialPaths: paths, options: options)
    }
}
```

`OpenCLIOptions`(`--hidden-files`/`--no-hidden-files`/`--sort`/`--line-numbers`/
`--no-line-numbers`/`--source`/`--preview`)はそのまま流用する。共有先が
1つの `ParsableCommand` のみになるため、`@OptionGroup` を使っても
TASK-97 のような曖昧さは生じない(サブコマンド振り分けが存在しないため)。

## 確認済みの挙動(ユーザーとの合意事項)

- `--check`/`--bookmark` は値を取らないブールフラグ。位置引数 `paths` を
  共通の対象パスリストとして扱う(例: `befold --check a.md b.md` は
  `a.md`/`b.md` の両方を check 対象にする)。
- `--check` と `--bookmark` は併用可能。両方指定時は **check → bookmark の順で
  全パスに対して実行**し、いずれか1件でも失敗すれば終了コードは非0にする
  (現行 `CLICheckCommand` の exitCode 方式を踏襲)。
- `--check`/`--bookmark` 指定時はファイルを開かない(`AppDelegate.launch` を
  呼ばない)。
- `--check`/`--bookmark` を指定したのに `paths` が空の場合は
  `validate()` でエラーにする(黙殺しない)。
- `bookmark` は現状 `add` という動詞のみ実装されているため、
  `--bookmark <path...>` に統合し、動詞を廃止する(YAGNI)。将来
  `remove` 等が必要になれば `--bookmark-remove` を別途追加する。
- 旧構文(`befold bookmark add <path>` / `befold check <path>`)は
  クリーンブレイクで完全に廃止する。README等の外部ドキュメントに
  依存箇所はない(確認済み)。

## 影響ファイル

- `BefoldApp/befold/App/BefoldRootCommand.swift`: `OpenPathsCommand`/
  `BookmarkPassthroughCommand`/`CheckPassthroughCommand` を削除し、単一の
  `BefoldRootCommand` に統合する。
- `BefoldApp/befold/App/CLISubcommandCommand.swift`: `CLIBookmarkCommand`/
  `CLICheckCommand` の独自 `--help`/`-h` ハンドリングと引数個数チェックを
  削除し(ArgumentParser が担うため不要)、単一パスを受け取って
  `CLICommandResult` を返す関数として残す。複数パスのループは呼び出し側
  (`BefoldRootCommand.run()`)が担う。
- `BefoldApp/befoldTests/BefoldRootCommandTests.swift`,
  `BefoldRootCommandIntegrationTests.swift`,
  `BefoldApp/befoldTests/CLIBookmarkCommandTests.swift`,
  `BefoldApp/befoldTests/CLICheckCommandTests.swift`: 新フラグ体系に
  合わせて全面改訂。特に以下を回帰テストとして追加する:
  - `befold --check a.md b.md` が両方を check し、片方失敗時に終了コード非0
  - `befold --check --bookmark a.md` が check→bookmark の順で実行される
  - `befold --hidden-files check.md` のように旧サブコマンド名と同名の
    ファイルパスがそのまま open 対象として扱われる(サブコマンド解釈が
    存在しないことの確認)
  - トップレベル `--help` に `--check`/`--bookmark`/`--hidden-files`/
    `--sort`/`--line-numbers`/`--source`/`--preview` がすべて含まれる

## スコープ外

- `--bookmark-remove` 等、`add` 以外のbookmark操作(将来必要になった時点で
  別タスクとして追加)。
- 旧構文との後方互換シム(クリーンブレイクとして合意済み)。
