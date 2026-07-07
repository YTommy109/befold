---
name: semantic-search
description: Configure, build, and verify dagayn embeddings and hybrid semantic search without losing FTS fallback behavior.
argument-hint: "[query]"
---

# Semantic Search

Use this when searching befold's code (Swift under `BefoldApp/befold/`, plus
`Resources/` web assets) by symbol, keyword, or concept.

<!-- dagayn skill embedding context -->
## Installed Search Mode

**既定は FTS（全文検索）。** `.mcp.json` は素の `dagayn serve` で起動しており、
埋め込みは構築されていない（SessionStart 表示でも空）。

- Treat `semantic_search_nodes_tool` as keyword/FTS search, not vector semantic search.
- Prefer exact symbols (ViewerStore, ViewerBridge, FileWatcher, UpdateChecker,
  ReleaseFetcher), file names, graph relationships, and one targeted `rg` for literals.
- Do not rebuild embeddings unless the user explicitly asks. 埋め込み構築は任意の
  高度・高コスト操作であり、既定の FTS 経路には不要である。
<!-- /dagayn skill embedding context -->

## Workflow (default: FTS)

これらは露出済みの MCP ツールで、そのまま呼べる。

1. Find functions/types by name or keyword:
   `semantic_search_nodes_tool(query="file watcher debounce", detail_level="minimal")`
2. Trace relationships instead of grepping:
   `query_graph_tool(pattern="callers_of", target="ViewerStore", detail_level="minimal")`
   （`callees_of` / `imports_of` / `tests_for` も同様）
3. Read `search_mode` / per-result `source` on the results. 既定では
   `search_mode="fts_only"` になる。これは正確な識別子・記号探索には十分である。
4. If FTS misses a fuzzy concept, fall back to a single targeted `rg` for the
   literal string before considering embeddings.

## Optional: Embeddings (advanced, heavy — off by default)

埋め込みは既定では不要。ファジーな概念検索やクロス言語検索を本当に強化したい
場合のみ、任意の高度操作として構築する。理由を述べ、ユーザーの明示的な合意を
得てから実行すること。埋め込み関連ツールは MCP に露出していないため CLI で回す:

```bash
# 埋め込み構築（重い任意操作。汎用ランナー経由）
dagayn tool embed_graph_tool
```

構築後は同じ `semantic_search_nodes_tool` クエリを再実行し、結果件数と
`search_mode`（`hybrid` になるか）、高価値ヒットが `source="embedding"` /
`source="both"` になったかを比較する。フラグが不明なときは
`dagayn <subcommand> --help` に委ねる。

## Troubleshooting

- `fts_only` is acceptable for exact symbol/name lookup; do not build embeddings
  just to find a precise identifier such as `FileType` or `UpdateChannel`.
- FTS-only keeps startup time and memory low; that is the intended default here.
- If graph queries miss a file, it may not be in the graph yet — see the
  `build-graph` skill (`dagayn update`) before assuming a search problem.

## Efficiency Rules

- Default to FTS results for exact names; only reach for the optional embeddings
  when fuzzy concepts or cross-language (Swift ↔ Resources JS/HTML) recall truly
  fails with FTS.
- If you do build embeddings, do one before/after query to prove search quality
  changed. Do not rebuild repeatedly without a changed file set or a failed
  verification.
- Never build embeddings to compensate for files not appearing in graph queries.
  Expose the files first, then run the smallest non-embedding graph refresh
  (`dagayn update`) that proves the claim.
