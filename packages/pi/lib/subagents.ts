// Subagents for pi: pi has none of its own, so each one is a separate `pi --mode json -p` process with the
// role's definition as system prompt. The definitions are the kit's (.claude/agents/<role>.md, the ones
// Claude Code runs): they are translated here, never duplicated.
//
// What the kit requires from a subagent (docs/agents/subagent-contract.md) and how it holds in pi:
//   - guardrails always on: the child loads only this package (--no-extensions -e <package>), and its
//     guardrails use the orchestrator's checkout (BARRILETE_TRUSTED_ROOT), never the worktree's copy, which
//     is the PR's unreviewed code (the same rule the contract gives retro.sh);
//   - it cannot launch other subagents: the child gets BARRILETE_SUBAGENT=1 and the tool is not registered;
//   - never more than 3 implementing at once (orchestrate): enforced here, not left to the model.
// No pi imports, so the tests run with plain Node.
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const ROLES = ["implementer", "implementer-light", "reviewer"] as const;
export type Role = (typeof ROLES)[number];
export const MAX_IMPLEMENTING = 3;
/** The package root, loaded into every child so it has the guardrails. */
export const PACKAGE_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..");

export interface AgentDef {
	name: string;
	model?: string;
	tools: string[];
	prompt: string;
	file: string;
}

// Claude Code tool names → pi's built-in tools. Skill has no equivalent: pi lists the skills in the
// system prompt and the agent opens them with read.
const TOOLS: Record<string, string[]> = {
	Read: ["read"],
	Edit: ["edit"],
	MultiEdit: ["edit"],
	Write: ["write"],
	Bash: ["bash"],
	Grep: ["grep"],
	Glob: ["find", "ls"],
	LS: ["ls"],
};

/** pi tools for a `tools:` line of a Claude Code agent. Unknown names are dropped, never widened. */
export function piTools(claudeTools: string[]): string[] {
	const out = new Set<string>();
	for (const t of claudeTools) for (const p of TOOLS[t] ?? []) out.add(p);
	return [...out];
}

/**
 * The pi model for a kit alias (opus, sonnet, haiku). BARRILETE_MODELS maps them for other providers,
 * "opus=openai/gpt-5,sonnet=openai/gpt-5-mini,haiku=openai/gpt-5-nano"; without it the alias goes as is,
 * and pi resolves it as a pattern among the available models (with Anthropic, the latest of that family).
 */
export function piModel(alias: string | undefined, env: NodeJS.ProcessEnv = process.env): string | undefined {
	if (!alias) return undefined;
	for (const pair of (env.BARRILETE_MODELS ?? "").split(",")) {
		const [k, v] = pair.split("=").map((s) => s.trim());
		if (k === alias && v) return v;
	}
	return alias;
}

function frontmatter(text: string): { fields: Record<string, string>; body: string } {
	const m = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
	if (!m) return { fields: {}, body: text };
	const fields: Record<string, string> = {};
	for (const line of m[1].split(/\r?\n/)) {
		const kv = line.match(/^([\w-]+):\s*(.*)$/);
		if (kv) fields[kv[1]] = kv[2].trim();
	}
	return { fields, body: text.slice(m[0].length) };
}

/** Reads .claude/agents/<role>.md of the project. */
export function loadAgent(root: string, role: string): AgentDef {
	if (!(ROLES as readonly string[]).includes(role)) {
		throw new Error(`Unknown role "${role}". Roles: ${ROLES.join(", ")}.`);
	}
	const file = join(root, ".claude/agents", `${role}.md`);
	if (!existsSync(file)) {
		throw new Error(`${file} does not exist (small mode has no subagents: python3 scripts/grow.py).`);
	}
	const { fields, body } = frontmatter(readFileSync(file, "utf8"));
	const tools = (fields.tools ?? "").split(",").map((t) => t.trim()).filter(Boolean);
	return { name: fields.name || role, model: fields.model, tools, prompt: body.trim(), file };
}

/** What changes for a kit subagent when it runs in pi. Appended to its definition. */
export const PI_NOTES = `## Running in pi

You run in pi, launched by barrilete-pi's \`subagent\` tool, not by Claude Code. Your definition and the contract still apply; only the tools change:
- Where they say \`Read\`, \`Edit\`, \`Write\`, \`Bash\`, \`Grep\` or \`Glob\`, use \`read\`, \`edit\`, \`write\`, \`bash\`, \`grep\` and \`find\`.
- There is no Skill tool: open each skill's SKILL.md with \`read\`, at the path your definition gives.
- There is no \`/code-review\` command: do the bug pass by hand and declare \`no code-review: not available in pi\`.
- Each bash command runs in a new shell: always \`cd <worktree> && …\` or \`git -C <worktree>\`, as the contract says.
- The guardrails (\`guardrails.py\` of the orchestrator's checkout) check every bash command. If one stops you, do not look for another way: return \`question\`.
- Your final reply is the contract's output block and nothing else.`;

/** Arguments of the child pi. Exported for the tests. */
export function childArgs(agent: AgentDef, promptFile: string, task: string, env: NodeJS.ProcessEnv = process.env): string[] {
	const args = ["--mode", "json", "-p", "--no-session", "--no-extensions", "-e", PACKAGE_DIR];
	const model = piModel(agent.model, env);
	if (model) args.push("--model", model);
	const tools = piTools(agent.tools);
	args.push(...(tools.length ? ["--tools", tools.join(",")] : ["--no-tools"]));
	args.push("--append-system-prompt", promptFile, `Task: ${task}`);
	return args;
}

/** How to start pi again: the same binary and script as this process, or BARRILETE_PI_BIN (tests). */
export function piCommand(env: NodeJS.ProcessEnv = process.env): { command: string; prefix: string[] } {
	if (env.BARRILETE_PI_BIN) return { command: env.BARRILETE_PI_BIN, prefix: [] };
	const script = process.argv[1];
	if (script && !script.startsWith("/$bunfs/") && existsSync(script)) {
		return { command: process.execPath, prefix: [script] }; // node <pi's cli.js>
	}
	const runtime = /^(node|bun)(\.exe)?$/i.test(process.execPath.split(/[\\/]/).pop() ?? "");
	return runtime ? { command: "pi", prefix: [] } : { command: process.execPath, prefix: [] }; // compiled pi binary
}

export interface RunResult {
	role: string;
	output: string;
	exitCode: number;
	stderr: string;
	model?: string;
	turns: number;
	cost: number;
	error?: string;
}

export interface RunOptions {
	trustedRoot: string;
	cwd: string;
	signal?: AbortSignal;
	onProgress?: (r: RunResult) => void;
	env?: NodeJS.ProcessEnv;
}

function lastText(message: any): string | undefined {
	if (message?.role !== "assistant" || !Array.isArray(message.content)) return undefined;
	const texts = message.content.filter((p: any) => p?.type === "text").map((p: any) => p.text);
	return texts.length ? texts.join("\n") : undefined;
}

/** Runs one subagent to the end and returns its final reply (the contract block). */
export async function runAgent(agent: AgentDef, task: string, opts: RunOptions): Promise<RunResult> {
	const env = opts.env ?? process.env;
	const result: RunResult = { role: agent.name, output: "", exitCode: 0, stderr: "", turns: 0, cost: 0 };
	const dir = mkdtempSync(join(tmpdir(), "barrilete-agent-"));
	const promptFile = join(dir, `${agent.name}.md`);
	writeFileSync(promptFile, `${agent.prompt}\n\n${PI_NOTES}\n`, { mode: 0o600 });
	const { command, prefix } = piCommand(env);
	try {
		result.exitCode = await new Promise<number>((done) => {
			const proc = spawn(command, [...prefix, ...childArgs(agent, promptFile, task, env)], {
				cwd: opts.cwd,
				env: { ...env, BARRILETE_SUBAGENT: "1", BARRILETE_TRUSTED_ROOT: opts.trustedRoot },
				stdio: ["ignore", "pipe", "pipe"],
			});
			let buffer = "";
			const line = (l: string) => {
				let ev: any;
				try {
					ev = JSON.parse(l);
				} catch {
					return;
				}
				if (ev?.type !== "message_end") return;
				const text = lastText(ev.message);
				if (ev.message?.role === "assistant") {
					result.turns++;
					result.cost += ev.message.usage?.cost?.total ?? 0;
					result.model ??= ev.message.model;
					if (ev.message.errorMessage) result.error = ev.message.errorMessage;
				}
				if (text !== undefined) result.output = text;
				opts.onProgress?.(result);
			};
			proc.stdout.on("data", (d) => {
				buffer += d.toString();
				const lines = buffer.split("\n");
				buffer = lines.pop() ?? "";
				for (const l of lines) if (l.trim()) line(l);
			});
			proc.stderr.on("data", (d) => (result.stderr += d.toString()));
			proc.on("error", (e) => {
				result.stderr += String(e);
				done(1);
			});
			proc.on("close", (code) => {
				if (buffer.trim()) line(buffer);
				done(code ?? 1);
			});
			const kill = () => {
				proc.kill("SIGTERM");
				setTimeout(() => proc.exitCode === null && proc.kill("SIGKILL"), 5000).unref();
			};
			if (opts.signal?.aborted) kill();
			else opts.signal?.addEventListener("abort", kill, { once: true });
		});
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
	return result;
}

export interface Task {
	agent: string;
	task: string;
	cwd?: string;
}

/** Counts the implementers running in this session (orchestrate: never more than 3 at once). */
export class Slots {
	running = 0;
	take(tasks: Task[]): string | undefined {
		const n = tasks.filter((t) => t.agent !== "reviewer").length;
		if (this.running + n > MAX_IMPLEMENTING) {
			return `At most ${MAX_IMPLEMENTING} implementing at once (orchestrate): ${this.running} running, ${n} asked.`;
		}
		this.running += n;
		return undefined;
	}
	give(tasks: Task[]) {
		this.running -= tasks.filter((t) => t.agent !== "reviewer").length;
	}
}

/** Text the orchestrator reads for each finished subagent. */
export function report(r: RunResult, task: Task): string {
	const failed = r.exitCode !== 0 || !r.output.trim();
	const head = `### ${task.agent}${task.cwd ? ` (${task.cwd})` : ""}${failed ? " — failed" : ""}`;
	if (!failed) return `${head}\n\n${r.output.trim()}`;
	const why = r.error || r.stderr.trim().split("\n").slice(-5).join("\n") || `exit ${r.exitCode}, no reply`;
	return `${head}\n\nThe subagent ended without its contract block (exit ${r.exitCode}).\n\n${why}`;
}

export interface Params {
	agent?: string;
	task?: string;
	cwd?: string;
	tasks?: Task[];
}

export interface ToolResult {
	content: Array<{ type: "text"; text: string }>;
	details: { results: RunResult[] };
	isError?: boolean;
}

/**
 * The `subagent` tool: one task (agent + task) or several in parallel (tasks). `root` is the orchestrator's
 * checkout, where the definitions and the trusted guardrails come from; `cwd` of each task is its worktree.
 */
export async function execute(
	params: Params,
	root: string,
	slots: Slots,
	opts: { signal?: AbortSignal; onUpdate?: (r: ToolResult) => void; env?: NodeJS.ProcessEnv } = {},
): Promise<ToolResult> {
	const fail = (text: string): ToolResult => ({ content: [{ type: "text", text }], details: { results: [] }, isError: true });
	const single = params.agent && params.task ? [{ agent: params.agent, task: params.task, cwd: params.cwd }] : [];
	const tasks = params.tasks?.length ? params.tasks : single;
	if (!tasks.length || (single.length && params.tasks?.length)) {
		return fail(`Give either agent + task, or tasks (several in parallel). Roles: ${ROLES.join(", ")}.`);
	}
	let agents: AgentDef[];
	try {
		agents = tasks.map((t) => loadAgent(root, t.agent));
	} catch (e) {
		return fail((e as Error).message);
	}
	const busy = slots.take(tasks);
	if (busy) return fail(busy);
	const results: RunResult[] = tasks.map((t) => ({ role: t.agent, output: "", exitCode: 0, stderr: "", turns: 0, cost: 0 }));
	const progress = () =>
		opts.onUpdate?.({
			content: [{ type: "text", text: results.map((r) => `${r.role}: ${r.turns} turns`).join(" · ") }],
			details: { results },
		});
	try {
		await Promise.all(
			tasks.map(async (t, i) => {
				results[i] = await runAgent(agents[i], t.task, {
					trustedRoot: root,
					cwd: t.cwd ? resolve(root, t.cwd) : root,
					signal: opts.signal,
					env: opts.env,
					onProgress: (r) => {
						results[i] = r;
						progress();
					},
				});
			}),
		);
	} finally {
		slots.give(tasks);
	}
	if (opts.signal?.aborted) return fail("Subagents aborted.");
	const failed = results.some((r) => r.exitCode !== 0 || !r.output.trim());
	return {
		content: [{ type: "text", text: results.map((r, i) => report(r, tasks[i])).join("\n\n") }],
		details: { results },
		isError: failed && results.every((r) => r.exitCode !== 0 || !r.output.trim()),
	};
}
