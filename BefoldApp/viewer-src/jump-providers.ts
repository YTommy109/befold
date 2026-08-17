// 目印の列挙。ジャンプの対象ごとにここへプロバイダを足す（TASK-485）。
// 列挙以外（位置・表示・スクロール）は jump.ts が持つので、ここには
// 「どれを目印とみなすか」だけを書く。

import type { JumpProvider, JumpTarget } from './jump.js';

// 見出しの列。Markdown レンダリング表示の h2 / h3 を文書順に拾う。
// h1 を含めないのは、文書題名が 1 つあるだけの文書で「1/1」しか出せず
// 移動の役に立たないため。h4 以降を含めないのは、節の移動という用途に対して
// 目印が細かくなりすぎるため（TASK-485.2 で見直す場合もここだけを変える）。
//
// 見出しには markdown.ts の assignHeadingIds が既に id を振っているが、
// ここでは id に依存せず要素そのものを目印にする（id は URL 断片用で、
// 目印の同一性とは別の関心）。
var HEADING_SELECTOR = 'h2, h3';

function collectHeadings(root: HTMLElement): JumpTarget[] {
  var elements = root.querySelectorAll<HTMLElement>(HEADING_SELECTOR);
  var targets: JumpTarget[] = [];
  elements.forEach(function (element) {
    targets.push({ anchor: element, highlight: [element] });
  });
  return targets;
}

var headingJumpProvider: JumpProvider = {
  id: 'heading',
  collect: collectHeadings,
};

export { headingJumpProvider, collectHeadings, HEADING_SELECTOR };
