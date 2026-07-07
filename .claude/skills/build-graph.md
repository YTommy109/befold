---
name: build-graph
description: Build or update the code review knowledge graph. Run this first to initialize, or let hooks keep it updated automatically.
argument-hint: "[full]"
---

# Build Graph

Build or incrementally update the persistent code knowledge graph for this
befold repository (a single macOS Swift 6 / AppKit + SwiftUI app under
`BefoldApp/befold/`).

> **通常は不要。** このリポジトリではグラフは編集/コミット時の hook で自動更新
> される。手動の `dagayn build` / `dagayn update` が要るのは、大規模なリファクタ
> やブランチ切り替えでグラフが不整合になったとき、または新規ファイルがグラフ
> クエリに現れないときだけである。

<!-- dagayn skill embedding context -->
## Installed Search Mode

素の `dagayn serve`（`.mcp.json`）で起動しており、既定は FTS（全文検索）。
SessionStart 表示でも埋め込みは空になる。

- Treat `semantic_search_nodes_tool` as keyword/FTS search, not vector semantic search.
- Prefer exact symbols (ViewerStore, FileWatcher, UpdateChecker), file names,
  graph relationships, and one targeted `rg` for literals.
- Do not rebuild embeddings unless the user explicitly asks. 埋め込み構築は任意の
  高度・高コスト操作である（後述の CLI Fallback を参照）。
<!-- /dagayn skill embedding context -->

## Steps

1. **Check graph status** with the CLI (the stats tool is not exposed over MCP):
   ```bash
   dagayn status
   ```
   - If the graph has never been built, proceed with a full build.
   - If the graph exists, proceed with an incremental update.

2. **Build the graph** via the CLI (the build/update tool is not exposed over MCP):
   - For first-time graph setup (full rebuild): `dagayn build`
   - For routine incremental updates: `dagayn update`
   - Do not run embedding-enabled rebuilds as a routine verification step.
     Embeddings are optional and expensive; only build them when the task
     explicitly requires embedding quality or hybrid-search freshness, and state
     that reason first. See the `semantic-search` skill for the embedding path.

3. **Verify** by running `dagayn status` again and report the results:
   - Number of files parsed
   - Number of nodes and edges created
   - Languages detected (expect Swift, plus HTML/CSS/JS in `Resources/`)
   - Any errors encountered

## When to Use

- First time setting up the graph for a repository
- After major refactoring or branch switches
- If the graph seems stale or out of sync (e.g. new files under `App/`,
  `Viewer/`, `FileWatching/`, `Updates/` missing from graph queries)
- The graph auto-updates via hooks on edit/commit, so manual builds are rarely needed

## Notes

- The graph is stored as a SQLite database (`.dagayn/graph.db`) in the repo root
- Binary files, generated files, and patterns in `.dagaynignore` are skipped
- Supported languages evolve with the parser registry; run
  `dagayn build --help` / `dagayn status` rather than relying on this skill as
  the authoritative language list.

## CLI Fallback

The stats/build/update tools are not exposed by the default `dagayn serve`
profile, so drive them through the CLI without restarting the agent:

```bash
dagayn status                 # graph freshness / node & edge counts
dagayn build                  # full rebuild
dagayn update                 # incremental (differential) update
dagayn detect-changes         # change-impact for the current diff
```

For any other MCP tool not exposed by the current profile, use the generic
runner:

```bash
dagayn tool <tool_name> [args]
```

When a flag is unknown, defer to `dagayn <subcommand> --help` rather than
guessing.

## Efficiency Rules

- Use incremental `dagayn update` unless the graph is empty, branch state
  changed heavily, or new files are missing from graph queries.
- For parser, flow, documentation-edge, or review verification, avoid embedding
  rebuilds so a graph check does not turn into an expensive embedding pass.
- Report node, edge, file, language, and error counts (from `dagayn status`)
  instead of reading the graph database or generated artifacts directly.
