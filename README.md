## IWE Agentic AI Skills

Main repository is here https://github.com/iwe-org/iwe

## Available skills

### `graph`

Gives agents bounded, graph-aware routes for finding, retrieving, creating, and safely refactoring notes without falling back to broad filesystem searches. The skill file is frontmatter only; the policy itself ships inside the binary as `iwe docs agent`, so it always describes the CLI that is actually installed.

Requirements:

- an IWE workspace;
- IWE CLI `>=0.20.0` — install via `npm install -g @iwe-org/iwe`, `brew install iwe-org/iwe/iwe`, or `cargo install iwe`;
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
written in the shape the store already uses — then scopes the sessions already
on disk and hands them over. `distill` is the only write path memory has: it
reads a session *with you*, puts what looks worth keeping in front of you one
item at a time with its evidence — remember or skip, with a comment if you have
one — writes what you keep, and then offers the sessions that came before. `reflect` evolves the policy with you: it edits `MEMORY.md`,
analyzes the frontmatter, proposes index fields, backfills them, groups notes
into areas, pulls the people, releases, components and other entities the notes
keep mentioning into typed pages the notes link to, and prunes or merges on
request.

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

Installed as a Claude Code plugin, `iwe` also carries durable session memory.
Memory is not a database the agent accretes — it is a knowledge base you
co-author: plain markdown in the repository's own IWE workspace, reviewed as
ordinary files. There is no separate memory directory and no second graph:
captured notes sit beside your project's markdown, link to it, and are found by
the same queries.

**Nothing is captured unattended.** An earlier version of this plugin swept
transcripts at turn boundaries and let a background agent write what it found.
It could not tell a suggestion from a decision — a window of conversation is
not the shape of a decision — so it wrote down choices nobody made. That whole
path is gone. `/iwe:distill` runs in the foreground, proposes with evidence,
and writes only what you pick.

### Set it up

1. Have IWE CLI `>=0.21.0` on `PATH`:

   ```bash
   npm install -g @iwe-org/iwe
   # or: brew install iwe-org/iwe/iwe
   # or: cargo install iwe
   ```

2. Install the plugin in Claude Code:

   ```
   /plugin marketplace add iwe-org/skills
   /plugin install iwe@iwe-org
   ```

3. Let the memory skills run the CLI. They run `iwe` and nothing else, and
   their commands carry no paths, so the whole permission story is one
   allowlist rule in `.claude/settings.json`:

   ```json
   { "permissions": { "allow": ["Bash(iwe:*)"] } }
   ```

The plugin is inert until you switch a repository on: without a `MEMORY.md`
document in the workspace, both hooks it installs exit 0 and print nothing —
on every machine, in every other repository.

### Turn memory on

Start Claude Code at the repository root and run:

```
/iwe:init
```

It writes `MEMORY.md` with you — the one document that is both the switch and
the policy. The policy is prose you own: what is worth capturing, how documents
in *this* store are written, how to dedup, how far curation may go. The plugin
imposes none of that — no document types, no schemas, no `learnings/`
directory; a distill run reads your policy, studies the store with `iwe schema`,
and writes documents that look like the ones already there. `init` tailors the
policy to an existing store, or starts from a starter for an empty one, with an
optional typed ontology for repositories that want structure out of the box.

Then it lists the sessions already on disk — read-only, ranked by user turns —
and asks how much of that history is worth reading. Watermarks never move while
`MEMORY.md` is absent, so a repository you enable months in is still readable
from line zero, and `iwe internal claude session adopt` marks the part that is
not worth reading as seen.

### Use it

- **"Remember this"** — `/iwe:distill`, or just say it in plain words. It reads
  the current session, puts up to five proposals in front of you one at a time
  with a quote for each — remember or skip, with a free-form comment if you
  want the item changed — writes what you keep, and then offers the backlog one
  session at a time.
- **What memory has read, and what it has not**:

  ```bash
  iwe internal claude session list --all
  cat .iwe/claude/sessions/<session-id>.yaml
  iwe find --filter '{ session: "<session-id>" }' -f keys
  ```

- **Reorganize** — `/iwe:reflect` edits the policy with you, proposes index
  fields and backfills them, groups notes into areas with hub pages, extracts
  the entities the notes keep mentioning into typed pages, and merges or
  prunes on request — never unattended.

### What happens on its own

Two things, and neither of them decides what to remember.

**At session start** the plugin injects a token-budgeted index of memory —
titles and keys, never content — plus how many sessions are still undistilled
and the commands for going deeper. What goes in is the policy's `injection`
knob: a list of slices the binary runs in order, each a `filter` and/or a
`sort` over the store's frontmatter, with an optional `heading` and `limit`. A
store with `kind: rule` and `status: open` fields puts its rules and its open
traps in front of every session, then the recent ones — deterministic queries
the user owns, no model in the loop. At
most once a week it also asks the assistant to offer a distill run at the next
natural pause.

**After the assistant writes a file** a `PostToolUse` hook checks that one
document, the way format-on-save and a linter check the file you just saved.
It watches the editing tools (Write, Edit, MultiEdit) and Bash. A markdown
document the assistant wrote with an editing tool — bypassing the CLI, which
normalizes on the way in — is rewritten into the store's canonical form, and a
document that breaks a schema this store binds is reported back so the
assistant fixes it. A Bash call is looked at only when it ran `iwe create`,
`update`, `rename`, `delete` or `attach` without `--strict`: the documents that
write produced are validated, and the assistant is told to put the flag on
every write. It only ever touches the documents that tool call just wrote, it
never reads a transcript, and it never decides that something is worth
remembering. `MEMORY.md` and the session records are left alone. Writes that
already went through `iwe ... --strict` are not schema-checked twice; the one
thing the net says about a fresh `iwe create` is when the new document closely
matches one the store already has — the same similar-page check `--strict`
runs — with the older key to read and the merge to make. Everything else —
any other shell command, a `.py` file, a document outside the workspace —
exits in a couple of milliseconds without loading the graph.

**When a distill run records what it wrote** (`session complete --wrote`), a
document keyed `<area>/<slug>` is linked into its area hub `<area>` by the
command itself, once, so a store grouped into areas never drifts from its
hubs; the brief's `=== hubs ===` census shows every area and any stray, and
its `=== schemas ===` section shows which schema `--strict` enforces on the
documents the policy calls memory — `init` installs one from the start.

Capture is still yours alone: `/iwe:distill`, in the foreground, on what you
pick.

### Tune it

The frontmatter of `MEMORY.md` carries the mechanical knobs, all optional, all
defaulted: `distill` — how sessions are read: `max_chunk_size` (how much
conversation one read serves, 25000), `max_proposals` (5) and
`remind_after_days` (7; `-1` to never remind, `0` to remind every session) —
and `injection`, the slices session start renders, each a `filter` and/or a
`sort` with an optional `heading`, `limit` and `max_tokens`:

```yaml
distill:
  max_chunk_size: 25000
  max_proposals: 5
  remind_after_days: 7
injection:
  - { heading: "Rules this store keeps:", filter: { kind: rule }, limit: 10, max_tokens: 400 }
  - { heading: "Still open:", filter: { kind: trap, status: open }, limit: 10 }
  - { heading: "Most recently recorded:", filter: { created: { $exists: true } }, sort: created:-1, limit: 10 }
```

Each has an environment twin named for its path with dots as underscores
(`IWE_DISTILL_MAX_PROPOSALS`). The body is re-read on every run,
so a policy edit takes effect immediately.

To turn memory off, delete `MEMORY.md` — nothing else changes, and re-adding it
later resumes at the line each session was distilled through.

### Good to know

- Both hooks live in the `iwe` binary itself — the plugin ships no runtime
  scripts, and upgrading the binary upgrades the prompts with it. Without the
  binary, or one too old, the plugin is a no-op.
- Hooks and skills use the session's working directory verbatim, so start
  Claude Code at the workspace root.
- On Windows the hook one-liners need git-bash or WSL.
- Subagent transcripts are never read. They are the assistant talking to
  itself, and nothing durable originates there that the session transcript does
  not also show.
- A session someone else is still in the middle of is never read either: a
  transcript touched in the last 30 minutes is listed `active` and skipped
  unless you name it.
- Retrieval has no embeddings, on purpose: fuzzy and lexical ranking fused
  with graph expansion is the story. "Find it phrased completely differently"
  is the honest gap.
- The parts that only exist with a model in the loop — what a distill run
  proposes, what it refuses to propose, whether memory changes what a later
  session does — are evals rather than tests, and live under
  [evals/harbor](evals/harbor/README.md).
