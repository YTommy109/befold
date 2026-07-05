# /release — DMG ビルド & GitHub リリース一括作成

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
リリースノートを Markdown で生成する。生成結果はユーザーに表示し、
GitHub リリースの body として使う。

### 3. DMG ビルド

```bash
cd MmdviewApp && xcodebuild build -scheme mmdview -configuration Release -derivedDataPath .build
```

ビルド成功後:

```bash
scripts/create-dmg.sh MmdviewApp/.build/Build/Products/Release/mmdview.app mmdview.dmg
```

### 4. GitHub リリース作成

最新タグ（`git describe --tags --abbrev=0`）を使って GitHub リリースを作成する:

```bash
gh release create <タグ> mmdview.dmg --title "<タグ>" --notes "<リリースノート>"
```

### 5. クリーンアップ

```bash
rm -f mmdview.dmg
rm -rf MmdviewApp/.build
```

各ステップの結果をユーザーに報告する。
