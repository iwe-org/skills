# Write And Refactor

Use this reference for graph-aware write operations. Prefer these commands over manual markdown edits when the task changes note structure or references.

Official docs:

- `iwe new`: https://iwe.md/docs/cli/new/
- Extract actions: https://iwe.md/docs/code-actions/extract/
- Inline notes: https://iwe.md/docs/code-actions/inline/
- Files renaming: https://iwe.md/docs/features/renaming/
- Agentic tools: https://iwe.md/docs/agentic/

## `iwe new`

Create a document through project templates.

```bash
iwe new <TITLE> [OPTIONS]
```

Useful examples:

```bash
iwe new "My New Note"
iwe new "Meeting Notes" --content "Discussed project timeline"
iwe new "Daily Journal" --template journal
```

Prefer `iwe new` over creating files by hand. The command prints the created absolute path, and `--template` only works when that template exists in `.iwe/config.toml`.

## `iwe extract`

Use `extract` when a section should become its own note.

`extract` creates a new note from a section and replaces the section with an inclusion link.

Official CLI examples:

```bash
iwe extract my-document --list
iwe extract my-document --section "Architecture"
iwe extract my-document --block 2
iwe extract my-document --section "Design" --dry-run
```

Use `--list` when the target is unclear, `--section` when the title is known, `--block` when titles are ambiguous, and `--dry-run` before structural edits.

## `iwe inline`

Use `inline` as the reverse of extract when linked content should be embedded back into the parent context.

`inline` is the reverse of `extract`: it embeds linked content back into the parent context.

Official CLI examples:

```bash
iwe inline my-document --list
iwe inline my-document --reference "architecture"
iwe inline my-document --block 1
iwe inline my-document --reference "notes" --as-quote
iwe inline my-document --block 2 --keep-target
iwe inline my-document --reference "design" --dry-run
```

Use `--list` when the target is unclear, `--reference` when the note is known, `--block` when references repeat, `--keep-target` when this should stay an embed instead of a merge, `--as-quote` when markdown structure matters, and `--dry-run` before structural edits.

## `iwe rename`

Use `rename` when a note key or file path should change without breaking references.

`rename` changes a note key or path and updates references to keep the graph consistent.

Official CLI examples:

```bash
iwe rename old-topic new-topic
iwe rename old-topic new-topic --dry-run
iwe rename old-topic new-topic --quiet
iwe rename old-topic new-topic --keys
```

Use `--dry-run` before a rename that may touch many references. Use `--keys` when another step should inspect affected documents.

## `iwe delete`

Use `delete` when a document should be removed and the graph should be cleaned up.

`delete` removes the note, removes inclusion links to it, and converts inline links to plain text.

Useful examples:

```bash
iwe delete document-key
iwe delete document-key --force
iwe delete document-key --dry-run
iwe delete document-key --keys
```

Treat `delete` as high-impact. Use `--dry-run` before deletion unless the user explicitly wants immediate execution. `--force` removes the confirmation boundary.

## Command selection guide

- Create a note: `iwe new`
- Split a section out structurally: `iwe extract`
- Merge linked content back into context: `iwe inline`
- Change a note key or path: `iwe rename`
- Remove a note safely: `iwe delete`

If the user asks for a structural change and the CLI supports it, use the CLI instead of editing markdown references by hand. If exact arguments still matter, run `iwe <command> --help`. After a write operation, inspect affected files or rerun `find` or `retrieve` to confirm the graph state.
