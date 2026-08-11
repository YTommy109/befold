"use strict";
(() => {
  var __defProp = Object.defineProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };

  // viewer-src/main.js
  var main_exports = {};
  __export(main_exports, {
    BASE_SCALE: () => BASE_SCALE,
    BODY_CLASSES: () => BODY_CLASSES,
    CODE_TAB_SIZE: () => CODE_TAB_SIZE,
    CSV_COL_COUNT: () => CSV_COL_COUNT,
    DEFAULT_LINE_SCROLL_STEP: () => DEFAULT_LINE_SCROLL_STEP,
    DIAGRAM_ZOOM_MAX: () => DIAGRAM_ZOOM_MAX,
    MACOS_DEFAULT_BODY: () => MACOS_DEFAULT_BODY,
    PAGE_SCROLL_RATIO: () => PAGE_SCROLL_RATIO,
    WEB_BASELINE: () => WEB_BASELINE,
    ZOOM_DEFAULT: () => ZOOM_DEFAULT,
    ZOOM_MAX: () => ZOOM_MAX,
    ZOOM_MIN: () => ZOOM_MIN,
    ZOOM_STEP: () => ZOOM_STEP,
    _MSG_FIND_OPTIONS_CHANGED: () => _MSG_FIND_OPTIONS_CHANGED,
    _MSG_LOAD_MORE_LINES: () => _MSG_LOAD_MORE_LINES,
    _MSG_REFERENCE_ACTIVATED: () => _MSG_REFERENCE_ACTIVATED,
    _MSG_REFERENCE_CONTEXT_MENU: () => _MSG_REFERENCE_CONTEXT_MENU,
    _MSG_RESOLVE_REFERENCES: () => _MSG_RESOLVE_REFERENCES,
    _MSG_SCROLL_POSITION_CHANGED: () => _MSG_SCROLL_POSITION_CHANGED,
    _MSG_ZOOM_CHANGED: () => _MSG_ZOOM_CHANGED,
    _annotatePathRefs: () => _annotatePathRefs,
    _mmdApplyDiagramZoom: () => _mmdApplyDiagramZoom,
    _mmdApplyResolvedReferences: () => _mmdApplyResolvedReferences,
    _mmdApplyZoom: () => _mmdApplyZoom,
    _mmdBuildDiagramControls: () => _mmdBuildDiagramControls,
    _mmdChunkTail: () => _mmdChunkTail,
    _mmdCloseFind: () => _mmdCloseFind,
    _mmdDiagramZoomReset: () => _mmdDiagramZoomReset,
    _mmdDiagramZoomStep: () => _mmdDiagramZoomStep,
    _mmdDiagramZoomValue: () => _mmdDiagramZoomValue,
    _mmdDocPath: () => _mmdDocPath,
    _mmdDocument: () => _mmdDocument,
    _mmdFind: () => _mmdFind,
    _mmdFindNextIfOpen: () => _mmdFindNextIfOpen,
    _mmdFindPrevIfOpen: () => _mmdFindPrevIfOpen,
    _mmdFindRefresh: () => _mmdFindRefresh,
    _mmdFitImage: () => _mmdFitImage,
    _mmdInit: () => _mmdInit,
    _mmdInitCodeFont: () => _mmdInitCodeFont,
    _mmdInitFind: () => _mmdInitFind,
    _mmdInitFontSize: () => _mmdInitFontSize,
    _mmdInitKeyboard: () => _mmdInitKeyboard,
    _mmdInitLoadMore: () => _mmdInitLoadMore,
    _mmdInitMarkdown: () => _mmdInitMarkdown,
    _mmdInitReferenceClicks: () => _mmdInitReferenceClicks,
    _mmdInitResize: () => _mmdInitResize,
    _mmdInitScrollNotify: () => _mmdInitScrollNotify,
    _mmdInitWheelZoom: () => _mmdInitWheelZoom,
    _mmdInitZoom: () => _mmdInitZoom,
    _mmdInvalidatePendingRefs: () => _mmdInvalidatePendingRefs,
    _mmdLoadMore: () => _mmdLoadMore,
    _mmdMermaidConfig: () => _mmdMermaidConfig,
    _mmdMermaidParseError: () => _mmdMermaidParseError,
    _mmdModeSwitch: () => _mmdModeSwitch,
    _mmdOpenFind: () => _mmdOpenFind,
    _mmdPdfBlob: () => _mmdPdfBlob,
    _mmdPostMessage: () => _mmdPostMessage,
    _mmdPostScrollPosition: () => _mmdPostScrollPosition,
    _mmdReinitializeMermaidIfLoaded: () => _mmdReinitializeMermaidIfLoaded,
    _mmdRenameDocPath: () => _mmdRenameDocPath,
    _mmdRerenderCurrent: () => _mmdRerenderCurrent,
    _mmdResolveReferences: () => _mmdResolveReferences,
    _mmdRestoreScrollPosition: () => _mmdRestoreScrollPosition,
    _mmdRunMermaid: () => _mmdRunMermaid,
    _mmdScroll: () => _mmdScroll,
    _mmdScrollTarget: () => _mmdScrollTarget,
    _mmdSetBodyClasses: () => _mmdSetBodyClasses,
    _mmdSetRenderDocPath: () => _mmdSetRenderDocPath,
    _mmdSetRestoreScroll: () => _mmdSetRestoreScroll,
    _mmdSetTruncated: () => _mmdSetTruncated,
    _mmdViewOptions: () => _mmdViewOptions,
    _mmdWheelZoom: () => _mmdWheelZoom,
    _mmdWrapDiagrams: () => _mmdWrapDiagrams,
    _mmdZoom: () => _mmdZoom,
    _mmdZoomIn: () => _mmdZoomIn,
    _mmdZoomOut: () => _mmdZoomOut,
    _mmdZoomReset: () => _mmdZoomReset,
    _renderCsv: () => _renderCsv,
    _renderHtml: () => _renderHtml,
    _renderImage: () => _renderImage,
    _renderMarkdown: () => _renderMarkdown,
    _renderMmd: () => _renderMmd,
    _renderPdf: () => _renderPdf,
    _renderSource: () => _renderSource,
    _renderSvg: () => _renderSvg,
    _sourceLanguage: () => _sourceLanguage,
    _walkTextNodes: () => _walkTextNodes,
    appendChunk: () => appendChunk,
    base64ToBytes: () => base64ToBytes,
    buildFindRegExp: () => buildFindRegExp,
    buildLineNumberRows: () => buildLineNumberRows,
    buildTableHtml: () => buildTableHtml,
    clampZoom: () => clampZoom,
    codeChunkInnerHtml: () => codeChunkInnerHtml,
    csvRowsHtml: () => csvRowsHtml,
    csvSourceInnerHtml: () => csvSourceInnerHtml,
    diagramScrollHeight: () => diagramScrollHeight,
    diffMarkerGlyph: () => diffMarkerGlyph,
    effectiveZoom: () => effectiveZoom,
    escapeHtml: () => escapeHtml,
    halfPageScrollStep: () => halfPageScrollStep,
    highlightCode: () => highlightCode,
    highlightedDiffLines: () => highlightedDiffLines,
    imageDataURI: () => imageDataURI,
    imageFitSize: () => imageFitSize,
    indentColumns: () => indentColumns,
    isHostFeatureEnabled: () => isHostFeatureEnabled,
    isLocalPathHref: () => isLocalPathHref,
    isSafeLinkURL: () => isSafeLinkURL,
    keptMatchIndex: () => keptMatchIndex,
    lastLines: () => lastLines,
    leadingIndentInfo: () => leadingIndentInfo,
    lineContentCell: () => lineContentCell,
    lineScrollStep: () => lineScrollStep,
    markdownFontSize: () => markdownFontSize,
    markdownRenderer: () => markdownRenderer,
    mermaidTheme: () => mermaidTheme,
    nextMatchIndex: () => nextMatchIndex,
    onColorSchemeChange: () => onColorSchemeChange,
    pageScrollStep: () => pageScrollStep,
    pairDiffLines: () => pairDiffLines,
    parseCsv: () => parseCsv,
    parseStoredZoom: () => parseStoredZoom,
    parseUnifiedDiff: () => parseUnifiedDiff,
    prefersDark: () => prefersDark,
    prevMatchIndex: () => prevMatchIndex,
    reflowSpanBalancedLines: () => reflowSpanBalancedLines,
    render: () => render,
    renderCodeHtml: () => renderCodeHtml,
    renderCsvSourceHtml: () => renderCsvSourceHtml,
    renderDiffHtml: () => renderDiffHtml,
    renderInlineDiffHtml: () => renderInlineDiffHtml,
    renderShape: () => renderShape,
    renderSideBySideDiffHtml: () => renderSideBySideDiffHtml,
    resolveScrollKey: () => resolveScrollKey,
    sanitizeLang: () => sanitizeLang,
    sanitizeRenderedHtml: () => sanitizeRenderedHtml,
    setDiff: () => setDiff,
    setDiffLayout: () => setDiffLayout,
    setLineNumbers: () => setLineNumbers,
    setViewMode: () => setViewMode,
    stepZoom: () => stepZoom,
    svgDataURI: () => svgDataURI,
    tokenizeCsvRows: () => tokenizeCsvRows,
    wheelZoom: () => wheelZoom,
    wrapWithLineNumbers: () => wrapWithLineNumbers,
    zoomLabel: () => zoomLabel
  });

  // viewer-src/bridge.ts
  var _MSG_ZOOM_CHANGED = "zoomChanged";
  var _MSG_REFERENCE_ACTIVATED = "referenceActivated";
  var _MSG_REFERENCE_CONTEXT_MENU = "referenceContextMenu";
  var _MSG_FIND_OPTIONS_CHANGED = "findOptionsChanged";
  var _MSG_SCROLL_POSITION_CHANGED = "scrollPositionChanged";
  var _MSG_LOAD_MORE_LINES = "loadMoreLines";
  var _MSG_RESOLVE_REFERENCES = "resolveReferences";
  function _mmdPostMessage(name, payload) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
      window.webkit.messageHandlers[name].postMessage(payload);
      return true;
    }
    return false;
  }
  function isHostFeatureEnabled(hostFeatures, key) {
    if (!hostFeatures) {
      return true;
    }
    return hostFeatures[key] !== false;
  }

  // viewer-src/encoding.js
  function escapeHtml(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function svgDataURI(svgText) {
    return "data:image/svg+xml;base64," + btoa(unescape(encodeURIComponent(svgText)));
  }
  function imageDataURI(base64, mimeType) {
    return "data:" + (mimeType || "image/png") + ";base64," + base64;
  }
  function base64ToBytes(base64) {
    var binary = atob(base64);
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }

  // viewer-src/doc-path.js
  function _createDocPathTracker() {
    var docPath = null;
    var pendingDocPath;
    return {
      // 次の render() が表示する文書パスの予告。採用は adoptPending()(= render 開始時)。
      // ここで即時に切り替えると、render script の実行前に通知が発火したとき
      // 旧文書の値が新パスのキーで保存される。
      setPending: function(path) {
        pendingDocPath = path;
      },
      // rename / move の追随。DOM は同一文書のまま名前だけ変わるため render を経ずに
      // 即時差し替える。現在値・予告値のうち from に一致するものだけを書き換える
      // (不一致 = 別文書へ切替中なら何もしない。誤った付け替えより、旧キーへの
      // 短時間の保存のほうが安全)。
      rename: function(from, to) {
        if (docPath === from) {
          docPath = to;
        }
        if (pendingDocPath === from) {
          pendingDocPath = to;
        }
      },
      current: function() {
        return docPath;
      },
      adoptPending: function() {
        if (pendingDocPath === void 0) {
          return;
        }
        docPath = pendingDocPath;
        pendingDocPath = void 0;
      }
    };
  }
  var _mmdDocPath = _createDocPathTracker();
  function _mmdSetRenderDocPath(path) {
    _mmdDocPath.setPending(path);
  }
  function _mmdRenameDocPath(from, to) {
    _mmdDocPath.rename(from, to);
  }

  // viewer-src/view-options.js
  var _mmdModeSwitch = /* @__PURE__ */ (function() {
    var pending = false;
    return {
      mark: function() {
        pending = true;
      },
      consume: function() {
        var value = pending;
        pending = false;
        return value;
      }
    };
  })();
  function _createViewOptions() {
    var mode = "rendered";
    var lineNumbers = false;
    var diff = null;
    var diffLayout = "inline";
    return {
      mode: function() {
        return mode;
      },
      setMode: function(newMode) {
        if (newMode !== "rendered" && newMode !== "source") {
          return;
        }
        if (newMode !== mode) {
          _mmdModeSwitch.mark();
        }
        mode = newMode;
      },
      lineNumbers: function() {
        return lineNumbers;
      },
      setLineNumbers: function(show) {
        lineNumbers = show;
      },
      diff: function() {
        return diff;
      },
      setDiff: function(text) {
        diff = typeof text === "string" && text !== "" ? text : null;
      },
      diffLayout: function() {
        return diffLayout;
      },
      setDiffLayout: function(layout) {
        if (layout !== "inline" && layout !== "side-by-side") {
          return;
        }
        diffLayout = layout;
      }
    };
  }
  var _mmdViewOptions = _createViewOptions();
  function setViewMode(mode) {
    _mmdViewOptions.setMode(mode);
  }
  function setLineNumbers(show) {
    _mmdViewOptions.setLineNumbers(show);
  }
  function setDiff(text) {
    _mmdViewOptions.setDiff(text);
  }
  function setDiffLayout(layout) {
    _mmdViewOptions.setDiffLayout(layout);
  }

  // viewer-src/document-state.js
  function _createDocumentState() {
    var content = null;
    var type = "mmd";
    var lang = null;
    return {
      record: function(newContent, newType, newLang) {
        content = newContent;
        type = newType;
        lang = newLang;
      },
      // 追記チャンクを直近内容の末尾に足す。まだ何も描画していない間は何もしない。
      append: function(text) {
        if (content !== null) {
          content += text;
        }
      },
      content: function() {
        return content;
      },
      type: function() {
        return type;
      },
      lang: function() {
        return lang;
      },
      hasContent: function() {
        return content !== null;
      }
    };
  }
  var _mmdDocument = _createDocumentState();
  var _mmdChunkTail = /* @__PURE__ */ (function() {
    var endedWithNewline = true;
    return {
      record: function(text) {
        endedWithNewline = text.length > 0 && text[text.length - 1] === "\n";
      },
      endedWithNewline: function() {
        return endedWithNewline;
      }
    };
  })();

  // viewer-src/color-scheme.js
  var darkQuery = null;
  function query() {
    if (darkQuery === null) {
      darkQuery = window.matchMedia("(prefers-color-scheme: dark)");
    }
    return darkQuery;
  }
  function prefersDark() {
    return query().matches;
  }
  function onColorSchemeChange(handler) {
    query().addEventListener("change", handler);
  }

  // viewer-src/fonts.ts
  var MACOS_DEFAULT_BODY = 13;
  var WEB_BASELINE = 16;
  function markdownFontSize(raw) {
    var s = parseFloat(raw);
    if (isNaN(s) || s <= 0) {
      return WEB_BASELINE;
    }
    return WEB_BASELINE * (s / MACOS_DEFAULT_BODY);
  }
  function _mmdInitFontSize() {
    document.documentElement.style.setProperty(
      "--mmd-markdown-font-size",
      markdownFontSize(window._mmdSystemFontSize) + "px"
    );
  }
  function _mmdInitCodeFont() {
    var root = document.documentElement;
    var family = window._mmdMonoFontFamily || "";
    if (family) {
      var safe = family.replace(/[\\"]/g, "\\$&");
      root.style.setProperty(
        "--mmd-mono-font-family",
        '"' + safe + '", ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace'
      );
    } else {
      root.style.removeProperty("--mmd-mono-font-family");
    }
    var pt = window._mmdCodeFontSize;
    if (typeof pt === "number" && pt > 0) {
      root.style.setProperty("--mmd-code-font-size", pt * 16 / 13 + "px");
    } else {
      root.style.removeProperty("--mmd-code-font-size");
    }
  }

  // viewer-src/code-html.js
  function sanitizeLang(lang) {
    return String(lang).replace(/[^\w+-]/g, "");
  }
  function highlightCode(hljs2, str, lang) {
    if (hljs2 && lang && hljs2.getLanguage(lang)) {
      try {
        var result = hljs2.highlight(str, { language: lang, ignoreIllegals: true });
        return '<pre><code class="hljs language-' + sanitizeLang(lang) + '">' + result.value + "</code></pre>";
      } catch (e) {
      }
    }
    return "";
  }
  function reflowSpanBalancedLines(codeHtml) {
    var lines = codeHtml.split("\n");
    if (lines.length > 1 && lines[lines.length - 1] === "") {
      lines.pop();
    }
    var openSpans = [];
    var result = [];
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i] || "";
      var reopen = openSpans.join("");
      var tagRe = /<span\b[^>]*>|<\/span>/g;
      var tag;
      while ((tag = tagRe.exec(line)) !== null) {
        if (tag[0] === "</span>") {
          openSpans.pop();
        } else {
          openSpans.push(tag[0]);
        }
      }
      var close = "";
      for (var j = 0; j < openSpans.length; j++) {
        close += "</span>";
      }
      result.push(reopen + line + close);
    }
    return result;
  }
  var CODE_TAB_SIZE = 4;
  function indentColumns(text, tabSize) {
    var cols = 0;
    for (var i = 0; i < text.length; i++) {
      var ch = text[i];
      if (ch === "	") {
        cols += tabSize - cols % tabSize;
      } else if (ch === " ") {
        cols += 1;
      } else {
        break;
      }
    }
    return cols;
  }
  function leadingIndentInfo(lineHtml, tabSize) {
    var rest = lineHtml;
    var openTag = /^<span\b[^>]*>/;
    var match;
    while ((match = openTag.exec(rest)) !== null) {
      rest = rest.slice(match[0].length);
    }
    var cols = 0;
    var hasContent = false;
    for (var i = 0; i < rest.length; i++) {
      var ch = rest[i];
      if (ch === "	") {
        cols += tabSize - cols % tabSize;
      } else if (ch === " ") {
        cols += 1;
      } else {
        hasContent = true;
        break;
      }
    }
    if (!hasContent) {
      return { cols: 0, depth: 0 };
    }
    return { cols, depth: Math.floor(cols / tabSize) };
  }
  function lineContentCell(lineHtml) {
    var info = leadingIndentInfo(lineHtml, CODE_TAB_SIZE);
    var style = info.depth > 0 ? ' style="--indent-cols:' + info.cols + ";--indent-depth:" + info.depth + '"' : "";
    return '<td class="line-content"' + style + ">" + lineHtml + "</td>";
  }
  function buildLineNumberRows(codeHtml, startLine, showLineNumbers) {
    var withNumbers = showLineNumbers === true;
    var lines = reflowSpanBalancedLines(codeHtml);
    var rows = "";
    for (var i = 0; i < lines.length; i++) {
      var numberCell = withNumbers ? '<td class="line-number">' + (startLine + i) + "</td>" : "";
      rows += "<tr>" + numberCell + lineContentCell(lines[i]) + "</tr>";
    }
    return rows;
  }
  function wrapWithLineNumbers(codeHtml, showLineNumbers) {
    return '<table class="code-table">' + buildLineNumberRows(codeHtml, 1, showLineNumbers) + "</table>";
  }
  function renderCodeHtml(hljs2, str, lang, showLineNumbers) {
    var withNumbers = showLineNumbers === true;
    var highlighted = highlightCode(hljs2, str, lang);
    if (highlighted) {
      var match = highlighted.match(/^(<pre><code[^>]*>)([\s\S]*)(<\/code><\/pre>)$/);
      if (match) {
        return match[1] + wrapWithLineNumbers(match[2], withNumbers) + match[3];
      }
    }
    return "<pre><code>" + wrapWithLineNumbers(escapeHtml(str), withNumbers) + "</code></pre>";
  }
  function codeChunkInnerHtml(hljs2, str, lang, contextStr) {
    if (contextStr) {
      var highlightedWithContext = highlightCode(hljs2, contextStr + str, lang);
      if (highlightedWithContext) {
        var inner = highlightedWithContext.replace(/^<pre><code[^>]*>/, "").replace(/<\/code><\/pre>$/, "");
        var lines = reflowSpanBalancedLines(inner);
        var contextLineCount = (contextStr.match(/\n/g) || []).length;
        var body = lines.slice(contextLineCount).join("\n");
        return str.endsWith("\n") ? body + "\n" : body;
      }
    }
    var highlighted = highlightCode(hljs2, str, lang);
    if (highlighted) {
      return highlighted.replace(/^<pre><code[^>]*>/, "").replace(/<\/code><\/pre>$/, "");
    }
    return escapeHtml(str);
  }
  function lastLines(str, maxLines) {
    if (str.length === 0) {
      return "";
    }
    var idx = str.length - 1;
    var count = 0;
    while (count < maxLines) {
      var nl = str.lastIndexOf("\n", idx - 1);
      if (nl === -1) {
        return str;
      }
      idx = nl;
      count++;
    }
    return str.slice(idx + 1);
  }

  // viewer-src/diff-html.js
  var DIFF_HUNK_HEADER = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/;
  function parseUnifiedDiff(text) {
    var files = [];
    var file = null;
    var hunk = null;
    var oldNumber = 0;
    var newNumber = 0;
    var lines = String(text == null ? "" : text).split("\n");
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (line.indexOf("diff --git ") === 0) {
        file = { oldPath: null, newPath: null, isBinary: false, hunks: [] };
        files.push(file);
        hunk = null;
        continue;
      }
      if (file === null) {
        continue;
      }
      if (hunk === null) {
        if (line.indexOf("--- ") === 0) {
          file.oldPath = diffPath(line.slice(4));
          continue;
        }
        if (line.indexOf("+++ ") === 0) {
          file.newPath = diffPath(line.slice(4));
          continue;
        }
        if (line.indexOf("Binary files ") === 0 || line.indexOf("GIT binary patch") === 0) {
          file.isBinary = true;
          continue;
        }
      }
      var header = line.match(DIFF_HUNK_HEADER);
      if (header) {
        oldNumber = parseInt(header[1], 10);
        newNumber = parseInt(header[3], 10);
        hunk = { oldStart: oldNumber, newStart: newNumber, lines: [] };
        file.hunks.push(hunk);
        continue;
      }
      if (hunk === null) {
        continue;
      }
      if (line.indexOf("\\") === 0) {
        continue;
      }
      var marker = line.charAt(0);
      var body = line.slice(1);
      if (marker === "+") {
        hunk.lines.push({ type: "add", text: body, oldNumber: null, newNumber });
        newNumber += 1;
      } else if (marker === "-") {
        hunk.lines.push({ type: "del", text: body, oldNumber, newNumber: null });
        oldNumber += 1;
      } else if (marker === " ") {
        hunk.lines.push({ type: "context", text: body, oldNumber, newNumber });
        oldNumber += 1;
        newNumber += 1;
      }
    }
    return files;
  }
  function diffPath(raw) {
    var path = raw.split("	")[0];
    if (path === "/dev/null") {
      return path;
    }
    return path.replace(/^[ab]\//, "");
  }
  function highlightedSideLines(hljs2, lines, indexes, lang) {
    var texts = [];
    for (var i = 0; i < indexes.length; i++) {
      texts.push(lines[indexes[i]].text);
    }
    var joined = texts.join("\n");
    var lineHtmls = null;
    var highlighted = highlightCode(hljs2, joined, lang);
    if (highlighted) {
      var match = highlighted.match(/^<pre><code[^>]*>([\s\S]*)<\/code><\/pre>$/);
      if (match) {
        lineHtmls = reflowSpanBalancedLines(match[1]);
      }
    }
    if (lineHtmls === null) {
      lineHtmls = reflowSpanBalancedLines(escapeHtml(joined));
    }
    while (lineHtmls.length < indexes.length) {
      lineHtmls.push("");
    }
    return lineHtmls.slice(0, indexes.length);
  }
  function highlightedDiffLines(hljs2, hunk, lang) {
    var lines = hunk.lines;
    var oldIndexes = [];
    var newIndexes = [];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].type !== "add") {
        oldIndexes.push(i);
      }
      if (lines[i].type !== "del") {
        newIndexes.push(i);
      }
    }
    var result = [];
    for (var n = 0; n < lines.length; n++) {
      result.push("");
    }
    var oldHtmls = highlightedSideLines(hljs2, lines, oldIndexes, lang);
    for (var o = 0; o < oldIndexes.length; o++) {
      result[oldIndexes[o]] = oldHtmls[o];
    }
    var newHtmls = highlightedSideLines(hljs2, lines, newIndexes, lang);
    for (var w = 0; w < newIndexes.length; w++) {
      result[newIndexes[w]] = newHtmls[w];
    }
    return result;
  }
  function diffMarkerGlyph(type) {
    if (type === "add") {
      return "+";
    }
    if (type === "del") {
      return "-";
    }
    return " ";
  }
  function diffRow(line, lineHtml, showLineNumbers) {
    var numbers = "";
    if (showLineNumbers === true) {
      numbers = '<td class="line-number diff-old">' + (line.oldNumber === null ? "" : line.oldNumber) + '</td><td class="line-number diff-new">' + (line.newNumber === null ? "" : line.newNumber) + "</td>";
    }
    return '<tr class="diff-line diff-' + line.type + '">' + numbers + '<td class="diff-marker" aria-hidden="true">' + diffMarkerGlyph(line.type) + "</td>" + lineContentCell(lineHtml) + "</tr>";
  }
  function diffHunkSeparatorRow(colspan) {
    return '<tr class="diff-hunk" aria-hidden="true"><td class="diff-hunk-separator" colspan="' + colspan + '"></td></tr>';
  }
  function renderInlineDiffHtml(hljs2, diffText, lang, showLineNumbers) {
    var files = parseUnifiedDiff(diffText);
    var rows = "";
    for (var f = 0; f < files.length; f++) {
      var hunks = files[f].hunks;
      for (var h = 0; h < hunks.length; h++) {
        var hunk = hunks[h];
        var lineHtmls = highlightedDiffLines(hljs2, hunk, lang);
        if (rows !== "") {
          rows += diffHunkSeparatorRow(showLineNumbers === true ? 4 : 2);
        }
        for (var i = 0; i < hunk.lines.length; i++) {
          rows += diffRow(hunk.lines[i], lineHtmls[i], showLineNumbers);
        }
      }
    }
    if (rows === "") {
      return "";
    }
    return '<pre><code class="hljs"><table class="code-table diff-table">' + rows + "</table></code></pre>";
  }
  function pairDiffLines(lines) {
    var pairs = [];
    var i = 0;
    while (i < lines.length) {
      if (lines[i].type === "context") {
        pairs.push({ left: i, right: i });
        i += 1;
        continue;
      }
      var dels = [];
      var adds = [];
      while (i < lines.length && lines[i].type === "del") {
        dels.push(i);
        i += 1;
      }
      while (i < lines.length && lines[i].type === "add") {
        adds.push(i);
        i += 1;
      }
      var count = Math.max(dels.length, adds.length);
      for (var k = 0; k < count; k++) {
        pairs.push({
          left: k < dels.length ? dels[k] : null,
          right: k < adds.length ? adds[k] : null
        });
      }
    }
    return pairs;
  }
  function diffSideCells(line, lineHtml, showLineNumbers, side) {
    var numberClass = side === "left" ? "diff-old" : "diff-new";
    if (line === null) {
      var emptyNumber = showLineNumbers === true ? '<td class="line-number ' + numberClass + '"></td>' : "";
      return emptyNumber + '<td class="diff-marker diff-empty" aria-hidden="true"></td><td class="line-content diff-empty"></td>';
    }
    var number = showLineNumbers === true ? '<td class="line-number ' + numberClass + '">' + (side === "left" ? line.oldNumber : line.newNumber) + "</td>" : "";
    return number + '<td class="diff-marker" aria-hidden="true">' + diffMarkerGlyph(line.type) + "</td>" + lineContentCell(lineHtml);
  }
  function renderSideBySideDiffHtml(hljs2, diffText, lang, showLineNumbers) {
    var files = parseUnifiedDiff(diffText);
    var span = 2;
    var rows = "";
    for (var f = 0; f < files.length; f++) {
      var hunks = files[f].hunks;
      for (var h = 0; h < hunks.length; h++) {
        var hunk = hunks[h];
        var lineHtmls = highlightedDiffLines(hljs2, hunk, lang);
        if (rows !== "") {
          rows += diffHunkSeparatorRow(span);
        }
        var pairs = pairDiffLines(hunk.lines);
        for (var p = 0; p < pairs.length; p++) {
          var left = pairs[p].left;
          var right = pairs[p].right;
          var leftClass = left === null ? "diff-empty" : "diff-" + hunk.lines[left].type;
          var rightClass = right === null ? "diff-empty" : "diff-" + hunk.lines[right].type;
          rows += '<tr class="diff-line"><td class="diff-side diff-side-left ' + leftClass + '"><table class="diff-side-table"><tr>' + diffSideCells(
            left === null ? null : hunk.lines[left],
            left === null ? "" : lineHtmls[left],
            showLineNumbers,
            "left"
          ) + '</tr></table></td><td class="diff-side diff-side-right ' + rightClass + '"><table class="diff-side-table"><tr>' + diffSideCells(
            right === null ? null : hunk.lines[right],
            right === null ? "" : lineHtmls[right],
            showLineNumbers,
            "right"
          ) + "</tr></table></td></tr>";
        }
      }
    }
    if (rows === "") {
      return "";
    }
    return '<pre><code class="hljs"><table class="code-table diff-table diff-split">' + rows + "</table></code></pre>";
  }
  function renderDiffHtml(hljs2, diffText, lang, showLineNumbers, layout) {
    return layout === "side-by-side" ? renderSideBySideDiffHtml(hljs2, diffText, lang, showLineNumbers) : renderInlineDiffHtml(hljs2, diffText, lang, showLineNumbers);
  }

  // viewer-src/csv-html.js
  function tokenizeCsvRows(content, delimiter) {
    if (!content) {
      return [];
    }
    var rows = [];
    var row = [];
    var value = "";
    var raw = "";
    var inQuotes = false;
    var i = 0;
    function pushField() {
      row.push({ value, raw });
      value = "";
      raw = "";
    }
    function pushRow() {
      pushField();
      rows.push(row);
      row = [];
    }
    while (i < content.length) {
      var ch = content[i];
      if (inQuotes) {
        if (ch === '"') {
          if (i + 1 < content.length && content[i + 1] === '"') {
            value += '"';
            raw += '""';
            i += 2;
          } else {
            raw += ch;
            inQuotes = false;
            i++;
          }
        } else {
          value += ch;
          raw += ch;
          i++;
        }
      } else {
        if (ch === '"') {
          inQuotes = true;
          raw += ch;
          i++;
        } else if (ch === delimiter) {
          pushField();
          i++;
        } else if (ch === "\r") {
          pushRow();
          i++;
          if (i < content.length && content[i] === "\n") {
            i++;
          }
        } else if (ch === "\n") {
          pushRow();
          i++;
        } else {
          value += ch;
          raw += ch;
          i++;
        }
      }
    }
    if (value !== "" || raw !== "" || row.length > 0) {
      pushRow();
    }
    return rows;
  }
  function parseCsv(content, delimiter) {
    var tokenRows = tokenizeCsvRows(content, delimiter);
    var rows = [];
    for (var r = 0; r < tokenRows.length; r++) {
      var row = [];
      for (var c = 0; c < tokenRows[r].length; c++) {
        row.push(tokenRows[r][c].value);
      }
      rows.push(row);
    }
    return rows;
  }
  function csvRowsHtml(rows, minCols) {
    var html = "";
    for (var r = 0; r < rows.length; r++) {
      var cols = Math.max(minCols, rows[r].length);
      html += "<tr>";
      for (var c = 0; c < cols; c++) {
        html += "<td>" + escapeHtml(c < rows[r].length ? rows[r][c] : "") + "</td>";
      }
      html += "</tr>";
    }
    return html;
  }
  function buildTableHtml(rows) {
    if (rows.length === 0) {
      return "";
    }
    var maxCols = 0;
    for (var r = 0; r < rows.length; r++) {
      if (rows[r].length > maxCols) {
        maxCols = rows[r].length;
      }
    }
    var html = "<table><thead><tr>";
    for (var c = 0; c < maxCols; c++) {
      html += "<th>" + escapeHtml(c < rows[0].length ? rows[0][c] : "") + "</th>";
    }
    html += "</tr></thead><tbody>";
    html += csvRowsHtml(rows.slice(1), maxCols);
    html += "</tbody></table>";
    return html;
  }
  var CSV_COL_COUNT = 8;
  function csvSourceInnerHtml(content, delimiter) {
    if (!content) {
      return "";
    }
    var tokenRows = tokenizeCsvRows(content, delimiter);
    var htmlLines = [];
    for (var r = 0; r < tokenRows.length; r++) {
      var cells = tokenRows[r];
      var htmlParts = [];
      for (var c = 0; c < cells.length; c++) {
        var cls = "csv-col-" + c % CSV_COL_COUNT;
        htmlParts.push('<span class="' + cls + '">' + escapeHtml(cells[c].raw) + "</span>");
      }
      htmlLines.push(htmlParts.join(delimiter));
    }
    var body = htmlLines.join("\n");
    return content.endsWith("\n") ? body + "\n" : body;
  }
  function renderCsvSourceHtml(content, delimiter, showLineNumbers) {
    if (!content) {
      return '<pre><code class="csv-source"></code></pre>';
    }
    var body = csvSourceInnerHtml(content, delimiter);
    if (showLineNumbers === true) {
      body = wrapWithLineNumbers(body, true);
    }
    return '<pre><code class="csv-source">' + body + "</code></pre>";
  }

  // viewer-src/zoom.js
  var ZOOM_MIN = 0.5;
  var ZOOM_MAX = 2;
  var ZOOM_STEP = 0.25;
  var ZOOM_DEFAULT = 1;
  var BASE_SCALE = 0.75;
  var DIAGRAM_ZOOM_MAX = 3;
  function clampZoom(z, max) {
    if (max === void 0) {
      max = ZOOM_MAX;
    }
    return Math.max(ZOOM_MIN, Math.min(max, z));
  }
  function stepZoom(current, delta, max) {
    return clampZoom(Math.round((current + delta) * 100) / 100, max);
  }
  function wheelZoom(current, deltaY, max) {
    return clampZoom(Math.round((current - deltaY * 0.01) * 1e3) / 1e3, max);
  }
  function zoomLabel(zoom) {
    return Math.round(zoom * 100) + "%";
  }
  function effectiveZoom(zoom) {
    return zoom;
  }
  function parseStoredZoom(raw) {
    var z = parseFloat(raw);
    return isNaN(z) ? ZOOM_DEFAULT : z;
  }
  function diagramScrollHeight(naturalHeight, diagramZoom, viewportHeight, globalZoom) {
    var viewportCap = (viewportHeight - 64) / effectiveZoom(globalZoom);
    return Math.min(naturalHeight * diagramZoom * BASE_SCALE, viewportCap);
  }
  function imageFitSize(naturalWidth, naturalHeight, availWidth, availHeight) {
    if (naturalWidth <= 0 || naturalHeight <= 0 || availWidth <= 0 || availHeight <= 0) {
      return { width: naturalWidth, height: naturalHeight };
    }
    var scale = Math.min(1, availWidth / naturalWidth, availHeight / naturalHeight);
    return { width: naturalWidth * scale, height: naturalHeight * scale };
  }
  function _createZoomStore() {
    var zoom = ZOOM_DEFAULT;
    var lastPosted = ZOOM_DEFAULT;
    var diagramZooms = /* @__PURE__ */ new Map();
    function diagramValue(index) {
      return diagramZooms.has(index) ? diagramZooms.get(index) : ZOOM_DEFAULT;
    }
    return {
      value: function() {
        return zoom;
      },
      // Swift が注入した保存値を採用する。範囲外の保存値はクランプした値を採用しつつ、
      // 直近通知値には注入値そのままを記録する: 次の takePostable() が補正後の値を
      // 通知対象として返し、Swift 側の保存値が正される。
      adoptStored: function(raw) {
        var parsed = parseStoredZoom(raw);
        zoom = clampZoom(parsed);
        lastPosted = parsed;
      },
      step: function(delta) {
        zoom = stepZoom(zoom, delta);
      },
      wheel: function(deltaY) {
        zoom = wheelZoom(zoom, deltaY);
      },
      reset: function() {
        zoom = ZOOM_DEFAULT;
      },
      // 直近通知値と変わっていれば通知すべき倍率を返し、同時に直近通知値を更新する。
      // 変わっていなければ null を返す（通知は不要）。
      takePostable: function() {
        if (zoom === lastPosted) {
          return null;
        }
        lastPosted = zoom;
        return zoom;
      },
      diagramValue,
      diagramStep: function(index, delta) {
        diagramZooms.set(index, stepZoom(diagramValue(index), delta, DIAGRAM_ZOOM_MAX));
      },
      diagramWheel: function(index, deltaY) {
        diagramZooms.set(index, wheelZoom(diagramValue(index), deltaY, DIAGRAM_ZOOM_MAX));
      },
      diagramReset: function(index) {
        diagramZooms.set(index, ZOOM_DEFAULT);
      }
    };
  }
  var _mmdZoom = _createZoomStore();
  function _mmdInitZoom() {
    _mmdZoom.adoptStored(window._mmdInitialZoom);
    _mmdApplyZoom();
  }
  function _mmdApplyZoom() {
    var zoom = _mmdZoom.value();
    var wrap = document.getElementById("diagram-wrap");
    if (wrap.classList.contains("pdf-body")) {
      wrap.style.zoom = 1;
      wrap.style.width = effectiveZoom(zoom) * 100 + "%";
      wrap.style.height = effectiveZoom(zoom) * 100 + "%";
    } else {
      wrap.style.width = "";
      wrap.style.height = "";
      wrap.style.zoom = effectiveZoom(zoom);
    }
    _mmdUpdateAllDiagramScrollHeights();
    var postable = _mmdZoom.takePostable();
    if (postable !== null) {
      _mmdPostMessage(_MSG_ZOOM_CHANGED, { zoom: postable, path: _mmdDocPath.current() });
    }
  }
  function _mmdZoomIn() {
    _mmdZoom.step(ZOOM_STEP);
    _mmdApplyZoom();
  }
  function _mmdZoomOut() {
    _mmdZoom.step(-ZOOM_STEP);
    _mmdApplyZoom();
  }
  function _mmdZoomReset() {
    _mmdZoom.reset();
    _mmdApplyZoom();
  }
  function _mmdWheelZoom(deltaY) {
    _mmdZoom.wheel(deltaY);
    _mmdApplyZoom();
  }
  function _mmdInitWheelZoom() {
    document.addEventListener("wheel", function(e) {
      if (!e.ctrlKey) {
        return;
      }
      e.preventDefault();
      var wrap = e.target instanceof Element ? e.target.closest(".diagram-zoom-wrap") : null;
      if (wrap) {
        _mmdDiagramWheelZoom(wrap, e.deltaY);
      } else {
        _mmdWheelZoom(e.deltaY);
      }
    }, { passive: false });
  }
  function _mmdInitResize() {
    window.addEventListener("resize", function() {
      _mmdUpdateAllDiagramScrollHeights();
      var wrap = document.getElementById("diagram-wrap");
      var img = wrap.classList.contains("image-body") ? wrap.querySelector("img") : null;
      if (img && img.complete && img.naturalWidth) {
        _mmdFitImage(img, wrap);
      }
    });
  }
  function _mmdFitImage(img, wrap) {
    var zoom = effectiveZoom(_mmdZoom.value());
    var fit = imageFitSize(img.naturalWidth, img.naturalHeight, wrap.clientWidth * zoom, wrap.clientHeight * zoom);
    img.style.width = fit.width + "px";
    img.style.height = fit.height + "px";
  }
  function _mmdDiagramZoomValue(index) {
    return _mmdZoom.diagramValue(index);
  }
  function _mmdUpdateAllDiagramScrollHeights() {
    document.querySelectorAll(".diagram-zoom-wrap").forEach(function(wrap) {
      _mmdUpdateDiagramScrollHeight(wrap);
    });
  }
  function _mmdUpdateDiagramScrollHeight(wrap) {
    var zoom = _mmdDiagramZoomValue(Number(wrap.dataset.diagramIndex));
    var naturalHeight = Number(wrap.dataset.naturalHeight);
    wrap.querySelector(".diagram-zoom-scroll").style.height = diagramScrollHeight(naturalHeight, zoom, window.innerHeight, _mmdZoom.value()) + "px";
  }
  function _mmdApplyDiagramZoom(wrap) {
    var index = Number(wrap.dataset.diagramIndex);
    var zoom = _mmdDiagramZoomValue(index);
    wrap.querySelector(".diagram-zoom-inner").style.zoom = zoom * BASE_SCALE;
    _mmdUpdateDiagramScrollHeight(wrap);
    wrap.querySelector(".diagram-zoom-label").textContent = zoomLabel(zoom);
    wrap.querySelector(".diagram-zoom-in").disabled = zoom >= DIAGRAM_ZOOM_MAX;
    wrap.querySelector(".diagram-zoom-out").disabled = zoom <= ZOOM_MIN;
  }
  function _mmdDiagramZoomStep(wrap, delta) {
    _mmdZoom.diagramStep(Number(wrap.dataset.diagramIndex), delta);
    _mmdApplyDiagramZoom(wrap);
  }
  function _mmdDiagramZoomReset(wrap) {
    _mmdZoom.diagramReset(Number(wrap.dataset.diagramIndex));
    _mmdApplyDiagramZoom(wrap);
  }
  function _mmdDiagramWheelZoom(wrap, deltaY) {
    _mmdZoom.diagramWheel(Number(wrap.dataset.diagramIndex), deltaY);
    _mmdApplyDiagramZoom(wrap);
  }
  function _mmdBuildDiagramControls(wrap) {
    var controls = document.createElement("div");
    controls.className = "diagram-zoom-controls";
    var zoomOut = document.createElement("button");
    zoomOut.className = "diagram-zoom-out";
    zoomOut.title = "\u7E2E\u5C0F";
    zoomOut.textContent = "\u2212";
    zoomOut.addEventListener("click", function() {
      _mmdDiagramZoomStep(wrap, -ZOOM_STEP);
    });
    var label = document.createElement("span");
    label.className = "diagram-zoom-label";
    label.title = "\u30AF\u30EA\u30C3\u30AF\u3067\u30EA\u30BB\u30C3\u30C8";
    label.addEventListener("click", function() {
      _mmdDiagramZoomReset(wrap);
    });
    var zoomIn = document.createElement("button");
    zoomIn.className = "diagram-zoom-in";
    zoomIn.title = "\u62E1\u5927";
    zoomIn.textContent = "+";
    zoomIn.addEventListener("click", function() {
      _mmdDiagramZoomStep(wrap, ZOOM_STEP);
    });
    controls.appendChild(zoomOut);
    controls.appendChild(label);
    controls.appendChild(zoomIn);
    return controls;
  }
  function _mmdWrapDiagrams(diagramWrap) {
    diagramWrap.querySelectorAll(".mermaid").forEach(function(el, i) {
      var wrap = document.createElement("div");
      wrap.className = "diagram-zoom-wrap";
      wrap.dataset.diagramIndex = i;
      var scroll = document.createElement("div");
      scroll.className = "diagram-zoom-scroll";
      var inner = document.createElement("div");
      inner.className = "diagram-zoom-inner";
      el.parentNode.insertBefore(wrap, el);
      inner.appendChild(el);
      scroll.appendChild(inner);
      wrap.appendChild(scroll);
      wrap.appendChild(_mmdBuildDiagramControls(wrap));
      wrap.dataset.naturalHeight = inner.offsetHeight;
      _mmdApplyDiagramZoom(wrap);
    });
  }

  // viewer-src/scroll.js
  function _mmdScrollTarget() {
    var codeEl = document.querySelector("#diagram-wrap.code-body pre code");
    if (codeEl) {
      return codeEl;
    }
    return document.querySelector(".viewer");
  }
  function _createScrollSync(notify, docPathTracker) {
    var pendingRestore = null;
    var debounceTimer = null;
    function cancelPendingNotify() {
      if (debounceTimer === null) {
        return;
      }
      clearTimeout(debounceTimer);
      debounceTimer = null;
    }
    return {
      setRestore: function(position) {
        pendingRestore = position;
      },
      // 復元位置が注入されている(=Swift 主導のファイル/モード切替)ときだけ保留中の
      // デバウンス通知を破棄する。無条件に破棄すると、Swift を経由しない内部再描画
      // (カラースキーム変更時など、ファイル/モードは変わらない)で直前のスクロール確定
      // 保存が失われたまま二度と発火しなくなるため。
      // 文書パスの採用も同じ時点で行う。破棄と採用が同時なので、旧文書の位置が
      // 新パスのキーで通知されることはない。
      beginRender: function() {
        if (pendingRestore !== null) {
          cancelPendingNotify();
        }
        docPathTracker.adoptPending();
      },
      // 注入された復元位置があればそれを、無ければ fallback を返して消費する。
      // fallback は Swift を経由しない内部再描画で現在位置を保つための値。
      takeRestorePosition: function(fallback) {
        var position = pendingRestore !== null ? pendingRestore : typeof fallback === "number" ? fallback : 0;
        pendingRestore = null;
        return position;
      },
      notifyDebounced: function() {
        cancelPendingNotify();
        debounceTimer = setTimeout(function() {
          debounceTimer = null;
          notify();
        }, 200);
      }
    };
  }
  function _mmdPostScrollPosition() {
    var el = _mmdScrollTarget();
    if (!el) return;
    _mmdPostMessage(_MSG_SCROLL_POSITION_CHANGED, {
      position: el.scrollTop,
      mode: _mmdViewOptions.mode(),
      path: _mmdDocPath.current()
    });
  }
  var _mmdScroll = _createScrollSync(_mmdPostScrollPosition, _mmdDocPath);
  function _mmdSetRestoreScroll(position) {
    _mmdScroll.setRestore(position);
  }
  function _mmdRestoreScrollPosition(fallbackScrollTop) {
    var el = _mmdScrollTarget();
    if (!el) return;
    el.scrollTop = _mmdScroll.takeRestorePosition(fallbackScrollTop);
  }
  function _mmdInitScrollNotify() {
    document.addEventListener("scroll", function() {
      _mmdScroll.notifyDebounced();
    }, true);
  }

  // viewer-src/find.js
  function buildFindRegExp(query2, options) {
    if (!query2) {
      return null;
    }
    var source = options.useRegex ? query2 : query2.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (options.wholeWord) {
      source = "\\b(?:" + source + ")\\b";
    }
    var flags = "g" + (options.caseSensitive ? "" : "i");
    try {
      return new RegExp(source, flags);
    } catch (e) {
      return null;
    }
  }
  function nextMatchIndex(currentIndex, count) {
    if (count <= 0) {
      return -1;
    }
    return (currentIndex + 1) % count;
  }
  function prevMatchIndex(currentIndex, count) {
    if (count <= 0) {
      return -1;
    }
    return (currentIndex - 1 + count) % count;
  }
  function keptMatchIndex(previousIndex, count) {
    if (count <= 0) {
      return -1;
    }
    return Math.min(Math.max(previousIndex, 0), count - 1);
  }
  function _createFindController() {
    var options = { caseSensitive: false, wholeWord: false, useRegex: false };
    var query2 = "";
    var matches = [];
    var currentIndex = -1;
    var isOpenFlag = false;
    var truncated = false;
    var skipTags = ["MARK", "SVG", "STYLE", "SCRIPT"];
    function clearMarks() {
      var marks = document.querySelectorAll("#diagram-wrap mark.mmd-find-match");
      var parents = /* @__PURE__ */ new Set();
      marks.forEach(function(mark) {
        var parent = mark.parentNode;
        if (!parent) return;
        while (mark.firstChild) {
          parent.insertBefore(mark.firstChild, mark);
        }
        parent.removeChild(mark);
        parents.add(parent);
      });
      parents.forEach(function(parent) {
        parent.normalize();
      });
    }
    var bridgeTags = [
      "SPAN",
      "A",
      "CODE",
      "EM",
      "STRONG",
      "B",
      "I",
      "U",
      "S",
      "DEL",
      "INS",
      "SMALL",
      "SUB",
      "SUP",
      "ABBR",
      "KBD",
      "SAMP",
      "VAR",
      "Q",
      "CITE",
      "TIME",
      "LABEL"
    ];
    function isBridgeable(node) {
      return node.nodeType === 1 && bridgeTags.indexOf(node.tagName.toUpperCase()) !== -1;
    }
    function collectScopes(root) {
      var scopes = [];
      var current = [];
      function flush() {
        if (current.length > 0) {
          scopes.push(current);
          current = [];
        }
      }
      function recurse(node) {
        var children = node.childNodes;
        for (var i = 0; i < children.length; i++) {
          var child = children[i];
          if (child.nodeType === 3) {
            current.push(child);
          } else if (child.nodeType === 1 && skipTags.indexOf(child.tagName.toUpperCase()) === -1) {
            if (isBridgeable(child)) {
              recurse(child);
            } else {
              flush();
              recurse(child);
              flush();
            }
          }
        }
      }
      recurse(root);
      flush();
      return scopes;
    }
    function locate(textNodes, starts, offset, isStart) {
      for (var i = 0; i < textNodes.length; i++) {
        var start = starts[i];
        var length = textNodes[i].length;
        var fits = isStart ? offset < start + length : offset <= start + length;
        if (fits) {
          return { node: textNodes[i], localOffset: offset - start };
        }
      }
      var last = textNodes.length - 1;
      return { node: textNodes[last], localOffset: textNodes[last].length };
    }
    function matchScope(root, textNodeList, regex, found) {
      var starts = [];
      var text = "";
      textNodeList.forEach(function(node) {
        starts.push(text.length);
        text += node.textContent;
      });
      regex.lastIndex = 0;
      var ranges = [];
      var match;
      while ((match = regex.exec(text)) !== null) {
        if (match[0].length === 0) {
          regex.lastIndex++;
          if (regex.lastIndex > text.length) break;
          continue;
        }
        ranges.push({ start: match.index, end: match.index + match[0].length });
      }
      if (ranges.length === 0) return;
      var scopeFound = [];
      ranges.reverse().forEach(function(range) {
        var start = locate(textNodeList, starts, range.start, true);
        var end = locate(textNodeList, starts, range.end, false);
        var startAncestor = start.node.parentNode;
        var endAncestor = end.node.parentNode;
        var domRange = document.createRange();
        domRange.setStart(start.node, start.localOffset);
        domRange.setEnd(end.node, end.localOffset);
        var mark = document.createElement("mark");
        mark.className = "mmd-find-match";
        mark.appendChild(domRange.extractContents());
        domRange.insertNode(mark);
        scopeFound.unshift(mark);
        pruneEmptyAncestors(startAncestor, root);
        pruneEmptyAncestors(endAncestor, root);
      });
      found.push.apply(found, scopeFound);
    }
    function walk(root, regex, found) {
      collectScopes(root).forEach(function(textNodeList) {
        matchScope(root, textNodeList, regex, found);
      });
    }
    function pruneEmptyAncestors(node, root) {
      while (node && node !== root && node.nodeType === 1 && node.textContent === "") {
        var parent = node.parentNode;
        if (!parent) break;
        parent.removeChild(node);
        node = parent;
      }
    }
    function updateCount() {
      var countEl = document.getElementById("mmd-find-count");
      var input = document.getElementById("mmd-find-input");
      if (query2.length === 0 || input.classList.contains("mmd-find-error")) {
        countEl.textContent = "";
      } else {
        var current = matches.length === 0 ? 0 : currentIndex + 1;
        var text = current + "/" + matches.length;
        if (truncated) {
          var strings = window._mmdFindStrings || {};
          text += " (" + (strings.withinDisplayedRange || "Displayed range") + ")";
        }
        countEl.textContent = text;
      }
    }
    function highlightCurrent() {
      matches.forEach(function(mark) {
        mark.classList.remove("mmd-find-match-current");
      });
      var current = matches[currentIndex];
      if (!current) return;
      current.classList.add("mmd-find-match-current");
      current.scrollIntoView({ block: "center", behavior: "smooth" });
    }
    function moveTo(index) {
      currentIndex = index;
      highlightCurrent();
      updateCount();
    }
    function run(suppressAutoHighlight) {
      var input = document.getElementById("mmd-find-input");
      query2 = input.value;
      clearMarks();
      matches = [];
      currentIndex = -1;
      var regex = buildFindRegExp(query2, options);
      input.classList.toggle("mmd-find-error", query2.length > 0 && regex === null);
      if (regex) {
        walk(document.getElementById("diagram-wrap"), regex, matches);
      }
      if (matches.length > 0) {
        currentIndex = 0;
        if (!suppressAutoHighlight) {
          highlightCurrent();
        }
      }
      updateCount();
    }
    function refresh(resetToFirst) {
      var previousIndex = resetToFirst ? 0 : currentIndex;
      run(true);
      if (matches.length > 0) {
        moveTo(keptMatchIndex(previousIndex, matches.length));
      }
    }
    function next() {
      if (matches.length === 0) return;
      moveTo(nextMatchIndex(currentIndex, matches.length));
    }
    function prev() {
      if (matches.length === 0) return;
      moveTo(prevMatchIndex(currentIndex, matches.length));
    }
    function toggleOption(optionName, buttonId) {
      options[optionName] = !options[optionName];
      document.getElementById(buttonId).classList.toggle("active", options[optionName]);
      _mmdPostMessage(_MSG_FIND_OPTIONS_CHANGED, {
        caseSensitive: options.caseSensitive,
        wholeWord: options.wholeWord,
        useRegex: options.useRegex
      });
      run();
    }
    function applyHostSettings() {
      var opts = window._mmdInitialFindOptions || {};
      options.caseSensitive = !!opts.caseSensitive;
      options.wholeWord = !!opts.wholeWord;
      options.useRegex = !!opts.useRegex;
      document.getElementById("mmd-find-case").classList.toggle("active", options.caseSensitive);
      document.getElementById("mmd-find-word").classList.toggle("active", options.wholeWord);
      document.getElementById("mmd-find-regex").classList.toggle("active", options.useRegex);
      var strings = window._mmdFindStrings || {};
      var input = document.getElementById("mmd-find-input");
      if (strings.placeholder) {
        input.placeholder = strings.placeholder;
      }
      if (strings.previous) {
        document.getElementById("mmd-find-prev").title = strings.previous;
      }
      if (strings.next) {
        document.getElementById("mmd-find-next").title = strings.next;
      }
      if (strings.matchCase) {
        document.getElementById("mmd-find-case").title = strings.matchCase;
      }
      if (strings.matchWholeWord) {
        document.getElementById("mmd-find-word").title = strings.matchWholeWord;
      }
      if (strings.useRegularExpression) {
        document.getElementById("mmd-find-regex").title = strings.useRegularExpression;
      }
      if (strings.close) {
        document.getElementById("mmd-find-close").title = strings.close;
      }
    }
    function initControls() {
      document.getElementById("mmd-find-input").addEventListener("input", function() {
        run();
      });
      document.getElementById("mmd-find-input").addEventListener("keydown", function(e) {
        if (e.key === "Enter") {
          if (e.isComposing || e.keyCode === 229) {
            return;
          }
          e.preventDefault();
          if (e.shiftKey) {
            prev();
          } else {
            next();
          }
        }
      });
      document.getElementById("mmd-find-next").addEventListener("click", next);
      document.getElementById("mmd-find-prev").addEventListener("click", prev);
      document.getElementById("mmd-find-close").addEventListener("click", close);
      document.getElementById("mmd-find-case").addEventListener("click", function() {
        toggleOption("caseSensitive", "mmd-find-case");
      });
      document.getElementById("mmd-find-word").addEventListener("click", function() {
        toggleOption("wholeWord", "mmd-find-word");
      });
      document.getElementById("mmd-find-regex").addEventListener("click", function() {
        toggleOption("useRegex", "mmd-find-regex");
      });
    }
    function open() {
      isOpenFlag = true;
      document.getElementById("mmd-find-bar").style.display = "flex";
      var input = document.getElementById("mmd-find-input");
      input.value = query2;
      input.focus();
      input.select();
      run();
    }
    function close() {
      isOpenFlag = false;
      document.getElementById("mmd-find-bar").style.display = "none";
      clearMarks();
      matches = [];
      currentIndex = -1;
    }
    function setTruncated(value) {
      truncated = value;
      if (isOpenFlag) {
        updateCount();
      }
    }
    return {
      isOpen: function() {
        return isOpenFlag;
      },
      open,
      close,
      next,
      prev,
      refresh,
      applyHostSettings,
      initControls,
      setTruncated
    };
  }
  var _mmdFind = _createFindController();
  function _mmdInitFind() {
    _mmdFind.applyHostSettings();
  }
  function _mmdOpenFind() {
    _mmdFind.open();
  }
  function _mmdCloseFind() {
    _mmdFind.close();
  }
  function _mmdFindRefresh(resetToFirst) {
    _mmdFind.refresh(resetToFirst);
  }
  function _mmdFindNextIfOpen() {
    if (!_mmdFind.isOpen()) return;
    _mmdFind.next();
  }
  function _mmdFindPrevIfOpen() {
    if (!_mmdFind.isOpen()) return;
    _mmdFind.prev();
  }

  // viewer-src/keyboard.js
  var PAGE_SCROLL_RATIO = 0.9;
  var DEFAULT_LINE_SCROLL_STEP = 24;
  function pageScrollStep(clientHeight) {
    return clientHeight * PAGE_SCROLL_RATIO;
  }
  function halfPageScrollStep(clientHeight) {
    return pageScrollStep(clientHeight) / 2;
  }
  function lineScrollStep(lineHeightPx, fallback) {
    var lh = parseFloat(lineHeightPx);
    return isNaN(lh) ? fallback : lh;
  }
  function resolveScrollKey(key, shiftKey) {
    if (key === " ") {
      return { down: !shiftKey, amount: "page" };
    }
    var down;
    if (key === "ArrowDown" || key === "j") {
      down = true;
    } else if (key === "ArrowUp" || key === "k") {
      down = false;
    } else {
      return null;
    }
    return { down, amount: shiftKey ? "half" : "line" };
  }
  function _mmdInitKeyboard() {
    document.addEventListener("keydown", function(e) {
      if (e.key === "Escape" && _mmdFind.isOpen() && !e.isComposing && e.keyCode !== 229) {
        e.preventDefault();
        _mmdFind.close();
        return;
      }
      document.body.classList.toggle("cmd-held", e.metaKey);
      if (e.metaKey) {
        if (e.key === "-") {
          e.preventDefault();
          _mmdZoomOut();
        } else if (e.key === "=" || e.key === "+") {
          e.preventDefault();
          _mmdZoomIn();
        }
        return;
      }
      var action = resolveScrollKey(e.key, e.shiftKey);
      if (!action) {
        return;
      }
      if (e.key === " " && !isHostFeatureEnabled(window._mmdHostFeatures, "spaceScroll")) {
        return;
      }
      var active = document.activeElement;
      if (active && (active.tagName === "INPUT" || active.tagName === "TEXTAREA" || active.isContentEditable)) {
        return;
      }
      var scrollEl = _mmdScrollTarget();
      if (!scrollEl) {
        return;
      }
      e.preventDefault();
      var step;
      if (action.amount === "page") {
        step = pageScrollStep(scrollEl.clientHeight);
      } else if (action.amount === "half") {
        step = halfPageScrollStep(scrollEl.clientHeight);
      } else {
        step = lineScrollStep(getComputedStyle(scrollEl).lineHeight, DEFAULT_LINE_SCROLL_STEP);
      }
      scrollEl.scrollBy({ top: action.down ? step : -step, behavior: "auto" });
    });
    document.addEventListener("keyup", function(e) {
      if (!e.metaKey) document.body.classList.remove("cmd-held");
    });
    window.addEventListener("blur", function() {
      document.body.classList.remove("cmd-held");
    });
  }

  // viewer-src/path-refs.js
  function isLocalPathHref(href) {
    if (!href) {
      return false;
    }
    if (href.charAt(0) === "#") {
      return false;
    }
    var m = href.match(/^([a-zA-Z][a-zA-Z0-9+.\-]*):/);
    if (m && m[1].indexOf(".") === -1) {
      return false;
    }
    return true;
  }
  var _PATH_RE = /(?:(?<![/\w.])(?:\/?\.\.?\/[\w./-]+|[\w.-]+\/[\w./-]+)|(?:^|(?<=\s))\/[\w./-]+)(?:\.(?:swift|md|mmd|ts|tsx|js|jsx|py|rb|go|rs|java|kt|c|cpp|h|hpp|json|yaml|yml|toml|txt|html|css|sh))(?::\d+)*/g;
  var _PATH_ANNOTATE_TAGS = ["p", "li", "td", "th", "blockquote", "dt", "dd", "code"];
  function _annotatePathRefs() {
    var wrap = document.getElementById("diagram-wrap");
    if (wrap) {
      _walkTextNodes(wrap, false);
    }
  }
  function _walkTextNodes(node, allowed) {
    if (node.nodeType === 3) {
      if (!allowed) return;
      var text = node.textContent;
      _PATH_RE.lastIndex = 0;
      var match = _PATH_RE.exec(text);
      if (!match) return;
      var frag = document.createDocumentFragment();
      var lastIndex = 0;
      do {
        if (match.index > lastIndex) {
          frag.appendChild(document.createTextNode(text.slice(lastIndex, match.index)));
        }
        var span = document.createElement("span");
        span.className = "befold-path-ref";
        span.dataset.path = match[0];
        span.textContent = match[0];
        frag.appendChild(span);
        lastIndex = _PATH_RE.lastIndex;
      } while ((match = _PATH_RE.exec(text)) !== null);
      if (lastIndex < text.length) {
        frag.appendChild(document.createTextNode(text.slice(lastIndex)));
      }
      node.parentNode.replaceChild(frag, node);
    } else if (node.nodeType === 1) {
      var tag = node.tagName.toLowerCase();
      if (tag === "a" || tag === "svg" || node.classList.contains("mermaid") || node.classList.contains("befold-path-ref")) {
        return;
      }
      var childAllowed;
      if (tag === "pre") {
        childAllowed = false;
      } else {
        childAllowed = allowed || _PATH_ANNOTATE_TAGS.indexOf(tag) !== -1;
      }
      var children = Array.prototype.slice.call(node.childNodes);
      for (var j = 0; j < children.length; j++) {
        _walkTextNodes(children[j], childAllowed);
      }
    }
  }
  var _mmdPendingRefBatches = [];
  function _mmdIsClassifiedRef(el) {
    return el.classList.contains("befold-link-pending") || el.classList.contains("befold-link") || el.classList.contains("befold-link-dead");
  }
  function _mmdResolveReferences() {
    if (!isHostFeatureEnabled(window._mmdHostFeatures, "referenceActivation")) {
      return;
    }
    var wrap = document.getElementById("diagram-wrap");
    if (!wrap) {
      return;
    }
    var targets = [];
    wrap.querySelectorAll("a[href]").forEach(function(a) {
      if (_mmdIsClassifiedRef(a)) {
        return;
      }
      var href = a.getAttribute("href");
      if (isLocalPathHref(href)) {
        targets.push({ el: a, raw: href });
      }
    });
    wrap.querySelectorAll(".befold-path-ref").forEach(function(s) {
      if (_mmdIsClassifiedRef(s) || !s.dataset.path) {
        return;
      }
      targets.push({ el: s, raw: s.dataset.path });
    });
    if (!targets.length) {
      return;
    }
    var uniq = /* @__PURE__ */ Object.create(null);
    targets.forEach(function(t) {
      uniq[t.raw] = true;
    });
    if (!_mmdPostMessage(_MSG_RESOLVE_REFERENCES, { paths: Object.keys(uniq) })) {
      return;
    }
    targets.forEach(function(t) {
      t.el.classList.add("befold-link-pending");
    });
    _mmdPendingRefBatches.push(targets);
  }
  function _mmdApplyResolvedReferences(map) {
    var targets = _mmdPendingRefBatches.shift() || [];
    targets.forEach(function(t) {
      t.el.classList.remove("befold-link-pending");
      var abs = map && Object.prototype.hasOwnProperty.call(map, t.raw) ? map[t.raw] : null;
      if (abs) {
        t.el.classList.add("befold-link");
        t.el.dataset.resolved = abs;
        t.el.setAttribute("title", abs);
      } else {
        t.el.classList.add("befold-link-dead");
        if (t.el.tagName === "A") {
          t.el.removeAttribute("href");
        }
        t.el.removeAttribute("title");
      }
    });
  }
  function _mmdInvalidatePendingRefs() {
    for (var i = 0; i < _mmdPendingRefBatches.length; i++) {
      _mmdPendingRefBatches[i] = [];
    }
  }

  // viewer-src/reference-clicks.js
  function _mmdReferenceTargetHref(e) {
    var anchor = e.target.closest("a");
    var pathRef = e.target.closest(".befold-path-ref");
    var target = anchor || pathRef;
    if (!target) return null;
    if (target.classList.contains("befold-link-pending") || target.classList.contains("befold-link-dead")) {
      return null;
    }
    return anchor ? anchor.getAttribute("href") : pathRef.dataset.path;
  }
  function _mmdInitReferenceClicks() {
    var wrap = document.getElementById("diagram-wrap");
    wrap.addEventListener("click", function(e) {
      if (!e.isTrusted) return;
      if (e.ctrlKey || e.button !== 0) return;
      var href = _mmdReferenceTargetHref(e);
      if (!href) return;
      if (href.charAt(0) === "#") {
        e.preventDefault();
        try {
          var id = decodeURIComponent(href.slice(1));
        } catch (_) {
          var id = href.slice(1);
        }
        var el = document.getElementById(id) || document.querySelector('[name="' + CSS.escape(id) + '"]');
        if (el) el.scrollIntoView({ behavior: "smooth" });
        return;
      }
      e.preventDefault();
      if (!isHostFeatureEnabled(window._mmdHostFeatures, "referenceActivation")) {
        return;
      }
      _mmdPostMessage(_MSG_REFERENCE_ACTIVATED, {
        href,
        metaKey: e.metaKey,
        shiftKey: e.shiftKey
      });
    });
    wrap.addEventListener("contextmenu", function(e) {
      if (!e.isTrusted) return;
      if (!isHostFeatureEnabled(window._mmdHostFeatures, "referenceActivation")) {
        return;
      }
      var href = _mmdReferenceTargetHref(e);
      if (!href || href.charAt(0) === "#") {
        return;
      }
      e.preventDefault();
      _mmdPostMessage(_MSG_REFERENCE_CONTEXT_MENU, { href });
    });
  }

  // viewer-src/markdown.js
  var md;
  function isSafeLinkURL(url) {
    var str = String(url).trim().toLowerCase();
    if (/^data:image\//.test(str)) {
      return true;
    }
    return !/^(vbscript|javascript|file|data):/.test(str);
  }
  function sanitizeRenderedHtml(purify, html) {
    return purify.sanitize(html);
  }
  function markdownRenderer() {
    return md;
  }
  function _mmdInitMarkdown() {
    if (typeof markdownit === "undefined") {
      return;
    }
    md = markdownit({
      html: true,
      linkify: true,
      typographer: true,
      // highlight.min.js の読み込み失敗時は hljs 未定義 → highlightCode が '' を
      // 返し、ハイライトなしの従来表示に縮退する。
      highlight: function(str, lang) {
        return highlightCode(typeof hljs !== "undefined" ? hljs : null, str, lang);
      }
    });
    var _mdRenderOriginal = md.render.bind(md);
    md.render = function(src, env) {
      return sanitizeRenderedHtml(DOMPurify, _mdRenderOriginal(src, env));
    };
    md.linkify.set({ fuzzyLink: false });
    md.validateLink = isSafeLinkURL;
    var defaultFence = md.renderer.rules.fence;
    md.renderer.rules.fence = function(tokens, idx, options, env, self) {
      var token = tokens[idx];
      if (token.info.trim() === "mermaid") {
        return '<pre class="mermaid">' + md.utils.escapeHtml(token.content) + "</pre>";
      }
      if (defaultFence) {
        return defaultFence(tokens, idx, options, env, self);
      }
      return "<pre><code>" + md.utils.escapeHtml(token.content) + "</code></pre>";
    };
  }

  // viewer-src/mermaid.js
  function mermaidTheme(isDark) {
    return isDark ? "dark" : "default";
  }
  function _mmdMermaidConfig() {
    return {
      startOnLoad: false,
      theme: mermaidTheme(prefersDark()),
      // 図ラベル内の生 HTML をサニタイズする（デフォルトだが将来の既定変更に備えて明示）
      securityLevel: "strict",
      // mermaid.js のデフォルト上限（50,000文字/500エッジ）はアプリが許容するテキストファイル上限（10MB）より
      // はるかに小さく、大きめの図が "Maximum text size in diagram exceeded" になるため引き上げる。
      maxTextSize: 10 * 1024 * 1024,
      maxEdges: 1e4,
      sequence: { useMaxWidth: false },
      er: { useMaxWidth: false },
      flowchart: { useMaxWidth: false },
      gantt: { useMaxWidth: false },
      journey: { useMaxWidth: false },
      pie: { useMaxWidth: false },
      state: { useMaxWidth: false },
      class: { useMaxWidth: false }
    };
  }
  function _mmdMermaidParseError(err) {
    var msg = err && (err.message || err.str) || String(err);
    var panel = document.getElementById("mmd-error");
    panel.textContent = msg;
    panel.style.display = "block";
    if (_mmdDocument.type() === "mmd") {
      document.getElementById("diagram-wrap").style.display = "none";
    }
  }
  var _mermaidLoadPromise = null;
  function _mmdEnsureMermaidLoaded() {
    if (_mermaidLoadPromise) return _mermaidLoadPromise;
    _mermaidLoadPromise = new Promise(function(resolve, reject) {
      var script = document.createElement("script");
      script.src = "mermaid.min.js";
      script.onload = resolve;
      script.onerror = function() {
        reject(new Error("mermaid.min.js failed to load"));
      };
      document.head.appendChild(script);
    }).then(function() {
      mermaid.initialize(_mmdMermaidConfig());
      mermaid.parseError = _mmdMermaidParseError;
    });
    return _mermaidLoadPromise;
  }
  function _mmdReinitializeMermaidIfLoaded() {
    if (_mermaidLoadPromise) {
      mermaid.initialize(_mmdMermaidConfig());
    }
  }
  async function _mmdRunMermaid(diagramWrap, onlyUnprocessed) {
    var selector = onlyUnprocessed ? ".mermaid:not([data-processed])" : ".mermaid";
    var elements = diagramWrap.querySelectorAll(selector);
    if (elements.length === 0) {
      return;
    }
    try {
      await _mmdEnsureMermaidLoaded();
      elements.forEach(function(el, i) {
        if (!onlyUnprocessed) {
          el.removeAttribute("data-processed");
        }
        el.id = "mmd-" + i + "-" + Date.now();
      });
      await mermaid.run({ nodes: Array.from(elements) });
    } catch (e) {
    }
    _mmdWrapDiagrams(diagramWrap);
  }

  // viewer-src/renderers.js
  var BODY_CLASSES = [
    "markdown-body",
    "code-body",
    "html-body",
    "csv-body",
    "image-body",
    "pdf-body"
  ];
  function _mmdSetBodyClasses(el) {
    var keep = Array.prototype.slice.call(arguments, 1);
    BODY_CLASSES.forEach(function(name) {
      el.classList.toggle(name, keep.indexOf(name) >= 0);
    });
  }
  function _createPdfBlobHolder() {
    var url = null;
    return {
      issue: function(bytes) {
        url = URL.createObjectURL(new Blob([bytes], { type: "application/pdf" }));
        return url;
      },
      release: function() {
        if (!url) {
          return;
        }
        URL.revokeObjectURL(url);
        url = null;
      }
    };
  }
  var _mmdPdfBlob = _createPdfBlobHolder();
  function _renderMmd(diagramWrap, content) {
    diagramWrap.innerHTML = '<pre class="mermaid">' + escapeHtml(content) + "</pre>";
  }
  function _renderSvg(diagramWrap, content) {
    var img = document.createElement("img");
    img.src = svgDataURI(content);
    img.style.maxWidth = "100%";
    img.alt = "SVG";
    var wrap = document.createElement("div");
    wrap.className = "diagram-zoom-wrap";
    wrap.dataset.diagramIndex = "0";
    var scroll = document.createElement("div");
    scroll.className = "diagram-zoom-scroll";
    var inner = document.createElement("div");
    inner.className = "diagram-zoom-inner";
    inner.appendChild(img);
    scroll.appendChild(inner);
    wrap.appendChild(scroll);
    wrap.appendChild(_mmdBuildDiagramControls(wrap));
    diagramWrap.innerHTML = "";
    diagramWrap.appendChild(wrap);
    img.onload = function() {
      wrap.dataset.naturalHeight = inner.offsetHeight;
      _mmdApplyDiagramZoom(wrap);
    };
  }
  function _renderHtml(diagramWrap, content) {
    diagramWrap.classList.add("html-body");
    var iframe = document.createElement("iframe");
    iframe.setAttribute("sandbox", "allow-same-origin");
    iframe.srcdoc = content;
    iframe.style.width = "100%";
    iframe.style.border = "none";
    iframe.onload = function() {
      try {
        var h = iframe.contentDocument.documentElement.scrollHeight;
        iframe.style.height = h + "px";
      } catch (e) {
        iframe.style.height = "80vh";
      }
    };
    iframe.style.height = "80vh";
    diagramWrap.innerHTML = "";
    diagramWrap.appendChild(iframe);
  }
  function _renderCsv(diagramWrap, content, lang) {
    diagramWrap.classList.add("markdown-body", "csv-body");
    diagramWrap.innerHTML = buildTableHtml(parseCsv(content, lang || ","));
  }
  function _renderImage(diagramWrap, content, lang) {
    diagramWrap.classList.add("image-body");
    var img = document.createElement("img");
    img.alt = "Image";
    img.onload = function() {
      _mmdFitImage(img, diagramWrap);
    };
    img.src = imageDataURI(content, lang);
    diagramWrap.innerHTML = "";
    diagramWrap.appendChild(img);
  }
  function _renderPdf(diagramWrap, content) {
    diagramWrap.classList.add("pdf-body");
    var iframe = document.createElement("iframe");
    iframe.src = _mmdPdfBlob.issue(base64ToBytes(content));
    diagramWrap.innerHTML = "";
    diagramWrap.appendChild(iframe);
  }
  function _renderMarkdown(diagramWrap, content) {
    diagramWrap.classList.add("markdown-body");
    var md2 = markdownRenderer();
    if (!md2) {
      diagramWrap.innerHTML = "<p>markdown-it not loaded</p>";
      return false;
    }
    diagramWrap.innerHTML = md2.render(content);
    return true;
  }
  function _renderSource(diagramWrap, content, type, lang, shape) {
    _mmdSetBodyClasses(diagramWrap, "code-body");
    var diffHtml = _renderDiffHtmlIfAvailable(type, lang);
    if (diffHtml !== "") {
      diagramWrap.innerHTML = diffHtml;
      return "diff";
    }
    diagramWrap.innerHTML = shape === "csv-source" ? renderCsvSourceHtml(content, lang || ",", _mmdViewOptions.lineNumbers()) : renderCodeHtml(window.hljs, content, _sourceLanguage(type, lang), _mmdViewOptions.lineNumbers());
    return shape;
  }
  function _sourceLanguage(type, lang) {
    if (type === "svg" || type === "html") {
      return "xml";
    }
    if (type === "md") {
      return "markdown";
    }
    return lang || "plaintext";
  }
  function _renderDiffHtmlIfAvailable(type, lang) {
    var diff = _mmdViewOptions.diff();
    if (diff === null || type === "csv") {
      return "";
    }
    try {
      return renderDiffHtml(
        window.hljs,
        diff,
        _sourceLanguage(type, lang),
        _mmdViewOptions.lineNumbers(),
        _mmdViewOptions.diffLayout()
      );
    } catch (e) {
      return "";
    }
  }

  // viewer-src/render.js
  function renderShape(type, mode) {
    if (mode === "source" && type !== "code" && type !== "image" && type !== "pdf") {
      return type === "csv" ? "csv-source" : "code";
    }
    if (type === "code") {
      return "code";
    }
    if (type === "csv") {
      return "csv-table";
    }
    if (type === "md") {
      return "markdown";
    }
    return type;
  }
  var _mmdRenderedAs = "";
  var CODE_CHUNK_CONTEXT_LINES = 200;
  function _mmdFindRefreshAfterRender() {
    var modeJustSwitched = _mmdModeSwitch.consume();
    if (_mmdFind.isOpen()) {
      _mmdFind.refresh(modeJustSwitched);
    }
  }
  async function render(content, type, lang) {
    _mmdScroll.beginRender();
    var scrollTargetBeforeRender = _mmdScrollTarget();
    var fallbackScrollTop = scrollTargetBeforeRender ? scrollTargetBeforeRender.scrollTop : 0;
    _mmdDocument.record(content, type, lang);
    _mmdChunkTail.record(content);
    var shape = renderShape(type, _mmdViewOptions.mode());
    _mmdRenderedAs = shape;
    _mmdInvalidatePendingRefs();
    var errorPanel = document.getElementById("mmd-error");
    errorPanel.style.display = "none";
    errorPanel.textContent = "";
    var diagramWrap = document.getElementById("diagram-wrap");
    diagramWrap.style.display = "block";
    _mmdSetBodyClasses(diagramWrap);
    _mmdPdfBlob.release();
    if (shape === "code" || shape === "csv-source") {
      _mmdRenderedAs = _renderSource(diagramWrap, content, type, lang, shape);
    } else if (shape === "mmd") {
      _renderMmd(diagramWrap, content);
    } else if (shape === "svg") {
      _renderSvg(diagramWrap, content);
    } else if (shape === "html") {
      _renderHtml(diagramWrap, content);
    } else if (shape === "csv-table") {
      _renderCsv(diagramWrap, content, lang);
    } else if (shape === "image") {
      _renderImage(diagramWrap, content, lang);
    } else if (shape === "pdf") {
      _renderPdf(diagramWrap, content);
    } else if (!_renderMarkdown(diagramWrap, content)) {
      return;
    }
    await _mmdRunMermaid(diagramWrap);
    _annotatePathRefs();
    _mmdResolveReferences();
    _mmdFindRefreshAfterRender();
    _mmdApplyZoom();
    _mmdRestoreScrollPosition(fallbackScrollTop);
  }
  function _mmdRerenderCurrent() {
    if (!_mmdDocument.hasContent()) {
      return;
    }
    render(_mmdDocument.content(), _mmdDocument.type(), _mmdDocument.lang());
  }
  function appendChunk(text, type, lang) {
    if (!text) {
      return;
    }
    var diagramWrap = document.getElementById("diagram-wrap");
    if (!diagramWrap) {
      return;
    }
    var highlightContext = _mmdChunkTail.endedWithNewline() && _mmdDocument.content() ? lastLines(_mmdDocument.content(), CODE_CHUNK_CONTEXT_LINES) : "";
    _mmdDocument.append(text);
    if (_mmdRenderedAs === "diff") {
      return;
    }
    if (_mmdRenderedAs === "markdown") {
      var md2 = markdownRenderer();
      if (!md2) {
        return;
      }
      diagramWrap.insertAdjacentHTML("beforeend", md2.render(text));
      _annotatePathRefs();
      _mmdRunMermaid(diagramWrap, true);
    } else if (_mmdRenderedAs === "csv-table") {
      var csvRows = parseCsv(text, lang || ",");
      var tbody = diagramWrap.querySelector("tbody");
      if (!tbody) {
        return;
      }
      var table = tbody.parentElement;
      var headRow = table.tHead && table.tHead.rows[0];
      var minCols = headRow ? headRow.cells.length : 0;
      var maxNewCols = 0;
      for (var r = 0; r < csvRows.length; r++) {
        if (csvRows[r].length > maxNewCols) {
          maxNewCols = csvRows[r].length;
        }
      }
      if (maxNewCols > minCols && headRow) {
        for (var c = minCols; c < maxNewCols; c++) {
          headRow.insertAdjacentHTML("beforeend", "<th></th>");
        }
        minCols = maxNewCols;
      }
      var firstNew = tbody.rows.length;
      tbody.insertAdjacentHTML("beforeend", csvRowsHtml(csvRows, minCols));
      for (var r2 = firstNew; r2 < tbody.rows.length; r2++) {
        _walkTextNodes(tbody.rows[r2], false);
      }
    } else {
      var isCsvSource = _mmdRenderedAs === "csv-source";
      var codeEl = diagramWrap.querySelector("pre code");
      if (!codeEl) {
        return;
      }
      var inner = isCsvSource ? csvSourceInnerHtml(text, lang || ",") : codeChunkInnerHtml(window.hljs, text, lang, highlightContext);
      var codeTable = codeEl.querySelector("table.code-table");
      if (codeTable) {
        var startLine = codeTable.rows.length + (_mmdChunkTail.endedWithNewline() ? 1 : 0);
        var rowsHtml = buildLineNumberRows(inner, startLine, _mmdViewOptions.lineNumbers());
        if (!_mmdChunkTail.endedWithNewline() && codeTable.rows.length > 0) {
          var pendingRows = document.createElement("tbody");
          pendingRows.innerHTML = rowsHtml;
          var continuationRow = pendingRows.rows[0];
          if (continuationRow) {
            var lastRow = codeTable.rows[codeTable.rows.length - 1];
            var lastContentCell = lastRow.querySelector(".line-content");
            var continuationContentCell = continuationRow.querySelector(".line-content");
            if (lastContentCell && continuationContentCell) {
              lastContentCell.insertAdjacentHTML("beforeend", continuationContentCell.innerHTML);
            }
            continuationRow.remove();
            rowsHtml = pendingRows.innerHTML;
            _walkTextNodes(lastRow, false);
          }
        }
        var firstNewRow = codeTable.rows.length;
        codeTable.insertAdjacentHTML("beforeend", rowsHtml);
        for (var i = firstNewRow; i < codeTable.rows.length; i++) {
          _walkTextNodes(codeTable.rows[i], false);
        }
      } else {
        codeEl.insertAdjacentHTML("beforeend", inner);
        _annotatePathRefs();
      }
    }
    _mmdChunkTail.record(text);
    _mmdResolveReferences();
    _mmdFindRefreshAfterRender();
  }

  // viewer-src/truncation.ts
  function _mmdSetTruncated(isTruncated, lineCount, failed) {
    _mmdFind.setTruncated(isTruncated);
    var banner = document.getElementById("mmd-truncated-banner");
    if (!isTruncated) {
      banner.style.display = "none";
      return;
    }
    banner.style.display = "flex";
    var strings = window._mmdBannerStrings || {};
    var textEl = document.getElementById("mmd-truncated-text");
    var btn = document.getElementById("mmd-load-more-btn");
    if (failed) {
      textEl.textContent = strings.loadError || "Failed to load the rest of the file";
      btn.style.display = "none";
    } else if (typeof lineCount === "number") {
      textEl.textContent = (strings.showing || "Showing {count} lines").replace("{count}", String(lineCount));
      if (isHostFeatureEnabled(window._mmdHostFeatures, "loadMore")) {
        btn.textContent = strings.loadMore || "Load More";
        btn.style.display = "inline-block";
      } else {
        btn.style.display = "none";
      }
    } else {
      textEl.textContent = strings.showing ? strings.showing.replace("{count}", "?") : "Showing partial content";
      btn.style.display = "none";
    }
  }
  function _mmdLoadMore() {
    if (!isHostFeatureEnabled(window._mmdHostFeatures, "loadMore")) {
      return;
    }
    _mmdPostMessage(_MSG_LOAD_MORE_LINES, {});
  }
  function _mmdInitLoadMore() {
    document.getElementById("mmd-load-more-btn").addEventListener("click", function(e) {
      if (!e.isTrusted) return;
      _mmdLoadMore();
    });
  }

  // viewer-src/init.js
  function _mmdInitColorScheme() {
    onColorSchemeChange(function() {
      _mmdReinitializeMermaidIfLoaded();
      _mmdRerenderCurrent();
    });
  }
  function _mmdInit() {
    _mmdInitKeyboard();
    _mmdInitReferenceClicks();
    _mmdInitWheelZoom();
    _mmdInitResize();
    _mmdInitColorScheme();
    _mmdInitMarkdown();
    _mmdFind.initControls();
    _mmdInitScrollNotify();
    _mmdInitLoadMore();
    _mmdInitZoom();
    _mmdInitFontSize();
    _mmdInitCodeFont();
    _mmdInitFind();
  }

  // viewer-src/expose.ts
  function exposeGlobals(namespace) {
    for (const [name, value] of Object.entries(namespace)) {
      globalThis[name] = value;
    }
  }

  // viewer-src/index.js
  exposeGlobals(main_exports);
  _mmdInit();
})();
