# Copilot instructions — knowledge-catalog

This repository defines the **Open Knowledge Format (OKF)** — an open,
human- and agent-friendly format for storing knowledge as a directory of
markdown files with YAML frontmatter. The specification is [`.github/okf/SPEC.md`](okf/SPEC.md).

## Storing and querying knowledge

When the user wants to **store** knowledge into, or **query** knowledge from, an
OKF bundle, use the purpose-built customizations in `.github/` rather than
improvising:

- **Agents** (`.github/agents/`) — pick from the agent selector in Copilot Chat:
  - **OKF Librarian** — captures information and writes it as OKF concept
    documents (the enrichment / storage side).
  - **OKF Researcher** — answers questions by retrieving from OKF bundles,
    read-only (the consumption / query side).

- **Prompt files (skills)** — invoke as slash commands in Copilot Chat:
  - `/okf-add-concept` — create a new concept and wire it into the bundle.
  - `/okf-query` — answer a question from the knowledge base with citations.
  - `/okf-index` — generate or refresh `index.md` directory listings.
  - `/okf-log` — append a dated entry to a bundle's `log.md`.
  - `/okf-validate` — check a bundle for OKF v0.1 conformance.

When editing files inside a bundle, the OKF authoring rules in
`.github/instructions/okf.instructions.md` are applied automatically.

## OKF essentials

- One markdown file = one **concept**. Its **concept ID** is its bundle-relative
  path without `.md`.
- Frontmatter requires only a non-empty **`type`**; `title`, `description`,
  `resource`, `tags`, and `timestamp` are recommended.
- `index.md` (directory listing) and `log.md` (change history) are reserved
  filenames — never use them for concepts.
- Cross-link concepts with bundle-relative markdown links (`/tables/orders.md`).
- Consumption is permissive: tolerate unknown `type` values, extra keys, and
  broken links rather than rejecting them.

## Claude Code users

An equivalent integration exists for Claude Code: [`CLAUDE.md`](../CLAUDE.md) at
the repo root, subagents in `.claude/agents/`, and skills in `.claude/skills/`.
Both toolchains read the same canonical `SPEC.md` and are meant to stay
equivalent — if you change behavior in one, consider whether the other needs
the same update.
