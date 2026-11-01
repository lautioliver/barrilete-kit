// Guardrails: runs every bash command of the agent through the project's scripts/agents/guardrails.py
// before it executes, the same script the Claude Code, Codex, Copilot and Cursor hooks call. It sends
// the Claude Code hook JSON ({tool_name: "Bash", tool_input: {command}, cwd}); exit 2 means blocked and
// stderr is the reason the agent reads. There is one source of truth: this file only translates.
//
// Like the other hooks it fails open (no python3, no script, a crash): they are guardrails against the
// common mistake, not a lock. The lock is branch protection (AGENTS.md, "Agent autonomy").
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { projectRoot } from "../lib/project.ts";

/** The orchestrator's checkout when this pi is a subagent (BARRILETE_TRUSTED_ROOT), if it is a project. */
export function trustedRoot(env: NodeJS.ProcessEnv = process.env): string | undefined {
	const root = env.BARRILETE_TRUSTED_ROOT;
	return root && existsSync(join(root, "scripts/agents/guardrails.py")) ? root : undefined;
}

export type Verdict ={ block: true; reason: string } | undefined;

/** Asks guardrails.py about `command`. Exported for the tests. */
export function check(root: string, command: string, cwd: string): Verdict {
	const input = JSON.stringify({ tool_name: "Bash", tool_input: { command }, cwd });
	const r = spawnSync("python3", [join(root, "scripts/agents/guardrails.py")], {
		cwd,
		input,
		encoding: "utf8",
		timeout: 10_000,
	});
	if (r.status !== 2) return undefined;
	const reason = (r.stderr || "").trim() || "Blocked by scripts/agents/guardrails.py.";
	return { block: true, reason };
}

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;
		const command = (event.input as { command?: unknown }).command;
		if (typeof command !== "string" || !command.trim()) return undefined;
		// A subagent works in a worktree, whose guardrails.py is the PR's unreviewed code: it uses the
		// orchestrator's checkout, which the subagent tool passes (lib/subagents.ts).
		const root = trustedRoot() ?? projectRoot(ctx.cwd);
		if (!root) return undefined;
		return check(root, command, ctx.cwd);
	});
}
