# Working in everything

This is a dirigent project: pipelines are YAML documents under `pipelines/`, checked and run by
the `dg` command line this project pins. These notes are for whoever edits it, a person or a
coding agent.

## The loop

Every command goes through `uv run dg`, so it runs the dirigent version `pyproject.toml` pins.

1. **Find what exists before writing anything.**
   - `uv run dg examples list --local` lists the documents every installed plugin ships, and
     `uv run dg examples show CODE --local` prints one verbatim. Copy from the closest one.
   - `uv run dg pipeline new STARTER` copies a starter into `pipelines/` as a pipeline of its own;
     `uv run dg examples list --local --starter` names the starters.
   - `uv run dg blocks list --local` lists every block, and `uv run dg blocks show BLOCK --local`
     gives its config and output schemas.
   - `uv run dg pipeline schema -f .dirigent/document.schema.json` writes the JSON Schema a
     document is checked against, every installed block's config included. A document whose first
     line is `# yaml-language-server: $schema=../.dirigent/document.schema.json` is checked by any
     editor that reads that comment.
2. **Check it offline:** `uv run dg validate pipelines/NAME.yaml`. `--explain` adds how wide the
   work is, how many tries it may take and how long it may run.
3. **Run it in a throwaway instance:** `uv run dg run --local pipelines/NAME.yaml`, with `-v` to
   see every step's output. A pipeline that starts at a source takes `--input '{...}'`, or runs
   with its source's `sample`.
4. **Apply it to an instance** once it runs: `uv run dg apply`, then `uv run dg run CODE --watch`.
   `uv run dg dev` starts a local instance with its web UI; it keeps running, so a person starts it
   in a terminal of its own.

## Reading what dg says

Outside a terminal, which is every agent's shell, every `dg` command writes NDJSON: one JSON
record per line, each with a `kind`. Select with `jq`, for example
`uv run dg run --local pipelines/NAME.yaml | jq -c 'select(.kind == "run")'`.

- A document that does not validate is a `validation` record with `message` `invalid` and
  `problems[]`, each with a stable `code`, a `message` and the `location` in the document it is
  about. Fix what `location` names, then validate again.
- Anything else refused is a record of kind `error`, with a stable `code`, the `params` it was
  built from, and `problems[]` where there is more than one thing to say.
- A run's stream is `run`, `step`, `log` and `output` records, and the closing `run` record
  carries every step's outcome, its output and the failures. `exit_code` is the command's own.
- `uv run dg runs show RUN_ID`, `uv run dg runs logs RUN_ID` and `uv run dg runs profile RUN_ID`
  read a run an instance holds.

## Rules that are easy to get wrong

- A document starts `format: dirigent/v1`, `kind: pipeline`, and a `code` in lowercase with
  dashes. A step is exactly one of `block`, `source` or `reply`.
- Values move between steps by reference, never by copying: `${params.NAME}`,
  `${steps.STEP.output.FIELD}`, and `${item}` inside a `for_each`. A step that reads another's
  output lists it under `depends_on`.
- Secrets never go in a document. A connection holds them, created once with
  `uv run dg connection create KIND CODE`, and a step names it by its code.
- `.dirigent/state/` and `.env` belong to the local instance; they are not edited by hand.

## Reading further

The documentation is at https://winterop-com.github.io/dirigent/, and
https://winterop-com.github.io/dirigent/llms.txt lists every page with what it covers. The
installed examples are the most reliable reference, because each one is run by dirigent's own
tests.
