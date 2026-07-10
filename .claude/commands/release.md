# /release — バージョン bump & GitHub リリース作成

引数: $ARGUMENTS（patch | minor | major | dev）

## 手順

### 1. バージョン bump（またはdev タグ作成）

`/bump` コマンドと同じ手順で bump する:

```bash
scripts/bump.sh $ARGUMENTS
```

エラー終了した場合はここで停止する（リカバリーしない）。

### 2. リリースノートの生成

`/release-notes` コマンドの手順に従い、最新タグと前回タグ間のコミットから
リリースノートを Markdown で生成する。

- **dev リリースの場合**（タグに `-` が含まれる場合）: `/release-notes dev` の
  方針（全コミット対象）で生成する。
- **stable リリースの場合**: `/release-notes stable` の方針（ユーザー影響の
  ある内容のみ）で生成する。除外したコミットがあれば、生成結果と合わせて
  ユーザーに提示する。

生成結果はユーザーに表示する。

### 3. GitHub リリース作成

最新タグ（`git describe --tags --abbrev=0`）を使い、リリースノートを body にして
GitHub リリースを作成する。

**dev リリースの場合**（タグに `-` が含まれる場合）:

```bash
gh release create <タグ> --title "<タグ>" --notes "<リリースノート>" --prerelease
```

**stable リリースの場合**:

```bash
gh release create <タグ> --title "<タグ>" --notes "<リリースノート>"
```

DMG のビルドと添付は GitHub Actions（release.yml）が自動で行うため、
ローカルでのビルド・DMG 作成は不要。

### 4. CHANGELOG.md への追記（stable リリースのみ）

**stable リリースの場合のみ**、`.claude/skills/changelog.md` スキルの手順に
従い、生成したリリースノートを `CHANGELOG.md` に追記し、
`git add CHANGELOG.md && git commit -m "docs: CHANGELOG.md に <タグ> を追記する"`
でコミット・push する（バージョン bump コミットとは分けて新規コミットにする）。

dev リリースの場合は追記しない。

各ステップの結果をユーザーに報告する。
