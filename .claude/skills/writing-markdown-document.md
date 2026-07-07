---
name: writing-markdown-document
description: Author Markdown documents (READMEs, design docs, RFCs) so dagayn extracts correct dependency edges. Four-stage flow — outline & sort, draft & verify, polish, summary.
argument-hint: "[doc path]"
---

# Writing a Markdown Document

Write Markdown that dagayn can index correctly so the document becomes a first-class node in the knowledge graph, with dependency edges to other docs and to code.

<!-- dagayn skill embedding context -->
## Installed Search Mode

Installed in FTS-only mode (`--mode fts`).

- Treat `semantic_search_nodes_tool` as keyword/FTS search, not vector semantic search.
- Prefer exact symbols, file names, graph relationships, and one targeted `rg` for literals.
- Do not rebuild embeddings unless the user explicitly changes install mode.
<!-- /dagayn skill embedding context -->

## Stage 0 — Prerequisites

Run **once** at the start, regardless of what the rest of the flow says:

1. `get_minimal_context_tool(task="write <doc path>")` — check graph freshness. If it reports the graph is missing or empty, rebuild via the CLI (`dagayn tool build_or_update_graph_tool --arg full_rebuild=true --arg local_embedding='"none"'`) and stop until that returns.
2. Resolve the doc path:
   - If `[doc path]` was provided and the file exists → that's your target.
   - If it was provided but the file is new → continue (Stage 1 will create it).
   - If no arg → ask the user for the doc's purpose, audience, and intended path before going further. Do not invent a path.

## dagayn Markdown reference

dagayn's Markdown parser extracts edges from these constructs. Use them deliberately:

| Construct | Syntax | Edges produced |
|-----------|--------|----------------|
| **Heading** | `## Section Title` | `CONTAINS` (file → section, section → subsection) |
| **Dependency directive** (HTML comment, case-insensitive) | `<!-- constrained-by ./other.md#Section -->` | `DEPENDS_ON` always; **plus** `IMPORTS_FROM` when the target is a different file |
| **Documentation directive** (`dagayn:` HTML comment) | `<!-- dagayn: implemented-by BefoldApp/befold/Viewer/ViewerStore.swift::ViewerStore.updateContent -->` | `CROSS_ARTIFACT` from the enclosing Markdown section to a code/doc/artifact target |
| **Inline link, no anchor** | `[text](./other.md)` | `IMPORTS_FROM` only |
| **Inline link, with anchor** | `[text](./other.md#Section)` | `IMPORTS_FROM` (file→file) **and** `REFERENCES` (section→section) |
| **Reference-style link** | `[label]: ./other.md#Section` | Same as inline links — same regex path |
| **Code span** | `` `BridgeDetector` `` | `CROSS_ARTIFACT` (resolved to a code symbol during postprocessing) |

Directive kinds: `constrained-by`, `blocked-by`, `supersedes`, `derived-from`. All four emit identical edge kinds — the kind is preserved as metadata.

Directive / link target shapes:
- `#Section` — local section in the same doc (slug after `#` is itself slugified, so `#My Section` and `#my-section` are equivalent)
- `./relative/path.md` — whole-file dependency
- `./relative/path.md#Section` — specific section in another doc

**Slug rules**:
- Alphanumerics are lowercased.
- Spaces and hyphens both become `-`.
- Underscores are **preserved** (not converted to `-`).
- All other characters (punctuation, em-dashes, unicode symbols) are **stripped**.
- Duplicate headings get `-1`, `-2`, … suffixes appended in document order.

Worked examples:
- `## API Reference` → `api-reference`
- `## user_id lookup` → `user_id-lookup`
- `## What's new?` → `whats-new`
- `## Stage 1 — Outline` → `stage-1--outline` (em-dash stripped, two surrounding spaces both become `-`)

**Code-span identifier rules**:
- Regex: `^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*$` — dots only allowed *between* identifier segments (so `module.Class` is fine, `..foo` or `foo.` are not).
- Identifiers shorter than 3 chars are skipped.
- Identifiers without `_` or `.` need ≥ 10 chars (filters generic English words like `list` / `parser`).

**Postprocessing**: each unresolved Markdown-sourced `CROSS_ARTIFACT` edge is resolved against the code graph by symbol name. **One non-Markdown match → target is promoted to that node's qualified name with HIGH/0.8 confidence. Zero or 2+ matches → target stays or returns to `<unresolved:Symbol>` with LOW/0.2 confidence.** The edge is kept so a future graph update can resolve it; the `markdown_artifact_refs_dropped` counter means "demoted", not deleted. Use distinctive, ideally qualified, symbol names.

## Markdown ↔ code documentation links

Use `dagayn:` documentation directives for intentional documentation/code obligations. Use ordinary backticked code spans only for low-intent prose mentions that may resolve to `describes_symbol`.

Direction rule: the source should be the artifact that owns the assertion.

| Authoring site | Preferred syntax | Stored role | Use when |
|----------------|------------------|-------------|----------|
| Markdown contract/spec section | `<!-- dagayn: implemented-by BefoldApp/befold/Viewer/ViewerStore.swift::ViewerStore.updateContent -->` | `implemented_by` | The doc section defines intent and code realizes it. |
| Markdown explanation/problem section | `<!-- dagayn: discusses-artifact BefoldApp/befold/FileWatching/FileWatcher.swift::FileWatcher -->` or `<!-- dagayn: raises-issue-for BefoldApp/befold/FileWatching/FileWatcher.swift::FileWatcher -->` | `discusses_artifact`, `raises_issue_for` | The doc owns the discussion, audit note, or issue statement about code. |
| Code line comment | `// dagayn: implements docs/dev/coding_rule.md#Render Pipeline` | `implements_contract` | The implementation is the stable place to declare conformance to a doc section. |
| Code line comment | `// dagayn: explained-by docs/dev/coding_rule.md#File Watching` | `explained_by` | The implementation points to rationale, behavior notes, or background. |
| Code line comment | `// dagayn: has-runbook docs/dev/coding_rule.md#Release Flow` | `has_runbook` | The implementation points to an operational runbook. |
| Code line comment | `// dagayn: problem-described-by docs/superpowers/specs/2026-07-07-dev-release-versioning-design.md#Known Issues` | `problem_described_by` | The implementation points to an audit, incident, or known issue. |

Supported directive kinds are `implemented-by`, `implements`, `explained-by`, `has-runbook`, `problem-described-by`, `discussed-by`, `discusses`, `discusses-artifact`, `raises-issue-for`, `describes`, and `describes-symbol`.

Target rules:
- Markdown → code point: prefer a concrete graph node target in `path::symbol` form, e.g. `BefoldApp/befold/Viewer/ViewerStore.swift::ViewerStore.updateContent`. Verify the exact node exists before writing the directive. A bare symbol target is allowed but starts LOW/0.2 as `<unresolved:Symbol>` until postprocessing finds exactly one non-Markdown node with that `name`.
- Code → Markdown section: always include a Markdown path plus `#Heading`, e.g. `docs/dev/coding_rule.md#Render Pipeline` or `../docs/dev/coding_rule.md#Render Pipeline`. The parser slugifies the heading and stores the target as `docs/dev/coding_rule.md::render-pipeline`.
- In `dagayn:` directives, `./` and `../` paths are resolved relative to the source file; other file paths are treated as repo-root-relative and normalized.
- `#Local Heading` is valid for Markdown-authored same-document targets. Do not use a bare `#Heading` in code comments; from code it would target the code file, not a Markdown document.
- Code-authored line comments are extracted from source-file comments in the languages your dagayn install supports; confirm the edge landed (rebuild, then `docs_for` / `implementations_of`) rather than assuming a given language is parsed. Put the directive inside the implementation node or directly above the following declaration (type / function / property); the parser attaches it to the nearest enclosing node or a following node within 3 lines.

Verification rules:
- Starting from a Markdown contract section, run `query_graph_tool(pattern="implementations_of", target="<doc.md>::<section-slug>", detail_level="minimal")` and check both doc-authored `implemented_by` and code-authored `implements_contract` edges. Treat those as `authored` contract evidence.
- Starting from a code point, run `query_graph_tool(pattern="docs_for", target="<path::symbol>", detail_level="minimal")` to find specs, explanations, runbooks, and issue notes linked by documentation roles. Check each result's `evidence_type`: explanatory roles are usually `extracted`, and unresolved/low-confidence links are `heuristic_reachable`.
- If a verification query returns zero results or `status="not_found"`, keep its `zero_result_reason`, `next_action`, and `missingness` in the draft notes instead of assuming the target or relationship cannot exist.
- Do not author both directions for the same fact unless there are genuinely two separate assertions. Query tools expose inverse labels; duplicate inverse edges become stale during incremental updates.

## Stage 1 — Outline & sort sections

1. Draft a section list (one line per section, in any order).
2. For each prospective section, list its dependencies:
   - **Existing docs you intend to depend on** — for each candidate doc that is *already in the repo*, run `query_graph_tool(pattern="file_summary", target="<doc.md>", detail_level="minimal")` to confirm the section slug you plan to cite actually exists.
   - **Code symbols you plan to backtick** — run `semantic_search_nodes_tool(query="<symbol>", detail_level="minimal")` and require **exactly one exact symbol match**. With hybrid search, ignore fuzzy/semantic hits whose `name` or `qualified_name` does not exactly match the symbol you will write. If zero exact matches remain, the symbol will stay unresolved (don't rely on it as an obligation). If multiple exact matches remain, qualify the prose mention if possible, or switch to an explicit `dagayn:` directive with a concrete `path::symbol` target.
   - **Code points you plan to target from `dagayn:` directives** — run `query_graph_tool(pattern="file_summary", target="<path>", detail_level="minimal")` or `semantic_search_nodes_tool(query="<symbol>", detail_level="minimal")` and verify the exact `path::symbol` target exists.
3. Topologically sort sections so each appears **after** every section it depends on. If a cycle remains after splitting offending sections in two, **stop and ask the user** which dependency to break — do not silently emit a forward reference.

Stage 1 done when: every prospective dependency is verified (or explicitly noted as "external — not in graph"), and the section list is acyclic.

Tool-call budget for Stage 1: ≤ 1 call per existing dependency + 1 per code symbol. Bound it by counting deps before you start.

## Stage 2 — Draft each section & verify edges

For each section, in dependency order:

1. **Draft the prose.**
2. **Express dependencies explicitly:**
   - Hard prerequisites → `<!-- constrained-by ./prereq.md#Section -->` near the top of the section.
   - Material this section is derived from → `<!-- derived-from … -->`.
   - Inline narrative references → `[text](./other.md#Section)`.
   - Intentional Markdown → code obligations → `<!-- dagayn: implemented-by path::symbol -->`, `<!-- dagayn: discusses-artifact path::symbol -->`, or `<!-- dagayn: raises-issue-for path::symbol -->`.
   - Low-intent code mentions → backtick the symbol exactly as it appears in code.
3. **Save the file** and rebuild the graph for Markdown/parser/postprocess
   verification via the CLI: `dagayn tool build_or_update_graph_tool --arg local_embedding='"none"'`.
   In local embedding installs, an omitted `local_embedding` argument may inherit
   the server preset and turn a documentation-edge check into a large embedding refresh.
4. **Verify the edges resolved:**
   - `query_graph_tool(pattern="importers_of", target="<doc.md>", detail_level="minimal")` — file-level inbound edges. **Use the file path only — `importers_of` resolves the target to a file path; `<doc.md>::<section>` will silently return zero hits.**
   - `review_tool(mode="impact", changed_files=["<doc.md>"], detail_level="minimal")` — outbound blast radius for the whole file.
   - For explicit Markdown → code directives, `query_graph_tool(pattern="implementations_of", target="<doc.md>::<section-slug>", detail_level="minimal")` — confirms linked implementation/artifact targets.
5. **If a directive looks like it didn't take effect**, re-read your slug against the rules in the reference table above (most common bug: punctuation in heading not accounted for, or section slug typo). Fix and re-run step 3 + 4.

Tool-call budget for Stage 2: ≤ 3 calls per section in the happy path (build + importers_of + impact), plus ≤ 1 `implementations_of` call when the section has explicit Markdown → code directives. Allow 1 extra retry per section for slug fixes.

Stage 2 done for the section when: dependency/link directives appear either as inbound edges on the cited section or as outbound entries in the file's impact radius, and explicit documentation directives appear in `implementations_of` / `docs_for` as appropriate.

## Stage 3 — Polish

1. Re-read the full draft top-to-bottom; tighten prose; merge or split sections if Stage 2 surfaced badly-balanced ones.
2. For every backticked `Symbol`, run `semantic_search_nodes_tool(query="<symbol>", detail_level="minimal")` and require exactly one exact symbol match. Ignore semantic near-matches when embeddings are enabled; only exact `name` / `qualified_name` matches count for Markdown code-span `CROSS_ARTIFACT` promotion. If multiple exact matches remain, qualify (`module.Symbol`); if still multiple after qualification, **accept that this edge will remain LOW/0.2 and unresolved** and either (a) leave the backticks for prose readability and add a `<!-- TODO: ambiguous symbol — qualify when API stabilizes -->` comment, or (b) remove the backticks and use plain text.
3. Rebuild once more via the CLI (`dagayn tool build_or_update_graph_tool --arg local_embedding='"none"'`), then `review_tool(mode="impact")` again. Compare its output to Stage 2's. **Done criterion: no edge that was present in Stage 2 has disappeared.**

Tool-call budget for Stage 3: ≤ 1 call per backticked symbol + 2 final builds.

## Stage 4 — Summary / Conclusion

Add the wrap-up sections **last**, once the rest of the body is stable:

- **Summary** — recap each major section with `<!-- derived-from #stage-N-title -->` so the graph shows the summary depends on the sections it summarizes (use the actual slugs, not the human title).
- **Conclusion** — if this document supersedes or extends another, declare it: `<!-- supersedes ./old-design.md -->`. List external follow-ups with explicit links.

Final check: `query_graph_tool(pattern="file_summary", target="<doc.md>")` should list every section. Done.

## CLI Fallback

Use MCP tools first. If the current MCP server profile does not expose a graph
tool needed for Markdown authoring or verification, run the same implementation
through the CLI without restarting the agent:

```bash
dagayn tool build_or_update_graph_tool --arg local_embedding='"none"'
dagayn tool query_graph_tool --arg pattern='"file_summary"' --arg target='"docs/design.md"'
dagayn tool query_graph_tool --arg pattern='"implementations_of"' --arg target='"docs/design.md::contract-section"'
dagayn tool query_graph_tool --arg pattern='"docs_for"' --arg target='"BefoldApp/befold/Viewer/ViewerStore.swift::ViewerStore.updateContent"'
dagayn tool review_tool --arg mode='"impact"' --arg 'changed_files=["docs/design.md"]' --arg detail_level='"minimal"'
dagayn tool semantic_search_nodes_tool --arg query='"ViewerStore"' --arg detail_level='"minimal"'
```

## Token Efficiency Rules (graph exploration only)

These bound the *graph-tool* spend; they don't apply to drafting prose or to the per-section verification loops which have their own budgets above.

- Before any *exploratory* graph call (i.e., not one of the per-stage targeted calls listed above), run `get_minimal_context_tool(task="<your task>")`.
- Use `detail_level="minimal"` on every call unless minimal omits something you specifically need.
- Hard ceiling for one full document end-to-end (Stages 0–4): ≤ 30 tool calls and ≤ 5,000 output tokens of graph-tool output across the session. If you're approaching it, stop and ask the user whether to continue.
