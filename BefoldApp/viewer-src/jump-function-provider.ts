// ソースコード表示の関数・型定義の目印（TASK-485.4）。見出しなど他の目印は
// jump-providers.ts が持つ。

import { _mmdDocument } from './document-state.js';
import type { JumpProvider, JumpTarget } from './jump-view.js';

// ソース表示の 1 行のテキスト。行番号セルは別の <td> なので、行全体の
// textContent を使うと行番号が本文の先頭に混ざる（`1# title` のように読める）。
function sourceLineText(row: HTMLTableRowElement): string {
  return row.querySelector('.line-content')?.textContent ?? '';
}

// ソースコード表示の関数・型定義（TASK-485.4）。
//
// ## 判定を 2 つの役に分ける
//
// 「この行は定義の始まりか」は**行テキストの正規表現**で決め、
// 「その行は本当にコードか（コメント・文字列の中でないか）」は
// **hljs のスパン**で決める。
//
// 除外を自前の状態持ち回り（上の collectSourceHeadings が CODE_FENCE で
// やっている形）で書かないのは、4 言語へ広げるとブロックコメント・生文字列・
// ヒアドキュメント・テンプレートリテラルの規則を各言語ぶん抱えることになり、
// 「行単位のパターン一致だけで文脈を決める」形（TASK-316 と同型）へ戻るため。
// hljs は既にその字句解析をしており、`reflowSpanBalancedLines`（code-html.ts）が
// 行末で開いたままの span を閉じて次行の先頭で開き直すので、**複数行コメント／
// 文字列の途中の行も自分の td.line-content 内に hljs-comment / hljs-string を持つ**。
//
// 逆に `span.hljs-title.function_` を「定義である」ことの判定には使わない。
// JS/TS では呼び出し側（`foo(1)` / `obj.method(2)`）にも同じクラスが付き、
// 定義と区別できない（実測）。トークンは除外にだけ使う。
//
// ## JS/TS のメソッド短縮記法（TASK-485.23）
//
// `foo() {` / `async foo() {` / `get foo() {` は `if (x) {` / `while (x) {` /
// `} catch (e) {` と行の形が同じなので、**名前の位置に予約語が来ないこと**を
// 否定先読みで要求して分ける。ここが唯一の分かれ目なので、予約語の取りこぼしは
// そのまま誤検出になる（`viewer-main-jump-function.test.js` の
// 「制御構文を定義として拾わない」がそれを落とす）。
//
// `} else {` のように `}` で始まる行は、名前が行頭に来ないので先読み以前に外れる。
// 呼び出しにコールバックを渡す行（`describe('x', () => {`）も、`)` の直後が `{` で
// ないため外れる。ここでもトークンは使わない——判定の分かれ目は行の形のままで、
// backlog decision-12 の決定は変えていない。
//
// ## 対応言語
//
// 非対応言語ではメニューごと無効になる（Swift 側 ViewerCapabilities）。
// この表と Swift の `FunctionJumpLanguages.supported` のずれは
// `ViewerFunctionJumpLanguageContractTests` が落とす。
//
var FUNCTION_JUMP_LANGUAGES = [
  'swift',
  'python',
  'javascript',
  'typescript',
  'go',
  'rust',
  'java',
  'kotlin',
];

// 言語ごとに 1 本へ結合した判定。collect は rebuild のたびに全行を走査するので、
// 行あたりに走らせる正規表現を増やさない（TASK-485.4 の設計レビュー項目 6）。
// `g` を付けないので `test` は状態を持たない（lastIndex の持ち越しが起きない）。
var JS_DEFINITION =
  /^\s*(?:export\s+)?(?:default\s+)?(?:declare\s+)?(?:abstract\s+)?(?:async\s+)?(?:function\b|class\s+[A-Za-z_$]|interface\s+[A-Za-z_$]|enum\s+[A-Za-z_$]|namespace\s+[A-Za-z_$]|type\s+[A-Za-z_$][\w$]*\s*[=<]|(?:const|let|var)\s+[A-Za-z_$][\w$]*\s*(?::[^=]*)?=\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*(?::[^=]*)?=>|[A-Za-z_$][\w$]*\s*=>)|(?:(?:public|private|protected|static|readonly|abstract|override|declare|async|get|set)\s+)*\*?\s*(?!(?:if|for|while|switch|catch|do|else|try|finally|return|throw|new|typeof|void|delete|await|yield|case|with|in|of|function|class|import|export)\b)[#A-Za-z_$][\w$]*\s*(?:<[^<>()]*>)?\s*\([^;{)]*\)\s*(?::[^;{]+)?\{)/u;

var DEFINITION_PATTERNS: Record<string, RegExp> = {
  // `class func` のように修飾子として現れる語も定義キーワードなので、
  // 修飾子の繰り返しは省略可能にしてある（`class Foo` は修飾子 0 個で一致する）。
  swift:
    /^\s*(?:(?:public|private|fileprivate|internal|open|package|static|class|final|override|mutating|nonmutating|convenience|required|dynamic|lazy|weak|unowned|indirect|nonisolated|isolated)\s+)*(?:func|class|struct|enum|protocol|extension|actor|init|deinit|subscript)\b/u,
  // デコレータは別の行にあるので def / class そのものに錨を下ろす。
  python: /^\s*(?:async\s+)?(?:def|class)\s+/u,
  javascript: JS_DEFINITION,
  typescript: JS_DEFINITION,
  // `func (r *T) Name` のレシーバつきも拾う。`type (` のグループ宣言の中身は拾わない。
  go: /^\s*(?:func\s*(?:\([^)]*\)\s*)?[A-Za-z_]|type\s+[A-Za-z_])/u,
  // `const X: u32` は定義に数えないので、const は fn の修飾子としてだけ許す。
  rust: /^\s*(?:pub(?:\s*\([^)]*\))?\s+)?(?:(?:const|async|unsafe|default|extern(?:\s+"[^"]*")?)\s+)*(?:(?:fn|struct|enum|trait|impl|type|mod|union)\b|macro_rules!)/u,
  // Java はメソッドが戻り値型から始まり、キーワードで錨を下ろせない。
  // `型 名前(` の形で拾い、型の位置に来る予約語（`return foo(` / `else if (` /
  // `throw new X(`）を否定先読みで外す。`String s = f(x)` は名前の直後が `=` で外れる。
  // 修飾子なしのコンストラクタ `Foo(...) {` は、大文字始まりと行末の `{` で呼び出しと分ける。
  java: /^\s*(?:@[\w.]+(?:\([^)]*\))?\s+)*(?:(?:public|private|protected|static|final|abstract|synchronized|native|strictfp|default|sealed|non-sealed)\s+)*(?:(?:class|interface|enum|record|@interface)\s+[A-Za-z_$]|(?:<[^()]*>\s*)?(?!(?:return|new|throw|else|case|yield|assert|import|package)\b)[A-Za-z_$][\w$.]*(?:<[^()]*>)?(?:\[\])*\s+[A-Za-z_$][\w$]*\s*\(|[A-Z][\w$]*\s*\([^;]*\)\s*(?:throws\s[^;{]*)?\{)/u,
  kotlin:
    /^\s*(?:@[\w.]+(?:\([^)]*\))?\s+)*(?:(?:public|private|protected|internal|open|final|abstract|sealed|data|inline|value|enum|annotation|inner|override|suspend|operator|infix|tailrec|external|const|lateinit|companion|expect|actual)\s+)*(?:(?:fun|class|interface|object|typealias)\b|constructor\s*\(|init\s*\{)/u,
};

// いまの文書に使う判定。ソース表示（shape 'code'）でなければ null。
// 表示モードや DOM の形から推し直さないのは collectHeadings と同じ理由。
function definitionPattern(): RegExp | null {
  if (_mmdDocument.shape() !== 'code') {
    return null;
  }
  var lang = _mmdDocument.lang();
  // 対応言語の判定は FUNCTION_JUMP_LANGUAGES を必ず経由する。表の引き当てだけで
  // 済ませると、この配列が「エクスポートされているだけで誰も見ていない値」になり、
  // Swift 側との契約テストが実際の挙動を測らなくなる。
  if (lang === undefined || !FUNCTION_JUMP_LANGUAGES.includes(lang)) {
    return null;
  }
  return DEFINITION_PATTERNS[lang] ?? null;
}

// コメント・文字列を取り除いた、その行の実効的なコード。
// 行まるごとがブロックコメントの内側なら空文字になる。
//
// 直下の子だけを見れば足りる。reflowSpanBalancedLines が行頭で開き直すスパンは
// 行の最上位に来るため、「行がコメント／文字列の内側にある」ことは直下の子で表れる。
// clone してから remove する形を採らないのは、行数ぶんの DOM 複製を避けるため。
function codeTextOf(cell: HTMLElement): string {
  var text = '';
  cell.childNodes.forEach(function (node) {
    if (node instanceof HTMLElement && node.matches('.hljs-comment, .hljs-string')) {
      return;
    }
    text += node.textContent ?? '';
  });
  return text;
}

function collectFunctionDefinitions(root: HTMLElement): JumpTarget[] {
  const pattern = definitionPattern();
  if (!pattern) {
    return [];
  }
  var targets: JumpTarget[] = [];
  root.querySelectorAll<HTMLTableRowElement>('tr').forEach(function (row) {
    // 素のテキストで足切りしてから、候補になった行だけコメント・文字列を
    // 除いて再判定する。clone を全行に対して作ると段階読み込みのたびに
    // 行数ぶんの DOM 複製が走るため（rebuild は appendChunk ごとに呼ばれる）。
    if (!pattern.test(sourceLineText(row))) {
      return;
    }
    var cell = row.querySelector<HTMLElement>('.line-content');
    if (!cell) {
      return;
    }
    if (cell.querySelector('.hljs-comment, .hljs-string') && !pattern.test(codeTextOf(cell))) {
      return;
    }
    targets.push({ anchor: cell, highlight: [cell] });
  });
  return targets;
}

var functionDefinitionJumpProvider: JumpProvider = {
  id: 'functionDefinition',
  collect: collectFunctionDefinitions,
  // ignoresTruncation は付けない。差分表示と違いソース表示は appendChunk で
  // 実際に追記が起きるため、未読み込み範囲の定義は DOM に存在しない。
  // 「表示範囲内」ラベルはその事実をユーザーへ伝えるもので、消してはいけない。
};

export {
  collectFunctionDefinitions,
  functionDefinitionJumpProvider,
  FUNCTION_JUMP_LANGUAGES,
  sourceLineText,
};
