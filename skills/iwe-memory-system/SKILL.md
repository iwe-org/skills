---
name: iwe-memory-system
description: Use this skill when working in an IWE knowledge-graph workspace, especially to help an agent read, navigate, retrieve context from, and safely refactor Markdown notes with the `iwe` CLI instead of ad-hoc file edits. Covers project discovery, inclusion links, context-building, and structural operations such as `find`, `tree`, `retrieve`, `new`, `extract`, `inline`, `rename`, and `delete`.
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
4. For structural note changes, prefer `iwe new`, `iwe extract`, `iwe inline`, `iwe rename`, and `iwe delete`.
5. Use preview modes such as `--dry-run` when the command supports them.

## Inclusion links

IWE treats a markdown link on its own line as structure, not just a normal inline reference. That standalone link creates a parent-child relationship in the knowledge graph.

This distinction matters:

- A standalone link is an inclusion link and affects hierarchy, traversal, and `--depth`-based retrieval.
- A link inside a sentence is an inline link and only expresses a reference relationship.

Preserve that distinction. Do not append prose to an inclusion link line or rewrite it into inline text unless the user explicitly wants the hierarchy changed.

Example:

```md
# Photography

[Composition](composition)
[Lighting](lighting)
```

The two child links above are structural. They are not equivalent to writing a sentence like `See [Composition](composition) for more.`.

## Reference map

- For project discovery and config assumptions, read [./references/project-setup.md](./references/project-setup.md).
- For read and navigation flows, read [./references/read-and-navigate.md](./references/read-and-navigate.md).
- For write and refactor flows, read [./references/write-and-refactor.md](./references/write-and-refactor.md).

## Guardrails

- Do not assume markdown files live at repository root; check `library.path`.
- Do not assume a particular graph structure or file naming convention.
- Do not hand-edit references if `iwe` already has a safe operation for that change.
- Do not retrieve large context blindly; use preview modes such as `--dry-run` when available.
- Do not use `iwe delete` without explicit user intent.
- If the task is a structural change and the CLI supports it, use the CLI instead of editing markdown references by hand.
- If exact command arguments matter, run `iwe <command> --help` before execution instead of guessing flags.
- After a write operation, inspect affected files or rerun `find` or `retrieve` if you need to confirm the graph state.
