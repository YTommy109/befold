# dev リリースのバージョニング修正 設計

日付: 2026-07-07
状態: 承認済み

## 背景と問題

`scripts/bump.sh dev` はリリース済みの現行バージョン(`MARKETING_VERSION`、例 `1.4.8`)を
そのままベースに `v1.4.8-dev.N` タグを作る。SemVer ではプレリリース版は同じ数値部分の
正式版より古い(`1.4.8-dev.1 < 1.4.8`)ため、develop チャンネル
(`defaults write com.degino.befold UpdateChannel develop`)でも dev 版が更新として
検知されない。実機で再現済み。

さらに、dev タグではビルド時のバージョン注入がないため、dev ビルド自身が
`CFBundleShortVersionString = 1.4.8` を名乗り、仮にタグ順序を直しても
「自分自身への更新を提案し続ける」問題が残る。

## 設計

変更対象は `scripts/bump.sh` と `.github/workflows/release.yml` の 2 ファイルのみ。
Swift コードの変更は不要(`AppVersion` は pre-release の解析・比較に対応済み)。

### 1. bump.sh — dev タグを次期 patch ベースにする

<!-- derived-from #背景と問題 -->

dev 分岐で、`OLD_VERSION` の patch を +1 した値をベースにする:

```bash
IFS='.' read -r MAJOR MINOR PATCH <<< "$OLD_VERSION"
DEV_BASE="${MAJOR}.${MINOR}.$((PATCH + 1))"
DEV_PREFIX="v${DEV_BASE}-dev."
```

連番(既存 `v<DEV_BASE>-dev.*` タグの最大 N + 1)は現行ロジックを流用する。
前提となる不変条件「project.yml の `MARKETING_VERSION` = 最後にリリースした stable」は、
stable リリースで bump.sh が project.yml 書き換えとタグ作成を同時に行うため常に保たれる。

リリース順序の例: `1.4.9 → 1.4.10-dev.1 → 1.4.10-dev.2 → 1.4.10`
(dev は次の stable のプレリリースとして収束する。SemVer 準拠の並び)。

### 2. bump.sh — 誤解を招くコメントの削除

ビルド番号更新箇所のコメント
「`+1 は後続の bump コミット自身を含めるため（タグが指すコミットの総コミット数と一致させる）`」
は、コミット数一致が規約であるかのように読めるため削除する。
実態は「`CURRENT_PROJECT_VERSION` 導入時の初期値をコミット数にした」という経緯であり、
要件は単調増加のみ。

### 3. release.yml — タグからバージョンとビルド番号を注入する

ビルドステップで以下を `xcodebuild` に渡す(dev / stable 共通):

```yaml
xcodebuild build -scheme befold ... \
  MARKETING_VERSION="${GITHUB_REF_NAME#v}" \
  CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)"
```

- `MARKETING_VERSION`: dev ビルドが `1.4.10-dev.1` を正しく名乗る。
  stable でも project.yml とタグのずれ事故を構造的に防ぐ。
  Info.plist は `$(MARKETING_VERSION)` 参照のためコマンドライン上書きが反映される。
- `CURRENT_PROJECT_VERSION`: dev.1 と dev.2 に異なるビルド番号が付く。
  コミット数を使うのは規約ではなく、(1) 単調増加が保たれる、
  (2) stable では bump.sh が project.yml に書く値と同じ式になり食い違わない、という実利による。
- checkout は `fetch-depth: 0` が必要(`rev-list --count` を正しく数えるため)。

### 4. 既存タグのクリーンアップと再リリース

修正のマージ後:

1. `v1.4.8-dev.1` の GitHub リリースとタグを削除
   (`gh release delete v1.4.8-dev.1 --yes` と `git push origin --delete v1.4.8-dev.1`、
   ローカルタグも `git tag -d`)
2. `scripts/bump.sh dev` を再実行 → `v1.4.9-dev.1` が作成され、
   release.yml が DMG をビルド・添付する

## エッジケース

- stable `1.4.9` リリース後の dev はベースが `1.4.10` に自動で進むため衝突しない
- develop チャンネルで `1.4.9-dev.1` 使用中に stable `1.4.9` が出ると、
  `1.4.9-dev.1 < 1.4.9` により stable への更新が提案される(意図通り)
- stable チャンネルは `releases/latest`(GitHub 側が prerelease を除外)を使うため
  dev 版は見えない(現行仕様のまま)
- About パネルは標準実装のため `バージョン 1.4.10-dev.1 (ビルド番号)` と表示され、
  dev 版であることが識別できる(コード変更不要)

## 検証

1. `scripts/bump.sh dev --dry-run` が `v1.4.9-dev.1` を表示する
2. 再リリース後、develop チャンネルの実機で `v1.4.9-dev.1` が更新として検知される
   (今回の再現手順そのまま)
3. CI ビルドの DMG 内 Info.plist で `CFBundleShortVersionString` が `1.4.9-dev.1`、
   `CFBundleVersion` がそのコミットの `git rev-list --count` 値になっている
