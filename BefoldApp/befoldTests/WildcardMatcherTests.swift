import BefoldKit
import Testing

@Suite
struct WildcardMatcherTests {
    @Test("パターンに対する一致・不一致を判定する", arguments: [
        (pattern: "", target: "README.md", matches: true), // 空文字列は全件に一致する
        ("adme", "README.md", true), // 部分一致する文字列に一致する
        ("readme", "README.md", true), // 大文字小文字を無視する
        ("xyz", "README.md", false), // 含まれない文字列には一致しない
        ("RE*me", "README.md", true), // * は0文字以上の任意の文字列に一致する
        ("RE*me", "REme.md", true),
        ("REA?ME", "README.md", true), // ? は任意の1文字にのみ一致する
        ("REA??ME", "README.md", false),
        ("[Rr]eadme", "README.md", false), // [...] などその他の glob 構文はリテラル文字として扱う
        ("[Rr]eadme", "a[Rr]eadme.md", true),
        ("read.me", "readXme.md", false), // 正規表現のメタ文字はリテラル文字として扱う
        ("read.me", "read.me.md", true),
    ])
    func matches(pattern: String, target: String, matches: Bool) {
        #expect(WildcardMatcher.matches(pattern: pattern, in: target) == matches)
    }
}
