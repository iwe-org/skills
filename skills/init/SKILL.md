---
name: init
description: Turn this repository's IWE workspace into one that remembers — write the MEMORY.md policy document that switches memory on, in the shape the store already uses, then drain the sessions that already happened into it. Use when the user asks to set up, initialize, install, bootstrap, or onboard memory; to backfill or process past sessions; or to catch memory up on a project it has never seen.
compatibility: Requires IWE CLI >=0.20.0.
allowed-tools: Bash(iwe:*)
---
!`iwe internal claude prompt init`

Without injection, run `iwe internal claude prompt init` and follow it; an unknown command means iwe is older than 0.20.0 — say so and stop.
