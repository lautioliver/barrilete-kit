# ADR-002 — Structured validation of the red test

## Status

Accepted (2026-10-17)

Origin: epic lautioliver/barrilete-kit#148 and issue lautioliver/barrilete-kit#149. Decisions D1–D10 approved by @lautioliver in the chat (2026-10-17): D1–D7 and D10 as recommended, D8 option (a) and D9 approved. Amendments of the review of PR lautioliver/barrilete-kit#156, decided by @lautioliver in chat, 2026-10-17: D11 (this ADR lives in `docs/decisions/kit/`), the `--small` profile in D2, the per-case rule of D4 and the trusted `red` section of D7. Where a rule below says "decided by @lautioliver in chat, 2026-10-17", that is the approval.

Refinements written in the review of PR lautioliver/barrilete-kit#156 and not decided separately by the person: D2 (an array of stacks with `name`/`when`, no `report` field, `{out}` inside `run`, no `red.sh -- <command>`, `red.sh <stack>`, running every entry whose `when` matches, with no match exiting 2); D3 (exit code 64, the 20 MB and UTF-8 limits, rejecting `DOCTYPE`, and the definitions of skipped, TODO and aborted); D9 (the required `stack:` line, which adds a requirement to the CI check). They are approved when PR lautioliver/barrilete-kit#159, which records them, is merged.

Corrections of lautioliver/barrilete-kit#158 (amending this ADR was approved by @lautioliver in chat, 2026-10-17; they make rules stricter, fix text, or make the name comparison of D4 workable for jest, vitest and go): the matching rule of D4, where the TAP of D6 is written, the D3 detail on `testsuite`, and the wording of D11.

Amendments of lautioliver/barrilete-kit#150, decided by @lautioliver in chat, 2026-10-17 (the three open decisions of D4 that the second review of PR lautioliver/barrilete-kit#159 left): the cargo rules (a test attribute on the added `fn`, how far the module path is trimmed, workspaces and nextest), parametrized and table tests (compared by base name), and names built at run time (a literal TAP id; `it.each` templates with wildcards).

Decided by @lautioliver in chat, 2026-10-17, in the review of PR lautioliver/barrilete-kit#164: for cargo, the test attribute is read in the file of the red commit, directly above the added `fn` (git can show it as a context line when the new test is inserted before another one with the same attribute; a `fn` without the attribute, like a stub, still does not count), which is looser than "in the added lines" and is approved as such; D6 is not amended here (the narrower `ERR` behaviour of tap.sh is being redesigned in lautioliver/barrilete-kit#165).

Refinements written while implementing lautioliver/barrilete-kit#150 and not decided separately by the person. They only make the rules stricter or say how a reporter's output is read; `scripts/agents/red_report.py` and the corpus are their detail: a `failure` that is not a test counts as an `error` (vitest reports a file that did not load as a case named like its file; gotestsum reports a package that failed outside any test as `TestMain`); a `testsuite` that declares more `failures` or `errors` than its cases carry, or that holds an `error` or `failure` outside any case, is rejected; in a go package a new file does not make every case of the package new; a `file` that two files of the repository end with is not mapped; `red.sh` rejects uncommitted changes in tracked files, because it validates the commit and not the working tree; a report with NUL bytes (UTF-16 without a BOM looks like UTF-8) is rejected; for `format: "tap"`, `red.sh` exports `TAP_OUT` with the path of `{out}`. They are approved when the PR of lautioliver/barrilete-kit#150 is merged.

Decided by @lautioliver in chat, 2026-10-17, in the review of PR lautioliver/barrilete-kit#164 (recorded by lautioliver/barrilete-kit#166): the kit's own `red` section in agents-map.json, with the `bash` entry for its `test-*.sh`, is added in lautioliver/barrilete-kit#164 so the repo has a working red when that PR merges, instead of waiting for lautioliver/barrilete-kit#152, #153 and #154. D7 treats a change to `red` as sensitive, and this is its approval. The entry runs only the `test-*.sh` the commit adds or changes, and after each script it checks that the script left its `# file:` line in `{out}`: if it did not (it died before sourcing `tap.sh`), it appends a `Bail out!`, so a load error in one script is never hidden by a valid failure in another (D3). `red_report.py` parses a JUnit report as UTF-8 whatever its declaration says, and rejects a declaration of another encoding however it is written (spaces or tabs around `=`, a BOM before it).

Implementation state: `red.sh`, `scripts/agents/red_report.py` (lautioliver/barrilete-kit#150), `tap.sh` (lautioliver/barrilete-kit#163) and the kit's own `red` entry already implement D1, D3, D4 and D5, and `red.sh` no longer takes a command. The check-docs.py validation of the `red` entries (D2), the structured PR block and the migration of the projects (`init`, `update`, the small profile) are still missing: until the other issues of the epic land, a checkout whose docs/agents-map.json has no `red` section gets the rejection with a guide of D1. This note is removed by the amendment that closes lautioliver/barrilete-kit#154 (the projects do not edit the ADRs of `kit/`, so it would go stale).

## Context

- `red.sh` (step 3 of `implement-issue`, the TDD table of `review-pr`) decides whether a test fails "for the right reason" by matching regexes over the runner's output: a list of load errors, a list of assertion patterns, and everything else is rejected.
- Free text does not scale: any new runner, language or crash shape lands on the wrong side. In lautioliver/barrilete-kit#146, two rounds of accepting more formats with lists of crashes ended with the reviewer finding cases that passed as a valid red both times.
- There is no timeout, and it does not tell the failures of the new tests from an old test that was already broken.
- The block that goes into the PR is free text the reviewer cannot compare against anything.
- The kit's own 12 `test-*.sh` each define their own `ok()`/`fail()`, and the docs CI only looks at the exit code.
- The format is documented nowhere (end-to-end test of lautioliver/barrilete-kit#115).

## Decision

1. **D1. The only evidence is a structured report (JUnit XML or TAP).** Without a report, `red.sh` exits with 2 and explains how to configure the reporter. There is no text fallback: it is exactly the hole to close.

2. **D2. The project declares how to get the report in a `red` section of agents-map.json.**
   - **Shape.** `red` is an array, like `verify`. Each entry is a stack: `{"name": "...", "when": ["<glob of test files>"], "run": "...", "format": "junit"|"tap", "timeout": 600}`. `timeout` is optional (D5).
   - **There is no `report` field.** `{out}` must appear in `run`. `red.sh` replaces it with a temporary path of its own, deletes the file before running and requires that it was created in this run, so an old report cannot be reused. `check-docs.py` rejects an entry whose `run` has no `{out}`, whose `format` is not `junit` or `tap`, or that has no `when`.
   - **Which entry runs.** `red.sh` runs every entry whose `when` matches a file changed by the red commit (D4's diff), one after another, and the red is valid only if each one is valid. If no entry matches, it exits with 2. `red.sh` no longer takes a command: `red.sh -- <command>` is gone, because a command typed by the agent is a path outside the declared evidence (D1, D8). `red.sh <stack>` runs only the entry with that name, for the implementer's iterations.
   - **stdout and the exit code.** `run` executes with `bash -o pipefail -c`. `red.sh` does not capture stdout. `format: "tap"` means the TAP of the helper of D6, and `run` must make the helper write to `{out}`, never redirect stdout (`bash tests/run.sh > {out}`): on stdout, a test that prints `ok`/`not ok` lines injects cases into the stream. A TAP producer that can only write to stdout (`node --test`, `prove`) is converted to JUnit. With `pipefail`, a pipeline such as `cargo test | cargo2junit > {out}` keeps the failing exit code.
   - **The `--small` profile.** It declares `red` in a minimal docs/agents-map.json that contains only the `red` section (decided by @lautioliver in chat, 2026-10-17). The tools that read the map treat a missing section as empty. This ADR only decides it: the file itself and the reading code belong to the issues of the `red` section and of the profile, and to the migration issue.

3. **D3. A red is valid only if all of this holds at once:**
   - the exit code of `run` is not 0;
   - the report exists, was generated in this run and parses;
   - at least 1 case was executed;
   - at least 1 `failure` (an assertion);
   - **0** `error`;
   - no aborted case;
   - no timeout and no signal (a negative `returncode` in Python, or an exit code above 128).

   The exit code alone is never enough. Definitions:
   - **Failure and error, JUnit.** A `testcase` with a `failure` child is a failure. One with an `error` child is an error.
   - **Failure and error, TAP.** A `not ok` is a failure. A `Bail out!` is an error. `not ok … # TODO` is not a failure: it is an expected failure. `ok … # TODO` is an unexpected pass and counts as an executed, passing case.
   - **Executed.** A case is executed if it is not skipped. Skipped: a `skipped` child (JUnit), `# SKIP` or `not ok … # TODO` (TAP). A report with only skipped cases has no executed case: exit 2.
   - **Aborted.** JUnit: the XML is truncated or does not parse, or the `tests` attribute of a `testsuite` does not match the `testcase` elements it contains, nested `testsuite` elements included (a `testsuite` without a `tests` attribute is not compared: its cases still count; the root `testsuites` is not compared). TAP: there is no plan (`1..N` at the start or at the end), the plan does not match the number of cases, or the stream ends without the plan.
   - **Parser safety.** The report is rejected if it has a `<!DOCTYPE` (JUnit never needs one; this also closes internal entity expansion on old expat versions), if it is larger than 20 MB, or if it is not UTF-8.
   - **Exit codes of `red.sh`.** 0: valid red. 1: the tests pass (exit code 0 and a report with no failure or error). 2: rejected for any other reason, including a `run` that exits 0 with failures in the report (inconsistent) and any internal error. 64: wrong usage. `implement-issue`, `review-pr` and the tests of `red.sh` depend on this contract.

4. **D4. "New" is decided per test case, not per file, and every failed case must be a case that the red commit adds or changes** (decided by @lautioliver in chat, 2026-10-17). Otherwise an old broken test, even inside a file the red commit touches, would "prove" the TDD of any PR.
   - **The diff.** The red commit against its first parent. The red commit is a single commit and holds the tests (and stubs, if needed); the sha in the PR block (D7) is that commit's.
   - **The rule.** A failed case is valid if (1) it can be mapped to a file (table below), (2) that file is in the diff, and (3) the case's name, without its parameters (`test_x[1]` is `test_x`), appears as a whole identifier, in a line added by the diff in that file that defines the test (`def`, `fn`, `func`, `it(`/`test(`, or the case line of `tap.sh`), never in a comment. A whole identifier: `test_parse` does not match an added `def test_parse_empty`, and a mention in a comment or a call does not count. For `it(`/`test(`, where the name is a string, the whole string literal: `it('parses')` matches only a line with the literal `'parses'` (or `"parses"`), never `it('parses empty input')`. In a file the diff adds, every case qualifies. A case whose body changed but whose name did not appear in an added defining line is rejected: over-rejecting is accepted, the goal is to fail closed.
   - **The name compared.** It is the name that appears in the source, so the reporter has to give it that way: jest-junit with `titleTemplate="{title}"` (its default `"{classname} {title}"` prefixes the `describe` name); vitest, the last segment of the name, after the last ` > `; go, the first segment of a subtest (`TestX/case` compares `TestX`, the only one with a `func` line; a table row added to an old failing `TestX` is rejected: the row is not a `func` line, so it cannot be told from the old rows, and the red must add a new `TestX`). The exact options are checked with the corpus of lautioliver/barrilete-kit#150.
   - **Parametrized and table tests** (decided by @lautioliver in chat, 2026-10-17). The name compared is the base name, without the `[...]` suffix of pytest and the `/...` of go (`test_p[1-2]` is `test_p`, `TestX/row` is `TestX`). The definition of the base test has to be in the added lines. A new parametrized test passes. A new row in an old test is rejected (exit 2): fail closed, because the row cannot be told from the old rows.
   - **Ambiguous names.** The name is compared without its `describe` or class, so a name that appears more than once among the report's cases of that file (`it('works')` in `describe('A')` and in `describe('B')`, `TestA::test_x` and `TestB::test_x`) is ambiguous: `red.sh` exits with 2 and says to rename the test. The cases of one parametrized test (same class, same base name) are not ambiguous. In go, `package x_test` and an internal test with the same name give the same `classname`: the same full name twice in a package is ambiguous.
   - **Names built at run time** (decided by @lautioliver in chat, 2026-10-17). TAP: the helper of D6 takes as its first argument a literal id of the case, and `red.sh` compares only that id; the part that varies (a loop variable) goes in a description that is not compared. `it.each` of jest and vitest: the title in the code, with its markers (`%s`, `$x`, `${...}`) as wildcards, has to match the whole name, and the line of the template has to be an added line (when the table takes several lines, the line that closes it, which carries the title).
   - **Fail closed.** A failed case that cannot be mapped to a file added or changed by the diff makes `red.sh` exit with 2 and say which reporter option is missing. There is no exception per runner.
   - **Per format.**

     | Runner | Reporter | File of a case |
     |---|---|---|
     | bash | TAP from the helper of D6 | the `# file: <path>` comment line that precedes the cases of that script |
     | pytest | `--junitxml={out} -o junit_family=xunit1` (the default `xunit2` has no `file`) | the `file` attribute |
     | jest | `jest-junit` with `addFileAttribute=true` and `titleTemplate="{title}"` | the `file` attribute |
     | vitest | `--reporter=junit --outputFile={out}` | `classname`, which is the file path |
     | go | `gotestsum --junitfile {out}` | `classname` is the package import path: it is turned into a directory with the module line of `go.mod`, and the name must appear in an added line of a `*_test.go` file of that directory |
     | cargo | `cargo2junit` or `nextest` (`junit`) | `classname` is a module path, not a file: it is mapped to one (decided by @lautioliver in chat, 2026-10-17). The crate name is dropped; `a::b::tests` maps to `src/a/b.rs` or `src/a/b/mod.rs`, and trailing segments are dropped one by one (an inline `mod tests` lives in its parent's file) until a file exists, never past the root of the crate: `src/lib.rs`, `src/main.rs` or `tests/<binary>.rs`. Workspaces are resolved with the members of the root `Cargo.toml`. With nextest, the crate and the binary come from the binary id in `classname` and the module path comes from the name. The whole identifier must appear in an added `fn` line of that file, with a test attribute above it: `#[test]`, or one that ends in `test]` such as `#[tokio::test]` (a `fn` without one, like a stub, does not count); and the file must be in the diff. If it does not resolve to a file, `red.sh` exits with 2. The corpus checks the exact `classname` each reporter writes |

     Any other runner follows the same rule: if it gives `file`, or a `classname` that is a path, it is used; if not, the reporter has to be configured to give it, or the red is rejected.
   - **TAP.** One stream for the whole run, with a single plan; the helper writes `# file: <path>` before the cases of each script. A `not ok` with no `# file:` before it is unmappable: exit 2. The id of a case is the text of its `ok N - <id>` line with the TAP 14 escapes undone (`\#` is `#`, `\\` is `\`), and `red.sh` compares it with the literal first argument of `tap_ok`, `tap_fail` or `tap_check` in an added line: a line that only mentions the id (an `echo`, a variable) does not define the case. What varies at run time goes in `# desc:` lines, which are not compared (`not ok 3 - lang-installs`, then `# desc: installs fr`); a repeated id is one case.

5. **D5. Timeout: 600 s by default, configurable with `"timeout"` (in seconds) in each `red` entry.** It covers the whole run, not each case. It is applied with Python, because `timeout` does not exist on macOS. `run` starts in its own process group, and on timeout `red.sh` kills the whole group, not only the child, so that no runner keeps writing to `{out}`. After a timeout, `red.sh` exits with 2.

6. **D6. The kit's tests use the same rule it demands.** A helper, scripts/agents/tap.sh (created by lautioliver/barrilete-kit#151), writes TAP 14: `ok N - x`, `not ok N - x`, `# file: <script>` before the cases of each script, one `1..N` plan, and `Bail out!` on an unexpected error through `trap ERR`. The TAP is written to a file that `red.sh` creates (`{out}`), never to stdout: a test that prints `ok`/`not ok` lines by accident then cannot inject cases. A test runs in the same shell as `tap.sh`, so it can see the path: a deliberate write to the file is not closed, and lautioliver/barrilete-kit#151 should keep the path out of the test's reach where it can. How the helper receives the path (argument or variable) is decided in lautioliver/barrilete-kit#151. The 12 `test-*.sh` migrate to it. `red.sh` takes a `Bail out!` as an error.

7. **D7. The reviewer checks it again, with the `red` of the base branch.**
   - **The block.** The PR carries, in "How to test it", exactly this (the lines are literals, they are not translated; only the title also accepts the Spanish `Rojo antes de implementar`):

     ```
     <details><summary>Red before implementing</summary>

     red commit: <sha of the red commit>

     stack: <name of the red entry>
     format: junit
     failing cases:
     - <file>::<name>
     - <file>::<name>

     </details>
     ```

     `red commit:` appears once. Then there is one group (`stack:`, `format:`, `failing cases:`) per `red` entry that ran (D2), so a red commit that touches two stacks has two groups. `<file>` is the file of D4 (or the `classname` when the report gives no file), `<name>` is the name of the case, one case per line.
   - **The check.** The reviewer runs the `red.sh` of the **trusted checkout** (the base branch) on that commit, in its review worktree, and compares, group by group (by `stack`), the list of failing cases with the one in the block as a set: order and repeats do not matter. A stack with no group, or a group of a stack that did not run, is a mismatch. If they do not match, it is a finding to fix.
   - **Where `red` comes from.** The reviewer's `red.sh` reads the `red` section from the trusted checkout on the base branch, never from the PR (decided by @lautioliver in chat, 2026-10-17). If it read it from the red commit, a PR could set `run` to any command and the reviewer would run it. A PR that changes the `red` section is a sensitive change: it needs the approval of a person, like CI, and the reviewer validates with the base's section meanwhile. When the base has no `red` yet, there is nothing to trust and the person decides.
   - This keeps the rule of point 8 approved in lautioliver/barrilete-kit#146: the reviewer runs only the PR's tests, not other code from the PR.

8. **D8. It lands before v1.0, as a breaking change, with no text mode.** Epic lautioliver/barrilete-kit#148 blocks lautioliver/barrilete-kit#91. A project without a `red` section gets a rejection with a guide on how to add it; there is no transition mode. Changing this after `v1.0.0` would be a break.

9. **D9. The CI check also requires structure.** Besides the `Red before implementing` title (or `Rojo antes de implementar`: the check accepts both), `labels.yml` requires the `red commit:` line (a hexadecimal sha) and at least one group with a `stack:` line, a `format:` line (`junit` or `tap`) and, under `failing cases:`, at least one line `- <file>::<name>`. It goes in the same PR as D7. CI is a sensitive path: approved by @lautioliver in the chat (2026-10-17).

10. **D10. Reference runners:** bash (TAP), pytest (`--junitxml`), vitest and jest (`junit` reporter), go (`gotestsum --junitfile`) and cargo (`cargo2junit` or `nextest`). They are documented and tested in the corpus. Any other runner follows the generic rules of D1–D5. They are the ones with a documented JUnit or TAP reporter in the stacks the kit's users have today.

11. **D11. The kit ADRs that projects install live in `docs/decisions/kit/`** (decided by @lautioliver in chat, 2026-10-17). This ADR is `docs/decisions/kit/ADR-002-…`. The project's own ADRs go in `docs/decisions/`, numbered from `ADR-001` with no gaps, independently of the kit's numbers (they live in another folder, so the two numberings do not collide). `check-docs.py` reads both folders, the index lists each ADR with its path, and two ADRs with the same number in different folders are not mixed up. The init keeps `docs/decisions/kit/` in the language of the installation, like the rest of the docs. A project should not edit the ADRs of `kit/` (a recommendation, not something `check-docs.py` enforces): if it needs another rule, it writes its own ADR that refers to the kit's. A bare `ADR-NNN` mention resolves against both folders, so it is ambiguous when the same number exists in both; the kit cites its own as `kit/ADR-002`.

## Rejected alternatives

- **A structured report, or text as a fallback (D1).** The text fallback is the hole that lautioliver/barrilete-kit#146 could not close.
- **An environment variable the project reads for the report path (D2).** It is not declared anywhere, `check-docs.py` cannot validate it, and the path is not controlled by `red.sh`.
- **A `report` field next to `run`, or a fixed path (D2).** If `report` were always `{out}` it would be redundant, and if it could be a fixed path `red.sh` would lose control of it.
- **The exit code alone, or the exit code plus a text match (D3).** The exit code does not tell an assertion from a crash, and a text match is the hole of D1 again.
- **Not checking that failures belong to new tests (D4).** An old broken test would turn any PR's red into valid.
- **New by file instead of by case, or new by running the tests at the parent commit (D4).** By file, an old broken test in a file that the red commit touches would pass. At the parent, the run fails open: if it does not load, no case is known and every case would look new.
- **A fixed timeout only (D5).** Some suites are legitimately slower than others.
- **Leaving the kit's tests as they are and accepting `FAIL - ` as de-facto TAP (D6).** The kit would not be validated by the rule it demands.
- **The reviewer not re-verifying, only reading the block (D7).** The block is a claim by the author that nothing backs. **The reviewer reading `red` from the PR (D7)** lets the PR choose the command the reviewer runs.
- **Entering in 1.1 with a transition period and a warning mode (D8).** It keeps the text path alive, which is exactly what D1 removes, and a break after v1.0 costs more.
- **Checking only the title of the block (D9).** A block with the title and nothing else would pass, and the reviewer would have nothing to compare.
- **Other runners as reference, or none (D10).** Other runners would be chosen without a reason, or each project would work out its reporter alone and untested.
- **Numbering the kit ADRs in the project's folder (D11)**, renumbering at the init, or documenting a gap. They collide with the project's own numbers and with future kit ADRs, and a renumbered file no longer matches what the kit updates.

## Consequences

- A red is accepted only with evidence an agent cannot fake by accident with a message in the output; the reviewer can compare it. A test that deliberately writes the report file is out of reach of the parser: the block of D7 and the reviewer's rerun are what catch it.
- It costs initial work per project: configuring the reporter. It is eased with defaults in the `init` for bash and copy-ready examples of `agents-map.json` per runner.
- False rejections will happen (a badly configured runner does not produce the report, or the per-case rule is stricter than the change): the messages say what to configure. Over-rejecting is accepted: failing closed is the goal.
- Out of scope: coverage, mutation testing, retrying flaky tests and validating the green (the project's CI keeps doing that).
- What changes is in the rest of epic lautioliver/barrilete-kit#148: the TAP helper and the migration of the 12 tests, `red.sh` with its parser (scripts/agents/red_report.py, created by lautioliver/barrilete-kit#150) and its corpus, the `red` section and its validation, the structured PR block and the `labels.yml` check, the migration of existing projects (the update and grow scripts, the installer and the CHANGELOG), and the end-to-end test.
