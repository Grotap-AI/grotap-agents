#!/usr/bin/env python3
"""stale-evidence-guard.py — Claude Code PreToolUse hook (2026-09-17, rev 3).

Sessions here reasoned from the SHARED local checkout, or from a cheap git signal,
instead of checking the live thing, and were confidently wrong: measured 2026-09-17
the tree was 505 commits behind origin/master and `orchestrator/src/server.ts`
differed from master by 692 lines, so any file:line quoted from it was fiction.

Family A (Bash) — a cheap signal used as a verdict: `git cherry` compares PATCH-IDs
not content; `git branch -r/-a/--contains/--merged` reads a LOCAL CACHE; `git show
<ref>:.dotpath` on Windows fatals and looks like absence. Heredoc BODIES are
stripped, then shlex(punctuation_chars=True) tokenizes AND segments — no hand-written
shell grammar. Only a segment's COMMAND WORD counts, so `git commit -m "...git
cherry..."`, `gh --body`, `echo` and `git cherry-pick` are silent. ONE level of
`bash -lc`/`sh -c`/`pwsh -c`/`cmd /c`/`doppler run --` is unwrapped and rescanned.
An unbalanced quote yields NO Family A findings.

Family B — a read of a file that ACTUALLY DIFFERS from origin/master: the target is
resolved from the tool input, made repo-relative, and warned about only if it is in
`git diff --name-only -z HEAD origin/master`; a file identical to master is silent
whatever the checkout's drift. NO fetch — that ref is only as fresh as the last one.
A (repo, path) warning fires ONCE then stays quiet for WARN_TTL (12h), claimed with
an O_CREAT|O_EXCL marker: exclusive create IS atomic on Windows, so it holds under
concurrent sessions where a shared JSON `seen` map loses nearly every race, and any
error claiming one means WARN (fail open). That window DELIBERATELY trades a repeat
warning for signal — at 10 minutes the same file re-warned every 10 minutes; a
repeat 200-call session fell from 65 messages to 17 at 12h. A file warns once.

Contract: never blocks, never raises, exit 0 on every path, stdlib only, no network.
BUDGET covers ALL git work AND the marker sweep per invocation (one call:
GIT_TIMEOUT). GROTAP_STALE_GUARD=0 disables everything. Mirrored byte-for-byte in
grotap-platform and grotap-agents as scripts/claudecode/stale-evidence-guard.py.
Cache <tempdir>/grotap-stale-guard-<sha1(root)[:16]>.json + <stem>.<sha1(path)[:16]>.warn
"""
from __future__ import annotations

import glob as _glob
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time

GIT_TIMEOUT = 2.0        # hard cap on any ONE subprocess call, seconds
BUDGET = 4.0             # hard cap on ALL git work + the sweep, per invocation
CACHE_TTL = 600          # recompute the repo state when older than 10 minutes
WARN_TTL = 12 * 3600     # a (repo, path) warning fires once per 12 hours
SWEEP_MAX = 200          # markers unlinked per sweep, oldest first
MAX_NAMED_FILES = 3      # never name more than this many files in one message
FUTURE_SLOP = 300.0      # clock/filesystem skew tolerated before "future" means broken
_START = time.time()

_PATH_TOOLS = {"Read", "Edit", "Write", "NotebookEdit", "MultiEdit"}
_GLOB_TOOLS = {"Grep", "Glob"}
# Bash commands that read a file's CONTENTS (sed only when not in-place)...
_FILE_READERS = set("grep egrep fgrep rg cat sed head tail less more awk nl".split())
# ...of those, the ones whose FIRST bare argument is a pattern/script, not a file.
_PATTERN_FIRST = set("grep egrep fgrep rg sed awk".split())
_PATTERN_OPT = set("-e -f --regexp --file --expression".split())
# Flags eating the NEXT token, PER COMMAND: `-n` is a value flag for head/tail but
# a boolean for grep, `-f` a value flag for grep but a boolean for tail. One shared
# table ate the pattern out of `grep -n foo f.py` and the file out of `tail -f log`.
_LONG_VALUE = set("--regexp --file --include --exclude --exclude-dir --max-count"
                  " --after-context --before-context --context --expression --assign"
                  " --lines --bytes --glob --type --type-not --max-depth --replace".split())
_VALUE_FLAGS = {c: {"-" + s for s in f.split()} | _LONG_VALUE for c, f in {
    "grep": "e f m A B C d", "egrep": "e f m A B C d", "fgrep": "e f m A B C d",
    "rg": "e f m A B C d g t T r", "sed": "e f", "awk": "f v",
    "head": "n c", "tail": "n c", "nl": "b n w s v"}.items()}
_LAUNCHERS = set("bash sh zsh dash ksh pwsh powershell cmd".split())
_GIT_VALUE_FLAGS = set("-C -c --git-dir --work-tree --namespace --exec-path"
                       " --super-prefix --config-env".split())
_ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
_GLOBBY = re.compile(r"[*?\[\]{}()|^$\n]")
# <<EOF / <<-EOF / <<'123' / <<"END-1" / <<\EOF; the << lookarounds keep a <<< herestring out.
_HEREDOC = re.compile(r"""(?<!<)<<(?!<)-?[ \t]*(?:'([^'\n]+)'|"([^"\n]+)"|\\?([^\s'";|&<>()]+))""")
_PUNCT = "();<>|&"

MSG_CHERRY = (
    "`git cherry` compares PATCH-IDs, so it answers \"was this exact diff applied\" — never "
    "\"is this content on master\". A `+` is EXPECTED whenever master's copy was amended, "
    "squashed or rebased: verified 2026-09-17, 8c1eafc9e and 6e7ff31a4 still show `+` while "
    "their content is demonstrably on master. To decide whether content is on master, read the "
    "content: `git grep <pat> origin/master -- <path>` or `git show origin/master:<path>`. Same "
    "caveat for `git log --oneline A..B` counts.")
MSG_BRANCH = (
    "Remote-tracking refs are a LOCAL CACHE written by the last fetch or push — `git branch -r`, "
    "`-a`, `--contains`, `--merged`/`--no-merged` against an origin/ ref all read that cache, not "
    "the server. They survive a branch being deleted on the server, and are absent for a branch "
    "never pushed. Only `git ls-remote --heads origin <branch>` asks the server; trusting the "
    "cached answer nearly destroyed 2,654 lines of recovered work on 2026-09-16.")
MSG_DOTPATH = (
    "On Windows/MSYS, `git show <ref>:<path>` whose path's first component starts with a dot is "
    "rewritten by the MSYS path mangler and git fatals; piping it into grep turns that fatal into "
    "an EMPTY result indistinguishable from absence. Use `MSYS_NO_PATHCONV=1 git show "
    "\"<ref>:<path>\"`, or prefer `git ls-tree <ref> <dir>` — it enumerates, and cannot be "
    "defeated by a wrong guess, a leading dot, or a stale checkout.")


def _remaining() -> float:
    return BUDGET - (time.time() - _START)

def _git(root: str, *args: str, raw: bool = False):
    left = _remaining()
    if left <= 0.05:
        return None
    try:
        proc = subprocess.run(("git", "-C", root) + args, capture_output=True,
                              text=True, timeout=min(GIT_TIMEOUT, left))
    except Exception:
        return None
    return None if proc.returncode else (proc.stdout if raw else proc.stdout.strip())


# ------------------------------------------------------------- cache + dedupe
def _stem(root: str) -> str:
    key = hashlib.sha1(root.strip().lower().encode("utf-8", "ignore")).hexdigest()[:16]
    return os.path.join(tempfile.gettempdir(), "grotap-stale-guard-%s" % key)

def _read_cache(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}

def _write_cache(path: str, data: dict) -> None:
    """os.replace is NOT atomic-on-contention on Windows (a concurrent reader raises
    WinError 5; a probe left 240/240 orphans): mkstemp, retry, tolerate losing the
    race, ALWAYS unlink the temp in finally."""
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(prefix=os.path.basename(path) + ".",
                                   suffix=".tmp", dir=os.path.dirname(path) or ".")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh)
        for attempt in range(4):
            try:
                return os.replace(tmp, path)
            except Exception:
                time.sleep(0.02 * (attempt + 1))
    except Exception:
        pass
    finally:
        try:
            if tmp and os.path.exists(tmp):
                os.unlink(tmp)
        except Exception:
            pass

def _expired(mtime: float, now: float, ttl: float) -> bool:
    """A FUTURE mtime is EXPIRED, not eternally fresh: `now - mtime < ttl` holds for
    any negative age, which would silence that path forever. FUTURE_SLOP is the skew
    tolerated first — a Windows file time can run milliseconds AHEAD of time.time(),
    and a marker created microseconds ago must not sweep itself."""
    age = now - mtime
    return age < -FUTURE_SLOP or age >= ttl

def claim_warning(stem: str, rel: str) -> bool:
    """Warn about `rel` once per WARN_TTL, across processes. Fails OPEN."""
    h = hashlib.sha1(rel.lower().encode("utf-8", "ignore")).hexdigest()[:16]
    mark = "%s.%s.warn" % (stem, h)
    try:
        if not _expired(os.stat(mark).st_mtime, time.time(), WARN_TTL):
            return False
        os.unlink(mark)
    except FileNotFoundError:
        pass
    except Exception:
        return True
    try:
        os.close(os.open(mark, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
        return True
    except FileExistsError:
        return False
    except Exception:
        return True

def sweep_markers(stem: str) -> None:
    """Drop expired markers OLDEST FIRST, under BOTH a count cap and the shared
    deadline — the sweep is inside the budget, not outside it. What one run cannot
    reach the next does, so the population trends down."""
    now, found = time.time(), []
    try:
        for m in _glob.iglob(stem + ".*.warn"):
            try:
                found.append((os.stat(m).st_mtime, m))
            except Exception:
                pass
            if len(found) >= SWEEP_MAX * 5 or _remaining() < 0.5:
                break
        for mtime, m in sorted(found)[:SWEEP_MAX]:
            if _remaining() < 0.3:
                return
            if _expired(mtime, now, WARN_TTL):
                try:
                    os.unlink(m)
                except Exception:
                    pass
    except Exception:
        pass


# --------------------------------------------- shell parsing (no own grammar)
def strip_heredocs(cmd: str) -> str:
    """Drop heredoc BODIES + terminator before tokenizing: a `<<EOF` body holding
    `git cherry` is data, not a command."""
    lines, out, i = (cmd or "").splitlines(), [], 0
    while i < len(lines):
        out.append(lines[i])
        m = _HEREDOC.search(lines[i])
        i += 1
        if m:
            delim = m.group(1) or m.group(2) or m.group(3)   # quoted/\quoted/bare
            while i < len(lines) and lines[i].strip() != delim:
                i += 1
            i += 1                                 # drop the terminator line too
    return "\n".join(out)

def _lex(text: str) -> list:
    lex = shlex.shlex(text, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.escape = ""                                # backslash literal (Windows paths)
    lex.commenters = ""
    return list(lex)

def segments(cmd: str):
    """[[token, ...], ...], or None if the command will not tokenize.

    punctuation_chars makes shlex hand back `;|&()<>` as separators, quote-aware, so
    a quoted `;` stays data and there is no splitter to maintain. The whole text must
    lex cleanly — an unbalanced quote means say nothing rather than guess. Segmenting
    is per line (shlex eats newlines); a line that will not lex alone is skipped."""
    text = strip_heredocs(cmd)
    try:
        _lex(text)
    except Exception:
        return None
    segs = []
    for line in text.splitlines():
        try:
            toks = _lex(line)
        except Exception:
            continue
        cur = []
        for t in toks:
            if t and all(c in _PUNCT for c in t):
                segs.append(cur) if cur else None
                cur = []
            else:
                cur.append(t)
        if cur:
            segs.append(cur)
    return segs

def _basename(tok: str) -> str:
    b = os.path.basename(tok.replace("\\", "/")).lower()
    return b[:-4] if b.endswith(".exe") else b

def strip_prefix(tokens: list):
    """(argv, leading env-assignment NAMES); `doppler run -- X` unwraps to X."""
    toks, env = list(tokens), set()
    for _ in range(4):
        while toks and _ENV_ASSIGN.match(toks[0]):
            env.add(toks[0].split("=", 1)[0])
            toks = toks[1:]
        if not (toks and _basename(toks[0]) == "doppler"):
            return toks, env
        if "--" not in toks:
            return [], env
        toks = toks[toks.index("--") + 1:]
    return toks, env

def inner_script(toks: list):
    """The script of one `bash -lc "..."`/`sh -c`/`pwsh -c`/`cmd /c`, else None."""
    if not toks or _basename(toks[0]) not in _LAUNCHERS:
        return None
    for i in range(1, len(toks) - 1):
        low = toks[i].lower()
        if low in ("/c", "/k", "-command", "-c") or (
                low[:1] == "-" and low[:2] != "--" and "c" in low[1:]
                and low[1:].isalpha()):
            return toks[i + 1]
    return None

def git_subcommand(tokens: list):
    """(subcommand, rest) for a `git` argv, after its global flags (-C/-c/--git-dir)."""
    i = 1
    while i < len(tokens):
        t = tokens[i]
        if not t.startswith("-"):
            return t, tokens[i + 1:]
        i += 2 if t in _GIT_VALUE_FLAGS else 1
    return None, []


# ---------------------------------------------------------------------- Family A
def branch_reads_cache(args: list) -> bool:
    """True for a LISTING/QUERY of remote-tracking refs; False for a delete/rename/
    copy even when its flag cluster happens to contain `r`."""
    fire = mutate = False
    i = 0
    while i < len(args):
        a, i = args[i], i + 1
        if a == "--":
            break
        if a.startswith("--"):
            name, sep, val = a.partition("=")
            if name in ("--delete", "--move", "--copy"):
                mutate = True
            elif name in ("--remotes", "--all", "--contains", "--no-contains"):
                fire = True
            elif name in ("--merged", "--no-merged"):
                fire = fire or "/" in (val if sep else (args[i] if i < len(args) else ""))
                i += 0 if sep else 1
        elif a.startswith("-") and len(a) > 1:
            mutate = mutate or any(c in a[1:] for c in "dDmMcC")
            fire = fire or "r" in a[1:] or "a" in a[1:]
    return fire and not mutate

def show_has_dotpath(args: list) -> bool:
    for a in args:
        ref, _, path = a.partition(":")
        if a != "--" and path and len(ref) >= 2:   # len<2 skips a bare drive letter
            first = path.replace("\\", "/").split("/")[0]
            if first.startswith(".") and first not in (".", ".."):
                return True
    return False

def family_a(cmd: str, seen=None, out=None, depth: int = 0) -> list:
    """Cheap-signal-as-verdict warnings, anchored to the segment's command word."""
    seen, out = (set() if seen is None else seen), ([] if out is None else out)
    is_win = sys.platform.startswith("win") or os.name == "nt"
    for seg in segments(cmd) or []:
        toks, env = strip_prefix(seg)
        if not toks:
            continue
        if depth == 0:
            inner = inner_script(toks)
            if inner is not None:          # ONE level, never arbitrary depth
                family_a(inner, seen, out, 1)
                continue
        if _basename(toks[0]) != "git":    # `gh`, `echo`, prose: not a git call
            continue
        sub, args = git_subcommand(toks)   # `commit`/`tag` are not cherry/branch/show
        if sub == "cherry" and "cherry" not in seen:            # NOT cherry-pick
            seen.add("cherry")
            out.append("git cherry — " + MSG_CHERRY)
        elif sub == "branch" and "branch" not in seen and branch_reads_cache(args):
            seen.add("branch")
            out.append("git branch (remote-tracking) — " + MSG_BRANCH)
        elif (sub == "show" and is_win and "dotpath" not in seen
              and "MSYS_NO_PATHCONV" not in env    # a real env ASSIGNMENT exempts;
              and show_has_dotpath(args)):         # the word in a comment does not
            seen.add("dotpath")
            out.append("git show <ref>:<dot-path> on Windows — " + MSG_DOTPATH)
    return out


# ---------------------------------------------------------------------- Family B
def bash_read_targets(seg: list) -> list:
    """File arguments of a content-reading command in ONE shell segment."""
    toks, _ = strip_prefix(seg)
    cmd = _basename(toks[0]) if toks else ""
    if cmd not in _FILE_READERS:
        return []
    args = toks[1:]
    if cmd == "sed" and any(a[:2] == "-i" and a[:3] != "--i" for a in args):
        return []                                  # sed -i is a WRITE, not a read
    value_flags = _VALUE_FLAGS.get(cmd, set())
    # grep/sed/awk take the pattern as the first bare arg UNLESS -e/-f supplied it.
    seen_pat = cmd not in _PATTERN_FIRST or any(
        a in _PATTERN_OPT or (len(a) > 2 and a[:2] in ("-e", "-f") and a[:3] != "--")
        for a in args)
    out, i = [], 0
    while i < len(args):
        a = args[i]
        if a == "--":
            i += 1
        elif a.startswith("-") and len(a) > 1:
            i += 2 if a in value_flags else 1
        elif not seen_pat:
            seen_pat, i = True, i + 1
        else:
            out.append(a)
            i += 1
    return out

def candidate_paths(tool: str, tool_input: dict, cwd: str) -> list:
    raw = []
    if tool in _PATH_TOOLS or tool in _GLOB_TOOLS:
        for key in ("file_path", "notebook_path"):
            v = tool_input.get(key)
            if isinstance(v, str) and v.strip():
                raw.append(v)
    if tool in _GLOB_TOOLS:
        # `path` ONLY. `pattern` is a regex/glob, never a file anyone read:
        # Grep(pattern="README.md") used to warn about a file nobody opened.
        v = tool_input.get("path")
        if isinstance(v, str) and v.strip():
            raw.append(v)
    if tool == "Bash" and isinstance(tool_input.get("command"), str):
        for seg in segments(tool_input["command"]) or []:
            raw.extend(bash_read_targets(seg))
    out, seen = [], set()
    for p in raw:
        p = p.strip().strip("\"'").replace("\\", "/")
        if not p or _GLOBBY.search(p):
            continue                       # a glob or regex, not a file we can name
        if not (os.path.isabs(p) or re.match(r"^[A-Za-z]:/", p)):
            p = os.path.join(cwd or ".", p)
        p = os.path.normpath(p).replace("\\", "/")
        k = p.lower() if os.name == "nt" else p
        if k not in seen:
            seen.add(k)
            out.append(p)
    # No path in the tool input: fall back to cwd. A DIRECTORY is never in the
    # divergent file set, so that stays silent by construction.
    return (out or ([os.path.normpath(cwd).replace("\\", "/")] if cwd else []))[:8]

def repo_state(top: str):
    """Counts + the set of paths differing from origin/master, cached CACHE_TTL."""
    stem = _stem(top)
    state = _read_cache(stem + ".json")
    if (state.get("root") == top and isinstance(state.get("behind"), int)
            and isinstance(state.get("files"), list)
            and isinstance(state.get("at"), (int, float))
            and not _expired(state["at"], time.time(), CACHE_TTL)):
        return state                   # WARM PATH: no git call, no write at all
    counts = _git(top, "rev-list", "--left-right", "--count", "HEAD...origin/master")
    if not counts:
        return None                    # no origin/master ref here — say nothing
    try:
        ahead, behind = (int(x) for x in counts.split())
    except Exception:
        return None
    branch = _git(top, "rev-parse", "--abbrev-ref", "HEAD") or "?"
    names = _git(top, "diff", "--name-only", "-z", "HEAD", "origin/master", raw=True)
    if names is None:
        return None
    porcelain = _git(top, "status", "--porcelain")      # last: cheapest to lose
    fresh = {"root": top, "behind": behind, "ahead": ahead, "branch": branch,
             "dirty": len([l for l in (porcelain or "").splitlines() if l.strip()]),
             "at": time.time(), "files": [f for f in names.split("\0") if f]}
    _write_cache(stem + ".json", fresh)   # the ONLY cache write, once per CACHE_TTL
    sweep_markers(stem)
    return fresh

def line_delta(top: str, rel: str) -> int:
    """Lines changed HEAD..origin/master for one path. Reached only after a dedupe
    claim, so at most MAX_NAMED_FILES calls per fire."""
    out = _git(top, "diff", "--numstat", "HEAD", "origin/master", "--", rel) or ""
    return sum(int(b) for ln in out.splitlines()
               for b in ln.split("\t")[:2] if b.isdigit())

def family_b(payload: dict, tool: str, tool_input: dict):
    cwd = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or ""
    if not os.path.isdir(cwd):
        cwd = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    cwd = cwd.replace("\\", "/")

    by_root = {}
    for p in candidate_paths(tool, tool_input, cwd):
        d = p if os.path.isdir(p) else os.path.dirname(p)   # nearest existing dir
        top = _git(d, "rev-parse", "--show-toplevel") if os.path.isdir(d) else None
        if top:                                             # else outside any repo
            by_root.setdefault(top.replace("\\", "/").rstrip("/"), []).append(p)

    hits, header = [], None
    for top, paths in by_root.items():
        state = repo_state(top)
        if not state:
            continue
        index = {(f.lower() if os.name == "nt" else f): f for f in state.get("files") or []}
        for p in paths:
            try:
                rel = os.path.relpath(p, top).replace("\\", "/")
            except Exception:
                continue
            real = index.get(rel.lower() if os.name == "nt" else rel)
            if rel.startswith("..") or not real:
                continue                   # identical to origin/master — SILENT
            if not claim_warning(_stem(top), real):
                continue                   # already warned about this path
            delta = line_delta(top, real)
            hits.append("`%s` differs from origin/master%s; re-read it with "
                        "`git show origin/master:%s`%s"
                        % (real, " by %d line(s)" % delta if delta else "", real,
                           " (prefix `MSYS_NO_PATHCONV=1 `)"
                           if real.split("/")[0].startswith(".") else ""))
            header = header or state
            if len(hits) >= MAX_NAMED_FILES:
                break
        if len(hits) >= MAX_NAMED_FILES:
            break
    if not hits:
        return None
    return ("%s. This checkout is %d behind / %d ahead of origin/master, %d dirty path(s), on "
            "branch '%s' (%s) — line numbers and symbols read here are NOT master's. Re-read "
            "before quoting any file:line in a report, a correction or an argument. (The "
            "origin/master ref is itself only as fresh as the last fetch; this hook does not fetch.)"
            % ("; ".join(hits), header.get("behind", 0), header.get("ahead", 0),
               header.get("dirty", 0), header.get("branch", "?"), header.get("root", "?")))


def main() -> int:
    if os.environ.get("GROTAP_STALE_GUARD") == "0":
        return 0
    try:
        payload = json.load(sys.stdin)
        tool, tool_input = payload["tool_name"], payload["tool_input"]
    except Exception:
        return 0
    if not isinstance(tool, str) or not isinstance(tool_input, dict):
        return 0

    parts = []
    if tool == "Bash" and isinstance(tool_input.get("command"), str):
        try:
            parts.extend(family_a(tool_input["command"]))
        except Exception:
            pass
    try:
        b = family_b(payload, tool, tool_input)
    except Exception:
        b = None
    if b:
        parts.append("stale checkout — " + b)
    if not parts:
        return 0

    brief = "stale-evidence-guard: %d warning(s) added to context." % len(parts)
    sys.stdout.write(json.dumps({
        "systemMessage": brief,
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": brief,
            "additionalContext": "stale-evidence-guard: " + "\n\n".join(parts),
        }}))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
