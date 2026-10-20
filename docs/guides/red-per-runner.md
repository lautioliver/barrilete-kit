# Red command per runner

> Ready-to-copy entries for the `red` section of `docs/agents-map.json` (ADR-002, D2 and D10). `red.sh` runs every entry whose `when` matches a file of the red commit and accepts only a structured report: JUnit XML or TAP.

Each entry has `name`, `when` (globs of test files), `run` (with `{out}`: `red.sh` replaces it with the path where the report must be written), `format` (`junit` or `tap`) and an optional `timeout` in seconds. There is no `report` field. Change the paths, the test globs and the timeout to the project's. `check-docs.py` validates the section. The entries are examples: the reporter options of the corpus (`.claude/skills/implement-issue/corpus/`) are the ones that matter, and go and cargo were checked there only against the documented output of their tools.

## bash (TAP)

A bash test sources `scripts/agents/tap.sh` and calls `tap_check $? "literal id"` for each case; the id is a literal written in the source and what varies goes in the description. This is the entry the kit ships in the default `docs/agents-map.json`. It runs only the `test-*.sh` files the red commit adds or changes, each one with `TAP_OUT={out}` (the helper writes there, never redirect stdout), and checks that each script wrote its `# file: <path>` line: a script that dies before it sources `tap.sh` leaves no cases, and without that check a valid failure of another script would hide it, so the entry appends `Bail out!`. If you write your own entry, keep that check.

```json
{
  "name": "bash",
  "when": [
    "**/test-*.sh"
  ],
  "format": "tap",
  "run": "rc=0; while IFS= read -r -d '' t; do TAP_OUT={out} bash \"$t\" </dev/null || rc=1; grep -qxF \"# file: $t\" {out} || echo \"Bail out! $t wrote no TAP\" >>{out}; done < <(git diff -z --name-only --diff-filter=AM HEAD^ HEAD -- ':(glob)**/test-*.sh'); exit $rc",
  "timeout": 1800
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

Add a profile to `.config/nextest.toml`: `[profile.red.junit]` with `path = "junit.xml"`. nextest writes the report under `target/nextest/red/`, so `run` copies it to `{out}` and keeps the exit code of the tests. The `rm -f` runs first so a failed build cannot leave a report from an earlier run to be copied. This entry is unverified: the command, the profile path and the copy step were never run here (the corpus has a handwritten nextest report only).

```json
{
  "name": "cargo-nextest",
  "when": [
    "**/*.rs"
  ],
  "format": "junit",
  "run": "rm -f target/nextest/red/junit.xml; cargo nextest run --profile red; rc=$?; cp target/nextest/red/junit.xml {out}; exit $rc",
  "timeout": 1200
}
```

## Dependencies in a fresh worktree

A new worktree has no `.venv` or `node_modules`, and the entries above need them (`.venv/bin/python`, `npx vitest`). The **implementer** installs them in its worktree before the red (`python3 -m venv .venv && .venv/bin/pip install -r requirements.txt`, `npm ci`). The **reviewer** installs them in its review worktree without running PR code: `npm ci --ignore-scripts` (only if the PR does not change `package.json`, the lock file or `.npmrc`) or `python3 -m pip install --only-binary=:all: -r requirements.txt` (only if the PR does not change `requirements*.txt`, `pyproject.toml` or `setup.*`: pip has no `--ignore-scripts`, and a source build or `-e .` would run the PR's build backend). If the PR changes those files it does not install, flags it, and the TDD check stays unverified until a person decides. Never run the PR's own installer or scripts.

## Check it

Run `python3 scripts/agents/check-docs.py` to validate the section, then commit a failing test and run `.claude/skills/implement-issue/red.sh [<stack>]`: exit 0 is a valid red.
