# /bump — バージョン bump & リリースタグ

引数: $ARGUMENTS（patch | minor | major）

以下の手順を実行してください。

## 1. 引数の検証

- `$ARGUMENTS` が `patch`、`minor`、`major` のいずれかであることを確認する
- それ以外の場合はエラーメッセージを表示して終了する

## 2. ブランチの検証

- 現在のブランチが `main` であることを確認する
- `main` 以外の場合はエラーメッセージを表示して終了する

## 3. バージョンの bump

- `MmdviewApp/project.yml` の `MARKETING_VERSION` から現在のバージョン（例: `1.0.0`）を読み取る
- `$ARGUMENTS` に応じて semver をインクリメントする:
  - `patch`: 1.0.0 → 1.0.1
  - `minor`: 1.0.0 → 1.1.0
  - `major`: 1.0.0 → 2.0.0
- `MmdviewApp/project.yml` の `MARKETING_VERSION` を新バージョンに書き換える

## 4. ビルド番号の更新

- `git rev-list --count HEAD` の結果に 1 を足した値を新ビルド番号とする
  （+1 は後続の bump コミット自身を含めるため。これによりタグが指すコミットの総コミット数とビルド番号が一致する）
- 新ビルド番号が `MmdviewApp/project.yml` の現在の `CURRENT_PROJECT_VERSION` より大きいことを確認する。
  大きくない場合はエラーメッセージを表示して終了する
- `MmdviewApp/project.yml` の `CURRENT_PROJECT_VERSION` を新ビルド番号に書き換える

## 5. コミットとタグ

以下のコマンドを実行する:

```bash
git add MmdviewApp/project.yml
git commit -m "chore: バージョンを {旧バージョン} から {新バージョン} に更新する"
git tag "v{新バージョン}"
```

## 6. プッシュ

```bash
git push
git push --tags
```

## 7. 完了メッセージ

`v{旧バージョン} → v{新バージョン}`（ビルド番号 {新ビルド番号}）をリリースタグと共にプッシュしたことを報告する。
