# /cleanup-dev-releases — 古い dev リリースの一括削除

引数: $ARGUMENTS（しきい値バージョン、例: `1.19.0`。`--dry-run` を先頭に付けると削除せず対象一覧のみ表示）

以下のコマンドを実行し、出力をそのままユーザーに報告してください。
対象の洗い出し（R2 を正として直接列挙）・GitHub Release／タグの削除・
R2 オブジェクトの削除・appcast.xml / appcast-develop.xml の該当 item 削除は
すべてスクリプト内で決定論的に行われます。

```bash
scripts/cleanup-old-dev-releases.sh $ARGUMENTS
```

まず `--dry-run` 付きで対象一覧を確認し、ユーザーの承認を得てから
`--dry-run` 無しで実行することを推奨する（削除は破壊的なため）。

スクリプトが「トークンが見つかりません」で終了した場合は、
`site/README.md`「古い dev リリースの一括削除」節の手順で
Cloudflare API トークンを作成するようユーザーに案内する（勝手に作成しない）。

スクリプトがエラーで終了した場合は、エラーメッセージを報告して終了する
（勝手にリカバリーを試みない）。
