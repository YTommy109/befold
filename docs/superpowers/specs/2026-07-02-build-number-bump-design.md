# /bump でビルド番号をコミット数から更新する — 設計

## 背景

About ダイアログの「Version 1.1.3 (1)」の "(1)" はビルド番号
（`CFBundleVersion` ← `CURRENT_PROJECT_VERSION`）だが、現在は
`MmdviewApp/project.yml` で `"1"` に固定されており、リリースを重ねても
増えない。

## 方針

`/bump` 実行時に `MARKETING_VERSION` と同時に `CURRENT_PROJECT_VERSION`
も更新する。値は手動カウンタではなく **main のコミット数から導出**する。

- 新ビルド番号 = `git rev-list --count HEAD` **+ 1**
  - +1 は直後に作られる bump コミット自身を含めるため。これにより
    リリースタグが指すコミットの総コミット数とビルド番号が一致し、
    後から検証できる
- 安全チェック: 新ビルド番号が現在の `CURRENT_PROJECT_VERSION` より
  大きいことを確認する（コミット数は単調増加なので通常は常に成立）

## 変更対象

- `.claude/commands/bump.md` のみ
  - 手順 3 にビルド番号の算出・検証・書き換えを追加
  - コミット対象ファイルは `MmdviewApp/project.yml` のままで変更なし

## やらないこと

- `release.yml` / `Info.plist` / `mmdview.xcodeproj` の変更
  （CI は `xcodegen generate` で project.yml から再生成するため不要）
- 過去リリース（v1.1.3 以前）のビルド番号の遡及修正
