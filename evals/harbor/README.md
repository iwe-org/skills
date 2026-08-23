# Harbor evals for IWE memory

End-to-end evals for the memory layer, run against a real model in a container.
`check.sh` below pins everything that can be decided without a model — the hook
commands' wiring, the sweep's import and spawn-guard mechanics, the MEMORY.md gate, the
digest renderer, and every verifier against its oracle. What it cannot test is
the half of the design that only exists with a model in the loop: whether the
Stop block actually makes a live session launch `distill`, whether the
capture extracts signal rather than noise, whether it writes in the shape the
store's policy describes, and whether memory changes what a later session
does. That is what lives here.

These evals cost real API money and are **not** a per-PR gate. The per-PR gate
is `check.sh`, free and offline.

Implements `plans/harbor-memory-eval.md` over the architecture in
`plans/memory-plugin-v2.md` as amended by `plans/memory-plugin-v2-agnostic.md`.
Deviations from those plans are listed at the end of this file.

## What is under test

Memory lives in the repository's own IWE workspace. A workspace remembers when
it holds a `MEMORY.md` document; that document is the switch and the policy, and
the plugin brings no document types, schemas, templates or directories of its
own. So the suite has to prove two different things:

- the **machinery** works — imports, watermarks, expiry, races, silence;
- the machinery **imposes nothing** — capture writes whatever the store's
  policy says, including ontologies the plugin has never heard of.

## Layout

```
evals/harbor/
├── check.sh              lint + sweep wiring + oracle simulation, no docker, no API key
├── gate.sh               reward floors for scheduled runs
├── floors.txt            the floors themselves (empty until runs are stable)
├── lib/assert.sh         verifier helpers, sourced by every tests/test.sh
├── image/
│   ├── Dockerfile        the one shared image
│   ├── build-fixture.sh  writes the `releasekit` fixture project
│   ├── render-settings.sh  hooks/hooks.json -> .claude/settings.json
│   ├── setup-lib.sh      helpers for each step's workdir/setup.sh
│   ├── marker.sh         payload-dumping hook used by the probe
│   └── fixtures/*.jsonl  seedable transcript tails
└── tasks/<task>/         one Harbor task per directory
```

## Prerequisites

```bash
uv tool install harbor          # needs Python 3.12+, Docker, uv
export ANTHROPIC_API_KEY=...    # the claude-code adapter reads it from the host
```

The plugin needs IWE CLI `>=0.20.0` (`internal claude hook`, `internal claude
digest`, `internal claude job brief` and `job frontier`, `create --if-exists`,
`update --append`, `delete --expect`, `$exists` filters).
The image installs it, plus `jq` for the harness's own assertions. To test
against a locally built engine, stage a Linux binary at
`evals/harbor/image/bin/iwe` (gitignored) and build with
`--build-arg IWE_SOURCE=copy`; the default `IWE_SOURCE=npm` installs
`@iwe-org/iwe@$IWE_VERSION`.

## Build the image once

Every task references `iwe-memory-evals:latest` through
`[environment] docker_image`, so build it before any run. The build context is
the repository root, not the image directory:

```bash
docker build -f evals/harbor/image/Dockerfile -t iwe-memory-evals:latest .
```

Rebuild after changing anything under `hooks/`, `agents/`, `skills/`, or
`evals/harbor/{lib,image}/` — the image bakes all of them in.

## Run

```bash
harbor run -p evals/harbor/tasks --agent oracle                     # verifiers only, no API cost
harbor run -p evals/harbor/tasks --agent claude-code \
  -m anthropic/claude-sonnet-5 -k 3 -n 4 --job-name iwe-memory-$(date +%F)
harbor view jobs                                                    # web viewer over ~/.cache/harbor/jobs
```

`-p` takes a local dataset directory, and `evals/harbor/tasks` is one; pass a
single task directory instead to iterate on it — `-p
evals/harbor/tasks/capture-e2e`. Interactive container:
`harbor task start-env --path evals/harbor/tasks/capture-e2e -i`. Lint a task
definition with `harbor task check`. Pin the Claude Code build for comparable
runs with `--ak version=<x>`.

**A single green run proves nothing.** Every model-driven assertion here is
lexical and the model is not deterministic; run with `-k 3` at minimum and read
the component rewards, not the headline number.

Cost: the full suite at `-k 3` is a few dozen short sessions, single-digit
dollars per run. That is why it is scheduled and manual, never per-PR.

## Check it without docker or an API key

```bash
sh evals/harbor/check.sh                 # everything
sh evals/harbor/check.sh capture-e2e     # one task
IWE_EVAL_KEEP=1 sh evals/harbor/check.sh # keep the simulated container trees
```

`check.sh` does three things.

It **lints**: every harness shell script parses, `hooks.json` is valid and
points both hooks at `iwe internal claude hook` with no `jq`, no plugin root
and no inline strings — the binary carries the default reason and footer text —
the starter policy documents the sweep's
default threshold, no shipped
agent, skill or task reaches into a store with `iwe -C`, every declared step has an
instruction, a verifier, an oracle and a setup script, every task pins the
shared image, and the seeded transcript tails are valid JSONL that cross the
sweep threshold.

It **exercises the sweep end to end** against a real workspace, with no model
anywhere: the digest renderer produces the expected shape; outside a workspace
the hooks are silent; inside a workspace with no
`MEMORY.md` they are just as silent *and write nothing*; `internal claude enable` writes the
policy and refuses to write a second one; a transcript over the threshold then
gets chunk files under `.iwe/claude-sessions/<id>/` (and none in the store), one session record, and one block
asking for capture and carrying no path; nothing the machinery writes is stamped
with a `type`; a second sweep re-imports the same span onto the same keys rather
than duplicating it; `job next` serves the chunk at the watermark and falls
silent once the queue is worked; `job brief` serves the policy, the inferred
schema and the recent keys with the machinery left out of the shape it teaches;
`job frontier` serves one chunk per session; two backlogs differing only in when
their conversations happened are served most-recent-first by both, and the older
one waits until the recent one drains; the survey carries the yield signal and
totals it; a settled store stays silent — nothing but
capture ever runs in the background;
SessionStart injects an index that points
at the policy and leaves the machinery out; and deleting `MEMORY.md` turns
all of it off again.

Then it **simulates each task without Docker**: it builds the fixture project
into a temporary directory, runs each step's `workdir/setup.sh`, then its
`solution/solve.sh`, then its `tests/test.sh`, and requires the reward to be
exactly 1.0. That simulation is how the verifiers are tested — same setup
scripts, same oracle solutions, same verifier code the container runs, with
`/app` and `/logs` redirected through `IWE_EVAL_APP` and `IWE_EVAL_LOGS`.

It needs `iwe` `>=0.20.0` and `jq` on PATH; without them it lints and skips the
rest.

What the simulation cannot cover, by construction: hooks firing from a live
session, the model's behavior, and the capture agent's judgment. Those need a
Harbor run.

## The fixture project

`releasekit`, a POSIX-shell release tool, built by `image/build-fixture.sh` and
committed as a single git commit at image build. It is an ordinary code
repository — each task's setup turns it into a memory-enabled workspace by
running the same `iwe internal claude enable` a user runs. Its planted facts are
chosen to be non-obvious from the code and checkable by identifier:

- `make deploy` exits 3 with `DEPLOY_ENV is unset (RB-417)` and exits 2 until
  `make build` has written the bundle. Valid targets live only in
  `ops/runbook-417.txt`.
- `bin/deploy.sh` appends every invocation to `.deploy-attempts`, including the
  value of `DEPLOY_ENV` or `<unset>`. That file is how a verifier tells
  "deployed straight away" from "re-diagnosed the failure first".
- The vendored parser under `src/parser/` must never become a registry
  dependency. Nothing in the repository records this; it is stated by the user
  in `capture-e2e`'s instruction, so capturing it is something the store should
  hold.
- `RB-508`, the standby-rotation runbook, is named once — in the middle of a
  14942-character message in `tail-backfill.jsonl`. That one line is what makes
  chunk sizing observable: at the default 10000-character budget the message
  becomes a chunk of its own, cut at the budget with a `[truncated at …]`
  marker, and `RB-508` never reaches capture at all; at 25000 it arrives whole.
- `CLAUDE.md` says the repository is an IWE workspace and shows how to query it,
  without naming any planted fact. That pointer is what makes the read path
  testable while SessionStart's headless behavior is still unknown (see the
  probe).

Because the repository *is* the store, its own markdown (README, CLAUDE.md,
`src/parser/README.md`) is in the graph. That is the design, and the verifiers
account for it: knowledge documents are the dated ones
(`created: { $exists: true }`), and "what capture wrote" is narrower still —
the documents a session record links to.

## Wiring

The plugin is not installed as a plugin. The image writes project-level
configuration into the fixture repository, generated from the shipped sources
so nothing can drift:

- `.claude/settings.json` — `hooks/hooks.json` copied verbatim
  (`render-settings.sh`); the hook commands run `iwe internal claude hook` off
  PATH, exactly as a plugin install would.
- `.claude/agents/` — `agents/distill.md` copied unmodified, so
  `subagent_type "distill"` resolves. A plugin install namespaces the agent as
  `iwe:distill`, and the binary names whichever applies: its Stop reason reads
  the plugin name off `$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json` when
  Claude Code runs the hook from a plugin, and falls back to the bare name when
  the hook comes from project settings, as it does here. `check.sh` pins both
  spellings against the shipped manifests.
- `.claude/skills/{init,distill,reflect}` — copied from `skills/`, so
  `distill-skill` tests the shipped skill rather than a paraphrase.

## The suite

| task | what it pins |
|---|---|
| `probe-hooks` | Diagnostic. Answers the four headless unknowns below; its reward is 1.0 whatever the answers are. |
| `capture-e2e` | The whole loop over three steps: hit the planted gotcha, capture it, then deploy again without re-diagnosing. |
| `capture-no-noise` | A session with nothing durable must leave the store empty — while still advancing the watermark and noting the capture. |
| `agnostic-store` | A store with its own ontology (`zettel` documents, own schema and template, own key prefix) and a policy describing it: capture writes *that* shape, and nothing from any default ontology appears. |
| `memory-knobs` | Two steps: a threshold no transcript reaches keeps the sweep silent; lowering it makes it import chunks under the one fixed prefix, `sessions/`, with the item cap the policy sets. |
| `inert-without-memory` | Two steps: no workspace and then a workspace with no `MEMORY.md` are both wholly silent and write nothing; adding the policy afterwards captures the same transcript from line zero. |
| `concurrency` | Two pending transcripts and two sweeps racing: each span imported once, one capture note per session, no duplicate items. |
| `stale-claim` | A capture that died leaves its chunk pending; the next sweep expires the claim, re-imports the real span onto the same key, and hands it to a fresh agent rather than losing it. |
| `recall-seeded` | A decision written nowhere in the repository, reachable only from seeded memory. |
| `recall-baseline` | The control for the pair: same instruction, no workspace at all. Its `answer_target` and `answer_reason` metrics are the baseline. |
| `distill-skill` | `remember this` with two facts against the optional typed ontology: one new document through the template, one update in place, no duplicate, no hand-written files. |
| `drain-sizing` | A backfill drained at `chunk_chars=25000`/`max_items_per_chunk=7`: fewer chunks over the same span than the 10000 baseline the fixture is measured against, the same facts kept, and the one the default budget truncates away (`RB-508`) delivered whole. |
| `drain-triage` | Three sessions, signal in one: the drain reads the frontier as a batch, finishes the two empty spans cheaply, and spends curation only where something was kept. |

`/reflect`'s propose-and-pick taxonomy loop stays out: a scripted "user pick"
would test the script, not the skill.

## Asserting on graph state

There is no log to grep: the sweep keeps its records in documents and its
queue in plain files under the workspace's `.iwe/claude-sessions/`, so every
verifier reads the store through `iwe` — by stepping into the workspace, never
with `-C` — and the queue off disk at that one path (`$EVAL_CHUNKS`; an
`IWE_MEMORY_STATE` override is honoured). `lib/assert.sh` is where that lives:

- `memory_enabled` — a `MEMORY.md` document exists; `memory_knob <name>` reads
  one knob out of its frontmatter. The machinery always writes records under
  the one prefix it owns, `sessions/`, and chunks under `.iwe/claude-sessions/`.
- `mem_watermark <session>` / `mem_watermark_max` — `distilled_lines` off the
  session record.
- `chunk_files` / `session_chunk_files <session>` / `pending_chunk_files` — the
  queue, read off disk the way the machinery reads it: chunks are never graph
  documents, and a store may gitignore the directory besides.
- `tail_claimed <session>` — the span's chunks are there, or the capture that
  worked them finished and left the watermark behind.
- `capture_noted <session>` — the session record carries a capture note, so a
  capture completed rather than merely starting.
- `provenance_linked <session>` — that note's links resolve, which is the whole
  provenance mechanism.
- `knowledge_count` — dated documents that are neither machinery nor policy;
  `captured_count` — the narrower set a session record actually links to.
- `pending_chunks` / `no_stale_claims`, `pending_tails` / `backlog_drained`.
- `session_chunk_count` / `baseline_chunks` / `chunks_below_baseline` — what a
  drain actually spent against what the same span costs at the default budget,
  recorded by `eval_record_chunk_baseline` at setup; `chunk_budget_at_least`
  reads the `max_items` stamped into the chunks, which is the durable evidence
  of the budget an import ran under.
- `capture_defaults_restored`, `no_truncation_marker_in_memory`,
  `empty_captures`, `frontier_used`, `stream_count` — the backfill-shape
  assertions: the live-capture knobs put back, no chunk boundary copied into a
  memory document, how many spans were finished having kept nothing, and
  whether the drain read the queue as a batch.
- `no_default_ontology` — nothing from the plugin's optional typed ontology
  exists, the check that the machinery imposed no structure.
- `store_has_no_state_files` — nothing under the mechanical prefixes but
  markdown.

Because the state is documents, the debug bundle is too: `state.txt` carries the
policy's frontmatter, the session records, the capture chunks and their
frontmatter, the knowledge documents, the capture notes and the hook output.

## Scoring

Every verifier writes `/logs/verifier/reward.json` with named components rather
than a bare 0/1, plus `reward` (the mean of the scoring components) and a
matching `reward.txt`. Values recorded with `metric` and `answer` are reported
but excluded from the mean — they are diagnostics, not grades. Each verifier
also drops `report.txt`, `state.txt` and `memory.tar.gz` into
`/logs/verifier/`, which Harbor downloads with the trial, so a failure is
debuggable from the trial directory alone.

The memory-lift number is a delta, not an absolute: compare `answer_target` and
`answer_reason` between `recall-seeded` and `recall-baseline` across `-k`
attempts.

Every verifier also emits `agent_api_error` (a metric, never scored): 1 means
the session died on an API failure outside the plugin — credit exhaustion,
rate limits, auth — and `report.txt` says so loudly. **A trial carrying
`agent_api_error = 1` is void, not bad**: its reward says nothing about the
plugin, no verifier should be tuned against it, and reward floors should skip
it rather than average it in.

## The probe, and the four unknowns

Four behaviors of headless Claude Code are undocumented and version-dependent.
`probe-hooks` re-answers them against whatever build a run uses, and a scheduled
run turns a regression red here first.

1. `sessionstart_fired`, `injection_visible` — does SessionStart fire headless,
   and does its output reach the session?
2. `stop_fired`, `sweep_imported_the_tail` — does the model act on the Stop
   hook's block decision?
3. `watermark_advanced`, `capture_wrote_a_document` — does a background
   subagent finish before the process exits?
4. `step_log_dir_shared` — does a later step see the previous step's
   transcripts?

**Answers, Claude Code build 2.1.233 (harbor 0.21.0, first live run
2026-08-15, job `iwe-memory-live-1`), measured against the v1 architecture —
the mechanics changed underneath them, the questions did not:**

1. `sessionstart_fired = 1`, `injection_visible = 1` — SessionStart **does**
   fire under `--print` on this build (it did not on 2.1.229) and its output
   reaches the session, cookbook pointer included.
2. `stop_fired = 1`, `sweep_imported_the_tail = 1` — the model acts on the block
   and launches `distill` in the background.
3. `watermark_advanced = 1`, `capture_wrote_a_document = 1`,
   `capture_found_the_planted_fact = 1`, queue drained — the background
   capture completes before the process exits.
   `subagent_transcript_written = 1` once the helper searched
   `*subagent*/*.jsonl` instead of an exact layout.
4. `step_log_dir_shared = 0` — a later step does **not** see the previous
   step's transcripts on harbor 0.21.0, so each step's capture must happen at
   that step's own turn boundaries, and `capture-e2e`'s flush step asserts on
   the store rather than re-sweeping step 1's tail.

## Deviations from the plans

- **Every task is multi-step**, including the single-step ones. `workdir/` and
  its reserved `setup.sh` are documented for steps only, and per-task setup has
  to run before the agent starts; one uniform mechanism beats a per-task
  Dockerfile.
- **No `artifacts` declarations.** Harbor's documented artifact examples are
  files, and a missing artifact path could fail a trial. Each verifier instead
  writes its debug bundle into `/logs/verifier/`, which is always downloaded.
- **Seeds are written at step setup, not at image build.** Same CLI gate, same
  validation, and the image stays generic across tasks.
- **The transcript fixtures are synthetic**, not scrubbed captures, and every
  one of them runs well past the 30-line default sweep threshold so the tasks
  exercise the shipped default rather than a lowered one.
- **`recall-baseline` scores only what is achievable without memory**
  (`deploy_succeeded`, `answer_written`), so its oracle can reach 1.0. The
  memory-sensitive assertions are reported as metrics on both halves of the
  pair.
- **`capture-e2e`'s flush step no longer re-sweeps**, because
  `step_log_dir_shared = 0`: it survives as the "did step 1's capture actually
  land" gate over the store.
- **Oracles run the real hook commands.** `eval_sweep` pipes a payload into
  `iwe internal claude hook stop` and `eval_complete_capture` works the queue
  the way the capture agent would — `job next`, then a `job complete --lines`
  per chunk that writes the watermark, the capture note with links and the
  captured stamp, or `eval_triage_capture` for the two-speed drain, which takes
  a `job frontier` batch and completes every entry in it — so an oracle pass exercises the shipped mechanics rather
  than a description of them. `inert-without-memory` goes further and fires the hook
  command straight out of the fixture's `settings.json`.
- **Observations only an oracle can make are metrics, never scores** —
  `hooks_printed_nothing` reads files the oracle
  writes, so scoring it would make a model run fail for the wrong reason.
- **`drain-sizing` certifies the number, and only a live run can.** The gate
  the plan asks for — extraction quality does not regress at the larger budget —
  needs a model in the loop, so `check.sh` proves the plumbing and the
  mechanical half (fewer chunks, the same span, the truncation boundary moved)
  while the quality half waits on a `harbor run`. The `25000`/`7` the init
  skill ships are the plan's proposal, not yet a certified number; if a live run
  shows a regression against `capture-e2e`'s 10000-character baseline, the skill
  text takes the largest value that passes.
- **`drain-triage` scores the shape and reports the cost.** "Full-rigor passes
  bounded by keep-flagged sessions" is not directly observable, so the scored
  checks are the durable outcomes — every span completed, two of them having
  kept nothing, the facts still captured — plus one shape check that the drain
  read the frontier as a batch. The pass counts (`frontier_reads`,
  `single_chunk_reads`, `dedup_searches`) are metrics, read across `-k`
  attempts.
- **Sizing and triage are one choice, not two.** A 25000-character chunk fills
  `job frontier`'s 24000-character batch by itself — both spend the same
  tool-output budget — so the init skill routes on the survey's signal column:
  raised budgets and `job next` for a high-signal backlog, default budgets and
  frontier batches for a low-signal one. The two drain tasks model one mode
  each, which is why `drain-sizing` never reads a batch and `drain-triage`
  never resizes.
- **`inert-on-plain-repo` became `inert-without-memory`**, which covers both
  halves the amendment asks for (no workspace, and a workspace without an
  `MEMORY.md`) plus the drain-from-zero property that makes the gate
  worth having.

## Where this touches the plugin's internals

Almost everything here asserts on behavior — documents in the store, watermarks,
what the session did — so it survives a refactor of how the plugin is
implemented. The places that name plugin internals track the current surface
(hook commands in the `iwe` binary, the workspace at the session's cwd, the
`MEMORY.md` document as the switch):

- `image/setup-lib.sh` — `eval_memory_init` runs `iwe internal claude enable`;
  `eval_hook` and `eval_sweep` run `iwe internal claude hook <event>`;
  `eval_watermark` writes `distilled_lines`; `eval_seed_capture_chunk` writes a
  chunk with the claim stamp of your choosing; `eval_complete_capture` works the
  queue and writes the capture notes; `eval_memory_set` turns a knob.
- `lib/assert.sh` — the graph-state helpers listed above.
- `image/render-settings.sh` — copies `hooks/hooks.json` into a project
  `settings.json`.
- `image/Dockerfile` — bakes the repository in at `/opt/iwe-skills` and
  provisions `iwe` per `IWE_SOURCE` (npm release or a staged local binary).

Nothing asserts on generated document keys beyond the conventions a task's own
policy declares.

## Risks

- **Headless hook drift.** Any of the four probe answers can change with a
  Claude Code release. Pin the build with `--ak version=` for comparable runs
  and re-probe on bumps.
- **Project-settings hooks.** These evals rely on hooks declared in
  `/app/.claude/settings.json` executing under `--permission-mode
  bypassPermissions`. If a build starts gating project hooks behind a trust
  prompt, every capture task goes red and the probe says why.
- **Session cwd.** Hooks and agents use the payload's working directory
  verbatim, so a session started in a subdirectory finds no workspace and memory
  is inert. Every task runs at `/app`, which is where Claude Code starts.
- **Model nondeterminism.** Assertions are lexical, so they key on planted
  identifiers (`DEPLOY_ENV`, `RB-417`, `staging-blue`) rather than prose.
