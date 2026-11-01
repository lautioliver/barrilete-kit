// Agent status for outside tools (a status bar, a notifier): translates pi's events into the JSON of Claude
// Code's hooks (session_id, hook_event_name, cwd, tool_name) and hands it, on stdin, to the command in
// BARRILETE_STATUS_HOOK. A script written for Claude Code's hooks works as is: the kit does not know who
// listens. Fire and forget, but in order: each call waits for the previous one to exit, so a late
// PostToolUse never lands after the Stop and leaves the session "working".
// No pi imports, so the tests run with plain Node.
import { spawn } from "node:child_process";
import { homedir } from "node:os";

export interface HookPayload {
	session_id: string;
	hook_event_name: string;
	cwd: string;
	tool_name?: string;
}

/** The hook command, with ~ expanded, or undefined if it is not configured. */
export function hookCommand(env: NodeJS.ProcessEnv = process.env): string | undefined {
	const raw = env.BARRILETE_STATUS_HOOK?.trim();
	if (!raw) return undefined;
	return raw.startsWith("~/") ? homedir() + raw.slice(1) : raw;
}

/** How many subagents a call of the subagent tool launches. */
export function subagentCount(args: any): number {
	if (Array.isArray(args?.tasks) && args.tasks.length) return args.tasks.length;
	return args?.agent ? 1 : 0;
}

/** Stop or StopFailure, from the messages of agent_end. */
export function stopEvent(messages: any[]): "Stop" | "StopFailure" {
	for (let i = (messages?.length ?? 0) - 1; i >= 0; i--) {
		const m = messages[i];
		if (m?.role === "assistant") return m.stopReason === "error" ? "StopFailure" : "Stop";
	}
	return "Stop";
}

/** Sends payloads to the hook one after the other. Errors are swallowed: status never breaks the session. */
export class StatusQueue {
	private chain: Promise<void> = Promise.resolve();
	private command: string;
	constructor(command: string) {
		this.command = command;
	}

	send(payload: HookPayload): Promise<void> {
		this.chain = this.chain.then(
			() =>
				new Promise<void>((done) => {
					let proc;
					try {
						proc = spawn(this.command, [], { stdio: ["pipe", "ignore", "ignore"] });
					} catch {
						return done();
					}
					const timer = setTimeout(() => proc.kill("SIGKILL"), 5000);
					timer.unref();
					proc.on("error", () => {
						clearTimeout(timer);
						done();
					});
					proc.on("close", () => {
						clearTimeout(timer);
						done();
					});
					proc.stdin.on("error", () => {});
					proc.stdin.end(JSON.stringify(payload));
				}),
		);
		return this.chain;
	}

	/** Resolves when everything sent so far has been delivered (tests, shutdown). */
	flush(): Promise<void> {
		return this.chain;
	}
}
