---
id: TASK-313
title: repeatedTimeoutsDoNotAccumulateResources の pipe 判定も自ランナーの pipe に絞る
status: Done
assignee: []
created_date: '2026-08-05 05:34'
updated_date: '2026-08-05 10:42'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 511000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
task-312 で releasesResourcesWhenWriteEndSurvivesTermination の pipe 判定を、GitCommandRunner の pipeObserver で通知された読み取り端 fd の (fd, st_ino) 同一性へ切り替えた。同じスイートの repeatedTimeoutsDoNotAccumulateResources は依然として openPipeCount()(プロセス全体の pipe fd 数)を slack = 3 で基準線と比較しており、同種の脆さが残っている。

基準線採取後に他スイートが pipe を 4 本以上開いて保持し続けると、条件は恒久的に成立しなくなり待機予算を使い切って落ちる。task-312 の実測で「恒久オフセットは予算の引き上げでは救えない」ことが分かっているため、再発すれば同じ調査を繰り返すことになる。

ただし優先度は低い。こちらは打ち切りを 20 ラウンド回すため、残留があれば 20 本ぶん積み上がり、slack 3 に対して検出マージンが約 6.7 倍ある。汚染が 4 本以上かつ待機中ずっと開きっぱなし、という条件が要る。

pipeObserver は複数回の呼び出しでも使えるので、20 本ぶんの PipeIdentity を集めて全部消えることを待つ形へ揃えられる。揃えれば openPipeCount() は使われなくなるので、ヘルパーごと削除できる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 repeatedTimeoutsDoNotAccumulateResources の pipe 判定が pipeObserver 由来の PipeIdentity 集合ベースになっている
- [x] #2 openPipeCount() が未使用になったことを確認し削除している
- [x] #3 実装を意図的に壊すと当該テストが失敗することを実測で確認している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
repeatedTimeoutsDoNotAccumulateResources の pipe 判定を pipeObserver 由来の PipeIdentity 集合へ切り替えた。20 ラウンドぶんの読み取り端を控え、全て「同じ pipe のままではない」ことを待つ形にしたため、他スイートが開きっぱなしにする pipe の影響を原理的に受けなくなった。openPipeCount() は未使用になったので削除し、スイートの型コメントからも参照を除いた。リーダースレッドの判定はプロセス全体でしか数えられないため slack 3 のまま残す。

実測: GitCommandRunner.run で作った Pipe をグローバルへ保持して解放を止めると、当該テストが GitCommandRunnerTests.swift:466(新しい pipe 同一性の待ち)で失敗することを確認。サボタージュを戻すと GitCommandRunnerResourceLeakTests は 7 件全て通る。
<!-- SECTION:NOTES:END -->
