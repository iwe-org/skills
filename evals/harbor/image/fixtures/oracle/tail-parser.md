# Proposals for SESSION_ID

## read -r drops an unterminated last line; parse.sh loops with || [ -n "$line" ]

`while IFS= read -r line` ends before processing a final line that has no trailing newline, because `read` returns non-zero on it — so a config written with `printf '%s'` lost its last key, and an `@include` on that line was silently dropped. src/parser/parse.sh loops with `read -r line || [ -n "$line" ]`, and bin/test.sh covers it as `parser reads an unterminated last line`. The March outage started this way.

## parse.sh normalizes key = value to key=value because releasekit-agent does not trim (RB-659)

releasekit-agent on the deploy hosts splits each parsed line on the first `=` and does not trim, so `key = value` becomes key `key ` with value ` value` and the lookup misses (RB-659). src/parser/parse.sh strips the spaces either side of the first `=` before printing; hand-written configs carry the spaces, generated ones do not.

## @include paths resolve relative to the including file, not the cwd (RB-655)

An `@include path` in a config is resolved relative to the file that contains the directive, never the cwd: releasekit-agent runs the parser from / and the configs live under /etc/releasekit/conf.d (RB-655). src/parser/parse.sh takes the base directory as its first argument and passes each included file's own directory down when it recurses; the first draft resolved against the cwd and was corrected.

## Include depth is capped at 3; deeper exits 7 (RB-661)

Includes nest at most 3 levels deep. An include loop in a generated config took deploy-host-2 down in May (RB-661), and three levels is the deepest any real config goes, so src/parser/parse.sh exits 7 with `parse.sh: include depth exceeds 3 (RB-661)` beyond that, and a failing nested parse propagates its exit code. The cap was set by the user in those terms.
