---
name: distill
description: Distill something worth keeping from the session at hand into this repository's IWE workspace, written in the shape the store's MEMORY.md policy document defines. Use when the user says remember this, note that, distill this, or save this for later, and when you have just established something durable a future session would need. For switching memory on or backfilling past sessions, use the init skill instead.
compatibility: Requires IWE CLI >=0.20.0.
allowed-tools: Bash(iwe:*)
---
!`iwe internal claude prompt distill`

Without injection, run `iwe internal claude prompt distill` and follow it; an unknown command means iwe is older than 0.20.0 — say so and stop.
