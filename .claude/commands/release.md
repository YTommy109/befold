# /release — バージョン bump & GitHub リリース作成

引数: $ARGUMENTS（patch | minor | major）

## 手順

### 1. バージョン bump

`/bump` スキルと同じ手順で bump する:

```bash
scripts/bump.sh $ARGUMENTS
```

エラー終了した場合はここで停止する（リカバリーしない）。

### 2. リリースノートの生成

`/release-notes` スキルの手順に従い、最新タグと前回タグ間のコミットから
リリースノートを Markdown で生成する。生成結果はユーザーに表示する。

### 3. GitHub リリース作成

最新タグ（`git describe --tags --abbrev=0`）を使い、リリースノートを body にして
GitHub リリースを作成する:

```bash
gh release create <タグ> --title "<タグ>" --notes "<リリースノート>"
```

DMG のビルドと添付は GitHub Actions（release.yml）が自動で行うため、
ローカルでのビルド・DMG 作成は不要。

各ステップの結果をユーザーに報告する。
