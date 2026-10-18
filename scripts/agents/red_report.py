#!/usr/bin/env python3
"""Validates the red of a TDD cycle with structured evidence (ADR-002, kit/ADR-002).

Called by .claude/skills/implement-issue/red.sh, which is a thin wrapper. It:
  1. reads the `red` section of docs/agents-map.json (a list of stacks, D2);
  2. runs every stack whose `when` matches a file of the red commit (HEAD against its first
     parent), with a path of its own for the report ({out}), a timeout and its own process group (D5);
  3. parses the report (JUnit XML or TAP) without executing anything it reads (D3);
  4. requires that every failed case is a case the red commit adds or changes (D4).

Fail closed: anything that is not clearly a valid red exits with 2.
Exit codes: 0 valid red, 1 the tests pass, 2 rejected, 64 wrong usage.

Usage: red_report.py [--map FILE] [<stack>]
"""
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

MAX_BYTES = 20 * 1024 * 1024
DEFAULT_TIMEOUT = 600
SAFE_PATH = re.compile(r"^[A-Za-z0-9_./+@%-]+$")


def glob_to_regex(glob):
    """Git-style glob: ** crosses directories, * does not (the rule of agents_map.py, which the small profile
    does not install, so it is repeated here). A leading "?" only marks the path as optional."""
    glob = glob[1:] if glob.startswith("?") else glob
    r, i = "", 0
    while i < len(glob):
        if glob.startswith("**/", i):
            r += "(?:.*/)?"
            i += 3
        elif glob.startswith("**", i):
            r += ".*"
            i += 2
        elif glob[i] == "*":
            r += "[^/]*"
            i += 1
        else:
            r += re.escape(glob[i])
            i += 1
    return re.compile(r + "$")


class Reject(Exception):
    """A reason to exit with 2. The message says what to do."""


# --------------------------------------------------------------------------- reports

class Case:
    __slots__ = ("file", "classname", "name", "status")

    def __init__(self, file, classname, name, status):
        self.file = file          # path given by the reporter, or None
        self.classname = classname  # JUnit classname, or ""
        self.name = name
        self.status = status      # pass | failure | error | skipped


class Report:
    def __init__(self):
        self.cases = []
        self.errors = []    # reasons that make the run an error (D3: 0 error)
        self.aborted = []   # reasons that make the report incomplete (D3: no aborted case)

    def executed(self):
        return [c for c in self.cases if c.status != "skipped"]

    def failed(self):
        return [c for c in self.cases if c.status == "failure"]

    def errored(self):
        return [c for c in self.cases if c.status == "error"]


def read_report(path):
    """Bytes of the report, checked: a regular file (not a link), at most 20 MB, UTF-8."""
    try:
        st = os.lstat(path)
    except OSError:
        raise Reject("the report was not created in this run")
    if not stat.S_ISREG(st.st_mode):
        raise Reject("the report is not a regular file")
    if st.st_size > MAX_BYTES:
        raise Reject("the report is larger than 20 MB: it is not read")
    with open(path, "rb") as f:
        data = f.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise Reject("the report is larger than 20 MB: it is not read")
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        raise Reject("the report is not UTF-8")
    if b"\0" in data:
        # UTF-16 and UTF-32 without a BOM are "valid UTF-8" because of their NUL bytes, and expat detects them by itself
        raise Reject("the report is not UTF-8 text (it has NUL bytes)")
    return data


def int_attr(el, name):
    v = el.get(name)
    if v is None:
        return None
    try:
        return int(v)
    except ValueError:
        return -1


def is_suite_level(diff, case):
    """A failure that is not a test: vitest reports a file that did not load as a case named like its file (a
    path of the repository), and gotestsum reports a package that failed outside any test (build failure, panic
    in TestMain) as TestMain."""
    if case.name == "TestMain":
        return True
    return bool(case.name) and case.name == case.classname and normalize_path(diff, case.name) is not None


def parse_junit(path):
    data = read_report(path)
    if not data.strip():
        raise Reject("the report is empty")
    text = data.decode("utf-8")
    if re.search(r"<!DOCTYPE", text, re.I):
        raise Reject("the report has a <!DOCTYPE: a JUnit report never needs one, so it is rejected")
    # XML allows spaces or tabs around "=", and a UTF-8 BOM can come before the declaration (\s does not match it)
    decl = re.match(r"[\s\ufeff]*<\?xml[^>]*?\bencoding\s*=\s*[\"']([^\"']+)[\"']", text)
    if decl and decl.group(1).lower().replace("_", "-") not in ("utf-8", "utf8"):
        raise Reject("the XML declares an encoding other than UTF-8")
    try:
        # whatever the declaration says, expat reads the bytes as UTF-8 (the check above rejects the others)
        root = ET.fromstring(data, parser=ET.XMLParser(encoding="utf-8"))
    except ET.ParseError as e:
        raise Reject(f"the report is truncated or is not valid XML ({e})")
    if root.tag not in ("testsuites", "testsuite"):
        raise Reject(f"the root of the report is <{root.tag}>, not <testsuites> or <testsuite>")

    rep = Report()
    parents = {}
    for p in root.iter():
        for c in p:
            parents[c] = p

    def suite_file(el):
        while el in parents:
            el = parents[el]
            if el.tag == "testsuite" and el.get("file"):
                return el.get("file")
        return None

    for tc in root.iter("testcase"):
        kinds = {c.tag for c in tc}
        if "error" in kinds:
            status = "error"
        elif "failure" in kinds:
            status = "failure"
        elif "skipped" in kinds:
            status = "skipped"
        else:
            status = "pass"
        rep.cases.append(Case(tc.get("file") or suite_file(tc), tc.get("classname") or "", tc.get("name") or "", status))

    for suite in root.iter("testsuite"):
        inner = list(suite.iter("testcase"))
        declared = int_attr(suite, "tests")
        if declared is not None and declared != len(inner):
            rep.aborted.append(f'testsuite "{suite.get("name", "")}" declares tests={suite.get("tests")} '
                               f"but contains {len(inner)} testcase elements")
        for attr, tag in (("errors", "error"), ("failures", "failure")):
            d = int_attr(suite, attr)
            counted = sum(1 for tc in inner if any(c.tag == tag for c in tc))
            if d is not None and d > counted:
                rep.aborted.append(f'testsuite "{suite.get("name", "")}" declares {attr}={suite.get(attr)} '
                                   f"but only {counted} testcase elements carry a <{tag}>")
        for child in suite:
            if child.tag in ("error", "failure"):
                rep.errors.append(f'testsuite "{suite.get("name", "")}" has a <{child.tag}> outside any testcase')
    return rep


TAP_CASE = re.compile(r"^(not )?ok(?=\s|$)(?:\s+(\d+))?\s*(?:-\s*)?(.*)$")
TAP_DIRECTIVE = re.compile(r"\s#\s*(TODO|SKIP)\w*\b", re.I)


def parse_tap(path):
    data = read_report(path)
    if not data.strip():
        raise Reject("the report is empty")
    rep = Report()
    plan, plan_at, cur_file, first_case_at, last_case_at = None, None, None, None, None
    for i, line in enumerate(data.decode("utf-8").splitlines()):
        if not line.strip() or line[0] in " \t":
            continue  # blank lines and indented diagnostics (YAML blocks, subtests) are not cases
        if re.match(r"^Bail out!", line, re.I):
            rep.errors.append(f"line {i + 1}: {line.strip()}")
            continue
        m = re.match(r"^1\.\.(\d+)\s*(#.*)?$", line)
        if m:
            if plan is not None:
                rep.aborted.append("the TAP has more than one plan")
            plan, plan_at = int(m.group(1)), i
            continue
        m = re.match(r"^#\s*file:\s*(.+?)\s*$", line)
        if m:
            cur_file = m.group(1)
            continue
        m = TAP_CASE.match(line)
        if not m:
            continue  # TAP version, comments and unknown lines are ignored
        first_case_at = i if first_case_at is None else first_case_at
        last_case_at = i
        rest = m.group(3)
        directive = TAP_DIRECTIVE.search(rest)
        # The id is the text of the case line without its directive, with the TAP 14 escapes (\# and \\) undone.
        # What tap.sh varies at run time goes in "# desc:" lines, which are comments and are not compared (D4).
        ident = re.sub(r"\\(.)", r"\1", (rest[:directive.start()] if directive else rest).strip())
        failed = bool(m.group(1))
        if directive:
            kind = directive.group(1).upper()
            if kind == "SKIP" or (kind == "TODO" and failed):
                status = "skipped"
            else:
                status = "pass"
        else:
            status = "failure" if failed else "pass"
        rep.cases.append(Case(cur_file, "", ident, status))
    if plan is None:
        rep.aborted.append("the TAP has no plan (1..N)")
    else:
        if first_case_at is not None and first_case_at < plan_at < last_case_at:
            rep.aborted.append("the plan of the TAP is in the middle of the cases")
        if plan != len(rep.cases):
            rep.aborted.append(f"the plan says {plan} cases and the TAP has {len(rep.cases)}")
    return rep


# --------------------------------------------------------------------------- the diff of the red commit

def git(root, *args, check=True):
    r = subprocess.run(["git", "-C", root, *args], capture_output=True)
    if check and r.returncode != 0:
        raise Reject(f"git {' '.join(args[:2])} failed: {r.stderr.decode('utf-8', 'replace').strip()}")
    return r


class Diff:
    """The red commit against its first parent: which files it adds or changes, and the lines it adds."""

    def __init__(self, root, commit):
        self.root, self.commit = root, commit
        r = git(root, "rev-parse", "--verify", "-q", f"{commit}^1", check=False)
        if r.returncode != 0:
            raise Reject("the red commit has no parent: there is nothing to compare against. "
                         "Commit the red tests on top of the base branch.")
        self.parent = r.stdout.decode().strip()
        raw = git(root, "diff", "--raw", "-z", "-M", "--no-ext-diff", self.parent, commit).stdout.decode("utf-8", "replace")
        self.status = {}   # new path -> A | M | R
        self.old_path = {}
        parts = [p for p in raw.split("\0")]
        i = 0
        while i < len(parts) and parts[i]:
            code = parts[i].split()[-1]
            if code[0] in "RC":
                old, new = parts[i + 1], parts[i + 2]
                i += 3
                self.status[new] = "R"
                self.old_path[new] = old
            else:
                path = parts[i + 1]
                i += 2
                if code[0] != "D":
                    self.status[path] = "A" if code[0] == "A" else "M"
        self._added = {}
        self._tree = None

    def files(self):
        return sorted(self.status)

    def tree(self):
        if self._tree is None:
            out = git(self.root, "ls-tree", "-r", "--name-only", "-z", self.commit).stdout.decode("utf-8", "replace")
            self._tree = set(p for p in out.split("\0") if p)
        return self._tree

    def read(self, path):
        r = git(self.root, "show", f"{self.commit}:{path}", check=False)
        return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None

    def is_new(self, path):
        return self.status.get(path) == "A"

    def added(self, path):
        """[(line number, text)] added by the diff in `path`."""
        if path not in self._added:
            lines = []
            if self.status.get(path) == "A":
                lines = [(i + 1, t) for i, t in enumerate((self.read(path) or "").split("\n"))]
            elif path in self.status:
                paths = [path] + ([self.old_path[path]] if path in self.old_path else [])
                out = git(self.root, "diff", "-U0", "-M", "--no-color", "--no-ext-diff", self.parent, self.commit,
                          "--", *paths).stdout.decode("utf-8", "replace")
                n, in_hunk = 0, False
                for line in out.split("\n"):
                    h = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
                    if h:
                        n, in_hunk = int(h.group(1)), True
                    elif in_hunk and line.startswith("+"):
                        lines.append((n, line[1:]))
                        n += 1
            self._added[path] = lines
        return self._added[path]


# --------------------------------------------------------------------------- mapping a case to its file

class Unmapped(Exception):
    pass


JS_EXT = (".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts")


def normalize_path(diff, p):
    """A path from the report, as a path of the repository, or None."""
    if not p:
        return None
    if os.path.isabs(p):
        rel = os.path.relpath(p, diff.root)
        if rel.startswith(".."):
            return None
        p = rel
    p = re.sub(r"^(\./)+", "", p)
    if ".." in p.split("/"):
        return None
    tree = diff.tree()
    if p in tree:
        return p
    # The runner ran in a subdirectory (rootdir): a path that only one file of the repository ends with.
    ends = [t for t in tree if t.endswith("/" + p)]
    return ends[0] if len(ends) == 1 else None


def go_module(diff):
    text = diff.read("go.mod")
    m = re.search(r"^module\s+(\S+)", text or "", re.M)
    return m.group(1).strip('"') if m else None


def cargo_crates(diff):
    """[(dir, package name)] of the root package and of the members of the root Cargo.toml workspace."""
    text = diff.read("Cargo.toml")
    if text is None:
        return []
    crates = []

    def pkg_name(t):
        m = re.search(r"^\[package\][^\[]*?^\s*name\s*=\s*[\"']([^\"']+)[\"']", t, re.M | re.S)
        return m.group(1) if m else None

    if pkg_name(text):
        crates.append(("", pkg_name(text)))
    m = re.search(r"^\[workspace\].*?^\s*members\s*=\s*\[(.*?)\]", text, re.M | re.S)
    if m:
        for pat in re.findall(r"[\"']([^\"']+)[\"']", m.group(1)):
            rx = glob_to_regex(pat.rstrip("/"))
            for t in sorted(diff.tree()):
                if t.endswith("/Cargo.toml") and rx.match(t[:-len("/Cargo.toml")]):
                    d = t[:-len("/Cargo.toml")]
                    name = pkg_name(diff.read(t) or "")
                    if name and (d, name) not in crates:
                        crates.append((d, name))
    return crates


def crate_files(tree, crate_dir, base, mod_path, roots):
    """Trims the module path segment by segment until a file exists, never past the root of the crate."""
    pre = (crate_dir + "/" if crate_dir else "")
    for k in range(len(mod_path), 0, -1):
        rel = "/".join(mod_path[:k])
        found = [p for p in (f"{pre}{base}/{rel}.rs", f"{pre}{base}/{rel}/mod.rs") if p in tree]
        if found:
            return k, found
    found = [pre + r for r in roots if pre + r in tree]
    return (0, found) if found else (None, [])


def cargo_files(diff, case):
    """Candidate files of a cargo case. cargo2junit gives the module path in `classname`; nextest gives
    the binary id in `classname` (the crate, then bin/<name> or the integration test) and the module path in the name."""
    crates = cargo_crates(diff)
    if not crates:
        raise Unmapped("Cargo.toml (root or workspace members) was not found, so a module path cannot be mapped to a file")
    tree = diff.tree()
    cls = [s for s in case.classname.split("::") if s]
    names = {n: d for d, n in crates}
    names.update({n.replace("-", "_"): d for d, n in crates})
    mod_path = case.name.split("::")[:-1] if "::" in case.name else None
    crate_dirs = [d for d, _ in crates]
    binary = None
    if cls and cls[0] in names:  # nextest binary id
        crate_dirs = [names[cls[0]]]
        binary = cls[1] if len(cls) > 1 else None
        if mod_path is None:
            mod_path = []
    elif mod_path is None:       # cargo2junit
        mod_path = cls
    if binary and binary.startswith("bin/"):
        base, roots = f"src/bin/{binary[4:]}", [f"src/bin/{binary[4:]}.rs", f"src/bin/{binary[4:]}/main.rs", "src/main.rs"]
    elif binary:
        base, roots = f"tests/{binary}", [f"tests/{binary}.rs", f"tests/{binary}/main.rs"]
    else:
        base, roots = "src", ["src/lib.rs", "src/main.rs"]
    found = []
    for d in crate_dirs:
        k, files = crate_files(tree, d, base, mod_path, roots)
        if files:
            found.append((k, files))
    if not found:
        raise Unmapped(f'the module path of "{case.classname}" / "{case.name}" maps to no file of the crate')
    best = max(k for k, _ in found)
    best_found = [f for k, f in found if k == best]
    if len(best_found) > 1:
        raise Unmapped(f'"{case.classname}" / "{case.name}" can belong to more than one crate of the workspace: '
                       "use nextest, whose binary id names the crate")
    return best_found[0]


def case_files(diff, case):
    """(kind, [candidate files], scope) for a case, cached. Raises Unmapped when it cannot be mapped (D4: fail closed)."""
    key = (case.file, case.classname, case.name)
    cache = diff.__dict__.setdefault("_mapped", {})
    if key not in cache:
        try:
            cache[key] = case_files_uncached(diff, case)
        except Unmapped as e:
            cache[key] = e
    if isinstance(cache[key], Unmapped):
        raise cache[key]
    return cache[key]


def case_files_uncached(diff, case):
    if case.file:
        f = normalize_path(diff, case.file)
        if f is None:
            raise Unmapped(f'the file "{case.file}" of the report is not a file of the repository')
        return "file", [f], f
    cls = case.classname
    if cls:
        f = normalize_path(diff, cls) if "/" in cls or cls.endswith(JS_EXT) else None
        if f and f in diff.tree():
            return "file", [f], f
        mod = go_module(diff)
        if mod and (cls == mod or cls.startswith(mod + "/")):
            d = cls[len(mod) + 1:]
            pre = d + "/" if d else ""
            files = sorted(t for t in diff.tree()
                           if t.startswith(pre) and t.endswith("_test.go") and "/" not in t[len(pre):])
            if not files:
                raise Unmapped(f'the package "{cls}" has no *_test.go file in "{d or "."}"')
            return "go", files, "go:" + cls
    mod = go_module(diff)
    if mod and not cargo_crates(diff):
        raise Unmapped(f'the classname "{cls}" is not under the module "{mod}" of go.mod: configure gotestsum so that '
                       "the classname is the package import path")
    files = cargo_files(diff, case)
    return "cargo", files, "cargo:" + ",".join(files)


# --------------------------------------------------------------------------- is the case defined by an added line?

def strip_comment(line, markers):
    """The line without a trailing comment (quote-aware, good enough for a name search)."""
    quote, i = None, 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "\"'`":
            quote = ch
        else:
            for mk in markers:
                if line.startswith(mk, i) and (mk != "#" or i == 0 or line[i - 1] in " \t;"):
                    return line[:i]
        i += 1
    return line


def base_name(kind, ext, name):
    if ext == ".py":
        return name.split("[", 1)[0]
    if ext == ".go":
        return name.split("/", 1)[0]
    if ext == ".rs":
        return name.split("::")[-1]
    if ext in JS_EXT:
        return name.split(" > ")[-1]
    return name


PLACEHOLDER = re.compile(r"%[sdifjoOp#]|%%|\$\{[^}]*\}|\$[A-Za-z_][\w.]*")


def title_matches(template, name):
    """An it.each template: placeholders are wildcards and the whole name has to match."""
    parts, last, literal = [], 0, ""
    for m in PLACEHOLDER.finditer(template):
        lit = template[last:m.start()]
        literal += lit
        parts.append(re.escape(lit))
        parts.append(re.escape("%") if m.group(0) == "%%" else ".*")
        last = m.end()
    lit = template[last:]
    literal += lit
    parts.append(re.escape(lit))
    if not literal.strip():
        return False  # a title made only of placeholders would match any name
    return re.fullmatch("".join(parts), name, re.S) is not None


JS_PLAIN = re.compile(
    r"(?<![\w$.])(?:it|test)(?:\.(?:only|skip|concurrent|todo|fails|failing|sequential))*\s*\(\s*([\"'`])((?:\\.|(?!\1).)*)\1")
JS_EACH_CALL = re.compile(r"[)`]\s*\(\s*([\"'`])((?:\\.|(?!\1).)*)\1")


def unescape_js(s):
    return re.sub(r"\\(.)", r"\1", s)


JS_EACH = re.compile(r"(?<![\w$])(?:it|test)(?:\.[a-zA-Z]+)*\.each\b")
JS_CLOSE = re.compile(r"^\s*[\])`]+\s*\(\s*([\"'`])((?:\\.|(?!\1).)*)\1")


def js_defines(added, name):
    """Does an added line define `name` with it(...) or test(...)? The whole string literal has to be the name.
    For it.each the title can have placeholders (%s, $x, ${...}) that match anything, and the whole name has to
    match. The title is in the same line as `.each` or, when the table takes several lines, in the line that closes it
    (`])('title', ...)`), which has to be an added line too."""
    pending, prev = False, None
    for no, line in added:
        if prev is None or no != prev + 1:
            pending = False  # the closing line must come right after added lines of the same block
        prev = no
        if line.strip().startswith(("//", "*", "/*")):
            continue
        code = strip_comment(line, ["//"])
        for m in JS_PLAIN.finditer(code):
            if unescape_js(m.group(2)) == name:
                return True
        em = JS_EACH.search(code)
        if em:
            found = False
            for m in JS_EACH_CALL.finditer(code[em.end():]):
                found = True
                title = unescape_js(m.group(2))
                if title == name or title_matches(title, name):
                    return True
            pending = not found
        elif pending:
            m = JS_CLOSE.match(code)
            if m:
                pending = False
                title = unescape_js(m.group(2))
                if title == name or title_matches(title, name):
                    return True
    return False


def rust_defines(diff, path, added, name):
    """An added `fn <name>` with a test attribute (`#[test]`, `#[tokio::test]`: it ends with `test]`) right above.
    The attribute is read in the file of the red commit: git can show it as context when the new test is
    inserted before another one that has the same attribute, so it is not always an added line."""
    lines = (diff.read(path) or "").split("\n")
    rx = re.compile(r"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:unsafe\s+)?fn\s+" + re.escape(name) + r"\s*[(<]")
    for no, line in added:
        if not rx.match(line):
            continue
        k = no - 2  # 0-based index of the line above
        while 0 <= k < len(lines):
            above = lines[k].strip()
            if re.search(r"\bfn\b", above):
                break  # the attribute above belongs to another function
            if above.startswith("#[") and above.endswith("test]"):
                return True
            if not (above.startswith("#[") or above.startswith("///")):
                break
            k -= 1
    return False


def defines(diff, path, added, name, ext_kind):
    """Does an added line of `path` define the test `name` (a whole identifier, never in a comment)?"""
    if ext_kind == "tap":
        # The case line of tap.sh: the id is the literal first argument of tap_ok, tap_fail or tap_check (after
        # the status). A line that only mentions the id (an echo, a variable) does not define the case.
        spellings = {name, name.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")}
        for _, line in added:
            code = strip_comment(line, ["#"])
            for sp in spellings:
                esc = re.escape(sp)
                if re.search(r"""(?<![\w])tap_(?:ok|fail)\s+(["'])""" + esc + r"""\1""", code) or \
                        re.search(r"""(?<![\w])tap_check\s+\S+\s+(["'])""" + esc + r"""\1""", code):
                    return True
        return False
    if path.endswith(".py"):
        rx = re.compile(r"^\s*(?:async\s+)?def\s+" + re.escape(name) + r"\s*\(")
        return any(rx.match(t) for _, t in added)
    if path.endswith(".go"):
        rx = re.compile(r"^\s*func\s+" + re.escape(name) + r"\s*\(")
        return any(rx.match(t) for _, t in added)
    if path.endswith(".rs"):
        return rust_defines(diff, path, added, name)
    if path.endswith(JS_EXT):
        return js_defines(added, name)
    raise Unmapped(f'I do not know how a test is defined in "{path}"')


def check_cases(diff, report, fmt):
    """D4 over the failed cases. Returns (reasons to reject, [(file, name)] for the PR block)."""
    problems, listed = [], []
    for c in report.failed():
        label = f"{c.file or c.classname or '?'}::{c.name}"
        try:
            if not c.name:
                raise Unmapped("the case has no name")
            if fmt == "tap":
                if not c.file:
                    raise Unmapped("a `not ok` has no `# file: <script>` line before it")
                f = normalize_path(diff, c.file)
                if f is None:
                    raise Unmapped(f'the `# file:` path "{c.file}" is not a file of the repository')
                kind, files, scope, ident, ext = "tap", [f], f, c.name, "tap"
            else:
                kind, files, scope = case_files(diff, c)
                ext = files[0][files[0].rfind("."):] if "." in files[0] else ""
                ident = base_name(kind, ext, c.name)
            # Ambiguous names: the same name in more than one describe or class of the scope.
            # (Not in TAP: the id is a literal of the helper, and a loop repeats it on purpose.)
            peers = []
            for o in ([] if fmt == "tap" else report.cases):
                if o is c:
                    continue
                try:
                    okind, ofiles, oscope = case_files(diff, o)
                    oext = ofiles[0][ofiles[0].rfind("."):] if "." in ofiles[0] else ""
                    same = oscope == scope and base_name(okind, oext, o.name) == ident
                except Unmapped:
                    continue
                if same:
                    peers.append(o)
            if peers:
                def container(x):
                    cls = x.classname[:-len(x.name)].strip() if x.name and x.classname.endswith(x.name) else x.classname
                    return (cls, " > ".join(x.name.split(" > ")[:-1]))
                if any(container(o) != container(c) or o.name == c.name for o in peers):
                    raise Unmapped(f'the name "{ident}" is ambiguous in {scope.split(":", 1)[-1]}: '
                                   "it appears more than once (two describe blocks or classes, or two packages of "
                                   "one directory). Rename the test.")
            ok = False
            for f in files:
                if f not in diff.status:
                    continue
                whole_file = diff.is_new(f) and len(files) == 1 and kind != "go"  # in a file the diff adds, every case qualifies
                if whole_file or defines(diff, f, diff.added(f), ident, "tap" if fmt == "tap" else ext):
                    ok = True
                    break
            if not ok:
                raise Unmapped(f'"{ident}" is not defined by a line this commit adds in {", ".join(files)}: it is an old '
                               "test, or a new row of an old test. The red must fail on a test that the red commit adds or changes.")
            listed.append((files[0] if len(files) == 1 else (c.file or c.classname), c.name))
        except Unmapped as e:
            hint = ""
            if "maps to no file" in str(e) or "not a file of the repository" in str(e) or "was not found" in str(e):
                hint = " (configure the reporter so each case carries its file: see docs/decisions/kit/ADR-002, D4)"
            problems.append(f"{label}: {e}{hint}")
    return problems, listed


# --------------------------------------------------------------------------- one stack

def judge(entry, rc, timed_out, report_error, report, diff):
    """(exit code, [messages], [(file, name)]) for one stack."""
    fmt = entry["format"]
    if timed_out:
        return 2, [f'the run passed its timeout ({entry["timeout"]} s) and was killed'], []
    if rc in (126, 127):
        return 2, [f"the test command did not run (exit code {rc}): check that it exists and can be executed"], []
    if rc is not None and (rc < 0 or rc > 128):
        return 2, [f"the run ended with a signal or a crash (exit code {rc})"], []
    if report_error:
        return 2, [f"{report_error}. Configure the reporter of this stack: see the `red` entry \"{entry['name']}\" "
                   "in docs/agents-map.json and docs/decisions/kit/ADR-002 (D1, D2)."], []
    for c in report.cases:
        if c.status == "failure" and is_suite_level(diff, c):
            c.status = "error"
    msgs = []
    if report.aborted:
        msgs += [f"incomplete report: {m}" for m in report.aborted]
    if report.errors or report.errored():
        msgs += [f"error (not an assertion): {m}" for m in report.errors]
        msgs += [f"error (not an assertion): {c.file or c.classname}::{c.name}" for c in report.errored()]
        msgs.append("an error (loading, setup, crash) is not a red: fix it so the tests fail on an assertion")
    if not report.executed():
        msgs.append("the report has no executed case (it has none, or all are skipped)")
    if rc == 0:
        if report.failed():
            msgs.append("the run exited with 0 but the report has failures: inconsistent")
        if msgs:
            return 2, msgs, []
        return 1, ["The tests PASS without the new code: they prove nothing. Check that they exercise the acceptance criterion."], []
    if not report.failed():
        msgs.append("the run failed but the report has no failure (an assertion): it did not fail on a test")
    if msgs:
        return 2, msgs, []
    problems, listed = check_cases(diff, report, fmt)
    if problems:
        return 2, problems, []
    return 0, [], listed


def run_stack(entry, out_dir, cwd):
    out = os.path.join(out_dir, "report." + ("xml" if entry["format"] == "junit" else "tap"))
    run = entry["run"].replace("{out}", out)
    env = dict(os.environ)
    if entry["format"] == "tap":
        env["TAP_OUT"] = out  # tap.sh writes the stream there (and not to stdout) when it sees it
    proc = subprocess.Popen(["bash", "-o", "pipefail", "-c", run], cwd=cwd, stdin=subprocess.DEVNULL,
                            start_new_session=True, env=env)
    timed_out = False
    try:
        rc = proc.wait(timeout=entry["timeout"])
    except subprocess.TimeoutExpired:
        timed_out, rc = True, None
    except BaseException:
        kill_group(proc.pid)
        raise
    kill_group(proc.pid)  # nothing keeps writing to {out} after the run
    if timed_out:
        proc.wait()
    return rc, timed_out, out


def kill_group(pid):
    try:
        os.killpg(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass


# --------------------------------------------------------------------------- the map

def load_stacks(map_path):
    try:
        with open(map_path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        raise Reject(f"cannot read {map_path}: {e}")
    stacks = data.get("red") if isinstance(data, dict) else None
    if not stacks:
        raise Reject(
            f"{map_path} has no `red` section: there is no evidence to validate the red (ADR-002, D1/D2). Declare, per stack:\n"
            '  "red": [{"name": "tests", "when": ["**/*test*"], "run": "<command that writes the report to {out}>", '
            '"format": "junit" | "tap", "timeout": 600}]\n'
            "pytest: pytest --junitxml={out} -o junit_family=xunit1 | vitest: vitest run --reporter=junit --outputFile={out} | "
            "jest: jest-junit with addFileAttribute and titleTemplate | go: gotestsum --junitfile {out} | "
            "cargo: nextest (junit) or cargo2junit | bash: tap.sh. There is no text fallback.")
    if not isinstance(stacks, list):
        raise Reject("`red` has to be a list of stacks")
    seen = set()
    for e in stacks:
        if not isinstance(e, dict):
            raise Reject("each `red` entry has to be an object")
        name = e.get("name")
        if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9._-]+", name) or name in seen:
            raise Reject("each `red` entry needs a unique `name` made of letters, digits, `.`, `_` and `-` "
                         "(it is part of the path of {out})")
        seen.add(name)
        if e.get("format") not in ("junit", "tap"):
            raise Reject(f'red "{name}": `format` has to be "junit" or "tap"')
        if not isinstance(e.get("run"), str) or "{out}" not in e["run"]:
            raise Reject(f'red "{name}": `run` has to be a string that contains {{out}}')
        w = e.get("when")
        if not isinstance(w, list) or not w or not all(isinstance(g, str) for g in w):
            raise Reject(f'red "{name}": `when` has to be a non-empty list of globs')
        t = e.get("timeout", DEFAULT_TIMEOUT)
        if isinstance(t, bool) or not isinstance(t, (int, float)) or t <= 0:
            raise Reject(f'red "{name}": `timeout` has to be a positive number of seconds')
        e["timeout"] = t
    return stacks


# --------------------------------------------------------------------------- main

def block(commit, groups):
    out = ["<details><summary>Red before implementing</summary>", "", f"red commit: {commit}", ""]
    for name, fmt, listed in groups:
        out += [f"stack: {name}", f"format: {fmt}", "failing cases:"]
        out += [f"- {f}::{n}" for f, n in sorted(set(listed))]
        out.append("")
    out.append("</details>")
    return "\n".join(out) + "\n"


def main(argv):
    args = argv[1:]
    map_path = None
    if args[:1] == ["--map"] and len(args) >= 2:
        map_path, args = args[1], args[2:]
    if len(args) > 1 or (args and args[0].startswith("-")):
        print("Usage: red.sh [<stack>]   (the command of each stack is declared in the `red` section of docs/agents-map.json;"
              " `red.sh -- <command>` no longer exists: a command typed by the agent is not declared evidence)", file=sys.stderr)
        return 64
    root = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
    if not root:
        raise Reject("this is not a git repository")
    map_path = map_path or os.path.join(root, "docs", "agents-map.json")
    stacks = load_stacks(map_path)
    commit = git(root, "rev-parse", "HEAD").stdout.decode().strip()
    if git(root, "status", "--porcelain", "--untracked-files=no").stdout.strip():
        raise Reject("there are uncommitted changes in tracked files: the red is validated for the commit "
                     "(HEAD), so commit the red tests first")
    diff = Diff(root, commit)
    if args:
        chosen = [s for s in stacks if s["name"] == args[0]]
        if not chosen:
            raise Reject(f'there is no `red` entry named "{args[0]}" (they are: {", ".join(s["name"] for s in stacks)})')
    else:
        chosen = [s for s in stacks if any(glob_to_regex(g).match(f) for f in diff.files() for g in s["when"])]
        if not chosen:
            raise Reject("no `red` entry matches a file of the red commit (" + (", ".join(diff.files()[:8]) or "it changes no file")
                         + "). Does the commit change a test file? Is `when` of the stack right?")
    base = tempfile.gettempdir()
    if not SAFE_PATH.match(base):
        raise Reject(f"TMPDIR ({base}) has characters that are not safe for {{out}}: use another TMPDIR")
    tmp = tempfile.mkdtemp(prefix="red-")
    codes, groups = [], []
    for entry in chosen:
        out_dir = tempfile.mkdtemp(prefix=entry["name"][:20] + "-", dir=tmp)
        print(f'== red: stack "{entry["name"]}" ({entry["format"]}, timeout {entry["timeout"]} s)', flush=True)
        rc, timed_out, out = run_stack(entry, out_dir, root)
        report, report_error = None, None
        if not timed_out:
            try:
                report = parse_junit(out) if entry["format"] == "junit" else parse_tap(out)
            except Reject as e:
                report_error = str(e)
        code, msgs, listed = judge(entry, rc, timed_out, report_error, report, diff)
        codes.append(code)
        label = {0: "red", 1: "the tests pass", 2: "rejected"}[code]
        print(f'-- stack "{entry["name"]}": {label}')
        for m in msgs:
            print(f"   {m}")
        if code == 0:
            for f, n in sorted(set(listed)):
                print(f"   failing: {f}::{n}")
            groups.append((entry["name"], entry["format"], listed))
    total = 2 if 2 in codes else (1 if 1 in codes else 0)
    if total == 0:
        path = os.path.join(tmp, "pr-block.md")
        with open(path, "w", encoding="utf-8") as f:
            f.write(block(commit, groups))
        print()
        print("Red. Confirm that each failure is an assertion of an acceptance criterion.")
        print(f'Block for "How to test it" in the PR: {path}')
    else:
        print(f"\nThe red is not valid (details above). Files of this run: {tmp}")
    return total


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Reject as e:
        print(f"red.sh: {e}", file=sys.stderr)
        sys.exit(2)
    except KeyboardInterrupt:
        sys.exit(2)
    except Exception as e:  # any internal error rejects: fail closed
        print(f"red.sh: internal error, the red is rejected: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(2)
