# Red command per runner

> Ready-to-copy entries for the `red` section of `docs/agents-map.json` (ADR-002, D2 and D10). `red.sh` runs every entry whose `when` matches a file of the red commit and accepts only a structured report: JUnit XML or TAP.

Each entry has `name`, `when` (globs of test files), `run` (with `{out}`: `red.sh` replaces it with the path where the report must be written), `format` (`junit` or `tap`) and an optional `timeout` in seconds. There is no `report` field. Change the paths, the test globs and the timeout to the project's. `check-docs.py` validates the section. The entries are examples: the reporter options of the corpus (`.claude/skills/implement-issue/corpus/`) are the ones that matter, and go and cargo were checked there only against the documented output of their tools.

## bash (TAP)

A bash test sources `scripts/agents/tap.sh` and calls `tap_check $? "literal id"` for each case; the id is a literal written in the source and what varies goes in the description. `run` must make the helper write to `{out}` through `TAP_OUT`, never redirect stdout. `run-tests.sh` stands for your own script that runs the `test-*.sh` files.

```json
{
  "name": "bash",
  "when": [
    "**/test-*.sh"
  ],
  "format": "tap",
  "run": "TAP_OUT={out} bash run-tests.sh",
  "timeout": 600
}
```

## pytest

`junit_family=xunit1` is needed: the default `xunit2` has no `file` attribute, and without it `red.sh` cannot tell which file a failed case belongs to.

```json
{
  "name": "pytest",
  "when": [
    "**/test_*.py",
    "**/*_test.py"
  ],
  "format": "junit",
  "run": "python3 -m pytest --junitxml={out} -o junit_family=xunit1",
  "timeout": 600
}
```

## vitest

The reporter writes the file of each case in `classname`. Nothing else is needed.

```json
{
  "name": "vitest",
  "when": [
    "**/*.test.ts",
    "**/*.test.tsx"
  ],
  "format": "junit",
  "run": "npx vitest run --reporter=junit --outputFile={out}",
  "timeout": 600
}
```

## jest

Install `jest-junit`. `JEST_JUNIT_TITLE='{title}'` makes the name the one in the source (the default prefixes the `describe` name); `JEST_JUNIT_ADD_FILE_ATTRIBUTE` writes the file; `JEST_JUNIT_REPORT_TEST_SUITE_ERRORS` reports a test file that failed to load as an error, so `red.sh` rejects it instead of reading a green report.

```json
{
  "name": "jest",
  "when": [
    "**/*.test.js",
    "**/*.test.ts"
  ],
  "format": "junit",
  "run": "JEST_JUNIT_OUTPUT_FILE={out} JEST_JUNIT_ADD_FILE_ATTRIBUTE=true JEST_JUNIT_TITLE='{title}' JEST_JUNIT_REPORT_TEST_SUITE_ERRORS=true npx jest --reporters=jest-junit",
  "timeout": 600
}
```

## go (gotestsum)

Install `gotestsum`. A table row added to an old failing test is rejected: the red must add a new `TestX` function.

```json
{
  "name": "go",
  "when": [
    "**/*_test.go"
  ],
  "format": "junit",
  "run": "gotestsum --junitfile {out} ./...",
  "timeout": 600
}
```

## cargo (cargo2junit)

Install `cargo2junit`. `RUSTC_BOOTSTRAP=1` enables the JSON output on stable. `run` executes with `pipefail`, so the failing exit code of `cargo test` survives the pipe. A test needs its `#[test]` attribute (or one that ends in `test]`) directly above the added `fn`.

```json
{
  "name": "cargo",
  "when": [
    "**/*.rs"
  ],
  "format": "junit",
  "run": "RUSTC_BOOTSTRAP=1 cargo test -- -Z unstable-options --format json | cargo2junit > {out}",
  "timeout": 1200
}
```

## cargo (nextest)

Add a profile to `.config/nextest.toml`: `[profile.red.junit]` with `path = "junit.xml"`. nextest writes the report under `target/nextest/red/`, so `run` copies it to `{out}` and keeps the exit code of the tests.

```json
{
  "name": "cargo",
  "when": [
    "**/*.rs"
  ],
  "format": "junit",
  "run": "cargo nextest run --profile red; rc=$?; cp target/nextest/red/junit.xml {out}; exit $rc",
  "timeout": 1200
}
```

## Check it

Run `python3 scripts/agents/check-docs.py` to validate the section, then commit a failing test and run `.claude/skills/implement-issue/red.sh [<stack>]`: exit 0 is a valid red.
