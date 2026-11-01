// The `subagent` tool, so /orchestrate can launch the kit's implementer, implementer-light and reviewer
// (.claude/agents/) in pi, which has no subagents of its own. The logic is in lib/subagents.ts.
// Not registered inside a subagent: they cannot launch others (docs/agents/subagent-contract.md).
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { projectRoot } from "../lib/project.ts";
import { execute, ROLES, Slots } from "../lib/subagents.ts";

const Role = Type.Union(
	ROLES.map((r) => Type.Literal(r)),
	{ description: `Kit role (.claude/agents/<role>.md): ${ROLES.join(", ")}` },
);
const TaskItem = Type.Object({
	agent: Role,
	task: Type.String({ description: "What the orchestrate skill says to pass this role (issue, worktree, BASE, shas, retro_sh…)" }),
	cwd: Type.Optional(Type.String({ description: "Worktree the subagent works in (absolute path)" })),
});

export default function (pi: ExtensionAPI) {
	if (process.env.BARRILETE_SUBAGENT === "1") return;
	const slots = new Slots();

	pi.registerTool({
		name: "subagent",
		label: "Subagent",
		description:
			"Launch the kit's subagents (implementer, implementer-light, reviewer from .claude/agents/) as separate pi processes, " +
			"one task or several in parallel (at most 3 implementing at once). Each one returns the contract block of " +
			"docs/agents/subagent-contract.md. Only for the orchestrate skill.",
		promptSnippet: "Launch the kit's implementer, implementer-light or reviewer (orchestrate skill)",
		promptGuidelines: [
			"Use the subagent tool only while following the orchestrate skill: it is pi's equivalent of Claude Code's Agent tool, with `agent` instead of `subagent_type`.",
		],
		parameters: Type.Object({
			agent: Type.Optional(Role),
			task: Type.Optional(Type.String({ description: "Task for a single subagent" })),
			cwd: Type.Optional(Type.String({ description: "Worktree of a single subagent (absolute path)" })),
			tasks: Type.Optional(Type.Array(TaskItem, { description: "Several subagents in parallel", maxItems: 6 })),
		}),
		async execute(_id, params, signal, onUpdate, ctx) {
			const root = projectRoot(ctx.cwd);
			if (!root) {
				return {
					content: [{ type: "text", text: "Not inside a Barrilete project: there are no kit subagents here." }],
					details: { results: [] },
					isError: true,
				};
			}
			return execute(params, root, slots, { signal, onUpdate });
		},
	});
}
