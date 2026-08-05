---
argument-hint: patch | minor | major | dev
---

# /release — バージョン bump & GitHub リリース作成

引数: $ARGUMENTS（patch | minor | major | dev、省略可）

## 手順

### 0. 引数省略時のレベル自動判定

`$ARGUMENTS` が空の場合、以下の方針でレベルを自動決定し、確認を挟まず
そのまま手順1以降を実行する。**`major` だけは commit 件名から機械的に
判定できない（破壊的変更の判断は意図的な人間の判断が必要）ため、自動選択
の対象外とし、明示的に `major` を指定された場合のみ扱う。**

1. 直前のタグ（stable/dev 問わず最新）から `HEAD` までのコミットを確認する:

   ```bash
   git log $(git describe --tags --abbrev=0)..HEAD --pretty=%s
   ```

2. `docs:` / `chore:` / `test:` / `ci:` のみで、アプリの挙動に影響する
   コミット（`feat:` / `fix:` / `refactor:` などプロダクトコードの変更）が
   1件もない場合は、**リリース不要と判断してここで中断する**。中断する
   旨と該当コミット一覧をユーザーに報告して終了する。
3. アプリに影響する変更が1件でもあれば、次に stable 化すべきかを判定する。
   直前の **stable** タグ（`-` を含まないタグのうち最新のもの）から `HEAD`
   までのコミットを確認する:

   ```bash
   git tag --sort=-v:refname | grep -v -- '-' | head -1
   git log <直前の stable タグ>..HEAD --pretty=%s
   ```

   このコミット群から、`/release-notes stable` の除外方針
   （`docs:`/`chore:`/`test:`/`ci:`/`refactor:`/`style:`、内部実装のみの
   `feat:`/`fix:`、`feat(gate):`/`fix(gate):` スコープの FeatureGate 配下）
   を適用してユーザー影響のある commit だけを残す。
   - 残った commit が 0 件 → レベルは `dev`
   - 残った commit に `feat:`（ユーザー影響のある新機能）が 1 件以上ある
     → レベルは `minor`
   - `feat:` は無いが `fix:`（ユーザー影響のある不具合修正）がある
     → レベルは `patch`
4. 決定したレベルをユーザーに一言報告し（例:「stable 化条件を満たしたため
   minor でリリースします」）、承認を待たずそのまま手順1へ進む。

`$ARGUMENTS` が明示的に `patch` / `minor` / `major` / `dev` 指定された場合は
手順0を行わず、ユーザー指定のレベルをそのまま使う。

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
