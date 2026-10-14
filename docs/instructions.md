# instructions.md — Agent Rules for the KON KON Repository

**Witchgame is a human-directed project. The human owner leads and reviews; the AI agent (Cline, in VS Code) implements. These rules are non-negotiable guardrails. Read this file before doing anything.**

## 0. Prime directive: human-directed development, AI implementation

The human decides what gets built, reviews every change, and owns every commit. The agent writes the code, runs the commands, and manages the working tree between reviews. Every change stays reviewable: small diffs, one concern at a time. Nothing is committed and nothing is pushed without an explicit go from the human.

## 1. Ask, don't assume

The game design documents are the canonical vision for the game, subject to update by the human at any time. Read them at the start of every session (`.clinerules` fixes the boot order). The doc family has split responsibilities: `docs/current_plan.md` is the working roadmap (the only doc describing future work in detail), `docs/world.md` and the game deltas are **final-form** law (current systems and ship-plan only — no history, no decision provenance), and `docs/dev_log.md` is the development log (session rulings, changelogs, supersessions — evidence, not law). If anything needed for the task at hand is ambiguous or under-specified, **ask, don't assume** — a wrong guess ships in the diff.

## 2. File access: the whole repo is yours

The agent may read, create, edit, and delete files anywhere in the project as the task requires. Three standing cautions:

- `docs/PROJECT_MAP.md` is **generated** by `build_project_map.py` — never hand-edit it; fix the docstrings in the `.gd` sources and re-run the audit.
- **File edits go through the file-modification tool, never the command line.** No shell heredocs, `sed -i`, `python` write scripts, or redirection to patch files — read commands are fine, but any write to a project file uses the editor tool.
- `.godot/` is engine cache — never touch it directly; rescan instead (§7).
- `.aider*` files are retired artifacts of the pre-migration tool — never recreate or commit them.

## 3. Commands: the agent runs them

The agent runs builds, tests, audits, and git plumbing itself. Two hard gates:

- `git commit` only on explicit human instruction, scoped to the agreed files.
- Anything outside the repo — installs, global config, `git push` — needs explicit human approval first.

## 4. Working as lead engineer

- The human is the designer and final authority; the agent is the one writing the code. Significant decisions get a brief "what and why" in chat.
- When the human pastes code or an error: diagnose before fixing — read the error, form a hypothesis, test it, land the fix, and say what it was.
- The teaching culture survives where it belongs: when the human asks *how* something works, teach it; when they ask for a change, build it.

## 5. Memory bank maintenance (your standing duty)

Update the bank (`docs/`):

- at the end of every working session,
- whenever the human reports a milestone, ruling, or state change,
- whenever you notice the bank has drifted from reality.

## 6. House comment style and the docstring linter

Every `.gd` file in the project is audited by **`build_project_map.py`** (repo
root) against a strict comment house style plus the palette law. On a clean pass it writes
`docs/PROJECT_MAP.md`; on any violation it writes nothing and reports every
issue. The audit governs every comment in `scripts/`, so every comment or
docstring the agent writes **must conform — re-run the audit after every
comment edit.**

### The four enforced rules

1. **File header.** Every `.gd` file begins with exactly **3 consecutive `##`
   lines**: a compact, information-dense description of the file's purpose.
   Not 2, not 4, and no blank line before them. Example:

       ## The unified per-tile packet (world.md §2), stored structure-of-arrays:
       ## one PackedByteArray column per field, one row per tile. The tile index
       ## is the row number.

2. **Function docstrings.** Every `func` has exactly **1 `##` line directly
   above it, at the same indent**. Never inside the body. `@annotations` may
   sit between the docstring and the `func` line:

       ## Tile (x, y) of flat index i.
       func xy_of(i: int) -> Vector2i:
           @warning_ignore("integer_division")
           return Vector2i(i % w, i / w)

3. **In-function comments.** Inside a function body, comments are **single `#`
   1-liners.** Two things are flagged: runs of 2 or more consecutive comment
   lines (merge them into one line), and any `##` marker inside a body
   (docstrings belong above the func). Inline trailing comments on a code line
   are fine:

       var avail := 0
       # one comment line at a time, however long it needs to be
       take_pool(idx(s, yy2), W, remaining)

4. **Palette literals.** The only home for a `Color(...)` constructor is
   `scripts/render/palette.gd`. Every other `.gd` file — except under
   `scripts/testing/` — fails the audit with a palette-law violation:
   shipped colors are `Palette` constants, never literals.

### Conventions that pass the audit (and should be kept)

- Section banners at class scope, outside functions, e.g.
  `# -- Indexing ------...------`.
- Docstrings written as dense one-liners covering: what the function does,
  its inputs, its return value, and any invariants the caller must know.
  Treat the docstring as the function's API documentation — the project map
  carries it into every AI session, so vague docstrings degrade every future
  session's context.
- One blank line between a docstring's func and the next docstring.

### Running the audit

    python3 build_project_map.py           # audit; writes docs/PROJECT_MAP.md on success
    python3 build_project_map.py --force   # write the map even if issues remain

Exit codes: `0` = clean (map written) · `1` = style violations (no map) ·
`2` = no `.gd` files found. Run from the project root; it skips `.git`,
`.godot`, and hidden directories.

### Why this matters

`docs/PROJECT_MAP.md` lists every file (with its 3-line header) and every
function as `signature — docstring`, and is loaded into agent context at the
start of every development session (`.clinerules` boot order). That means: the
docstrings the agent writes **are** the documentation future sessions rely
on. `PROJECT_MAP.md` itself is generated — never hand-edit it; fix the
docstrings in the `.gd` sources and re-run the audit.

## 7. Workflow notes (learned the hard way)

- **New or moved global classes need a Godot rescan before headless runs.**
  The class cache (`.godot/global_script_class_cache.cfg`) maps `class_name`
  to path and is regenerated by an editor scan. After adding a script with a
  new `class_name` or moving any scripts: reload the project in the open
  editor (Project → Reload Current Project), or headless:

      Godot --headless --editor --quit --path .

  The regression's compile gate fails loudly if this is skipped — but skip it
  and the editor is the thing that lies next.

- **The standing regression command** (suites are documented in `world.md` §11;
  the binary is the Godots-version-manager path wired into `.vscode/tasks.json`
  and `.clinerules`; a full run takes ~5½ minutes):

      Godot --headless --path . -s res://scripts/testing/run_all.gd

  Exit code 0 = every suite passes. The launcher is fail-closed: a global
  class that fails to parse (compile gate) or a suite that executes zero
  examples (vacuous check) fails the run.

- **Historical note — the old implementation ban.** Before the VS Code +
  Cline migration (2026-10-11), agents were barred from touching code
  entirely: the human typed every line, and the one recorded exception (the
  2026-09-27 cleanup pass) required regression output byte-identical to the
  prior green run. The ban is lifted; the discipline that governed its one
  exception stands — **the regression gate decides.**
