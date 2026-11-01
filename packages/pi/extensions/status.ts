// Agent status for outside tools: with BARRILETE_STATUS_HOOK set, every pi session reports its state in the
// JSON of Claude Code's hooks to that command (lib/status.ts). Without it, this extension does nothing.
//   session_start → SessionStart          agent_start → UserPromptSubmit
//   tool start/end → PreToolUse / PostToolUse(Failure), and the subagent tool → SubagentStart / SubagentStop per task
//   agent_end → Stop (StopFailure if the model ended in error)          session_shutdown → SessionEnd
// A subagent does not report itself: its orchestrator already counts it as a subagent.
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { hookCommand, StatusQueue, stopEvent, subagentCount } from "../lib/status.ts";

export default function (pi: ExtensionAPI) {
	if (process.env.BARRILETE_SUBAGENT === "1") return;
	const command = hookCommand();
	if (!command) return;
	const queue = new StatusQueue(command);
	const launched = new Map<string, number>(); // toolCallId of the subagent tool → subagents it launched

	const send = (ctx: ExtensionContext, hook_event_name: string, tool_name?: string) =>
		queue.send({ session_id: ctx.sessionManager.getSessionId(), hook_event_name, cwd: ctx.cwd, tool_name });

	pi.on("session_start", async (_e, ctx) => void send(ctx, "SessionStart"));
	pi.on("agent_start", async (_e, ctx) => void send(ctx, "UserPromptSubmit"));
	pi.on("tool_execution_start", async (e, ctx) => {
		void send(ctx, "PreToolUse", e.toolName);
		if (e.toolName !== "subagent") return;
		const n = subagentCount(e.args);
		launched.set(e.toolCallId, n);
		for (let i = 0; i < n; i++) void send(ctx, "SubagentStart");
	});
	pi.on("tool_execution_end", async (e, ctx) => {
		const n = launched.get(e.toolCallId) ?? 0;
		launched.delete(e.toolCallId);
		for (let i = 0; i < n; i++) void send(ctx, "SubagentStop");
		void send(ctx, e.isError ? "PostToolUseFailure" : "PostToolUse", e.toolName);
	});
	pi.on("agent_end", async (e, ctx) => void send(ctx, stopEvent(e.messages)));
	pi.on("session_shutdown", async (_e, ctx) => {
		send(ctx, "SessionEnd");
		await queue.flush(); // deliver it before pi exits
	});
}
