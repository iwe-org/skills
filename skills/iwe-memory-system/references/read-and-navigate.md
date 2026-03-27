# Read And Navigate

Use this reference for read workflows: discovery, hierarchy inspection, targeted retrieval, and context building.

Official docs:

- Agentic tools: https://iwe.md/docs/agentic/
- CLI reference: https://iwe.md/docs/cli/
- CLI workflows: https://iwe.md/docs/cli/workflows/
- `iwe squash`: https://iwe.md/docs/cli/squash/

## `iwe find`

Use `find` for discovery. The official docs describe it as the entry-point for fuzzy search.

```bash
iwe find
```

Use it to discover entry points, narrow to roots, inspect note relationships, or produce keys/JSON for the next step.

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
3. Pass the chosen key into `retrieve`.

## `iwe tree`

Use `tree` for hierarchy inspection.

```bash
iwe tree
```

Useful examples:

```bash
iwe tree
iwe tree --depth 5
```

Use `tree` for orientation, not full content retrieval. Increase depth only when you need a broader structural view.

## `iwe retrieve`

Use `retrieve` for context building.

```bash
iwe retrieve -k <KEY> -d <DEPTH> -c <CONTEXT>
```

Parameters worth knowing:

- `-d` controls child expansion.
- `-c` controls parent context.
- `-e` avoids reloading known content.
- `-l` and `-b` are worth adding only when inline refs or incoming refs matter.
- `--dry-run` is useful before broad retrievals.

Practical defaults:

- Focused read: `iwe retrieve -k topic -d 1 -c 1`
- Minimal read: `iwe retrieve -k topic -d 0 -c 0`
- Broader context: `iwe retrieve -k topic -d 2 -c 2`
- Programmatic chaining: `iwe retrieve -k topic -f keys`

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

Use `squash` when you want one linear artifact for review, export, or LLM context. `squash` gives merged structure; `retrieve` gives navigable graph context.
