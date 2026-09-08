import Foundation

/// 描画面（viewer.html を表示し、JS コマンドを受け取る面）への**送出**境界。
///
/// **WKWebView の API を写したものではない。** この層が実際に使っている操作だけを
/// 並べてある（TASK-595.1 の着手時に BefoldRenderKit 全 20 ファイルを実測して列挙した）。
/// 描画の実体は Swift ではなく `BefoldKit/Resources` の viewer.html + viewer-bundle.js に
/// あり、Swift 側の責務は「HTML をロードし、コマンドを送る」ことに尽きる。だから
/// 境界もその 2 つを中心に、直接 HTML モードが要求する周辺操作を足した形になる。
///
/// 受信方向（ナビゲーション事象・ブリッジメッセージ）はここに含まない。あちらは
/// 戻り値を返す判断（リンククリックの可否）を含み、性質が違う（TASK-595.2 で扱う）。
///
/// `@MainActor` なのは、実測でこの層の描画面接触が例外なく MainActor 上だったから。
/// Sendable の考慮は要らない。
@MainActor
public protocol RenderSurface: AnyObject {
    /// 描画コマンドを送る。**返り値は返さない。**
    ///
    /// この層の送出 5 箇所は 1 つも JS の返り値を使っていない（実測）。返り値を
    /// 返す形にすると呼び出し側が `await` したくなるが、それは避けなければならない——
    /// `ViewerScriptDispatcher.applyRender` は await の後を **await 無しの一続き**に
    /// 保っており、そこへ suspension point が入ると「送ったのにミラーが確定しない」
    /// 状態が生まれる。TASK-320 / 334 / 336 で 3 回連続して起きた形で、
    /// 部分更新の経路を畳んでようやく終息したもの。
    ///
    /// - Parameter completion: 失敗を記録するための口。JS が**返らない**場合
    ///   （無限ループ等）は呼ばれないので、それは別の手段で見る。
    func evaluateScript(_ script: String, completion: ((Error?) -> Void)?)

    /// 描画コマンドを送り、**完了を待って**返り値を受け取る。
    ///
    /// `evaluateScript` と分けてあるのは、待つ必要があるのが 1 回描画ホスト
    /// （QuickLook 拡張の `OneShotRenderer`）だけだから。2 つを 1 つにまとめると
    /// 全送出が async になり、上に書いた一続きが壊れる。
    func callScript(_ script: String) async throws -> Any?

    /// ローカルファイルを、指定ディレクトリ配下の読み取りを許して開く。
    ///
    /// viewer.html のロードと、直接 HTML モードでの文書ロードの 2 経路が使う。
    /// 読み取り許可の範囲を呼び出し側が決めるのは、前者が同梱リソース一式、
    /// 後者が文書の親ディレクトリと、必要な範囲が違うため。
    func loadLocalFile(_ url: URL, allowingReadAccessTo directory: URL)

    /// エンコーディングを明示して HTML を開く。
    ///
    /// charset 宣言の無い HTML だけが使う。宣言があれば `loadLocalFile` の方が
    /// 相対リソースを読めるぶん良く、こちらは文字化けを避けるための代替経路。
    func loadHTML(_ data: Data, mimeType: String, encoding: String, baseURL: URL)

    /// 表示倍率。
    ///
    /// 直接 HTML モードの前後で倍率を保つために読み書きする。ライブリロード時は
    /// 現在値を控えて当て直すため、get と set の両方が要る。
    var zoom: Double { get set }

    /// いま開いている URL。
    ///
    /// リンククリックが同一文書内のフラグメントかどうかの判定にだけ使う。
    var currentURL: URL? { get }

    /// 文書内の `<script>` を実行するか。
    ///
    /// 直接 HTML モードでは外部 HTML の JS を止め、viewer.html へ戻すときに
    /// 入れ直す（viewer.html は mermaid.js のため JS 必須）。
    var isContentJavaScriptEnabled: Bool { get set }

    /// リモート読み込みの遮断ポリシーを適用し、終わったら `completion` を呼ぶ。
    ///
    /// **この操作を境界に出しているのは、適用を無条件にするため。** 以前は
    /// 「WebKit 実装だったら適用する」という形で、実装型が変わると遮断が黙って
    /// 外れた（TASK-599）。ここに置けば、新しい描画エンジンは実装しないと
    /// コンパイルが通らない——空実装を書くのは意図的な選択として残り、
    /// 「気づかず外れる」経路が消える。
    ///
    /// 適用に失敗しても `completion` は必ず呼ぶこと。握り潰すとビューアが空のまま
    /// 何も表示されない状態になり、「外部画像が出る」より重い故障になる。
    func applyRemoteLoadPolicy(then completion: @escaping () -> Void)

    /// 名前つきの postMessage ハンドラを取り外す。
    ///
    /// 面を捨てるときの後始末。`applyRemoteLoadPolicy` と同じ理由で境界に置いてある
    /// （実装型への downcast にすると、解除が黙って行われない形になる）。
    /// 名前で受けるのは、どのハンドラを登録したかを決めるのが呼び出し側だから。
    func removeMessageHandlers(named names: [String])

    /// 背景の描画を文書側に委ねるか。
    ///
    /// 直接 HTML モードで外部文書が背景ごと所有する場合に true。viewer.html を
    /// 描くときは透過（false）が既定。`isContentJavaScriptEnabled` と同じく
    /// enter/exit と対で倒す状態で、描画ミラーの外にある。
    func setDocumentOwnsCanvas(_ documentOwns: Bool)
}
