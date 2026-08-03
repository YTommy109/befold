# /swiftlint-baseline — main との swiftlint 差分をゼロ確認する

swiftlint は main 時点で 80 件ほど警告があるため、絶対数では合否を判定できません。
**main とのベースライン差分がゼロ**であることを確認してください。

以下をそのまま実行し、diff の結果を報告してください。

```bash
SCRATCH=<このセッションのスクラッチパッドディレクトリ>
ROOT=$(git rev-parse --show-toplevel)
LINT="$ROOT/BefoldApp/.build/artifacts/swiftlintplugins/SwiftLintBinary/SwiftLintBinary.artifactbundle/macos/swiftlint"

# 1. main 側のベースラインを別ディレクトリへ展開して測る
rm -rf "$SCRATCH/main-baseline"; mkdir -p "$SCRATCH/main-baseline"
git -C "$ROOT" archive origin/main | tar -x -C "$SCRATCH/main-baseline"
(cd "$SCRATCH/main-baseline/BefoldApp" && "$LINT" lint --quiet 2>/dev/null \
  | sed -E 's/:[0-9]+:[0-9]+:/:/' | sed "s|$SCRATCH/main-baseline/||" | sort > "$SCRATCH/lint-main.txt")

# 2. 作業ツリー側を測る
(cd "$ROOT/BefoldApp" && "$LINT" lint --quiet 2>/dev/null \
  | sed -E 's/:[0-9]+:[0-9]+:/:/' | sed "s|$ROOT/||" | sort > "$SCRATCH/lint-head.txt")

# 3. 比較
diff "$SCRATCH/lint-main.txt" "$SCRATCH/lint-head.txt"
```

判定:

- diff が空 → 合格。「新規違反ゼロ」と報告する
- **既存の違反行が数値だけ変わった差分**（`type_body_length` の行数が増減した等）は、
  違反の種類が増えていないので合格扱いにしてよい。ただし何がどう増えたかを報告に明記する
- 新しいファイル・新しいルールの行が増えていたら不合格。修正してから再実行する

注意:

- **`git stash` を使わない。** stash は worktree 間で共有されるため、作業ツリーが clean だと
  `git stash push -u` が何も退避せず、続く `git stash pop` が別のセッション・別プロジェクトの
  stash を取り出してコンフリクトさせる。必ず `git archive` で別ディレクトリへ展開する
- swiftlint は `Package.swift` の `SwiftLintPlugins` がビルド時に実行するもので単体では
  インストールされていない。`brew install` すると CI とバージョンがずれるため、
  上記のプラグイン同梱バイナリを直接呼ぶ（`.build` が無ければ先に `swift build`）
- 行番号がずれただけの差分を除くため `sed` で正規化してから diff する
- swiftformat と衝突する指摘は手で往復せず、先に swiftformat の fix モードを回す
  （`.claude/CLAUDE.md` の Swift コーディング規約を参照）
