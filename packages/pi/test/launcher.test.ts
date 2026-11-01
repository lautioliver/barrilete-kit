// Tests of bin/barrilete.mjs with a fake `pi` on the PATH and HOME in a temp dir, so the real pi
// installation and home are never touched. Run: node --test packages/pi/test/*.test.ts
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { after, beforeEach, describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const PKG = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const BIN = join(PKG, "bin/barrilete.mjs");
const TMP = mkdtempSync(join(tmpdir(), "barrilete-bin-"));
after(() => rmSync(TMP, { recursive: true, force: true }));

let home: string, fakeBin: string, log: string;
beforeEach(() => {
	home = mkdtempSync(join(TMP, "home-"));
	fakeBin = join(home, "bin");
	log = join(home, "pi-launch.json");
	mkdirSync(fakeBin);
	writeFileSync(
		join(fakeBin, "pi"),
		`#!${process.execPath}
require("node:fs").writeFileSync(${JSON.stringify(log)}, JSON.stringify({ args: process.argv.slice(2), agentDir: process.env.PI_CODING_AGENT_DIR ?? null }));
process.exit(Number(process.env.FAKE_PI_EXIT ?? 0));
`,
		{ mode: 0o755 },
	);
});

function barrilete(args: string[], extra: Record<string, string | undefined> = {}, withPi = true) {
	const env: Record<string, string> = { PATH: `${withPi ? `${fakeBin}:` : ""}/usr/bin:/bin`, HOME: home };
	for (const [k, v] of Object.entries(extra)) if (v !== undefined) env[k] = v;
	const r = spawnSync(process.execPath, [BIN, ...args], { encoding: "utf8", env, cwd: home });
	return { code: r.status, out: r.stdout, err: r.stderr };
}
const launched = () => JSON.parse(readFileSync(log, "utf8"));
const piHome = () => join(home, ".pi/agent");
const ownHome = () => join(home, ".barrilete/agent");

describe("launch", () => {
	test("opens pi with the package, in its own home", () => {
		const r = barrilete(["--model", "sonnet", "hola"]);
		assert.equal(r.code, 0);
		assert.deepEqual(launched().args, ["-e", PKG, "--model", "sonnet", "hola"]);
		assert.equal(launched().agentDir, ownHome());
		assert.ok(existsSync(ownHome()));
	});

	test("BARRILETE_HOME moves the own home", () => {
		barrilete([], { BARRILETE_HOME: join(home, "otro") });
		assert.equal(launched().agentDir, join(home, "otro/agent"));
	});

	test("--link uses the pi home as is and is not passed to pi", () => {
		barrilete(["--link", "-c"]);
		assert.deepEqual(launched().args, ["-e", PKG, "-c"]);
		assert.equal(launched().agentDir, null);
		barrilete(["--link"], { PI_CODING_AGENT_DIR: join(home, "custom") });
		assert.equal(launched().agentDir, join(home, "custom"));
	});

	test("returns pi's exit code", () => {
		assert.equal(barrilete([], { FAKE_PI_EXIT: "3" }).code, 3);
	});

	test("without pi on the PATH it runs the pi npm installed next to the package", () => {
		// A copy of the package with a pi in node_modules shaped like the real one: `exports` without
		// "./package.json", which is how npm i -g barrilete-pi leaves it (peerDependency).
		const pkg = join(home, "global/barrilete-pi");
		const pi = join(pkg, "node_modules/@mariozechner/pi-coding-agent");
		mkdirSync(join(pkg, "bin"), { recursive: true });
		mkdirSync(join(pi, "dist"), { recursive: true });
		writeFileSync(join(pkg, "bin/barrilete.mjs"), readFileSync(BIN));
		writeFileSync(join(pkg, "package.json"), readFileSync(join(PKG, "package.json")));
		writeFileSync(
			join(pi, "package.json"),
			JSON.stringify({ name: "@mariozechner/pi-coding-agent", type: "module", bin: { pi: "dist/cli.js" }, exports: { ".": "./dist/index.js" } }),
		);
		writeFileSync(join(pi, "dist/index.js"), "export {};\n");
		writeFileSync(
			join(pi, "dist/cli.js"),
			`import { writeFileSync } from "node:fs";\nwriteFileSync(${JSON.stringify(log)}, JSON.stringify({ args: process.argv.slice(2), agentDir: process.env.PI_CODING_AGENT_DIR ?? null }));\n`,
		);
		const r = spawnSync(process.execPath, [join(pkg, "bin/barrilete.mjs"), "hola"], {
			encoding: "utf8",
			env: { PATH: "/usr/bin:/bin", HOME: home },
			cwd: home,
		});
		assert.equal(r.status, 0, r.stderr);
		assert.deepEqual(launched().args, ["-e", pkg, "hola"]);
	});

	test("without pi it says how to install it", () => {
		const r = barrilete([], {}, false);
		assert.equal(r.code, 127);
		assert.match(r.err, /npm i -g @mariozechner\/pi-coding-agent/);
	});

	test("hints at import-pi when pi has a login and the own home does not", () => {
		mkdirSync(piHome(), { recursive: true });
		writeFileSync(join(piHome(), "auth.json"), "{}"); // what pi leaves on start: not a login
		assert.doesNotMatch(barrilete([]).err, /import-pi/);
		writeFileSync(join(piHome(), "auth.json"), '{"anthropic":{}}');
		assert.match(barrilete([]).err, /barrilete home import-pi/);
		assert.doesNotMatch(barrilete(["--link"]).err, /import-pi/);
	});
});

describe("home import-pi", () => {
	beforeEach(() => {
		mkdirSync(piHome(), { recursive: true });
		writeFileSync(join(piHome(), "auth.json"), '{"anthropic":{"type":"oauth"}}');
		writeFileSync(
			join(piHome(), "settings.json"),
			JSON.stringify({ defaultProvider: "anthropic", defaultModel: "sonnet", theme: "dark", packages: ["x"] }),
		);
	});

	test("--dry-run says what it would do and writes nothing", () => {
		const r = barrilete(["home", "import-pi", "--dry-run"]);
		assert.equal(r.code, 0);
		assert.match(r.out, /Would do[\s\S]*copy {2}auth\.json[\s\S]*set {3}defaultProvider = "anthropic"/);
		assert.equal(existsSync(join(ownHome(), "auth.json")), false);
	});

	test("copies the login (0600) and the default model, nothing else", () => {
		assert.equal(barrilete(["home", "import-pi"]).code, 0);
		assert.equal(readFileSync(join(ownHome(), "auth.json"), "utf8"), '{"anthropic":{"type":"oauth"}}');
		assert.equal(statSync(join(ownHome(), "auth.json")).mode & 0o777, 0o600);
		assert.deepEqual(JSON.parse(readFileSync(join(ownHome(), "settings.json"), "utf8")), {
			defaultProvider: "anthropic",
			defaultModel: "sonnet",
		});
	});

	test("an empty auth.json in the own home (pi leaves one on start) is replaced by the login", () => {
		mkdirSync(ownHome(), { recursive: true });
		writeFileSync(join(ownHome(), "auth.json"), "{}");
		assert.match(barrilete(["home", "import-pi"]).out, /copy {2}auth\.json/);
		assert.equal(readFileSync(join(ownHome(), "auth.json"), "utf8"), '{"anthropic":{"type":"oauth"}}');
	});

	test("never overwrites what the own home already has", () => {
		mkdirSync(ownHome(), { recursive: true });
		writeFileSync(join(ownHome(), "auth.json"), '{"openai":{}}');
		writeFileSync(join(ownHome(), "settings.json"), JSON.stringify({ defaultModel: "opus", theme: "light" }));
		const r = barrilete(["home", "import-pi"]);
		assert.match(r.out, /keep {2}auth\.json[\s\S]*keep {2}defaultModel/);
		assert.equal(readFileSync(join(ownHome(), "auth.json"), "utf8"), '{"openai":{}}');
		assert.deepEqual(JSON.parse(readFileSync(join(ownHome(), "settings.json"), "utf8")), {
			defaultModel: "opus",
			theme: "light",
			defaultProvider: "anthropic",
		});
	});

	test("refuses when both homes are the same", () => {
		const r = barrilete(["home", "import-pi"], { BARRILETE_HOME: join(home, ".pi") });
		assert.equal(r.code, 1);
		assert.match(r.err, /are the same/);
	});
});

test("--version, --help and unknown home commands", () => {
	const v = JSON.parse(readFileSync(join(PKG, "package.json"), "utf8")).version;
	assert.equal(barrilete(["--version"]).out, `barrilete ${v}\n`);
	assert.match(barrilete(["--help"]).out, /barrilete --link/);
	assert.equal(barrilete(["home", "nope"]).code, 64);
});
