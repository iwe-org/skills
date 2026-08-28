---
name: distill
description: Read this session with the user and write what they select into this repository's IWE workspace, in the shape the store's MEMORY.md policy document defines — then offer the sessions that came before. Nothing is captured unattended: this is the only write path memory has. Use when the user says remember this, note that, distill this, save this for later, or asks to work through past sessions, and when you have just established something durable a future session would need. For switching memory on for a repository that does not have it, use the init skill instead.
compatibility: Requires IWE CLI >=0.21.0.
allowed-tools: Bash(iwe:*), AskUserQuestion
---
!`iwe internal claude prompt distill`

Without injection, run `iwe internal claude prompt distill` and follow it; an unknown command means iwe is older than 0.21.0 — say so and stop.
