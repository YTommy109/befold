import BefoldKit
import Testing

@Suite
struct WildcardMatcherTests {
    @Test("空文字列は全件に一致する")
    func emptyPatternMatchesEverything() {
        #expect(WildcardMatcher.matches(pattern: "", in: "README.md"))
    }

    @Test("部分一致する文字列に一致する")
    func substringMatches() {
        #expect(WildcardMatcher.matches(pattern: "adme", in: "README.md"))
    }

    @Test("大文字小文字を無視する")
    func caseInsensitive() {
        #expect(WildcardMatcher.matches(pattern: "readme", in: "README.md"))
    }

    @Test("含まれない文字列には一致しない")
    func nonMatchingSubstringFails() {
        #expect(!WildcardMatcher.matches(pattern: "xyz", in: "README.md"))
    }

    @Test("* は0文字以上の任意の文字列に一致する")
    func asteriskMatchesAnyLength() {
        #expect(WildcardMatcher.matches(pattern: "RE*me", in: "README.md"))
        #expect(WildcardMatcher.matches(pattern: "RE*me", in: "REme.md"))
    }

    @Test("? は任意の1文字にのみ一致する")
    func questionMarkMatchesExactlyOneCharacter() {
        #expect(WildcardMatcher.matches(pattern: "REA?ME", in: "README.md"))
        #expect(!WildcardMatcher.matches(pattern: "REA??ME", in: "README.md"))
    }

    @Test("[...] などその他の glob 構文はリテラル文字として扱う")
    func otherGlobSyntaxIsTreatedLiterally() {
        #expect(!WildcardMatcher.matches(pattern: "[Rr]eadme", in: "README.md"))
        #expect(WildcardMatcher.matches(pattern: "[Rr]eadme", in: "a[Rr]eadme.md"))
    }

    @Test("正規表現のメタ文字はリテラル文字として扱う")
    func regexMetacharactersAreTreatedLiterally() {
        #expect(!WildcardMatcher.matches(pattern: "read.me", in: "readXme.md"))
        #expect(WildcardMatcher.matches(pattern: "read.me", in: "read.me.md"))
    }
}
