// Tests of the pi extensions against the real kit scripts (guardrails.py, flow.py, .claude/skills) of this
// repo, with a fake `pi` that records what each extension registers. Run: node --test packages/pi/test/
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import flow from "../extensions/flow.ts";
import guardrails, { check } from "../extensions/guardrails.ts";
import skills, { COMMANDS } from "../extensions/skills.ts";

const KIT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const OUTSIDE = mkdtempSync(join(tmpdir(), "barrilete-pi-"));
after(() => rmSync(OUTSIDE, { recursive: true, force: true }));

type Handler = (event: any, ctx: any) => Promise<any>;

function fakePi() {
	const handlers: Record<string, Handler[]> = {};
	const commands: Record<string, { description: string; handler: (args: string, ctx: any) => Promise<void> }> = {};
	const sent: Array<{ content: string; options?: unknown }> = [];
	const pi = {
		on(name: string, h: Handler) {
			(handlers[name] ??= []).push(h);
		},
		registerCommand(name: string, opts: any) {
			commands[name] = opts;
		},
		sendUserMessage(content: string, options?: unknown) {
			sent.push({ content, options });
		},
		async exec(cmd: string, args: string[], opts?: { cwd?: string }) {
			try {
				const stdout = execFileSync(cmd, args, { cwd: opts?.cwd ?? KIT, encoding: "utf8" });
				return { stdout, stderr: "", code: 0, killed: false };
			} catch (e: any) {
				return { stdout: e.stdout ?? "", stderr: e.stderr ?? "", code: e.status ?? 1, killed: false };
			}
		},
	};
	const emit = async (name: string, event: any, ctx: any) => {
		let last;
		for (const h of handlers[name] ?? []) last = await h(event, ctx);
		return last;
	};
	return { pi: pi as any, handlers, commands, sent, emit };
}

function fakeCtx(cwd: string, idle = true) {
	const status: Record<string, string | undefined> = {};
	const notes: Array<[string, string]> = [];
	return {
		cwd,
		hasUI: true,
		isIdle: () => idle,
		status,
		notes,
		ui: {
			setStatus: (k: string, v: string | undefined) => (status[k] = v),
			notify: (m: string, l: string) => notes.push([m, l]),
			theme: { fg: (_c: string, s: string) => s },
		},
	};
}

describe("guardrails", () => {
	test("blocks what guardrails.py blocks, with its reason", () => {
		const v = check(KIT, "git push origin main", KIT);
		assert.equal(v?.block, true);
		assert.match(v!.reason, /guardrails/);
	});

	test("lets through what guardrails.py lets through", () => {
		assert.equal(check(KIT, "git status", KIT), undefined);
		assert.equal(check(KIT, "git push origin HEAD", KIT), undefined);
	});

	test("the tool_call handler only looks at bash, and only inside a project", async () => {
		const f = fakePi();
		guardrails(f.pi);
		const merge = { toolName: "bash", input: { command: "gh pr merge 12 --squash" } };
		assert.equal((await f.emit("tool_call", merge, fakeCtx(KIT)))?.block, true);
		assert.equal(await f.emit("tool_call", { toolName: "read", input: { path: "x" } }, fakeCtx(KIT)), undefined);
		assert.equal(await f.emit("tool_call", merge, fakeCtx(OUTSIDE)), undefined);
	});
});

describe("skills", () => {
	test("discovers the project's skills, orchestrate included", async () => {
		const f = fakePi();
		skills(f.pi);
		const r = await f.emit("resources_discover", { cwd: KIT, reason: "startup" }, fakeCtx(KIT));
		const names = r.skillPaths.map((p: string) => p.split("/").pop());
		assert.ok(names.includes("plan-feature") && names.includes("implement-issue"));
		assert.ok(names.includes("orchestrate"));
		assert.equal(await f.emit("resources_discover", { cwd: OUTSIDE, reason: "startup" }, fakeCtx(OUTSIDE)), undefined);
	});

	test("registers the human entry points", () => {
		const f = fakePi();
		skills(f.pi);
		assert.deepEqual(Object.keys(f.commands).sort(), Object.keys(COMMANDS).sort());
		assert.ok("orchestrate" in f.commands);
	});

	test("a command sends the whole skill plus the arguments, queued if the agent is busy", async () => {
		const f = fakePi();
		skills(f.pi);
		await f.commands["implement-issue"].handler("#43", fakeCtx(KIT));
		const { content, options } = f.sent[0];
		assert.match(content, /^<skill name="implement-issue" location="[^"]+\/\.claude\/skills\/implement-issue\/SKILL\.md">/);
		assert.match(content, /# Implement an issue/);
		assert.doesNotMatch(content, /^name: implement-issue/m); // frontmatter stripped
		assert.ok(content.endsWith("</skill>\n\n#43"));
		assert.equal(options, undefined);
		await f.commands["plan-feature"].handler("", fakeCtx(KIT, false));
		assert.deepEqual(f.sent[1].options, { deliverAs: "followUp" });
	});

	test("outside a project a command warns and sends nothing", async () => {
		const f = fakePi();
		skills(f.pi);
		const ctx = fakeCtx(OUTSIDE);
		await f.commands["plan-feature"].handler("", ctx);
		assert.equal(f.sent.length, 0);
		assert.equal(ctx.notes[0][1], "warning");
	});
});

describe("flow", () => {
	test("puts flow.py's line in the footer", async () => {
		const f = fakePi();
		flow(f.pi);
		const ctx = fakeCtx(KIT);
		await f.emit("session_start", { reason: "startup" }, ctx);
		assert.match(ctx.status["barrilete-flow"] ?? "", /plan .* merge/);
	});

	test("does nothing outside a project", async () => {
		const f = fakePi();
		flow(f.pi);
		const ctx = fakeCtx(OUTSIDE);
		await f.emit("agent_end", {}, ctx);
		assert.equal("barrilete-flow" in ctx.status, false);
	});
});
