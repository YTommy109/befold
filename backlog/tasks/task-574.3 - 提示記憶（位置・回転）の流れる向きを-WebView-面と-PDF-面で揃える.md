---
id: TASK-574.3
title: 提示記憶（位置・回転）の流れる向きを WebView 面と PDF 面で揃える
status: To Do
assignee: []
created_date: '2026-08-30 03:38'
labels:
  - refactor
dependencies: []
parent_task_id: TASK-574
priority: medium
type: task
ordinal: 834000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
同じ「窓の提示記憶」（`WindowPresentationMemory`）に対して、面ごとにデータフローの向きが違う。

| 値 | WebView 面 | PDF 面 |
| --- | --- | --- |
| スクロール位置 | JS の `scrollPositionChanged` → `recordScrollPosition` で**常時 push** | `saveScrollPositionBeforeTransition` からの**切替時 pull のみ**（呼び出し元は `performFileSwitch` と `setDisplayMode` の 2 箇所） |
| 回転 | （無し） | 提示開始時に `store.pdfRotation` へ読み込むが以後 store へ戻さず、退出時に `currentRotation` で面から pull |

結果として `WindowPresentationMemory` に PDF 専用の `rotations` 表が生え、`WebViewCommandController.rotate / currentRotation` は名前が web 面のまま両面へ dispatch している。今は動くが、次に PDF 固有の記憶（TASK-570 の検索語など）を足すたびに同じ二重構造が増える。

## 到達したい形

- 位置・回転とも、両面で同じ向き（push に揃えるなら PDF 面の `boundsDidChange` から `recordScrollPosition` へ、pull に揃えるなら web 面も切替時だけ）。どちらに揃えるかは着手時に `/review-design` で決める。判断の材料: web 面の push は「保存が遅れて届く」経路（`ViewerDocumentPresenter` の late-arriving save catch-up）を必要としており、pull に揃えるとその経路ごと消せる可能性がある
- `WindowPresentationMemory` の表が面固有でなく「提示記憶の種類」で並ぶ
- `WebViewCommandController` の回転 API の名前が実態（両面へ dispatch）に合う

TASK-570（PDF 内検索）が同じ記憶機構へ値を足す見込みなので、そちらより先に済ませる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 スクロール位置と回転が、WebView 面と PDF 面で同じ向き（push か pull か）で `WindowPresentationMemory` へ届く
- [ ] #2 `WindowPresentationMemory` に面固有の分岐（PDF だけの表・web だけの表）が無い
- [ ] #3 回転を扱う API の名前に web 面を指す語が残っていない
- [ ] #4 揃えた向きを破ると落ちるテストがある（例: PDF 面で位置を変えたのに記憶が更新されない、または web 面が切替以外で記憶を書いている）
- [ ] #5 `/review-design` の結果が Implementation Plan に反映されている
<!-- AC:END -->
