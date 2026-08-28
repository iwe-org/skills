---
name: init
description: Turn this repository's IWE workspace into one that remembers — write the MEMORY.md policy document that switches memory on, in the shape the store already uses, then scope the sessions already on disk and hand them to the distill skill. Use when the user asks to set up, initialize, install, bootstrap, or onboard memory, or to catch memory up on a project it has never seen.
compatibility: Requires IWE CLI >=0.21.0.
allowed-tools: Bash(iwe:*), AskUserQuestion
---
!`iwe internal claude prompt init`

Without injection, run `iwe internal claude prompt init` and follow it; an unknown command means iwe is older than 0.21.0 — say so and stop.
