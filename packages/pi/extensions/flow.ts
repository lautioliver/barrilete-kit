// Flow line: shows in pi's footer which step of the flow the current branch is in (scripts/agents/flow.py,
// docs/guides/flow-line.md), the same line Claude Code shows in its status line:
//     plan ● ─ ▸implement ─ review ─ ● merge   #176 · no PR yet
// It is refreshed when the session starts and when the agent finishes, which is when a branch or a PR changes.
import { join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { projectRoot } from "../lib/project.ts";

const ID = "barrilete-flow";

export default function (pi: ExtensionAPI) {
	async function refresh(ctx: ExtensionContext) {
		if (!ctx.hasUI) return;
		const root = projectRoot(ctx.cwd);
		if (!root) return;
		try {
			const r = await pi.exec("python3", [join(root, "scripts/agents/flow.py"), "--format", "plain"], {
				timeout: 15_000,
			});
			const line = r.code === 0 ? r.stdout.trim() : "";
			ctx.ui.setStatus(ID, line ? ctx.ui.theme.fg("dim", line) : undefined);
		} catch {
			ctx.ui.setStatus(ID, undefined); // flow.py failed (gh missing, no network): no line rather than a stale one
		}
	}

	pi.on("session_start", async (_event, ctx) => refresh(ctx));
	pi.on("agent_end", async (_event, ctx) => refresh(ctx));
}
