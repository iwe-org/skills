---
name: iwe-memory-system
description: Use this skill when working in an IWE knowledge-graph workspace, especially to help an agent read, navigate, retrieve context from, and safely refactor Markdown notes with the `iwe` CLI instead of ad-hoc file edits. Covers project discovery, inclusion links, context-building, analysis, and structural operations such as `find`, `tree`, `retrieve`, `stats`, `squash`, `new`, `extract`, `inline`, `rename`, `delete`, `normalize`, and `export`.
metadata:
  version: 0.0.66
---

# IWE

Use this skill when the repository or workspace is an IWE project, or when the user wants work on an IWE knowledge base through the `iwe` CLI.

IWE is local-first and markdown-based. Prefer `iwe` commands for graph-aware reads and refactors, and only fall back to direct file edits when the CLI does not cover the task.

IWE does not impose a single graph structure or file naming convention. Do not assume a particular hierarchy, naming scheme, or note layout unless the workspace itself shows one.

Official docs:

- Docs index: https://iwe.md/docs/
- Agentic tools: https://iwe.md/docs/agentic/
- Inclusion links: https://iwe.md/docs/concepts/inclusion-links/
- CLI reference: https://iwe.md/docs/cli/

## Quick start

1. Confirm the workspace is an IWE project by checking for `.iwe/config.toml`.
2. Read `.iwe/config.toml` before assuming where notes live. `library.path` may point to a subdirectory.
3. Use `iwe find`, `iwe tree`, and `iwe retrieve` to explore before editing.
4. Use `iwe stats` for analysis and `iwe squash` when one linear markdown artifact is more useful than graph-shaped retrieval.
5. For structural note changes, prefer `iwe new`, `iwe extract`, `iwe inline`, `iwe rename`, and `iwe delete`.
6. Use preview modes such as `--dry-run` when the command supports them, and run `iwe <command> --help` when exact flags matter.

## Inclusion links

IWE treats a markdown link on its own line as structure, not just a normal inline reference. That standalone link creates a parent-child relationship in the knowledge graph.

In practice, an inclusion link should be surrounded by blank lines. If adjacent inclusion links are written back-to-back with no empty line between them, IWE can treat them as inline content instead of structural links.

This distinction matters:

- A standalone link is an inclusion link and affects hierarchy, traversal, and `--depth`-based retrieval.
- A link inside a sentence is an inline link and only expresses a reference relationship.

Preserve that distinction. Keep inclusion links on their own lines with an empty line before and after each one. Do not append prose to an inclusion link line or rewrite it into inline text unless the user explicitly wants the hierarchy changed.

Example:

```md
# Photography

[Composition](composition)

[Lighting](lighting)

```

The two child links above are structural because each link is isolated by blank lines. They are not equivalent to writing a sentence like `See [Composition](composition) for more.`, and they should not be written back-to-back with no empty line between them.

## Reference map

- For project discovery and config assumptions, read [./references/project-setup.md](./references/project-setup.md).
- For read and navigation flows, read [./references/read-and-navigate.md](./references/read-and-navigate.md).
- For write and refactor flows, read [./references/write-and-refactor.md](./references/write-and-refactor.md).

## Guardrails

- Do not assume markdown files live at repository root; check `library.path`.
- Do not assume a particular graph structure or file naming convention.
- Do not hand-edit references if `iwe` already has a safe operation for that change.
- Do not place consecutive inclusion links with no blank line between them.
- Do not retrieve large context blindly; use preview modes such as `--dry-run` when available.
- Do not use `iwe delete` without explicit user intent.
- If the task is a structural change and the CLI supports it, use the CLI instead of editing markdown references by hand.
- If exact command arguments matter, run `iwe <command> --help` before execution instead of guessing flags.
- Treat `iwe normalize` as an in-place bulk rewrite of the whole library, not a harmless read command.
- Treat `iwe export` and `iwe squash` as artifact-generation commands that do not mutate notes unless you redirect their output into files yourself.
- After a write operation, inspect affected files or rerun `find` or `retrieve` if you need to confirm the graph state.
