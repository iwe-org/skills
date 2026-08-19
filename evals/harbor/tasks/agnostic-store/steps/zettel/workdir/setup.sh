#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_memory_init
eval_clean_run_state

# This store keeps zettels: its own type, its own template, its own schema, its
# own key prefix. Nothing here comes from the plugin.
mkdir -p "$EVAL_APP/.iwe/schemas"
cat >>"$EVAL_APP/.iwe/config.toml" <<'TOML'

[templates.zettel]
key_template = "notes/{{slug}}"
document_template = "---\ntype: zettel\ncreated: \"{{now}}\"\nsource: session\n---\n\n# {{title}}\n\n{{body}}\n"

[schemas.zettel]
match = "notes/**"
TOML
cat >"$EVAL_APP/.iwe/schemas/zettel.yaml" <<'YAML'
$schema: https://document-schema.org/draft/2026-06/schema
frontmatter:
  type: object
  required: [type, created, source]
  properties:
    type: { const: zettel }
    created: { type: string }
    source: { type: string }
  additionalProperties: false
maxTokens: 400
maxDepth: 2
YAML

# The policy describes that ontology back to capture, in the store's own
# vocabulary.
eval_iwe update -k MEMORY --content '# Memory policy

This store keeps zettels and nothing else.

## What to capture

Facts about this repository that stay true after the session that found them
ends, that are not obvious from the code, and that would change what a future
session does. Prefer none over noise.

## How to write it

Always through the zettel template, which stamps type, created and source and
derives the key from the title slug under notes/:

    iwe create --template zettel --strict --var title="<specific noun phrase>" --var body="<two to six sentences>"

Never write a document outside notes/, never invent another type, and never
add a frontmatter field: the zettel schema forbids extra properties and
--strict will reject the write.

## Dedup and updates

Search before every write and read the plausible hits:

    iwe find --lexical "<nouns>" --limit 5 --filter '"'"'{ type: zettel }'"'"' --project '"'"'title=$title,key=$key'"'"'

Scoping to type: zettel keeps the capture machinery'"'"'s own documents and this
repository'"'"'s markdown out of the results. Update an existing zettel only when
the new item states the same fact.

## Provenance

Do not add a session field: the schema forbids it. The capture note in the
session record is the provenance.

## Curation

Curation is human-invoked. It may merge two zettels that state the same fact,
and nothing else.' >/dev/null

eval_seed_transcript tail-deploy.jsonl 1a7f5b30-0000-4000-8000-0000000000b1
eval_finish

rm -- "$0"
