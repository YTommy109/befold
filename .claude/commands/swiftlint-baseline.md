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

# 4. 件数だけの増減を除き、「ルール × ファイル」の組で比較する
#    （既存違反の行数が 312 → 300 のように動いただけの差分を機械的に除く）
norm() { sed -E 's/currently [a-z ]*[0-9]+ lines//; s/currently contains [0-9]+//; s/currently complexity is [0-9]+//' "$1" | sort -u; }
norm "$SCRATCH/lint-main.txt" > "$SCRATCH/n-main.txt"
norm "$SCRATCH/lint-head.txt" > "$SCRATCH/n-head.txt"
echo "=== 真の新規 ==="; comm -13 "$SCRATCH/n-main.txt" "$SCRATCH/n-head.txt"
echo "=== 解消したもの ==="; comm -23 "$SCRATCH/n-main.txt" "$SCRATCH/n-head.txt"
```

判定:

- **手順 4 の「真の新規」が空 → 合格。**「新規違反ゼロ」と報告する
- 手順 3 の `diff` に差分があっても、**既存の違反行が数値だけ変わったもの**
  （`type_body_length` の行数が増減した等）は違反の種類が増えていないので合格扱いにしてよい。
  ただし何がどう増減したかを報告に明記する
- 新しいファイル・新しいルールの行が増えていたら不合格。修正してから再実行する

手順 3 の生の `diff` だけで判定しない。機能を足すと既存の大きいファイルの行数が動き、
**合格すべき差分が毎回 10 行前後出る**。目視で「これは数値だけ」と選り分けていると、
その中に紛れた本物の新規違反を見落とす（TASK-361 では 5 サブタスクで 4 回この選別が
必要になり、手順 4 の正規化を毎回その場で書き直していた）。

手順 4 の「解消したもの」も報告に含める。分割やリファクタで既存違反が減ったことは
成果なので、黙って捨てない。

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
