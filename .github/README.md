# OKF agents & skills for GitHub Copilot (VS Code)

This folder contains GitHub Copilot customizations that let you **store** and
**query** knowledge in the [Open Knowledge Format](okf/SPEC.md) directly from
Copilot Chat in Visual Studio Code.

## Contents

```
.github/
├── copilot-instructions.md              # Repo-wide OKF awareness + pointers
├── agents/                              # "Agents" — custom Copilot agents
│   ├── okf-librarian.agent.md           #   store / author knowledge
│   └── okf-researcher.agent.md          #   query / retrieve knowledge (read-only)
├── prompts/                             # "Skills" — slash commands
│   ├── okf-add-concept.prompt.md        #   /okf-add-concept
│   ├── okf-query.prompt.md              #   /okf-query
│   ├── okf-index.prompt.md              #   /okf-index
│   ├── okf-log.prompt.md                #   /okf-log
│   └── okf-validate.prompt.md           #   /okf-validate
├── instructions/
│   └── okf.instructions.md              # OKF authoring rules (auto-applied to bundle files)
└── okf/
    └── SPEC.md                          # Canonical Open Knowledge Format specification
```

## Requirements

- Visual Studio Code with the **GitHub Copilot** and **GitHub Copilot Chat**
  extensions.
- Prompt files and custom agents enabled. If you don't see them, set in
  VS Code settings:
  - `chat.promptFiles: true`
  - Agents are read from `.github/agents/` by default.

VS Code discovers these files automatically because they live under `.github/`.
No other setup is needed for this workspace.

## Safety defaults

- Use least-privilege tool lists in agents and prompts.
- Keep query and retrieval flows workspace-grounded with search tools only.
- Enable edit tools only for authoring flows that must modify files.
- Avoid terminal and web tools unless a workflow explicitly requires them.

## Using the agents

1. Open the Copilot Chat view.
2. Use the **agent dropdown** (top of the chat input) and pick:
   - **OKF Librarian** — then describe knowledge to capture ("Here's the schema
     for our `orders` table…"). It writes a conformant concept document, updates
     the directory `index.md`, and logs the change.
   - **OKF Researcher** — then ask a question ("Which table has customer
     lifetime value?"). It searches the bundle, follows cross-links, and answers
     with citations. It never edits files.

## Using the skills (prompt files)

Type the slash command in Copilot Chat. Some prompt you for input:

| Command             | What it does                                             |
|---------------------|----------------------------------------------------------|
| `/okf-add-concept`  | Create a new concept and wire it into the bundle.        |
| `/okf-query`        | Answer a question from the bundle, with citations.       |
| `/okf-index`        | Generate / refresh `index.md` directory listings.        |
| `/okf-log`          | Append a dated entry to a `log.md`.                      |
| `/okf-validate`     | Check a bundle for OKF v0.1 conformance and report.      |

## How they stay grounded

- All files reference the canonical spec, [`.github/okf/SPEC.md`](okf/SPEC.md).
- `instructions/okf.instructions.md` carries an `applyTo` glob
  (`**/bundles/**`, `**/catalog/**`, `**/knowledge/**`) so its rules are injected
  automatically whenever you edit a bundle markdown file. Adjust that glob if your
  bundles live elsewhere.

## Customizing

- **Different bundle location?** Edit the `applyTo` glob in
  `instructions/okf.instructions.md`.
- **New skill?** Add a `*.prompt.md` file under `prompts/` with `agent`,
  `description`, and `tools` frontmatter.
- **New agent?** Add a `*.agent.md` file under `agents/` with `description`
  and `tools` frontmatter; the body is the agent's system prompt.
