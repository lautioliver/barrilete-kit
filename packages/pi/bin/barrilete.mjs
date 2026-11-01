#!/usr/bin/env node
// barrilete: opens pi with barrilete-pi loaded, without installing it into your pi or editing its settings.
//
//   barrilete [pi options]            own home (~/.barrilete/agent): never touches your pi installation
//   barrilete --link [pi options]     reuses your pi as is (~/.pi/agent, or PI_CODING_AGENT_DIR)
//   barrilete home import-pi [--dry-run]
//                                     copies your pi login and default model into the own home
//   barrilete doctor                  checks what the kit needs here
//
// BARRILETE_HOME moves the own home (default ~/.barrilete). Plain JavaScript on purpose: it is the npm `bin`
// and runs on any Node that runs pi.
import { spawn, spawnSync } from "node:child_process";
import { accessSync, chmodSync, constants, copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { homedir } from "node:os";
import { delimiter, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const PACKAGE_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const VERSION = JSON.parse(readFileSync(join(PACKAGE_DIR, "package.json"), "utf8")).version;
const MODEL_KEYS = ["defaultProvider", "defaultModel", "defaultThinkingLevel"];

const ownAgentDir = () => join(process.env.BARRILETE_HOME || join(homedir(), ".barrilete"), "agent");
const piAgentDir = () => process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
const readJson = (file) => {
	try {
		return JSON.parse(readFileSync(file, "utf8"));
	} catch {
		return undefined;
	}
};

/**
 * pi to run: the one on the PATH (your version) or, without it, the one npm installed next to this package
 * (peerDependency), so \`npm i -g barrilete-pi\` is enough. null if there is none.
 */
function findPi() {
	for (const dir of (process.env.PATH || "").split(delimiter)) {
		if (!dir) continue;
		try {
			accessSync(join(dir, "pi"), constants.X_OK);
			return { command: join(dir, "pi"), prefix: [] };
		} catch {}
	}
	try {
		const pkg = createRequire(import.meta.url).resolve("@mariozechner/pi-coding-agent/package.json");
		const bin = JSON.parse(readFileSync(pkg, "utf8")).bin;
		const rel = typeof bin === "string" ? bin : bin?.pi;
		if (rel) return { command: process.execPath, prefix: [join(dirname(pkg), rel)] };
	} catch {}
	return null;
}

/** pi creates an empty auth.json on start: a login is one with at least one provider in it. */
const hasLogin = (dir) => Object.keys(readJson(join(dir, "auth.json")) ?? {}).length > 0;

const HELP = `barrilete ${VERSION}: Barrilete Kit on pi

Usage:
  barrilete [pi options]              pi with barrilete-pi, in its own home (${ownAgentDir()})
  barrilete --link [pi options]       pi with barrilete-pi, in your pi home (${piAgentDir()})
  barrilete home import-pi [--dry-run]
                                      copy your pi login (auth.json) and default model into the own home
  barrilete doctor                    check pi, python3, gh and the project
  barrilete --help | --version

Environment: BARRILETE_HOME (own home, default ~/.barrilete), BARRILETE_MODELS (subagent models),
BARRILETE_STATUS_HOOK (command that receives the agent status). See the package README.
`;

function launch(args) {
	const link = args.includes("--link");
	const piArgs = args.filter((a) => a !== "--link");
	const env = { ...process.env };
	if (!link) {
		const dir = ownAgentDir();
		mkdirSync(dir, { recursive: true });
		env.PI_CODING_AGENT_DIR = dir;
		if (!hasLogin(dir) && hasLogin(piAgentDir())) {
			process.stderr.write("barrilete: the own home has no login. To reuse pi's: barrilete home import-pi (or barrilete --link).\n");
		}
	}
	const pi = findPi();
	if (!pi) {
		process.stderr.write("barrilete: pi is not installed. Install it with: npm i -g @mariozechner/pi-coding-agent\n");
		process.exit(127);
	}
	const child = spawn(pi.command, [...pi.prefix, "-e", PACKAGE_DIR, ...piArgs], { stdio: "inherit", env });
	for (const sig of ["SIGINT", "SIGTERM", "SIGHUP"]) process.on(sig, () => {}); // pi handles them itself
	child.on("error", (e) => {
		process.stderr.write(`barrilete: could not start pi: ${e.message}\n`);
		process.exit(1);
	});
	child.on("exit", (code, signal) => process.exit(signal ? 1 : (code ?? 1)));
}

function importPi(args) {
	const dry = args.includes("--dry-run");
	const from = piAgentDir();
	const to = ownAgentDir();
	if (resolve(from) === resolve(to)) {
		process.stderr.write(`barrilete: the pi home and the own home are the same (${to}): nothing to import.\n`);
		return 1;
	}
	const plan = [];
	const auth = join(from, "auth.json");
	if (!hasLogin(from)) plan.push(`skip  auth.json: ${auth} has no login (log in with pi, or /login inside barrilete)`);
	else if (hasLogin(to)) plan.push("keep  auth.json: the own home already has a login (never overwritten)");
	else plan.push(`copy  auth.json → ${join(to, "auth.json")} (0600)`);

	const theirs = readJson(join(from, "settings.json")) ?? {};
	const ours = readJson(join(to, "settings.json")) ?? {};
	const added = {};
	for (const k of MODEL_KEYS) {
		if (theirs[k] === undefined) continue;
		if (ours[k] !== undefined) plan.push(`keep  ${k}: already set in the own home`);
		else {
			added[k] = theirs[k];
			plan.push(`set   ${k} = ${JSON.stringify(theirs[k])}`);
		}
	}
	if (!MODEL_KEYS.some((k) => theirs[k] !== undefined)) plan.push("skip  default model: your pi settings have none");

	process.stdout.write(`${dry ? "Would do" : "Done"} (${from} → ${to}):\n${plan.map((l) => `  ${l}`).join("\n")}\n`);
	process.stdout.write("Packages, extensions, sessions and caches are not copied. Two copies of a login can log one out if the provider rotates refresh tokens: --link shares a single one.\n");
	if (dry) return 0;
	mkdirSync(to, { recursive: true });
	if (plan.some((l) => l.startsWith("copy  auth.json"))) {
		copyFileSync(auth, join(to, "auth.json"));
		chmodSync(join(to, "auth.json"), 0o600);
	}
	if (Object.keys(added).length) writeFileSync(join(to, "settings.json"), `${JSON.stringify({ ...ours, ...added }, null, 2)}\n`);
	return 0;
}

function doctor() {
	const rows = [];
	const check = (name, ok, detail, hint) => rows.push({ name, ok, detail, hint });
	const run = (cmd, args, cwd) => spawnSync(cmd, args, { encoding: "utf8", cwd });

	const found = findPi();
	const pi = found ? run(found.command, [...found.prefix, "--version"]) : { status: 1 };
	const where = found ? (found.prefix.length ? "next to barrilete-pi" : found.command) : "";
	check("pi", pi.status === 0, pi.status === 0 ? `${(pi.stdout.trim() || pi.stderr.trim())} (${where})` : "not found", "npm i -g @mariozechner/pi-coding-agent");
	const py = run("python3", ["--version"]);
	check("python3", py.status === 0, py.status === 0 ? py.stdout.trim() : "not found", "the guardrails and the flow line need it");
	const gh = run("gh", ["auth", "status"]);
	check("gh", gh.status === 0, gh.status === 0 ? "authenticated" : "missing or not logged in", "gh auth login (the skills use it)");
	const top = run("git", ["rev-parse", "--show-toplevel"], process.cwd());
	const root = top.status === 0 ? top.stdout.trim() : "";
	const isProject = Boolean(root) && existsSync(join(root, "scripts/agents/guardrails.py"));
	check("project", isProject, isProject ? root : "not inside a Barrilete project", "open barrilete at the root of a repo with the kit (it does nothing elsewhere)");
	const own = ownAgentDir();
	check("login (own home)", hasLogin(own), own, "barrilete home import-pi, /login inside barrilete, or barrilete --link");
	const hook = process.env.BARRILETE_STATUS_HOOK;
	if (hook) {
		const path = hook.startsWith("~/") ? homedir() + hook.slice(1) : hook;
		check("status hook", existsSync(path), path, "BARRILETE_STATUS_HOOK points to a file that does not exist");
	}

	for (const r of rows) {
		process.stdout.write(`${r.ok ? "ok  " : "FAIL"} ${r.name.padEnd(17)} ${r.detail}${r.ok ? "" : `\n     → ${r.hint}`}\n`);
	}
	return rows.every((r) => r.ok) ? 0 : 1;
}

const args = process.argv.slice(2);
if (args[0] === "--help" || args[0] === "-h" || args[0] === "help") process.stdout.write(HELP);
else if (args[0] === "--version" || args[0] === "-v") process.stdout.write(`barrilete ${VERSION}\n`);
else if (args[0] === "doctor") process.exit(doctor());
else if (args[0] === "home" && args[1] === "import-pi") process.exit(importPi(args.slice(2)));
else if (args[0] === "home") {
	process.stderr.write("barrilete: unknown home command. Use: barrilete home import-pi [--dry-run]\n");
	process.exit(64);
} else launch(args);
