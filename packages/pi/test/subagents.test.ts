// Tests of the subagent tool (lib/subagents.ts) against this repo's real agent definitions
// (.claude/agents/), with test/fake-pi.mjs in place of the child pi. Run: node --test packages/pi/test/*.test.ts
import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { after, beforeEach, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import guardrails, { trustedRoot } from "../extensions/guardrails.ts";
import {
	childArgs,
	execute,
	loadAgent,
	MAX_IMPLEMENTING,
	PACKAGE_DIR,
	PI_NOTES,
	piModel,
	piTools,
	Slots,
} from "../lib/subagents.ts";

const HERE = dirname(fileURLToPath(import.meta.url));
const KIT = resolve(HERE, "../../..");
const FAKE = join(HERE, "fake-pi.mjs");
chmodSync(FAKE, 0o755);
const TMP = mkdtempSync(join(tmpdir(), "barrilete-sub-"));
after(() => rmSync(TMP, { recursive: true, force: true }));

let log: string;
const env = (extra: Record<string, string> = {}) => ({ ...process.env, BARRILETE_PI_BIN: FAKE, FAKE_PI_LOG: log, ...extra });
const launches = () => readdirSync(log).map((f) => JSON.parse(readFileSync(join(log, f), "utf8")));
beforeEach(() => {
	log = mkdtempSync(join(TMP, "log-"));
});

describe("translation of the kit's definitions", () => {
	test("Claude Code tools become pi tools; Skill and unknown names are dropped", () => {
		assert.deepEqual(piTools(["Read", "Edit", "Write", "Bash", "Grep", "Glob", "Skill"]), [
			"read", "edit", "write", "bash", "grep", "find", "ls",
		]);
		assert.deepEqual(piTools(["Read", "WebFetch"]), ["read"]);
	});

	test("model aliases pass as pi patterns, or through BARRILETE_MODELS", () => {
		assert.equal(piModel("sonnet", {}), "sonnet");
		const m = { BARRILETE_MODELS: "opus=openai/gpt-5, haiku = openai/gpt-5-nano" };
		assert.equal(piModel("opus", m), "openai/gpt-5");
		assert.equal(piModel("haiku", m), "openai/gpt-5-nano");
		assert.equal(piModel("sonnet", m), "sonnet");
		assert.equal(piModel(undefined, m), undefined);
	});

	test("reads the three roles from .claude/agents/", () => {
		assert.equal(loadAgent(KIT, "implementer").model, "sonnet");
		assert.equal(loadAgent(KIT, "implementer-light").model, "haiku");
		const reviewer = loadAgent(KIT, "reviewer");
		assert.equal(reviewer.model, "sonnet");
		assert.ok(!reviewer.tools.includes("Edit"));
		assert.match(reviewer.prompt, /subagent-contract\.md/);
		assert.doesNotMatch(reviewer.prompt, /^name:/m);
		assert.throws(() => loadAgent(KIT, "planner"), /Unknown role/);
		assert.throws(() => loadAgent(TMP, "implementer"), /does not exist/);
	});

	test("the child loads only this package, with the role's model and tools", () => {
		const args = childArgs(loadAgent(KIT, "reviewer"), "/p.md", "review #9", {});
		assert.deepEqual(args.slice(0, 7), ["--mode", "json", "-p", "--no-session", "--no-extensions", "-e", PACKAGE_DIR]);
		assert.equal(args[args.indexOf("--model") + 1], "sonnet");
		assert.equal(args[args.indexOf("--tools") + 1], "read,write,bash,grep,find,ls");
		assert.deepEqual(args.slice(-3), ["--append-system-prompt", "/p.md", "Task: review #9"]);
	});
});

describe("subagent tool", () => {
	test("runs a role in its worktree and returns its contract block", async () => {
		const wt = mkdtempSync(join(TMP, "wt-"));
		const r = await execute({ agent: "implementer", task: "issue #7", cwd: wt }, KIT, new Slots(), { env: env() });
		assert.equal(r.isError, false);
		assert.match(r.content[0].text, /^### implementer \(.+\)\n\nresult: pr\nissue: 1\nTask: issue #7$/);
		const [l] = launches();
		assert.equal(l.cwd, realpathSync(wt)); // realpath: on macOS the tmp dir is under /private
		assert.equal(l.subagent, "1");
		assert.equal(l.trusted, KIT);
		assert.ok(l.prompt.startsWith(loadAgent(KIT, "implementer").prompt));
		assert.ok(l.prompt.includes(PI_NOTES));
		assert.equal(r.details.results[0].model, "fake-model");
	});

	test("runs several in parallel and frees the slots at the end", async () => {
		const slots = new Slots();
		const tasks = [
			{ agent: "implementer", task: "a" },
			{ agent: "implementer-light", task: "b" },
			{ agent: "implementer", task: "c" },
			{ agent: "reviewer", task: "d" },
		];
		const r = await execute({ tasks }, KIT, slots, { env: env({ FAKE_PI_SLEEP_MS: "200" }) });
		assert.equal(r.isError, false);
		assert.equal(launches().length, 4);
		for (const t of ["a", "b", "c", "d"]) assert.match(r.content[0].text, new RegExp(`Task: ${t}`));
		assert.equal(slots.running, 0);
	});

	test(`never more than ${MAX_IMPLEMENTING} implementing at once, counting the ones already running`, async () => {
		const slots = new Slots();
		const four = Array.from({ length: 4 }, (_, i) => ({ agent: "implementer", task: `t${i}` }));
		const r = await execute({ tasks: four }, KIT, slots, { env: env() });
		assert.equal(r.isError, true);
		assert.match(r.content[0].text, /At most 3 implementing/);
		assert.equal(launches().length, 0);

		const running = execute({ tasks: four.slice(0, 2) }, KIT, slots, { env: env({ FAKE_PI_SLEEP_MS: "300" }) });
		const extra = await execute({ tasks: four.slice(2) }, KIT, slots, { env: env() });
		assert.equal(extra.isError, true);
		assert.match(extra.content[0].text, /2 running, 2 asked/);
		await running;
		assert.equal(slots.running, 0);
	});

	test("a child that ends without its block is reported as failed", async () => {
		const r = await execute({ agent: "reviewer", task: "x" }, KIT, new Slots(), {
			env: env({ FAKE_PI_REPLY: "", FAKE_PI_EXIT: "1" }),
		});
		assert.equal(r.isError, true);
		assert.match(r.content[0].text, /reviewer — failed[\s\S]*without its contract block \(exit 1\)/);
	});

	test("aborting kills the children", async () => {
		const ac = new AbortController();
		const started = Date.now();
		setTimeout(() => ac.abort(), 200);
		const r = await execute({ agent: "implementer", task: "x" }, KIT, new Slots(), {
			signal: ac.signal,
			env: env({ FAKE_PI_SLEEP_MS: "20000" }),
		});
		assert.equal(r.isError, true);
		assert.match(r.content[0].text, /aborted/);
		assert.ok(Date.now() - started < 5000);
	});

	test("bad calls fail without launching anything", async () => {
		for (const params of [{}, { agent: "planner", task: "x" }, { agent: "implementer", task: "x", tasks: [{ agent: "reviewer", task: "y" }] }]) {
			const r = await execute(params as any, KIT, new Slots(), { env: env() });
			assert.equal(r.isError, true, JSON.stringify(params));
		}
		assert.equal(launches().length, 0);
	});
});

describe("guardrails inside a subagent", () => {
	test("use the orchestrator's checkout, even if the worktree has no guardrails or other ones", async () => {
		assert.equal(trustedRoot({ BARRILETE_TRUSTED_ROOT: KIT }), KIT);
		assert.equal(trustedRoot({ BARRILETE_TRUSTED_ROOT: TMP }), undefined);
		assert.equal(trustedRoot({}), undefined);

		const handlers: any[] = [];
		guardrails({ on: (_n: string, h: any) => handlers.push(h) } as any);
		const before = process.env.BARRILETE_TRUSTED_ROOT;
		process.env.BARRILETE_TRUSTED_ROOT = KIT;
		try {
			const v = await handlers[0]({ toolName: "bash", input: { command: "git push origin main" } }, { cwd: TMP });
			assert.equal(v?.block, true);
		} finally {
			if (before === undefined) delete process.env.BARRILETE_TRUSTED_ROOT;
			else process.env.BARRILETE_TRUSTED_ROOT = before;
		}
	});
});
