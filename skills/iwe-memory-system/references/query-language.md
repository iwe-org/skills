# Query Language

Use this reference when filtering documents by frontmatter, narrowing graph traversals, or mutating frontmatter in bulk. The query language is shared by `iwe find`, `iwe count`, `iwe tree`, `iwe schema`, `iwe update`, and `iwe delete`.

Official docs:

- Query language: https://iwe.md/docs/concepts/query-language/

The language is YAML-based and MongoDB-style. CLI commands accept filter expressions through `--filter` (and graph-shorthand flags such as `--key`, `--includes`, `--included-by`, `--references`, `--referenced-by`). Treat the language as experimental: syntax may still change.

## Operations

The four operations exposed through the CLI are:

- `find`: return matched documents, optionally shaped by projection, sort, and limit
- `count`: return an integer count of matching documents
- `update`: mutate frontmatter on matched documents via `$set` / `$unset`
- `delete`: remove matched documents and clean up references

`update` and `delete` require an explicit filter. Passing an empty filter `{}` intentionally targets the entire corpus; do not do that without confirmation from the user.

## Filter syntax

### Equality

Bare YAML mapping is field equality. For arrays, a scalar value tests membership.

```bash
iwe find --filter 'status: draft'
iwe find --filter 'tags: rust'        # documents whose tags array includes "rust"
```

### Operator expressions

Dollar-prefixed keys provide MongoDB-style operators:

- `$eq`, `$ne`
- `$gt`, `$gte`, `$lt`, `$lte`
- `$in`, `$nin`
- `$exists`
- `$all`, `$size` (arrays)

```bash
iwe find --filter 'priority: { $gt: 3 }'
iwe find --filter 'status: { $in: [draft, review] }'
iwe find --filter 'reviewed: { $exists: false }'
```

### Logical composition

- Top-level AND is implicit
- `$and`, `$or`, `$not`, `$nor` for explicit composition

```bash
iwe find --filter '$or: [{ status: draft }, { status: review }]'
iwe find --filter '$and: [{ priority: { $gte: 3 } }, { reviewed: false }]'
```

### Nested fields

Use either dotted paths or nested mappings.

```bash
iwe find --filter 'author.name: alice'
iwe find --filter 'author: { name: alice }'
```

### Cross-type comparisons

Cross-type comparisons fail without implicit coercion. Quote values when the YAML scalar type matters: `count="5"` is a string, `count=5` is an integer.

## Graph operators

Graph operators traverse inclusion edges (block references) and reference edges (inline links).

### Identity

```yaml
$key: notes/foo
$key: { $in: [a, b, c] }
```

### Relational

| Operator | Meaning | Edge type | Bounds |
|---|---|---|---|
| `$includes` | this document includes anchor | inclusion | `maxDepth`, `minDepth` |
| `$includedBy` | this document is included by anchor | inclusion | `maxDepth`, `minDepth` |
| `$references` | this document references anchor | reference | `maxDistance`, `minDistance` |
| `$referencedBy` | this document is referenced by anchor | reference | `maxDistance`, `minDistance` |

Full form:

```yaml
$includedBy:
  match:
    type: project
    status: active
  maxDepth: 5
```

Omitting `maxDepth` / `maxDistance` makes the walk unbounded and reaches all transitively related documents. The CLI treats `:0` (e.g. `--included-by projects/alpha:0`) as unbounded.

### CLI shorthand for graph operators

Each relational operator has a flag that lowers into the YAML form:

```bash
iwe find --included-by projects/alpha            # depth defaults to --max-depth (1)
iwe find --included-by projects/alpha:5          # depth 5
iwe find --included-by projects/alpha:0          # unbounded
iwe find --references people/dmytro
iwe find --referenced-by index
iwe find -k notes/foo                             # $key shorthand; repeatable -> $in
```

Anchor flags are repeatable and are ANDed when combined.

## Projection (find / tree)

Choose which frontmatter fields appear in the output.

```bash
iwe find --project title,status -f json
iwe find --project 'title: 1, modified_at: 1, author.name: 1' -f json
iwe find --add-fields 'body=$content' -f json     # default projection plus body
iwe tree --project status -f json
```

`--project` replaces the default projection. `--add-fields` extends it. The two flags are mutually exclusive. Selectors include bare names, `name=path`, `name=$selector`, and `$selector`.

## Sort and limit

```bash
iwe find --filter 'status: draft' --sort modified_at:-1 --limit 10
iwe find --sort priority:1
```

`1` is ascending, `-1` is descending. The CLI currently accepts one sort key; ties resolve by document key ascending. `--limit 0` means unlimited.

## Update operations

`iwe update` has two modes. The body-overwrite mode (`-k KEY -c CONTENT`) replaces the markdown body of one document. The frontmatter mutation mode (`--filter` / `-k`, plus `--set` / `--unset`) applies `$set` or `$unset` across every matched document.

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

Body and frontmatter modes cannot be combined in one call. Run two passes if both must change. Use `--dry-run` before bulk mutations.

## Reserved prefixes

Field names beginning with `_`, `$`, `.`, `#`, or `@` are reserved. They are invisible to filters, projections, and sorts, and are stripped on writeback. Using them as update paths errors at parse time.

## Schema discovery

`iwe schema` infers the frontmatter schema across the workspace. Use it before composing a non-trivial filter so you know which fields exist, their types, and the distribution of enumerable values.

```bash
iwe schema
iwe schema --filter 'type: post'
iwe schema --field status
iwe schema --field engagement -f json
```

`--filter` restricts analysis to a subset; `--field` drills into one field and its children. `iwe schema` does not accept `--project` or `--add-fields`; it always reads raw frontmatter.

## Practical workflow

1. Explore the schema with `iwe schema` to learn which frontmatter fields and values exist.
2. Test a filter with `iwe count --filter '...'` to confirm the matched set size.
3. Run `iwe find --filter '...' -f keys` to inspect which documents match.
4. For destructive operations, run `iwe update ... --dry-run` or `iwe delete ... --dry-run` before applying.
5. Apply the operation. Use `--quiet` and `-f keys` when piping output into other steps.

## Examples

```bash
# All draft posts, newest first
iwe find --filter '$and: [{ type: post }, { status: draft }]' --sort modified_at:-1

# Count archived documents under a project subtree
iwe count --included-by projects/alpha:0 --filter 'status: archived'

# Promote every reviewed draft to published, preview first
iwe update --filter '$and: [{ status: draft }, { reviewed: true }]' --set status=published --dry-run
iwe update --filter '$and: [{ status: draft }, { reviewed: true }]' --set status=published

# Delete every archived note inside a subtree, preview first
iwe delete --filter '$and: [{ status: archived }, { $includedBy: { match: { $key: projects/alpha }, maxDepth: 0 } }]' --dry-run
```
