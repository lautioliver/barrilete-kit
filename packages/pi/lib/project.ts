// Finds the Barrilete project the session is in and the kit pieces the extensions reuse.
// A project is a git repo with scripts/agents/guardrails.py: without it the extensions do nothing,
// like the Claude Code hook (.claude/settings.json), which exits 0 when the script is missing.
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";

const cache = new Map<string, string | null>();

/** Root of the Barrilete project that contains `cwd`, or null if `cwd` is not inside one. */
export function projectRoot(cwd: string): string | null {
	if (cache.has(cwd)) return cache.get(cwd)!;
	let root: string | null = null;
	try {
		const top = execFileSync("git", ["rev-parse", "--show-toplevel"], {
			cwd,
			encoding: "utf8",
			stdio: ["ignore", "pipe", "ignore"],
		}).trim();
		if (top && existsSync(join(top, "scripts/agents/guardrails.py"))) root = top;
	} catch {
		// not a git repo
	}
	cache.set(cwd, root);
	return root;
}

/** Skills that need a pi piece that does not exist yet: they stay out of discovery and commands. */
export const UNSUPPORTED_SKILLS = new Set(["orchestrate"]); // needs subagents (phase 2)

/** Directories of the project's skills (.claude/skills/<name>/SKILL.md) that pi can run. */
export function skillDirs(root: string): string[] {
	const base = join(root, ".claude/skills");
	if (!existsSync(base)) return [];
	return readdirSync(base, { withFileTypes: true })
		.filter((d) => d.isDirectory() && !UNSUPPORTED_SKILLS.has(d.name))
		.map((d) => join(base, d.name))
		.filter((dir) => existsSync(join(dir, "SKILL.md")))
		.sort();
}
