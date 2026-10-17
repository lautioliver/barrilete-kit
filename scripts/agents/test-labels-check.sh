#!/usr/bin/env bash
# Runs the real script of the `labels` job of .github/workflows/labels.yml with a fake GitHub
# and checks what it says about the PR body (issue #143): an unfilled "<reason>" fails with a clear message.
# Usage: bash scripts/agents/test-labels-check.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=/dev/null
. "$ROOT/scripts/agents/tap.sh"
tap_begin "$0"
# Usage: <condition>; tap_check $? "description"

command -v node >/dev/null || { tap_fail "node is installed"; tap_done; }
node - "$ROOT/.github/workflows/labels.yml" >&2 <<'JS'
const fs = require('fs');
const src = fs.readFileSync(process.argv[2], 'utf8');
// The script of the `labels:` job: the block after its `script: |`, up to the end of the file.
const from = src.indexOf('\n  labels:\n');
const next = src.slice(from + 1).search(/\n  [a-z-]+:\n/);  // the next job, if any is added after this one
const job = next < 0 ? src.slice(from) : src.slice(from, from + 1 + next);
const start = job.indexOf('script: |\n') + 'script: |\n'.length;
const script = job.slice(start).split('\n').map(l => l.replace(/^ {12}/, '')).join('\n');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const run = async (body, { labels = ['type:task'], ref = 'claude/1-x', files = [] } = {}) => {
  const out = { failed: null };
  const pr = { labels: labels.map(name => ({ name })), body, head: { ref } };
  const github = {
    rest: { pulls: { get: async () => ({ data: pr }), listFiles: 'listFiles' } },
    paginate: async () => files.map(filename => ({ filename })),
  };
  const context = { repo: { owner: 'o', repo: 'r' }, payload: { pull_request: { number: 1 } } };
  const core = { setFailed: m => { out.failed = m; }, info() {}, notice() {}, warning() {} };
  await new AsyncFunction('github', 'context', 'core', script)(github, context, core);
  return out.failed;
};
const BL = { labels: ['type:task', 'business-logic'], ref: 'feat/1-x' };
const base = 'Closes #1\n<details><summary>Red before implementing</summary>x</details>\n';
const cases = [
  // [name, body, options, regex the failure must match (null: it must pass)]
  ['ADR unchanged: <reason> fails and says why', 'ADR unchanged: <reason>', BL, /ADR unchanged:.*(placeholder|reason)/i],
  ['ADR sin cambios: <motivo> fails', 'ADR sin cambios: <motivo>', BL, /placeholder/i],
  ['a real ADR reason passes', 'ADR unchanged: the rule is not touched', BL, null],
  ['no ADR line keeps the old message', 'nothing', BL, /add "ADR unchanged: <reason>"/],
  ['no tests: <reason> fails and says why', base.split('\n')[0] + '\nno tests: <reason>', {}, /no tests:.*placeholder/i],
  ['sin tests: <motivo> fails', 'Closes #1\nsin tests: <motivo>', {}, /placeholder/i],
  ['a loose "sin tests" fails with the old message', 'Closes #1\nesto no queda sin tests porque lo cubre otro', {}, /Red before implementing/],
  ['sin tests: with a reason passes', 'Closes #1\nsin tests: es solo docs', {}, null],
  ['the red block passes', base, {}, null],
  // Guards: comments, headings, CRLF and the old shapes that must keep their result.
  ['an ADR exception inside an <!-- --> comment does not count', '<!-- ADR unchanged: a real reason -->', BL, /ADR unchanged/],
  ['ADR unchanged: <reason> followed by a heading fails', 'ADR unchanged: <reason>\n## How to test it', BL, /placeholder/i],
  ['ADR unchanged: <reason> with CRLF line endings fails', 'ADR unchanged: <reason>\r\n## Why\r\n', BL, /placeholder/i],
  ['ADR unchanged: <reason> with a real reason after it, CRLF, passes', 'ADR unchanged: <reason> the rule is not touched\r\n', BL, null],
  ['no tests: <reason> with CRLF line endings fails', 'Closes #1\r\nno tests: <reason>\r\n', {}, /placeholder/i],
  ['no tests: <reason> inside an <!-- --> comment is ignored', 'Closes #1\n<!-- no tests: <reason> -->', {}, /Red before implementing/],
  ['"sin test" without a colon fails', 'Closes #1\nSin test automatizado: es documentación', {}, /Red before implementing/],
  // The literals as the docs show them: in quotes, backticks or bold, with the placeholder still unfilled.
  ['"ADR unchanged: <reason>" (quoted, as AGENTS.md shows it) fails', '"ADR unchanged: <reason>"', BL, /placeholder/i],
  ['`ADR sin cambios: <motivo>` (backticks) fails', '`ADR sin cambios: <motivo>`', BL, /placeholder/i],
  ['**ADR unchanged:** <reason> (bold after the colon) fails', '**ADR unchanged:** <reason>', BL, /placeholder/i],
  ['"no tests: <reason>" (quoted, as the PR template shows it) fails', 'Closes #1\n"no tests: <reason>"', {}, /placeholder/i],
  ['**`no tests: <reason>`** (as implement-issue shows it) fails', 'Closes #1\n**`no tests: <reason>`**', {}, /placeholder/i],
  ['`sin tests: <motivo>` (backticks) fails', 'Closes #1\n`sin tests: <motivo>`', {}, /placeholder/i],
  ['**sin tests:** <motivo> (bold after the colon) fails', 'Closes #1\n**sin tests:** <motivo>', {}, /placeholder/i],
  ['a wrapped real reason passes', 'Closes #1\n`no tests: docs only`', {}, null],
  ['a wrapped real ADR reason passes', '**ADR unchanged:** the rule is not touched', BL, null],
  ['no tests: on its own line, reason on the next one, passes', 'Closes #1\nno tests:\nonly docs', {}, null],
];

// Cases of the old regex-only tests, now through the full script: [body, 1 = it passes / 0 = it fails].
const TESTS_CASES = [["<summary>Red before implementing</summary>",1],["no tests: docs only",1],["No tests: it is config",1],["no test: only docs",1],["No tests:\nonly docs",1],
 ["there is no test coverage here",0],["no tests were added",0],["no test",0],["no tests:",0],["no tests: ",0],["nonetheless no testing",0],
 ["sin test: es solo docs",1],["sin tests: es config",1],["Sin tests:\nes solo docs",1],["<summary>Rojo antes de implementar</summary>",1],["sin test",0],["testear sin testigo",0],
 ["Sin test\nes solo docs",0],["esto no queda sin tests porque lo cubre otro",0],["sin tests es config",0],["sin test es solo docs",0],
 ["no tests: <reason>",0],["no tests:\n<reason>",0],["sin tests: <motivo>",0],["sin test: <motivo>",0],["no tests: <reason> ",0],["sin tests:   <motivo>  ",0],["no tests: <reason> only docs",1],["sin test: <motivo> es config",1],
 ["\"no tests: <reason>\"",0],["`no tests: <reason>`",0],["**`no tests: <reason>`**",0],["**no tests:** <reason>",0],["_no tests: <reason>_",0],
 ["\"sin tests: <motivo>\"",0],["`sin tests: <motivo>`",0],["**sin tests: <motivo>**",0],["**sin tests:** <motivo>",0],
 ["`no tests: docs only`",1],["**no tests:** docs only",1],["\"sin tests: es config\"",1]];
const ADR_CASES = [["ADR unchanged: the rule is not touched",1],["adr unchanged: x",1],["ADR sin cambios: no toca la regla",1],["ADR unchanged:",0],["ADR unchanged: ",0],["ADR sin cambios:",0],["the ADR is unchanged",0],["ADR unchanged because",0],
 ["ADR unchanged:\n\n## How to test it",0],["ADR unchanged: <reason>",0],["ADR sin cambios: <motivo>",0],["ADR unchanged:  <reason>  ",0],["ADR unchanged: <reason> the rule is not touched",1],["ADR sin cambios: <motivo>\n## Por qué",0],
 ["\"ADR unchanged: <reason>\"",0],["`ADR unchanged: <reason>`",0],["**ADR unchanged: <reason>**",0],["**ADR unchanged:** <reason>",0],
 ["\"ADR sin cambios: <motivo>\"",0],["`ADR sin cambios: <motivo>`",0],["**ADR sin cambios:** <motivo>",0],
 ["`ADR unchanged: docs only`",1],["**ADR sin cambios:** no toca la regla",1],["ADR sin cambios:\n## Por qué",0],["<!-- ADR unchanged: <reason> -->",0],["<!-- ADR sin cambios: <motivo> -->",0],["x <!-- c --> ADR unchanged: real reason",1]];
const more = [
  // Reasons that are real but were rejected by the first wrapper fix, and the shapes that must stay rejected.
  ['**ADR unchanged:** with the reason on the next line passes', '**ADR unchanged:**\nthe rule is not touched', BL, null],
  ['**ADR unchanged:** with no reason fails', '**ADR unchanged:**', BL, /ADR unchanged/],
  ['**ADR unchanged:** followed by a blank line and a heading fails', '**ADR unchanged:**\n\n## Why', BL, /ADR unchanged/],
  ['**ADR unchanged:** followed by a heading fails', '**ADR unchanged:**\n## Why', BL, /ADR unchanged/],
  ['plain ADR unchanged: with the reason on the next line still fails', 'ADR unchanged:\nthe rule is not touched', BL, /ADR unchanged/],
  ['_sin tests: es config_ (italic) passes', 'Closes #1\n_sin tests: es config_', {}, null],
  ['_no tests: docs only_ (italic) passes', 'Closes #1\n_no tests: docs only_', {}, null],
  ['_no tests: <reason>_ (italic) reaches the placeholder check', 'Closes #1\n_no tests: <reason>_', {}, /placeholder/i],
  ['no tests: <reason> and the reason on the next line passes', 'Closes #1\nno tests: <reason>\nonly docs', {}, null],
  ['"no tests: <reason>". (trailing period) fails', 'Closes #1\n"no tests: <reason>".', {}, /placeholder/i],
  ['no tests: <reason>, (trailing comma) fails', 'Closes #1\nno tests: <reason>,', {}, /placeholder/i],
  ['no tests: (<reason>) fails', 'Closes #1\nno tests: (<reason>)', {}, /placeholder/i],
];
(async () => {
  let bad = 0;
  for (const [name, body, opt, re] of cases.concat(more)) {
    const failed = await run(body, opt);
    const good = re === null ? failed === null : failed !== null && re.test(failed);
    console.log((good ? 'ok   - ' : 'FAIL - ') + name + (good ? '' : '  (got: ' + JSON.stringify(failed) + ')'));
    if (!good) bad++;
  }
  const table = async (rows, name, opt, prefix) => {
    for (const [body, pass] of rows) {
      const failed = await run(prefix + body, opt);
      const good = (failed === null) === !!pass;
      console.log((good ? 'ok   - ' : 'FAIL - ') + name + ': ' + JSON.stringify(body) + (good ? '' : '  (got: ' + JSON.stringify(failed) + ')'));
      if (!good) bad++;
    }
  };
  await table(TESTS_CASES, 'tests literal', {}, 'Closes #1\n');
  await table(ADR_CASES, 'ADR exception', BL, '');
  // Performance: a hostile body (the author controls it) must not make any regex of the job run for long.
  const N = 10000;
  const hostile = {
    spaces: ' '.repeat(N), stars: '*'.repeat(N), wrappers: '',
    lt: '<'.repeat(N), comments: '<!--'.repeat(N / 2), newlines: '\n'.repeat(N), mixedlines: ' *\n'.repeat(N / 2),
  };
  hostile.wrappers = '*_`"\''.repeat(N / 5) + '*'.repeat(0);
  const CHILD = `const { script, body, opt } = JSON.parse(require('fs').readFileSync(0, 'utf8'));
    globalThis.script = script; globalThis.AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
    const run = ${run.toString()};
    const t0 = performance.now();
    run(body, opt).then(() => console.log(performance.now() - t0));`;
  const both = { labels: ['type:task', 'business-logic'], ref: 'claude/1-x' };
  for (const [kind, x] of Object.entries(hostile)) {
    for (const [what, body] of [['plain', x], ['no tests:', 'Closes #1\nno tests:' + x + '\n\n'], ['ADR unchanged:', 'Closes #1\nADR unchanged:' + x + '\n\n'],
        ['sin tests: <reason>', 'Closes #1\nsin tests: <reason>' + x + '\n'], ['marker in the middle', x + 'no tests:' + x + 'ADR unchanged:' + x]]) {
      // In a child process with a hard timeout: a regex that never finishes must fail the test, not hang it.
      const r = require('child_process').spawnSync(process.execPath, ['-e', CHILD], {
        input: JSON.stringify({ script, body, opt: both }), timeout: 3000, encoding: 'utf8' });
      const ms = r.error || r.status !== 0 ? Infinity : Number(r.stdout.trim());
      const good = ms < 200;
      console.log((good ? 'ok   - ' : 'FAIL - ') + 'performance: ' + N + ' ' + kind + ' (' + what + ') in under 200 ms' + (good ? '' : '  (took ' + (ms === Infinity ? 'over 3 s' : Math.round(ms) + ' ms') + ')'));
      if (!good) bad++;
    }
  }
  process.exit(bad ? 1 : 0);
})();
JS
tap_check $? "the labels check reports the unfilled reasons (full script, fake GitHub)"
# Every job of the workflow has a short timeout (a runaway job must not hold a runner for the 6-hour default).
jobs=$(awk '/^jobs:/{j=1;next} j && /^  [a-z-]+:$/{n++} END{print n+0}' "$ROOT/.github/workflows/labels.yml")
tm=$(grep -cE '^    timeout-minutes: 2( |$)' "$ROOT/.github/workflows/labels.yml")
[ "$((jobs - 0))" -ge 1 ] && [ "$jobs" -eq "$tm" ]; tap_check $? "each job of labels.yml has timeout-minutes: 2" "each job of labels.yml has timeout-minutes: 2 ($tm of $jobs)"
echo
tap_done
echo "All tests pass."
