## IWE Agentic AI Skills

Main repository is here https://github.com/iwe-org/iwe

## Available skills

### `graph`

Gives agents bounded, graph-aware routes for finding, retrieving, creating, and safely refactoring notes without falling back to broad filesystem searches. The skill file is frontmatter only; the policy itself ships inside the binary as `iwe docs agent`, so it always describes the CLI that is actually installed.

Requirements:

- an IWE workspace;
- IWE CLI `>=0.20.0` — install via `npm install -g @iwe-org/iwe`, `brew tap iwe-org/iwe && brew install iwe`, or `cargo install iwe`;
- an agent runtime that supports skills.

Install with the skills CLI (works with Claude Code, Codex, Cursor, OpenCode, and many other agents):

```bash
npx skills add iwe-org/skills --skill graph
```

Claude Code users can also install natively as a plugin:

```
/plugin marketplace add iwe-org/skills
/plugin install iwe@iwe-org
```

See the [skill](skills/graph/SKILL.md), the [IWE repository](https://github.com/iwe-org/iwe), and the [IWE documentation](https://iwe.md/docs/) for details.

### `init`, `distill`, and `reflect`

Three skills over agent memory, which lives in the repository's own IWE
workspace.

`init` switches memory on for a repository — one `MEMORY.md` policy document,
written in the shape the store already uses — and then drains the sessions
already on disk into it, curating between waves rather than leaving one huge
cleanup for the end. `distill` records something worth keeping from the session
at hand, through the same policy the automatic capture follows. `reflect`
evolves the policy with you: it edits `MEMORY.md`, analyzes the frontmatter,
proposes index fields, backfills them, groups notes into areas, pulls the
people, releases, components and other entities the notes keep mentioning into
typed pages the notes link to, and prunes or merges on request.

The skill files here carry only their frontmatter — the name and the
description an agent triggers on. The instructions each one follows come from
the installed binary, `iwe internal claude prompt <init|distill|reflect>`, so
they always describe the commands that binary actually has and the plugin never
drifts from the CLI. Claude Code injects that text as the skill loads; any
other runtime runs the command as the skill's first step.

All three are plain skills, so `npx skills add iwe-org/skills` carries them to
Codex, Cursor, and OpenCode alongside Claude Code. What you type depends on how
they got there: Claude Code addresses a plugin's skills as `plugin:skill`, so
`/iwe:init`, `/iwe:distill`, `/iwe:reflect`; installed with the skills CLI they
are ordinary project skills, `/init`, `/distill`, `/reflect`. Start with
`init` — the other two assume the workspace it creates.

One caveat for the skills-CLI route on Claude Code: `init` is also the name of
a built-in skill there, so the bare form may resolve to that instead. The
plugin's prefixed `/iwe:init` is unambiguous, and asking in plain words
("set up memory here", "remember this") routes correctly either way.

## IWE Memory

Installed as a Claude Code plugin, `iwe` also carries automatic session memory.
Memory is not a database the agent accretes — it is a knowledge base you
co-author: plain markdown in the repository's own IWE workspace, reviewed as a
normal diff. There is no separate memory directory and no second graph:
captured notes sit beside your project's markdown, link to it, and are found by
the same queries.

### Set it up

1. Have IWE CLI `>=0.20.0` on `PATH`:

   ```bash
   npm install -g @iwe-org/iwe
   # or: brew tap iwe-org/iwe && brew install iwe
   # or: cargo install iwe
   ```

2. Install the plugin in Claude Code:

   ```
   /plugin marketplace add iwe-org/skills
   /plugin install iwe@iwe-org
   ```

3. Let the background capture agent run the CLI. It runs `iwe` and nothing
   else, and its prompts carry no paths, so the whole permission story is one
   allowlist rule in `.claude/settings.json`:

   ```json
   { "permissions": { "allow": ["Bash(iwe:*)"] } }
   ```

The plugin is inert until you switch a repository on: without a `MEMORY.md`
document in the workspace, every hook exits 0 and prints nothing — on every
machine, in every other repository.

### Turn memory on

Start Claude Code at the repository root and run:

```
/iwe:init
```

It writes `MEMORY.md` with you — the one document that is both the switch and
the policy. The policy is prose you own: what is worth capturing, how documents
in *this* store are written, how to dedup, how far curation may go. The plugin
imposes none of that — no document types, no schemas, no `learnings/`
directory; capture reads your policy, studies the store with `iwe schema`, and
writes documents that look like the ones already there. `init` tailors the
policy to an existing store, or starts from a starter for an empty one, with an
optional typed ontology for repositories that want structure out of the box.

Then it surveys the sessions already on disk — read-only, ranked by yield —
and asks how much of that history to drain into the store: in curated waves,
everything, or adopted unread. Watermarks never move while `MEMORY.md` is
absent, so a repository you enable months in is still drainable from line
zero.

### What happens on its own

- **At session start** the plugin injects a token-budgeted index of recent
  memory — titles and keys, never content — plus the commands for going
  deeper.
- **At turn boundaries** a sweep checks for un-captured transcript tails, in
  your idle time after the answer has landed. When a tail crosses the
  threshold it is imported as small chunks and a background `distill` agent
  works that queue: it judges each span against your policy, dedups against
  the store, writes or updates documents, and records provenance in
  `sessions/<session-id>`. Previous sessions — killed, cleared, interrupted,
  or short — are swept at the next boundary in the same project.

Capture is near-silent, not invisible: one background launch line after the
answer has landed, and reviewable diffs afterwards. Nothing curates the store
in the background — reorganizing memory is `/iwe:reflect`, human-invoked.

### Use it

- **"Remember this"** — `/iwe:distill`, or just say it in plain words. Same
  policy, same dedup, same write path as the automatic capture.
- **See what memory holds** — recent captures, what a session produced, and
  which sessions produced a document:

  ```bash
  iwe find --filter '{ distilled_lines: { $exists: true } }' --sort 'created:-1' --limit 10
  iwe retrieve -k sessions/<session-id>
  iwe find --filter '{ $includes: <key> }' -f keys
  ```

- **See what is queued** — the sweep in read-only mode, importing nothing:

  ```bash
  iwe internal claude hook stop --survey
  ```

- **Reorganize** — `/iwe:reflect` edits the policy with you, proposes index
  fields and backfills them, groups notes into areas with hub pages, extracts
  the entities the notes keep mentioning into typed pages, and merges or
  prunes on request — never unattended.

### Tune it

The frontmatter of `MEMORY.md` carries the mechanical knobs, all optional, all
defaulted: `sweep_threshold_lines`, `chunk_chars`, `max_chunks_per_sweep`,
`max_items_per_chunk`, `inflight_ttl_minutes`, `injection_max_tokens`. The
body is re-read on every run, so a policy edit takes effect immediately.

Whether the raw chunk digests under `.iwe/claude-sessions/` enter git is your
call, made in `.gitignore`; the machinery reads them by path, so capture works
either way. To turn memory off, delete `MEMORY.md` — nothing else changes, and
re-adding it later resumes where the watermarks stand.

### Good to know

- The hooks live in the `iwe` binary itself — the plugin ships no runtime
  scripts, and upgrading the binary upgrades the prompts with it. Without the
  binary, or one too old, the plugin is a no-op.
- Hooks and agents use the session's working directory verbatim, so start
  Claude Code at the workspace root.
- On Windows the hook one-liners need git-bash or WSL.
- Retrieval has no embeddings, on purpose: fuzzy and lexical ranking fused
  with graph expansion is the story. "Find it phrased completely differently"
  is the honest gap.
- The parts that only exist with a model in the loop — the Stop hook reaching
  a live session, what capture extracts, whether memory changes what a later
  session does — are evals rather than tests, and live under
  [evals/harbor](evals/harbor/README.md).
