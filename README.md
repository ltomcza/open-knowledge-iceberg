# OKF agents & skills for Claude Code and GitHub Copilot

This repository ships one set of customizations that let you **store** and
**query** knowledge in the [Open Knowledge Format](.claude/okf/SPEC.md). Both
**Claude Code** and **GitHub Copilot Chat in VS Code** load the same files, so
there is nothing to keep in sync between toolchains.

## Layout

```
README.md                         # This file
AGENTS.md                         # Project instructions (all agents)
CLAUDE.md                         # "@AGENTS.md" — imports AGENTS.md for Claude Code
.claude/
├── agents/                       # Agents (Claude subagent format)
│   ├── okf-librarian.md          #   store / author knowledge
│   └── okf-researcher.md         #   query / retrieve knowledge (read-only)
├── skills/                       # Skills (Agent Skills standard, SKILL.md)
│   ├── okf-add-concept/SKILL.md  #   /okf-add-concept
│   ├── okf-query/SKILL.md        #   /okf-query
│   ├── okf-index/SKILL.md        #   /okf-index
│   ├── okf-log/SKILL.md          #   /okf-log
│   └── okf-validate/SKILL.md     #   /okf-validate
├── rules/
│   └── okf.md                    # OKF authoring rules, auto-applied to bundle files
└── okf/
    └── SPEC.md                   # Canonical Open Knowledge Format specification
```

## Skills

Type the slash command in Claude Code or in Copilot Chat, optionally followed
by your input (e.g. `/okf-query how do I expire snapshots?`):

| Command             | What it does                                             |
|---------------------|----------------------------------------------------------|
| `/okf-add-concept`  | Create a new concept and wire it into the bundle.        |
| `/okf-query`        | Answer a question from the bundle, with citations.       |
| `/okf-index`        | Generate / refresh `index.md` directory listings.        |
| `/okf-log`          | Append a dated entry to a `log.md`.                      |
| `/okf-validate`     | Check a bundle for OKF v0.1 conformance and report.      |

## Agents

- **okf-librarian** — describe knowledge to capture ("Here's the schema for our
  `orders` table…"). It writes a conformant concept document, updates the
  directory `index.md`, and logs the change.
- **okf-researcher** — ask a question ("Which table has customer lifetime
  value?"). It searches the bundle, follows cross-links, and answers with
  citations. It never edits files.

In **Claude Code**, these run as subagents: Claude delegates to them
automatically, or you can ask for one by name. In **Copilot Chat**, pick them
from the agent dropdown. VS Code maps the Claude tool names (`Read`, `Grep`,
`Glob`, `Edit`, `Write`) to its own tools.

## Requirements and troubleshooting (VS Code)

VS Code discovers `.claude/skills/`, `.claude/agents/`, `AGENTS.md`, and
`.claude/rules/` by default. If something doesn't show up, check these settings:

- `chat.agentSkillsLocations`: skills (`.claude/skills` is a default location).
- `chat.agentFilesLocations`: agents (`.claude/agents` is a default location).
- `chat.useAgentsMdFile`: `AGENTS.md` project instructions.
- `chat.useClaudeMdFile`: `CLAUDE.md` and `.claude/rules` discovery.

**Not covered:** Copilot CLI and the Copilot cloud agent only read
`.github/agents/`, so the agents are not available there.

## Customizing

- **Different bundle location?** Edit the `paths` globs in
  `.claude/rules/okf.md`.
- **New skill?** Add `.claude/skills/<name>/SKILL.md` with `name` (must match
  the folder; lowercase and hyphens) and `description` frontmatter. Phrase the
  input as "given after the slash command" rather than relying on
  `$ARGUMENTS`, so the skill reads correctly in both tools.
- **New agent?** Add `.claude/agents/<name>.md` with `name`, `description`, and
  a comma-separated `tools` list; the body is the agent's system prompt.

## Safety defaults

- Use least-privilege tool lists in agents and skills.
- Keep query and retrieval flows read-only.
- Enable edit tools only for authoring flows that must modify files.
