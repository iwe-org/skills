## IWE Agentic AI Skills

Main repository is here https://github.com/iwe-org/iwe

## Available skills

### `iwe-v18`

Use `iwe-v18` with IWE CLI 0.18 and later. It gives agents bounded, graph-aware routes for finding, retrieving, creating, and safely refactoring notes without falling back to broad filesystem searches.

Requirements:

- an IWE workspace;
- IWE CLI `>=0.18.0`;
- an agent runtime that supports skills.

Install with:

```bash
npx skills add iwe-org/skills --skill iwe-v18
```

See the [skill](skills/iwe-v18/SKILL.md), the [IWE repository](https://github.com/iwe-org/iwe), and the [IWE documentation](https://iwe.md/docs/) for details.

### `iwe-memory-system`

Use the `iwe` skill when an agent is working inside an IWE knowledge graph and should prefer the `iwe` CLI for graph-aware reads and refactors instead of ad-hoc markdown edits.

Install with:

```bash
npx skills add iwe-org/skills --skill iwe-memory-system
```
