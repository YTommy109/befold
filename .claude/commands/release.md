---
argument-hint: patch | minor | major | dev
---

# /release — バージョン bump & GitHub リリース作成

引数: $ARGUMENTS（patch | minor | major | dev、省略可）

## 手順

### 0. 引数省略時のレベル自動判定

`$ARGUMENTS` が空の場合、以下の方針でレベルを決める。
**stable（patch/minor/major）へのバンプはリリースタイミングの意図的な判断
であるため自動選択しない。省略時は原則 `dev` とする。**

1. 直前のタグ（stable/dev 問わず最新）から `HEAD` までのコミットを確認する:

   ```bash
   git log $(git describe --tags --abbrev=0)..HEAD --pretty=%s
   ```

2. `docs:` / `chore:` / `test:` / `ci:` のみで、アプリの挙動に影響する
   コミット（`feat:` / `fix:` / `refactor:` などプロダクトコードの変更）が
   1件もない場合は、**リリース不要と判断してここで中断する**。中断する
   旨と該当コミット一覧をユーザーに報告して終了する。
3. アプリに影響する変更が1件でもあれば、レベルは `dev` とする。

`$ARGUMENTS` が明示的に `patch` / `minor` / `major` 指定された場合のみ、
その値で stable リリースを行う（この場合は手順0を行わず、ユーザー指定の
レベルをそのまま使う）。

### 1. バージョン bump（またはdev タグ作成）

`/bump` コマンドと同じ手順で bump する（レベルは `$ARGUMENTS` が指定されて
いればそれを、省略時は手順0で決定した `dev` を使う）:

```bash
scripts/bump.sh <レベル>
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
`git add CHANGELOG.md && ALLOW_MAIN_COMMIT=1 git commit -m "docs: CHANGELOG.md に <タグ> を追記する"`
でコミット・push する（バージョン bump コミットとは分けて新規コミットにする）。
main への直接コミットは pre-commit フックでブロックされるため `ALLOW_MAIN_COMMIT=1` が必須。

dev リリースの場合は追記しない。

各ステップの結果をユーザーに報告する。
