---
id: TASK-261
title: .ts ファイルが QuickLook でプレビューできない（システム UTI が動画に割り当てられている）
status: Done
assignee:
  - '@claude'
created_date: '2026-08-02 15:07'
updated_date: '2026-08-05 13:38'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 455000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
.ts ファイルを Finder のスペースキー（QuickLook）でプレビューしても befold の QuickLook 拡張が担当せず、ソースコードとして表示されない。アプリ本体で開く経路は拡張子ベース（FileType）のため正常に表示される。

原因: macOS は .ts を public.mpeg-2-transport-stream（MPEG-2 トランスポートストリーム＝動画）に分類する。継承ツリーは public.movie / public.audiovisual-content 配下で、QuickLook 拡張が列挙する public.source-code 系には適合しないため拡張が呼ばれない。befold/Info.plist は com.degino.befold.source-code の UTTypeTagSpecification に ts を宣言しているが、システム宣言の UTI が優先されるため上書きできない。

**結論: 対応不可のため見送る。** 起票時に想定していた「QLSupportedContentTypes に public.mpeg-2-transport-stream を追加すれば .ts は拾える」という前提は誤りで、実測で否定されている（2026-07-26 / macOS 26.5.2、および 2026-08-05 / macOS 26.6 の再実測）。この UTI を宣言しても macOS は内蔵プレビューアを優先し appex を呼ばない。宣言は効かず、本物の .ts 動画のプレビューを奪うリスクだけが残る。

この結論は BefoldQuickLook/Info.plist のコメントと QuickLookInfoPlistTests.supportedContentTypesExcludeTransportStream に既に固定されており、UTI の再追加はテストがブロックする。詳細な実測手順と結果は Implementation Notes を参照。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 .ts ファイルを Finder のスペースキーでプレビューしたときの挙動が決定され、方針が Implementation Notes に記録されている
- [x] #2 対応する場合: TypeScript の .ts が befold の QuickLook でソースコードとして表示される
- [x] #3 対応する場合: 実際の MPEG-2 トランスポートストリーム動画を befold が壊れた形で奪わない
- [ ] #4 見送る場合: 理由（動画 UTI との衝突）が記録され、アプリ本体では表示できることが判明する形で閉じられる
- [ ] #5 見送りの判断と、その根拠となる実測結果が Implementation Notes に記録されている
- [ ] #6 QLSupportedContentTypes に動画 UTI を宣言しても appex が呼ばれないことが、現行 macOS で実測されている
- [ ] #7 アプリ本体（拡張子ベース）では .ts をソースコードとして扱えることがテストで固定されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 計測台の妥当性を先に確保する: .swift など既に動く拡張子で qlmanage を回し、befold の appex が呼ばれたことを検出できる手段(ログ/プロセス/バッジ)を確定する。これが取れない限り「.ts で呼ばれない」は測定できない
2. QLSupportedContentTypes に public.mpeg-2-transport-stream を一時的に追加してビルドし、lsregister で登録する
3. TypeScript の .ts に対して qlmanage を回し、appex が呼ばれるかを 1 の手段で判定する
4. 併せて本物の MPEG-2 TS 動画(同期バイト 0x47 が 188 バイト周期)を用意し、呼ばれる場合に何が起きるかも観測する
5. 結果を Notes に実測付きで記録する
   - 呼ばれない: 2026-07-26 の結論が macOS 26.6 でも維持。一時変更を戻して見送りで閉じる
   - 呼ばれる: 内容判定(0x47 周期)で TypeScript と TS 動画を振り分ける実装へ進む。QuickLookInfoPlistTests の supportedContentTypesExcludeTransportStream も書き換え対象になる
6. いずれの結果でも、採用しない変更は必ず元に戻してから終える
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 再実測(2026-08-05 / macOS 26.6, BuildVersion 25G72)

2026-07-26(macOS 26.5.2)の結論が現行 OS でも維持されるかを実測した。結論は**変わらない**。

計測方法: qlmanage -p でプレビューを起こし、appex プロセス(BefoldQuickLook)が起動するかを pgrep で判定する。対照として、既に QuickLook で動く .swift を必ず同じ台で測り、検出手段自体が機能していることを毎回確認した。

計測台の是正: 最初の計測は無効だった。befold.app のコピーが複数(/Applications の 1.11.7-dev.8、既定 DerivedData、worktree の Debug ビルド)登録されており、バンドル ID が衝突するため pluginkit が有効としていたのは **UTI を宣言していない /Applications のコピー**だった。重複を lsregister -u で外し、pluginkit で「有効な appex = UTI を宣言した Debug ビルド」を確認してから測り直した。

QLSupportedContentTypes に public.mpeg-2-transport-stream を追加した Debug ビルドを有効にした状態での結果:

| 対象 | appex 起動 |
| --- | --- |
| probe.swift(対照) | yes |
| probe.ts(TypeScript) | no |
| sample.ts(実 MPEG-2 TS。同期バイト 0x47 が 188 バイト周期) | no |

つまり UTI を宣言しても macOS は内蔵プレビューアを優先し、appex を呼ばない。宣言は効かない。

副次的に判明したこと:
- .ts は TypeScript でも実 MPEG-2 TS でも kMDItemContentType = public.mpeg-2-transport-stream に解決される(継承ツリーは public.movie / public.audiovisual-content 配下)。UTI では両者を区別できない
- 内容では確実に区別できる(実 TS は 188 バイト周期の同期バイト 0x47、TypeScript はテキスト)。ただし appex がそもそも呼ばれないため、この判別を実装しても出番がない
- appex 側の対応可否判定(PreviewViewController.swift:22 の FileType.quickLookSupportedExtensions)は既に ts を通す。コード側にブロッカーは無く、詰まっているのは UTI 解決のみ

一時的に加えた Info.plist の変更は元に戻し、再ビルドして appex に宣言が残っていないことを確認済み。Launch Services の登録状態も /Applications/befold.app が有効な元の状態へ戻した。

## 本体アプリでの表示確認

Debug ビルドで probe.ts を開き、ウィンドウが当該ファイルで開くこと(System Events でウィンドウ名 = probe.ts)と、ログに reject が出ていないことを確認した。あわせて FileType の対応表テスト(befoldTests/FileTypeTests.swift)に ts のケースが無く tsx だけだったため、("ts", "typescript") を追加して固定した。FileTypeTests は 13 tests passed。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
対応不可のため見送り。QLSupportedContentTypes に public.mpeg-2-transport-stream を追加しても macOS は内蔵プレビューアを優先し appex を呼ばないことを、macOS 26.6 で再実測して確認した(対照の .swift は同じ計測台で appex 起動を確認。初回計測はバンドル ID 衝突により UTI 未宣言の /Applications のコピーを測っていたため、pluginkit で有効な appex を特定し直して測り直した)。UTI では TypeScript と実 MPEG-2 TS を区別できず、内容では区別できるが appex が呼ばれないため出番がない。コード変更は FileTypeTests への ts ケース追加のみで、Info.plist の一時変更は復元済み。
<!-- SECTION:FINAL_SUMMARY:END -->
