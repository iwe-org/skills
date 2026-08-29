---
name: reflect
description: Reorganize this repository's memory with the user — edit the MEMORY.md policy that governs what gets captured and how, analyze the store's frontmatter, propose new index fields, backfill them, group notes into areas with hub pages and subdirectories, extract the people, releases, components, tools and other entities the notes keep mentioning into typed pages the notes link to, prune or merge documents on request, and tune the knobs that pace reading and reminders. Use when the user asks to clean up, reorganize, group, audit, prune, or forget parts of memory, to structure the store into folders, areas, or hubs, to pull entities out of the notes and connect them, to change what memory captures, or to make the store more queryable.
compatibility: Requires IWE CLI >=0.21.0.
allowed-tools: Bash(iwe:*)
---
!`iwe internal claude prompt reflect`

Without injection, run `iwe internal claude prompt reflect` and follow it; an unknown command means iwe is older than 0.21.0 — say so and stop.
