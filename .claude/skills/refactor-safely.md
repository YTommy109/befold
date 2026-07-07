---
name: Refactor Safely
description: Plan and execute safe refactoring using dependency analysis
---

## Refactor Safely

Use the knowledge graph to plan and execute refactoring with confidence.

### Steps

1. Run `get_minimal_context_tool(task="<refactor goal>")` to check graph freshness,
   risk, and suggested next tools.
2. Use `refactor_tool` with mode="suggest" for evidence-ranked remove, move,
   split, and document candidates.
3. Use `refactor_tool` with mode="dead_code" only when the suggested remove
   candidates need a deeper dead-code drill-down.
4. For renames, use `refactor_tool` with mode="rename" to preview all affected
   locations (e.g. renaming `ViewerStore` or `FileWatcher`).
5. To apply a previewed refactor, use the CLI runner (the apply tool is not
   exposed over MCP): `dagayn tool apply_refactor_tool --arg dry_run=true`
   first, then re-run with the refactor_id once the diff is acceptable.
6. Before renaming, moving, or deleting public code, follow documentation bridge
   edges when present: `query_graph_tool(pattern="docs_for", target="<path::symbol>", detail_level="minimal")`
   for specs/runbooks/issue notes attached to code, and
   `query_graph_tool(pattern="implementations_of", target="<doc.md>::<section-slug>", detail_level="minimal")`
   when the refactor starts from a Markdown contract section.
7. After changes, run `review_tool(mode="changes")` and inspect `analysis_summary` to verify
   impact, recommended tests, affected flows, and architecture risks.

### Safety Checks

- Always preview before applying (rename mode gives you an edit list).
- Use `review_tool(mode="changes").analysis_summary` first; call
  `review_tool(mode="impact")` or `review_tool(mode="affected_flows")` only
  when a wider drill-down is needed.
- To identify decomposition targets, run the CLI runner (this tool is not
  exposed over MCP): `dagayn tool find_large_functions_tool`.
- Preserve authored `dagayn:` documentation directives. Update Markdown
  `implemented-by path::symbol` targets after code renames, and update code
  `implements docs/spec.md#Section` targets after doc heading/path changes.
  Do not add duplicate inverse directives unless there are two distinct claims.
- Treat suggestions as leads, not approval. Verify public APIs, dynamic
  dispatch, generated code, test artifacts, and framework entry points before
  removing or moving code.
- Prefer suggestions with explicit counts, thresholds, callers, communities, and
  reason codes; narrow truncated output with `top_n` or follow-up graph queries.

### Function Concern Separation Profiles

When a split suggestion contains `evidence.concern_separation`, treat it as a
role-aware refactoring profile, not a verdict that the function is bad.

- Read `role` first. Boundary functions, CLI handlers, adapters, coordinators,
  and test helpers may legitimately combine IO and orchestration.
- Read `score` against `split_score_threshold`. A score over the threshold means
  concern pressure can justify reviewing a large function for extraction; it
  does not prove that extraction is safe or required.
- Use `reason_codes` to identify the suspected pressure: callee community spread,
  callee scope spread, branch pressure, side-effect pressure, implicit context,
  or low context clarity.
- Use `evidence.purity_likelihood` only as side-effect evidence. It is not a
  proof of functional purity.
- Check `missingness` before acting. Low source, call, community, or unresolved
  call evidence lowers confidence and should trigger a source read or graph
  follow-up before recommending an edit.
- Use `action` as the first investigation step. Prefer extracting one cohesive
  decision, transformation, or context object before moving IO or changing public
  signatures.
- Do not turn this profile into a standalone review finding. Cite exact source
  behavior or a failing test when claiming a bug; cite the profile only as
  refactoring prioritization evidence.

## CLI Fallback

Prefer the exposed MCP tools for planning: `refactor_tool(mode="suggest")` and
`refactor_tool(mode="rename")` are the main path. Some refactor tools
(`apply_refactor_tool`, `find_large_functions_tool`) are **not** exposed by the
default `dagayn serve` profile, so run those through the CLI runner without
restarting the agent:

```bash
# planning (also available directly as MCP refactor_tool)
dagayn tool refactor_tool --arg mode='"suggest"' --arg limit=10
dagayn tool refactor_tool --arg mode='"rename"' --arg old_name='"ViewerStore"' --arg new_name='"ViewerModel"'

# apply / large-function scan (not exposed over MCP)
dagayn tool apply_refactor_tool --arg refactor_id='"refactor_123"' --arg dry_run=true
dagayn tool find_large_functions_tool

# documentation bridge edges
dagayn tool query_graph_tool --arg pattern='"docs_for"' --arg target='"BefoldApp/befold/Viewer/ViewerStore.swift::ViewerStore"'
dagayn tool query_graph_tool --arg pattern='"implementations_of"' --arg target='"docs/spec.md::contract-section"'
```

When a flag is unknown, defer to `dagayn <subcommand> --help` rather than
guessing.

## Token Efficiency Rules
- ALWAYS start with `get_minimal_context_tool(task="<your task>")` before any other graph tool.
- Use `detail_level="minimal"` on all calls. Only escalate to "standard" when minimal is insufficient.
- Target: complete any review/debug/refactor task in ≤5 tool calls and ≤800 total output tokens.
