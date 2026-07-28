@testable import befold
import Testing

@Suite
struct MonospaceFontCatalogTests {
    @Test("重複を除きアルファベット順に整列する")
    func dedupesAndSorts() {
        let result = MonospaceFontCatalog.names(from: ["Menlo", "SF Mono", "Menlo"])
        #expect(result == ["Menlo", "SF Mono"])
    }

    @Test("空入力は空を返す")
    func emptyInput() {
        #expect(MonospaceFontCatalog.names(from: []).isEmpty)
    }
}
