import BefoldKit
import Foundation
import Testing

@Suite(.serialized)
struct StringChunkReaderTests {
    private func makeCache(_ text: String) throws -> NormalizedTextCache {
        try NormalizedTextCache(data: Data(text.utf8))
    }

    private func makeLines(_ count: Int) -> String {
        (0 ..< count).map { "line\($0)\n" }.joined()
    }

    private func readAll(_ reader: StringChunkReader) async -> [String] {
        var chunks: [String] = []
        while true {
            let result = await reader.readNextChunk()
            if !result.text.isEmpty { chunks.append(result.text) }
            if result.isAtEnd { break }
        }
        return chunks
    }

    @Test("500 行のファイルが 1 チャンクで完結する")
    func smallFileOneChunk() async throws {
        let text = makeLines(500)
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let result = await reader.readNextChunk()
        #expect(result.text == text)
        #expect(result.isAtEnd == true)
    }

    @Test("2500 行のファイルが 3 チャンクに分割される")
    func largeFileSplits() async throws {
        let text = makeLines(2500)
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let chunks = await readAll(reader)
        #expect(chunks.count == 3)
        #expect(chunks.joined() == text)
    }

    @Test("空キャッシュは空チャンクと isAtEnd を返す")
    func emptyCache() async throws {
        let cache = try makeCache("")
        let reader = StringChunkReader(cache: cache)
        let result = await reader.readNextChunk()
        #expect(result.text == "")
        #expect(result.isAtEnd == true)
    }

    @Test("ちょうど 1000 行は 1 チャンクで isAtEnd")
    func exactly1000Lines() async throws {
        let text = makeLines(1000)
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let result = await reader.readNextChunk()
        #expect(result.isAtEnd == true)
        #expect(result.text == text)
    }

    @Test("全チャンクを結合すると元テキストに一致する")
    func chunksReconstructOriginal() async throws {
        let text = makeLines(3333)
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let chunks = await readAll(reader)
        #expect(chunks.joined() == text)
    }

    @Test("CSV 引用符内の改行はチャンク境界にならない")
    func csvQuotedNewline() async throws {
        var lines = (0 ..< 998).map { "cell\($0)\n" }.joined()
        lines += "\"quoted\nfield\"\n"
        lines += "after\n"
        let cache = try makeCache(lines)
        let reader = StringChunkReader(cache: cache, respectsCSVQuotes: true)
        let result = await reader.readNextChunk()
        #expect(result.isAtEnd == true)
        #expect(result.text.contains("\"quoted\nfield\""))
    }

    @Test("CSV 引用符なしモードでは全改行がチャンク境界になる")
    func withoutCSVQuotes() async throws {
        var lines = (0 ..< 999).map { "cell\($0)\n" }.joined()
        lines += "\"quoted\nfield\"\n"
        lines += "after\n"
        let cache = try makeCache(lines)
        let reader = StringChunkReader(cache: cache, respectsCSVQuotes: false)
        let result = await reader.readNextChunk()
        #expect(result.isAtEnd == false)
    }

    @Test("読了後の再呼び出しは空チャンクを返す")
    func readAfterEnd() async throws {
        let cache = try makeCache("abc\n")
        let reader = StringChunkReader(cache: cache)
        let first = await reader.readNextChunk()
        #expect(first.isAtEnd == true)
        let second = await reader.readNextChunk()
        #expect(second.text == "")
        #expect(second.isAtEnd == true)
    }

    @Test("末尾改行なしテキストのチャンク分割が正しい")
    func noTrailingNewline() async throws {
        let text = makeLines(1000) + "lastline"
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let chunks = await readAll(reader)
        #expect(chunks.count == 2)
        #expect(chunks.joined() == text)
    }

    @Test("対のない引用符を含む巨大CSVは規定長超過後に行ベース分割へ復帰し、少数の巨大チャンクにならない")
    func unbalancedQuoteLargeCSVIsChunked() async throws {
        // 500 バイト回復機能(TASK-57)導入後は、不均衡クォート検出後すぐに行ベース
        // 分割へ復帰するため、チャンクは maxChunkBytes(1MB)に達する前に 1000 行単位で
        // 区切られるようになった。「各チャンクが maxChunkBytes 以下」という
        // アサーションだけでは復帰後の小さなチャンクでも自明に成立してしまい、
        // 復帰の成否を検出できない。復帰していれば 300,000 行 / 1000 行 ≈ 300 個の
        // チャンクに分かれ、各チャンクは数KB程度に収まるはずである。復帰に失敗して
        // 不均衡クォートのままバイト上限まで走査し続けた場合は、maxChunkBytes ごとの
        // 少数(数個)の巨大チャンクにしかならない。
        let rowCount = 300_000
        let hugeAfterUnbalancedQuote = String(repeating: "a,b,c\n", count: rowCount)
        let text = "\"unbalanced\n" + hugeAfterUnbalancedQuote
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache, respectsCSVQuotes: true)
        let chunks = await readAll(reader)
        #expect(chunks.joined() == text)
        #expect(chunks.count >= 250)
        #expect(chunks.allSatisfy { $0.utf8.count <= 10000 })
    }

    @Test("respectsCSVQuotes:true でクォートフィールドの内部が maxChunkBytes 境界をまたいでも、クォート状態を保ったまま強制分割される")
    func forcedSplitPreservesQuoteStateAcrossBoundary() async throws {
        // 開きクォートの後、maxChunkBytes 境界がクォートフィールド内部(500バイト未満の
        // 位置、不均衡クォートの規定長には達しない)に来るよう埋め草を配置する。
        // 強制分割後も inQuotes/quotedRunLength が正しく保持されていなければ、
        // フィールド内部の改行がチャンク境界(または行境界)として扱われてしまったり、
        // フィールドを閉じた後の後続クォート対応(followUpField)が反転したりする。
        let openingQuoteOffset = StringChunkReader.maxChunkBytes - 150
        let filler = String(repeating: "a", count: openingQuoteOffset)
        let straddlingField = "\"" + String(repeating: "x", count: 300) + "\nafter\"\n"
        let trailingRows = (0 ..< 2000).map { "row\($0)\n" }.joined()
        let followUpField = "\"quoted\nfield\"\n"
        let text = filler + straddlingField + trailingRows + followUpField + "tail\n"
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache, respectsCSVQuotes: true)
        let chunks = await readAll(reader)
        #expect(chunks.joined() == text)
        #expect(chunks.allSatisfy { $0.utf8.count <= StringChunkReader.maxChunkBytes })
        // filler だけで maxChunkBytes 手前まで達しているため、強制分割(バイト上限)と
        // 通常の行ベース分割の両方が発生し、複数チャンクに分かれるはず。
        #expect(chunks.count > 2)
        // 強制分割を経てもクォート対応が破壊されていなければ、後続の複数行
        // クォートフィールドは分断されず1つのチャンク内に残る。
        #expect(chunks.contains { $0.contains("\"quoted\nfield\"") })
    }

    @Test("改行なしの巨大1行ファイルでもチャンクサイズが上限内に収まる")
    func noNewlineHugeSingleLineIsChunked() async throws {
        let text = String(repeating: "A", count: StringChunkReader.maxChunkBytes + 500_000)
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let chunks = await readAll(reader)
        #expect(chunks.count >= 2)
        #expect(chunks.allSatisfy { $0.utf8.count <= StringChunkReader.maxChunkBytes })
        #expect(chunks.joined() == text)
    }

    @Test("対のない引用符は規定長を超えると不均衡とみなされ通常の行ベース分割に復帰する")
    func unbalancedQuoteGivesUpAfterGuaranteedLengthAndRecovers() async throws {
        // 先頭の対のない `"` により一時的にクォート内と判定されるが、閉じずに
        // 規定長(500バイト)を超えたら不均衡クォートとみなして inQuotes を
        // 強制的に閉じ、以降は通常の 1000 行ベースのチャンクに復帰するはずである。
        // リセットせず永久にクォート内とみなしてしまうと、ファイル全体が
        // 巨大な1チャンク(または少数のバイト上限チャンク)のまま行数が把握できなくなる。
        let plainRows = String(repeating: "a,b,c\n", count: 5000)
        let text = "\"" + plainRows
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache, respectsCSVQuotes: true)
        let chunks = await readAll(reader)
        #expect(chunks.joined() == text)
        // 復帰していれば 5000 行 / 1000 行 = 5 チャンク程度に分かれる。
        // 復帰しなければ強制分割前提の巨大チャンク(1〜2個)にしかならない。
        #expect(chunks.count >= 4)
        // 不均衡クォート判定までの ~500 バイト分の行はカウントされないため多少の
        // 超過はあるが、大幅に(1 チャンクあたり linesPerChunk の 2 倍近くまで)
        // 超過してはならない。
        #expect(chunks.count <= 6)
    }

    @Test("500 バイトを超える正規のクォートフィールドの後もクォート状態が正しく追跡される")
    func longLegitimateQuotedFieldDoesNotCorruptSubsequentQuoteState() async throws {
        // 999 行の平文行の直後に、1 行内で開いて閉じる 600 バイトの正規クォート
        // フィールド(強制的な不均衡判定を経由するが本物の閉じクォートで終わる)を置き、
        // 直後(500 バイト未満の間隔)に本物の複数行クォートフィールドを続ける。
        // クォート状態が破壊されていれば、複数行フィールドの開きクォートが閉じクォート
        // として誤認識され、内部の改行が 1000 行目の境界と重なってチャンクが
        // フィールドの途中(quoted と field の間)で分断される。
        let paddingLines = (0 ..< 999).map { "cell\($0)\n" }.joined()
        let longField = "\"" + String(repeating: "x", count: 600) + "\"\n"
        let multilineField = "\"quoted\nfield\"\n"
        let text = paddingLines + longField + multilineField + "after\n"
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache, respectsCSVQuotes: true)
        let chunks = await readAll(reader)
        #expect(chunks.joined() == text)
        #expect(chunks.contains { $0.contains("\"quoted\nfield\"") })
    }

    @Test("クォートフィールド内のマルチバイト文字が maxChunkBytes 境界をまたいでも二重カウントされない")
    func multibyteCharacterAtChunkBoundaryInsideQuotedFieldIsNotDoubleCounted() async throws {
        // "あ"(3 バイト)の 2 バイト目がちょうど maxChunkBytes 境界に来るよう前置バイト数を
        // 調整する。境界を snappedToCharacterBoundary で巻き戻す際に quotedRunLength も
        // 同時に巻き戻さないと "あ" の先頭 2 バイトが次チャンクで再走査されて二重カウント
        // される。フィールドの実際の長さはちょうど 500 バイト
        // (495 の "a" + 3 バイトの "あ" + 改行 + "z") で不均衡判定されるべきではないが、
        // 二重カウントされると 501 バイト相当に見えてしまい、本来閉じクォートまで
        // カウントされないはずの内部改行が 1 行早く linesConsumed に数えられてしまう。
        // その 1 行のずれは以降ずっと持ち越されるため、フィールドの後に十分な数の平文行を
        // 続けると、二重カウントの有無でチャンク境界が 1 行分ずれて現れる。
        let openingQuoteByteOffset = StringChunkReader.maxChunkBytes - 498
        let filler = String(repeating: "a", count: openingQuoteByteOffset)
        let field = "\"" + String(repeating: "a", count: 495) + "あ\nz\"\n"
        // 二重カウントされると内部改行が数えられ始めるのが 1 行早まるため、
        // 999 行を続けると誤って 1000 行目でチャンクが切られ、"pad998" が
        // 分断後のチャンクに含まれなくなる。正しい実装では 1000 行目に届かず
        // 同じチャンク内に収まる。
        let paddingLines = (0 ..< 999).map { "pad\($0)\n" }.joined()
        let text = filler + field + paddingLines
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache, respectsCSVQuotes: true)
        let chunks = await readAll(reader)
        #expect(chunks.joined() == text)
        #expect(chunks.allSatisfy { $0.utf8.count <= StringChunkReader.maxChunkBytes })
        #expect(chunks.contains { $0.contains("あ\nz\"") })
        #expect(chunks.contains { $0.contains("pad998\n") && $0.contains("あ\nz\"") })
    }

    @Test("改行なしテキストの長さがちょうど maxChunkBytes のとき境界外アクセスせずに読み切れる")
    func exactMaxChunkBytesNoTrailingNewlineDoesNotCrash() async throws {
        let text = String(repeating: "A", count: StringChunkReader.maxChunkBytes)
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let chunks = await readAll(reader)
        #expect(chunks.count == 1)
        #expect(chunks.joined() == text)
    }

    @Test("1MB超の単一行日本語テキストの強制分割がマルチバイト文字境界を尊重する")
    func forcedSplitRespectsMultibyteCharacterBoundary() async throws {
        let text = String(repeating: "あ", count: StringChunkReader.maxChunkBytes)
        let cache = try makeCache(text)
        let reader = StringChunkReader(cache: cache)
        let chunks = await readAll(reader)
        #expect(chunks.count >= 2)
        #expect(chunks.allSatisfy { $0.utf8.count <= StringChunkReader.maxChunkBytes })
        // 分割位置が文字境界からずれていれば、結合結果が元テキストと一致しない、
        // または不正な UTF-8 途中断片から構築された文字列が混入して文字数が変化する。
        #expect(chunks.joined() == text)
        // 各分割点が文字境界を尊重していれば、3 バイト文字「あ」のみの列である以上
        // 各チャンクのバイト数は常に 3 の倍数になる。
        #expect(chunks.allSatisfy { $0.utf8.count % 3 == 0 })
    }
}
