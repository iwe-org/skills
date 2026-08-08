# Rare IWE errors

Read this file only when stderr does not explain the failure or when deciding whether fallback is permitted. Do not read it during a normal successful request.

## Decision table

| Signal | One permitted response | Fallback? |
|---|---|---|
| `iwe: command not found` or executable missing | Report that IWE is unavailable. Do not install it. | Yes, narrowly |
| Unknown command or option | Read command-specific help, correct once, retry once. | Only if still unsupported |
| Invalid YAML/filter | Correct shell quoting or YAML shape once. | No |
| Empty result | Refine search mode or query once. | Yes, only after refinement |
| Unsupported operation | Report the unsupported operation. | Yes, narrowly |
| Data outside workspace/index | Identify the unindexed source. | Yes, for that source |
| Truncation warning | Use returned evidence or narrow the query; do not raise limits reflexively. | No |
| Permission or I/O failure | Report the path and error without changing permissions. | Only for another authorized source |
| Schema or expectation failure | Do not mutate; narrow the target or fix the guarded input. | No |

## Stable classifications

- `iwe_unavailable`: executable cannot be started.
- `unsupported_cli_version`: installed CLI is older than 0.18.
- `cli_contract_mismatch`: a known command or option is rejected.
- `unsupported_operation`: IWE explicitly cannot perform the requested operation.

These names classify failures for reporting and evals. They do not authorize installation, reconfiguration, broad filesystem scans, or destructive retries.

## Retry ceiling

At most one syntax correction and one corrected retry are permitted. At most one query refinement is permitted after an empty result. Stop after those ceilings and either use an allowed narrow fallback or report the blocker.
