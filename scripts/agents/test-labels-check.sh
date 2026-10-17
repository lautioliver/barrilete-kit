#!/usr/bin/env bash
# Runs the real script of the `labels` job of .github/workflows/labels.yml with a fake GitHub
# and checks what it says about the PR body (issue #143): an unfilled "<reason>" fails with a clear message.
# Usage: bash scripts/agents/test-labels-check.sh
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
fails=0
ok() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
# Usage: <condition>; check $? "description"
check() { if [ "$1" -eq 0 ]; then ok "$2"; else fail "$2"; fi; }

command -v node >/dev/null || { echo "FAIL - node is missing"; exit 1; }
node - "$ROOT/.github/workflows/labels.yml" <<'JS'
const fs = require('fs');
const src = fs.readFileSync(process.argv[2], 'utf8');
// The script of the `labels:` job: the block after its `script: |`, up to the end of the file.
const job = src.slice(src.indexOf('\n  labels:\n'));
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
];
(async () => {
  let bad = 0;
  for (const [name, body, opt, re] of cases) {
    const failed = await run(body, opt);
    const good = re === null ? failed === null : failed !== null && re.test(failed);
    console.log((good ? 'ok   - ' : 'FAIL - ') + name + (good ? '' : '  (got: ' + JSON.stringify(failed) + ')'));
    if (!good) bad++;
  }
  process.exit(bad ? 1 : 0);
})();
JS
check $? "the labels check reports the unfilled reasons (full script, fake GitHub)"
echo
if [ "$fails" -ne 0 ]; then echo "$fails test(s) failed."; exit 1; fi
echo "All tests pass."
