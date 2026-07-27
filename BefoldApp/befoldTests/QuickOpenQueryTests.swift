@testable import BefoldKit
import Foundation
import Testing

struct QuickOpenQueryTests {
    @Test("空文字は履歴表示モードになる")
    func emptyInput() {
        #expect(QuickOpenQuery.classify("") == .empty)
    }

    @Test("空白のみの入力も履歴表示モードになる")
    func whitespaceOnlyInput() {
        #expect(QuickOpenQuery.classify("   ") == .empty)
        #expect(QuickOpenQuery.classify("\t \n") == .empty)
    }

    @Test("スラッシュ始まりはパスモードになる")
    func absolutePath() {
        #expect(QuickOpenQuery.classify("/usr/local") == .path("/usr/local"))
    }

    @Test("チルダ始まりはパスモードになる")
    func tildePath() {
        #expect(QuickOpenQuery.classify("~/dev/be") == .path("~/dev/be"))
    }

    @Test("チルダ単独もパスモードになる")
    func tildeAlone() {
        #expect(QuickOpenQuery.classify("~") == .path("~"))
    }

    @Test("ドット始まりはパスモードになる")
    func dotPath() {
        #expect(QuickOpenQuery.classify("./docs") == .path("./docs"))
        #expect(QuickOpenQuery.classify("../src/a.swift") == .path("../src/a.swift"))
        #expect(QuickOpenQuery.classify(".") == .path("."))
    }

    /// 隠しファイル名の断片(".gitignore" など)もパスモードへ倒す。
    /// パスモードは親ディレクトリの前方一致で候補を出すため、カレント直下の
    /// 隠しファイルはパスモードでもそのまま辿り着ける。
    @Test("ドット始まりの隠しファイル名もパスモードとして扱う")
    func dotfileGoesToPathMode() {
        #expect(QuickOpenQuery.classify(".gitignore") == .path(".gitignore"))
    }

    @Test("それ以外は fuzzy 検索モードになる")
    func fuzzyInput() {
        #expect(QuickOpenQuery.classify("viewer") == .fuzzy("viewer"))
        #expect(QuickOpenQuery.classify("src/utils") == .fuzzy("src/utils"))
    }

    @Test("前後の空白は落として分類する")
    func trimsSurroundingWhitespace() {
        #expect(QuickOpenQuery.classify("  viewer  ") == .fuzzy("viewer"))
        #expect(QuickOpenQuery.classify("  ~/dev  ") == .path("~/dev"))
    }
}
