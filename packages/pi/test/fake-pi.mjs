#!/usr/bin/env node
// A fake `pi --mode json -p` for the subagent tests: it writes what it was launched with (args, cwd, the
// barrilete env and the appended system prompt) to $FAKE_PI_LOG/<pid>.json and replies like pi does, with
// message_end events. FAKE_PI_REPLY is the final text, FAKE_PI_EXIT the exit code, FAKE_PI_SLEEP_MS a delay.
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const args = process.argv.slice(2);
const i = args.indexOf("--append-system-prompt");
const prompt = i >= 0 ? readFileSync(args[i + 1], "utf8") : "";
if (process.env.FAKE_PI_LOG) {
	writeFileSync(
		join(process.env.FAKE_PI_LOG, `${process.pid}.json`),
		JSON.stringify({
			args,
			cwd: process.cwd(),
			subagent: process.env.BARRILETE_SUBAGENT,
			trusted: process.env.BARRILETE_TRUSTED_ROOT,
			prompt,
		}),
	);
}
const say = (message) => process.stdout.write(`${JSON.stringify({ type: "message_end", message })}\n`);
say({ role: "user", content: [{ type: "text", text: args.at(-1) }] });
setTimeout(() => {
	const reply = process.env.FAKE_PI_REPLY;
	if (reply !== "") {
		const task = args.at(-1);
		say({
			role: "assistant",
			model: "fake-model",
			usage: { cost: { total: 0.01 } },
			content: [{ type: "text", text: reply ?? `result: pr\nissue: 1\n${task}` }],
		});
	}
	process.exit(Number(process.env.FAKE_PI_EXIT ?? 0));
}, Number(process.env.FAKE_PI_SLEEP_MS ?? 0));
