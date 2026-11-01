// Tests of the agent status (extensions/status.ts, lib/status.ts) with a hook script that writes down every
// payload it gets. Run: node --test packages/pi/test/*.test.ts
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { after, afterEach, beforeEach, describe, test } from "node:test";
import status from "../extensions/status.ts";
import { hookCommand, StatusQueue, stopEvent, subagentCount } from "../lib/status.ts";

const TMP = mkdtempSync(join(tmpdir(), "barrilete-status-"));
after(() => rmSync(TMP, { recursive: true, force: true }));

let log: string, hook: string;
beforeEach(() => {
	const dir = mkdtempSync(join(TMP, "case-"));
	log = join(dir, "payloads.jsonl");
	hook = join(dir, "hook.sh");
	// A slow first call proves the order holds: without the queue the later payloads would land first.
	writeFileSync(hook, `#!/bin/sh\nin=$(cat)\n[ -f "${log}" ] || sleep 0.3\nprintf '%s\\n' "$in" >> "${log}"\n`, { mode: 0o755 });
});
const payloads = () => (existsSync(log) ? readFileSync(log, "utf8").trim().split("\n").map((l) => JSON.parse(l)) : []);

describe("lib", () => {
	test("hook command from the environment, with ~ expanded", () => {
		assert.equal(hookCommand({}), undefined);
		assert.equal(hookCommand({ BARRILETE_STATUS_HOOK: "  " }), undefined);
		assert.equal(hookCommand({ BARRILETE_STATUS_HOOK: "~/x/hook.sh" }), join(homedir(), "x/hook.sh"));
	});

	test("subagents per call and the kind of stop", () => {
		assert.equal(subagentCount({ agent: "reviewer", task: "x" }), 1);
		assert.equal(subagentCount({ tasks: [{}, {}, {}] }), 3);
		assert.equal(subagentCount({}), 0);
		assert.equal(stopEvent([{ role: "assistant", stopReason: "stop" }]), "Stop");
		assert.equal(stopEvent([{ role: "assistant", stopReason: "error" }, { role: "toolResult" }]), "StopFailure");
		assert.equal(stopEvent([]), "Stop");
	});

	test("delivers in order even when a call is slow, and a broken hook does not throw", async () => {
		const q = new StatusQueue(hook);
		for (const e of ["A", "B", "C"]) q.send({ session_id: "s", hook_event_name: e, cwd: "/" });
		await q.flush();
		assert.deepEqual(payloads().map((p) => p.hook_event_name), ["A", "B", "C"]);
		await new StatusQueue(join(TMP, "does-not-exist")).send({ session_id: "s", hook_event_name: "X", cwd: "/" });
	});
});

describe("extension", () => {
	const saved = { hook: process.env.BARRILETE_STATUS_HOOK, sub: process.env.BARRILETE_SUBAGENT };
	afterEach(() => {
		for (const [k, v] of [["BARRILETE_STATUS_HOOK", saved.hook], ["BARRILETE_SUBAGENT", saved.sub]] as const) {
			if (v === undefined) delete process.env[k];
			else process.env[k] = v;
		}
	});

	function load() {
		const handlers: Record<string, any> = {};
		status({ on: (n: string, h: any) => (handlers[n] = h) } as any);
		const ctx = { cwd: "/repo", sessionManager: { getSessionId: () => "sess-1" } };
		return { handlers, emit: (n: string, e: any = {}) => handlers[n]?.(e, ctx) };
	}

	test("reports a session the way Claude Code's hooks do, subagents included", async () => {
		process.env.BARRILETE_STATUS_HOOK = hook;
		delete process.env.BARRILETE_SUBAGENT;
		const { emit } = load();
		await emit("session_start");
		await emit("agent_start");
		await emit("tool_execution_start", { toolCallId: "1", toolName: "bash", args: {} });
		await emit("tool_execution_end", { toolCallId: "1", toolName: "bash", isError: true });
		await emit("tool_execution_start", { toolCallId: "2", toolName: "subagent", args: { tasks: [{}, {}] } });
		await emit("tool_execution_end", { toolCallId: "2", toolName: "subagent", isError: false });
		await emit("agent_end", { messages: [{ role: "assistant", stopReason: "stop" }] });
		await emit("session_shutdown", { reason: "quit" }); // waits for every payload
		const got = payloads();
		assert.deepEqual(
			got.map((p) => [p.hook_event_name, p.tool_name ?? null]),
			[
				["SessionStart", null],
				["UserPromptSubmit", null],
				["PreToolUse", "bash"],
				["PostToolUseFailure", "bash"],
				["PreToolUse", "subagent"],
				["SubagentStart", null],
				["SubagentStart", null],
				["SubagentStop", null],
				["SubagentStop", null],
				["PostToolUse", "subagent"],
				["Stop", null],
				["SessionEnd", null],
			],
		);
		assert.ok(got.every((p) => p.session_id === "sess-1" && p.cwd === "/repo"));
	});

	test("does nothing without a hook, or inside a subagent", () => {
		delete process.env.BARRILETE_STATUS_HOOK;
		assert.deepEqual(Object.keys(load().handlers), []);
		process.env.BARRILETE_STATUS_HOOK = hook;
		process.env.BARRILETE_SUBAGENT = "1";
		assert.deepEqual(Object.keys(load().handlers), []);
	});
});
