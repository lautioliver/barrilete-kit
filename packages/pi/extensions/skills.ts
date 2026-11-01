// Skills and commands: pi looks for skills in .pi/skills and .agents/skills, not in .claude/skills, where
// the kit keeps them. This adds the project's skills to discovery (they show up in the system prompt and
// as /skill:<name>) and registers the kit's human entry points with the same name they have in Claude Code:
// /plan-feature, /implement-issue <n>, /review-pr <n>, /project-status, /improve-skills, /add-member, /remove-member.
//
// A command loads the whole SKILL.md into the message, in the same block pi builds for /skill:<name>, so the
// skill runs whether or not the model would have opened the file on its own.
import { existsSync, readFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { projectRoot, skillDirs, UNSUPPORTED_SKILLS } from "../lib/project.ts";

/** Skills a person invokes by name (the rest the model loads when they apply). */
export const COMMANDS: Record<string, string> = {
	"plan-feature": "Turn an idea into an epic with issues and blockers (does not write code)",
	"implement-issue": "Take an issue to a PR with green CI, TDD (does not merge)",
	"review-pr": "Review a PR in this session (does not approve or merge)",
	"project-status": "State of the work and what can be started now",
	"improve-skills": "Propose skill improvements from the retros, in a PR",
	"add-member": "Add a member to the team (.github/team.json)",
	"remove-member": "Remove a member from the team (.github/team.json)",
};

function stripFrontmatter(text: string): string {
	return text.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, "");
}

/** The message a command sends: pi's /skill:<name> block plus the arguments. Exported for the tests. */
export function skillMessage(skillFile: string, args: string): string {
	const name = basename(dirname(skillFile));
	const body = stripFrontmatter(readFileSync(skillFile, "utf8")).trim();
	const block = `<skill name="${name}" location="${skillFile}">\nReferences are relative to ${dirname(skillFile)}.\n\n${body}\n</skill>`;
	return args.trim() ? `${block}\n\n${args.trim()}` : block;
}

export default function (pi: ExtensionAPI) {
	pi.on("resources_discover", async (event) => {
		const root = projectRoot(event.cwd);
		if (!root) return undefined;
		return { skillPaths: skillDirs(root) };
	});

	for (const [name, description] of Object.entries(COMMANDS)) {
		if (UNSUPPORTED_SKILLS.has(name)) continue;
		pi.registerCommand(name, {
			description: `Barrilete: ${description}`,
			handler: async (args, ctx) => {
				const root = projectRoot(ctx.cwd);
				const file = root && join(root, ".claude/skills", name, "SKILL.md");
				if (!file || !existsSync(file)) {
					ctx.ui.notify(
						root
							? `This project has no ${name} skill (small mode? python3 scripts/grow.py moves to the full one).`
							: "Not inside a Barrilete project (no scripts/agents/guardrails.py in the git root).",
						"warning",
					);
					return;
				}
				const message = skillMessage(file, args ?? "");
				if (ctx.isIdle()) pi.sendUserMessage(message);
				else pi.sendUserMessage(message, { deliverAs: "followUp" });
			},
		});
	}
}
