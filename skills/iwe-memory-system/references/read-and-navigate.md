# Read And Navigate

Use this reference for read workflows: discovery, hierarchy inspection, targeted retrieval, and context building.

Official docs:

- Agentic tools: https://iwe.md/docs/agentic/
- CLI reference: https://iwe.md/docs/cli/
- CLI workflows: https://iwe.md/docs/cli/workflows/
- `iwe squash`: https://iwe.md/docs/cli/squash/

## `iwe find`

Use `find` for discovery. The official docs describe it as the entry-point for fuzzy search, and the current CLI also sorts results by popularity when you omit the query.

```bash
iwe find
```

Use it to discover entry points, narrow to roots, inspect note relationships, or produce keys/JSON for the next step.

Current formats:

- `-f markdown`: human-readable titles with `#key` suffix and optional parent context
- `-f keys`: one key per line for piping
- `-f json`: structured results with metadata such as `incoming_refs` and `parent_documents`

Useful examples:

```bash
iwe find "authentication" --roots -f keys
iwe find --roots -f json
iwe find --refs-to authentication
iwe find --refs-from index
iwe find "$QUERY" --limit 5 -f keys
```

Workflow:

1. Start with `iwe find "topic"`.
2. If results are broad, add `--roots` or `--limit`.
3. Use `--refs-to` or `--refs-from` when you already know one anchor key and want relationship-based discovery.
4. Pass the chosen key into `retrieve`.

## `iwe tree`

Use `tree` for hierarchy inspection.

```bash
iwe tree
```

Useful examples:

```bash
iwe tree
iwe tree --depth 5
iwe tree -k project-overview
iwe tree -f json
```

Current behavior worth knowing:

- Default depth is `4`
- Without `-k`, `tree` starts from root documents
- With `-k`, `tree` starts from the specified key even if the note is not a root
- Formats are `markdown`, `keys`, and `json`
- In `-f keys`, nested children are indented with tabs rather than flattened into an unstructured list

Use `tree` for orientation, not full content retrieval. Increase depth only when you need a broader structural view.

## `iwe retrieve`

Use `retrieve` for context building.

```bash
iwe retrieve -k <KEY> -d <DEPTH> -c <CONTEXT>
```

Parameters worth knowing:

- `-k` can be repeated to retrieve multiple anchor documents in one call.
- `-d` controls child expansion.
- `-c` controls parent context.
- `-e` avoids reloading known content.
- `-l` and `-b` are worth adding only when inline refs or incoming refs matter.
- `--dry-run` is useful before broad retrievals.
- `--no-content` keeps metadata while skipping document bodies.
- `--dry-run` currently prints document and line counts, not a per-document preview.

Practical defaults:

- Focused read: `iwe retrieve -k topic -d 1 -c 1`
- Minimal read: `iwe retrieve -k topic -d 0 -c 0`
- Broader context: `iwe retrieve -k topic -d 2 -c 2`
- Programmatic chaining: `iwe retrieve -k topic -f keys`
- Metadata-only pass: `iwe retrieve -k topic --no-content -f json`

Use `--dry-run` before deeper retrievals and increase depth gradually.

Typical workflow from the official docs:

```bash
iwe find "authentication" --roots -f keys
iwe retrieve -k authentication -d 2 -c 1
iwe retrieve -k login-flow -e authentication
```

That is the core loop: discover an entry point, retrieve enough context, then follow adjacent notes with `-e` to avoid duplication.

## `iwe stats`

Use `stats` when the task is analytical rather than navigational.

```bash
iwe stats
```

Useful examples:

```bash
iwe stats
iwe stats --format csv > stats.csv
iwe stats -f csv | tail -n +2 | sort -t, -k12 -nr | head -5
```

Use `stats` before proposing large reorganizations. Prefer `csv` only when another script should consume the output.

Current formats:

- `-f markdown`: overview plus reference, size, structure, and network sections
- `-f csv`: per-document rows with graph and content metrics

## `iwe squash`

Use `squash` when you want one combined markdown artifact.

```bash
iwe squash <KEY> [OPTIONS]
```

Useful examples:

```bash
iwe squash project-overview
iwe squash project-overview --depth 4
```

Current behavior worth knowing:

- Default depth is `2`
- `squash` writes combined markdown to stdout
- When linked content is inlined, headers are shifted down to preserve hierarchy

Use `squash` when you want one linear artifact for review, export, or LLM context. `squash` gives merged structure; `retrieve` gives navigable graph context.

## `iwe export`

Use `export` when you need a graph artifact for visualization or downstream tooling.

```bash
iwe export dot
```

Useful examples:

```bash
iwe export dot
iwe export dot --key project-overview --depth 1
iwe export dot --key project-overview --depth 1 --include-headers
```

Current behavior worth knowing:

- The only supported export format is currently `dot`
- Without `--key`, export starts from root notes
- `--include-headers` adds document structure detail to the graph output
- `export` writes the DOT graph to stdout and does not mutate notes
