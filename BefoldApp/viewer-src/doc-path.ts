// 「いま DOM に出ている文書」のパスを追跡する。Swift へ送る per-file な通知
// (スクロール位置・倍率)の保存キーは、すべてここから読んで payload に載せる。
// 値を読むのが通知の発火時点なので、evaluateJavaScript のキューや postMessage
// 配達の遅延と無関係に実 DOM と一致する(Swift 側が現在 URL や描画済みミラーから
// 配達時に推定するのをやめた理由 = TASK-400 / TASK-393)。

function _createDocPathTracker() {
  var docPath: string | null = null;
  // undefined = 予告なし(Swift を経由しない内部再描画)。null は「文書パス無し」の予告。
  // 区別しないと、カラースキーム変更などの内部 render() が採用済みのパスを破棄してしまう。
  var pendingDocPath: string | null | undefined;

  return {
    // 次の render() が表示する文書パスの予告。採用は adoptPending()(= render 開始時)。
    // ここで即時に切り替えると、render script の実行前に通知が発火したとき
    // 旧文書の値が新パスのキーで保存される。
    setPending: function (path: string | null): void {
      pendingDocPath = path;
    },
    // rename / move の追随。DOM は同一文書のまま名前だけ変わるため render を経ずに
    // 即時差し替える。現在値・予告値のうち from に一致するものだけを書き換える
    // (不一致 = 別文書へ切替中なら何もしない。誤った付け替えより、旧キーへの
    // 短時間の保存のほうが安全)。
    rename: function (from: string, to: string): void {
      if (docPath === from) {
        docPath = to;
      }
      if (pendingDocPath === from) {
        pendingDocPath = to;
      }
    },
    current: function (): string | null {
      return docPath;
    },
    adoptPending: function (): void {
      if (pendingDocPath === undefined) {
        return;
      }
      docPath = pendingDocPath;
      pendingDocPath = undefined;
    },
  };
}

var _mmdDocPath = _createDocPathTracker();

function _mmdSetRenderDocPath(path: string | null): void {
  _mmdDocPath.setPending(path);
}

function _mmdRenameDocPath(from: string, to: string): void {
  _mmdDocPath.rename(from, to);
}

export { _mmdDocPath, _mmdSetRenderDocPath, _mmdRenameDocPath };
