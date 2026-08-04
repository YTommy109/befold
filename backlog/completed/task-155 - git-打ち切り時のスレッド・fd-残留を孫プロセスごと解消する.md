---
id: TASK-155
title: git 打ち切り時のスレッド・fd 残留を孫プロセスごと解消する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-26 00:07'
updated_date: '2026-07-26 00:26'
labels:
  - path-reference
dependencies: []
priority: medium
ordinal: 209000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitCommandRunner.run はタイムアウト時に process.terminate() して呼び出し元を解放するだけで、読み取り側には触れない。git が孫プロセス(フック/エイリアス経由の子)へ標準出力を渡していると SIGTERM 後もパイプが閉じないため、打ち切り 1 回につき 読み取りスレッド 1 本 + Pipe の fd 2 本 + Process が孫の終了まで残る。

TASK-150 の AC#2 では打ち切り時に読み取り端を close して解放していたが、この方法は 65c4ef6b で撤回した。read に入る前に閉じると EBADF で NSFileHandleOperationException が飛び Swift から catch できずプロセスごと落ちる(CI で実際に SIGABRT)、かつ閉じた fd 番号が再利用されると無関係な読み取りを壊すため。したがって残留の解消は未解決のまま残っている。

GitCommandFileIndex.warm はファイルオープン時とタブ切替時(ViewerWindowController)に都度発火するので、応答しないリポジトリ(NFS 上など)では残留が蓄積し、GUI アプリの soft RLIMIT_NOFILE(典型 256)に対して 100 回強で fd 枯渇に到達しうる。

なお読み取りを専用スレッドへ移した 23de8147 以降、残留の影響はスレッド 1 本に閉じており、共有ワーカープールを恒久的に食い潰す経路は解消済み。本タスクは残るリソースリークの恒久対策。

候補: (a) git を独立プロセスグループで起動し、打ち切り時に kill(-pgid) で孫ごと殺す。パイプが閉じて read が EOF で自然終了するため EBADF の危険がない。(b) 読み取りを DispatchIO の生 fd 経路へ移す。スレッドを占有せず cleanup handler が close を所有するので NSException 経路が無い。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 打ち切り後に読み取りスレッド・fd・Process が残留しないことをテストで固定する
- [x] #2 fd を外から閉じる方式は採らない(65c4ef6b の EBADF / fd 再利用の問題を再導入しない)
- [x] #3 孫プロセスが標準出力を握ったまま親を打ち切るケースで解放されることを確認する
- [x] #4 打ち切りを繰り返しても fd 使用数が増え続けないことを確認する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化の検討: 候補(b) DispatchIO/posix_spawn への全面移行は読み取り経路を作り直すが、fd が残る原因(孫がパイプ書き込み端を握る)自体は解けない。候補(a) はプロセスグループを殺してパイプを閉じさせ、read が EOF で自然終了する = 既存の「専用スレッドで読む」構造をそのまま使える。新設する状態は起動時に控えた pgid 1 つだけで、terminate() の置き換え 1 箇所で済むため (a) を採る。
2. 実測で Process(macOS) は子を pgid == pid の新しいプロセスグループへ置くことを確認済み。run() 直後に pgid を控え、pgid == pid が成り立つときだけ打ち切りで kill(-pgid, SIGKILL) する。成り立たない環境では自プロセスを巻き込むため従来どおり terminate() へ倒す。
3. SIGTERM ではなく SIGKILL: 無視できない signal であることが「必ずパイプが閉じる」保証の根拠。このランナーは読み取り専用クエリ専用でフックも無害化済みのため、猶予を与えて後始末させる必要が無い。
4. テスト: (a) 孫が標準出力を握ったまま打ち切ると孫ごと消えること(一意な sleeper スクリプトを pgrep で追跡)。(b) 打ち切りを繰り返しても fd 数・スレッド数がベースラインへ戻ること。
5. swift test で回帰確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査で判明した前提の訂正: タスク記述は「git が孫へ標準出力を渡していると SIGTERM 後もパイプが閉じない」としていたが、実測すると git は素直に SIGTERM で死ぬ子孫なら道連れに畳むため、それだけでは残留しない。残留するのは子孫が SIGTERM に応じない場合で、このとき git 自身も子を待ったまま死ねず、git・シェル・孫の三者が書き込み端を握ったまま残る。SIGKILL を選んだ根拠はここにある(SIGTERM をグループへ送るだけでは伏せられて解決しない)。

macOS の Process が子を pgid == pid の新しいプロセスグループへ置くことは実測で確認した(未文書の挙動なので、成り立つことを確かめてからグループを消し、崩れていれば terminate() へ倒す)。

テストの検証力を両方向で確認した。実装を打ち切り前の process.terminate() に戻すと新規 2 テストが落ち(孫が消えない / fd もスレッドも基準線へ戻らない)、プロセスグループ SIGKILL に戻すと通る。
検証中に見つかった注意点を 2 つテストへ書き残した: (1) 打ち切り予算を 0.2 秒にすると git がエイリアスのシェルを fork する前に打ち切られ、残留のある実装でも通ってしまう(0.5 秒へ引き上げ)。(2) sleeper を素朴に sleep 300 と書くとシェルが exec 最適化して単一プロセスに潰れ、再現にならない。

併せて、23de8147 が同一コミット内で持ち込んだ自己矛盾を解消した。読み取りスレッドのコメントは「stackSize は既定(512KB)のまま触らない」と理由付きで述べているのに、直後の行が 64KB を設定していた。コメント側の理由(waitUntilExit のラン・ループと NSException のバックトレース採取が走るため切り詰めると SIGSEGV に化ける)が妥当なので設定行を落とした。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
git 打ち切り時に、git 単体ではなくプロセスグループごと SIGKILL するようにした。書き込み端を持つ子孫が全員いなくなるので read が EOF で自然終了し、読み取りスレッド・Pipe の fd・Process がまとめて解放される。fd を外から閉じる方式(65c4ef6b で撤回)は採っていないため、EBADF による NSFileHandleOperationException と fd 番号再利用の問題は再導入していない。

プロセスグループ ID は子が確実に生きている run() 直後に控える(打ち切り時に採り直すと、reap 済みで pid が再利用されていた場合に無関係なグループを殺しうる)。macOS の Process が子を pgid == pid の新しいグループへ置く挙動は未文書のため、成り立つことを確かめてから使い、崩れていれば従来どおり terminate() へ倒す。SIGTERM ではなく SIGKILL なのは、伏せられない signal であることが「必ず書き込み端が閉じる」保証そのものだから。このランナーは読み取り専用クエリ専用でフックも無害化済みなので、猶予を与えて後始末させる必要が無い。

検証: befoldTests/GitCommandRunnerTests.swift に 2 テストを追加。(1) 標準出力を握った子孫が打ち切りで消えること(pgrep でポーリング)、(2) 打ち切り 20 回で fd 数・スレッド数が基準線へ戻ること(fcntl 走査と task_threads で実測)。実装を process.terminate() に戻すと両方落ち、戻すと通ることを確認済み。swift test 全 696 テスト 99 スイート green、SwiftLint 新規違反なし、テスト後に残留プロセスなし。
<!-- SECTION:FINAL_SUMMARY:END -->
