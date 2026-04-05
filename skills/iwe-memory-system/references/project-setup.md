# Project Setup

Use this reference when you need to confirm whether the current workspace is an IWE project and how the project is configured.

Official docs:

- `iwe init`: https://iwe.md/docs/cli/init/
- CLI reference: https://iwe.md/docs/cli/
- Documentation index: https://iwe.md/docs/

## Project marker

An IWE project is identified by:

```text
.iwe/config.toml
```

Running `iwe init` creates that directory and file.

## Example config

Read `.iwe/config.toml` before assuming file locations or defaults. A generated config looks like this:

```toml
# Generated config also contains a top-level `version` field.

[markdown]
# "" means links are written without an extension, e.g. [Doc](key)
# instead of [Doc](key.md).
refs_extension = ""

# Date format used when templates render dates into document content.
date_format = "%b %d, %Y"

[library]
# Where markdown notes live relative to the project root.
# "" means the root directory itself. "docs" would mean ./docs/.
path = ""

# Date format used by key-oriented template variables such as {{today}}.
date_format = "%Y-%m-%d"

# Optional. If set, plain `iwe new "Title"` uses this template.
# default_template = "journal"

[completion]
# Optional. Can be used to prefer markdown or wiki links in completions.
# link_format = "markdown"

[commands.default]
# Default command used by transform-style actions.
run = "claude -p"
timeout_seconds = 120

[actions.extract]
type = "extract"
title = "Extract"
link_type = "markdown"
key_template = "{{id}}"

[actions.extract_all]
type = "extract_all"
title = "Extract all subsections"
link_type = "markdown"
key_template = "{{id}}"

[actions.inline_section]
type = "inline"
title = "Inline section"
inline_type = "section"
keep_target = false

[actions.inline_quote]
type = "inline"
title = "Inline quote"
inline_type = "quote"
keep_target = false

[templates.default]
# File key/path for `iwe new`.
key_template = "{{slug}}"

# Initial markdown content for `iwe new`.
document_template = """
# {{title}}

{{content}}"""
```

## What to look at first

- `library.path`: determines where notes actually live.
- `library.default_template`: changes what plain `iwe new` uses.
- `markdown.refs_extension`: affects whether links include `.md`.
- `actions.*`: `iwe extract --action ...` and `iwe inline --action ...` resolve here.
- `templates.*`: controls how `iwe new` names files and renders content.

## Working notes

- Check `.iwe/config.toml` before searching for note files manually.
- If `iwe` behavior seems surprising, inspect config before assuming a bug.
- Re-running `iwe init` in an existing project does not overwrite the config.
