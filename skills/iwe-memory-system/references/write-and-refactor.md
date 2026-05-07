# Write And Refactor

Use this reference for graph-aware write operations. Prefer these commands over manual markdown edits when the task changes note structure or references.

Official docs:

- `iwe new`: https://iwe.md/docs/cli/new/
- Extract actions: https://iwe.md/docs/code-actions/extract/
- Inline notes: https://iwe.md/docs/code-actions/inline/
- File renaming: https://iwe.md/docs/features/renaming/
- Agentic tools: https://iwe.md/docs/agentic/
- Query language: https://iwe.md/docs/concepts/query-language/

For `--filter` syntax used by `iwe update` and `iwe delete`, see [./query-language.md](./query-language.md).

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

Current behavior worth knowing:

- `--if-exists` supports `suffix`, `override`, and `skip`
- `--edit` opens the created file in `$EDITOR`
- `--content` can be replaced with piped stdin content
- Current template variables include `{{title}}`, `{{slug}}`, `{{content}}`, `{{id}}`, `{{now}}`, and `{{today}}`
- If `library.default_template` is set, plain `iwe new` uses that template automatically
- If `library.path` points to a subdirectory, created files are written there

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

Current behavior worth knowing:

- `--block` is 1-indexed
- `--list` shows block numbers for the current document structure, including the root block and extractable sections
- `--action <NAME>` uses an extract action from `.iwe/config.toml`
- `--keys` prints affected document keys
- `--quiet` suppresses progress output

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

Current behavior worth knowing:

- `--block` is 1-indexed
- `--reference` can match by key or by the displayed reference title
- `--action <NAME>` uses an inline action from `.iwe/config.toml`
- Without `--keep-target`, the target document is deleted and other references are cleaned up
- `--keys` prints affected document keys
- `--quiet` suppresses progress output

## `iwe rename`

Use `rename` when a document key should change without breaking references.

`rename` changes a document key and updates references to keep the graph consistent. Keys may include path segments, so this also covers path-like renames within the library.

Official CLI examples:

```bash
iwe rename old-topic new-topic
iwe rename old-topic new-topic --dry-run
iwe rename old-topic new-topic --quiet
iwe rename old-topic new-topic --keys
```

Use `--dry-run` before a rename that may touch many references. Use `--keys` when another step should inspect affected documents. `--quiet` suppresses progress output.

Current behavior worth knowing:

- `NEW_KEY` can include path segments such as `reference/api-contract`
- `--keys` prints the affected set, which can include the new key, updated referring documents, and the old key

## `iwe update`

Use `update` for two distinct write modes: rewriting the markdown body of one document, or mutating frontmatter on a set of documents selected by a filter.

### Body-overwrite mode

```bash
iwe update -k notes/draft -c "# Draft\n\nNew content."
cat new-content.md | iwe update -k notes/draft -c -
```

`-k KEY` and `-c CONTENT` together replace the markdown body of one document. Use `-` as content to read from stdin. This mode does not touch frontmatter.

### Frontmatter-mutation mode

```bash
iwe update -k notes/draft --set status=published --set priority=10
iwe update --filter 'status: draft' --set 'reviewed=true'
iwe update --filter 'status: archived' --unset draft_notes
iwe update --filter 'status: draft' --set status=published --dry-run
```

`--set FIELD=VALUE` parses the value as a YAML scalar:

- `--set 'priority=5'` writes integer `5`
- `--set 'reviewed=true'` writes boolean `true`
- `--set 'status=draft'` writes string `"draft"`
- `--set 'tags=[a, b]'` writes a list
- `--set 'count="5"'` writes string `"5"` (quoted)

Behavior worth knowing:

- Body and frontmatter modes cannot be combined; use two passes if both must change.
- `--filter '{}'` would target every document; do not run that without explicit user intent.
- Reserved-prefix fields (`_`, `$`, `.`, `#`, `@`) cannot be `$set` or `$unset`.
- Frontmatter is re-serialized as YAML 1.2 after mutation, so quote styles on untouched fields may change.
- Always run `--dry-run` before bulk mutations.

## `iwe delete`

Use `delete` when a document should be removed and the graph should be cleaned up.

`delete` removes the note, removes inclusion links to it, and converts inline links to plain text. Targets are selected by either a positional `KEY` (sugar for `--filter '$key: K'`) or a `--filter` expression. Both may be given; the union is deleted.

Useful examples:

```bash
iwe delete document-key
iwe delete document-key --force
iwe delete document-key --dry-run
iwe delete --filter 'status: archived'
iwe delete --filter '$and: [{ type: scratch }, { reviewed: false }]' --dry-run
iwe delete --filter 'status: archived' -f keys
```

Treat `delete` as high-impact. Use `--dry-run` before deletion unless the user explicitly wants immediate execution. `--force` removes the confirmation boundary on key-based deletes.

Current behavior worth knowing:

- Without `--force`, key-based `delete` prompts for confirmation
- Filter-based deletes can match many documents at once; preview with `--dry-run` and confirm the count with `iwe count --filter '...'` first
- `-f keys` prints affected document keys (target plus every document whose references were rewritten), suitable for piping
- `--quiet` suppresses progress output
- `--filter '{}'` targets the entire corpus; do not run that without explicit user intent

## `iwe normalize`

Use `normalize` for in-place cleanup across the whole library.

```bash
iwe normalize
```

Current behavior worth knowing:

- `normalize` rewrites files in place across the project
- It updates formatting and link titles to match the current graph
- If standalone links are not separated by blank lines, normalization can merge them onto one line and turn them into inline links
- Treat it as a bulk write operation, not as a read-only check

## Command selection guide

- Create a note: `iwe new`
- Split a section out structurally: `iwe extract`
- Merge linked content back into context: `iwe inline`
- Change a document key, including path-like keys: `iwe rename`
- Remove a note safely: `iwe delete` (positional key) or `iwe delete --filter ...`
- Rewrite the body of a single note: `iwe update -k KEY -c CONTENT`
- Mutate frontmatter on one or many notes: `iwe update [--filter ...|-k KEY] --set / --unset`

If the user asks for a structural change and the CLI supports it, use the CLI instead of editing markdown references by hand. If exact arguments still matter, run `iwe <command> --help`. After a write operation, inspect affected files or rerun `find` or `retrieve` to confirm the graph state.
