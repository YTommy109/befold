@testable import BefoldKit
import Foundation
import Testing

struct QuickOpenQueryTests {
    @Test("入力文字列を種別へ分類する", arguments: [
        ("", QuickOpenQuery.Kind.empty), // 空文字は履歴表示モードになる
        ("   ", .empty), // 空白のみの入力も履歴表示モードになる
        ("\t \n", .empty),
        ("/usr/local", .path("/usr/local")), // スラッシュ始まりはパスモードになる
        ("~/dev/be", .path("~/dev/be")), // チルダ始まりはパスモードになる
        ("~", .path("~")), // チルダ単独もパスモードになる
        ("./docs", .path("./docs")), // ドット始まりはパスモードになる
        ("../src/a.swift", .path("../src/a.swift")),
        (".", .path(".")),
        (".gitignore", .path(".gitignore")), // 隠しファイル名の断片もパスモードへ倒す(親ディレクトリの前方一致で候補を出すため)
        ("viewer", .fuzzy("viewer")), // それ以外は fuzzy 検索モードになる
        ("src/utils", .fuzzy("src/utils")),
        ("  viewer  ", .fuzzy("viewer")), // 前後の空白は落として分類する
        ("  ~/dev  ", .path("~/dev")),
    ])
    func classify(input: String, expected: QuickOpenQuery.Kind) {
        #expect(QuickOpenQuery.classify(input) == expected)
    }
}
