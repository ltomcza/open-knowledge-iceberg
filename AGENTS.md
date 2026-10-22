# Agent guide — open-knowledge-iceberg

This repository defines the **Open Knowledge Format (OKF)** — an open,
human- and agent-friendly format for storing knowledge as a directory of
markdown files with YAML frontmatter. The specification is
[`.claude/okf/SPEC.md`](.claude/okf/SPEC.md) — read it if you're unsure about a
detail; it wins over any summary here.

This file is the single source of project instructions for every coding agent.
Claude Code loads it through `CLAUDE.md` (`@AGENTS.md`); GitHub Copilot in
VS Code reads it directly.

## Storing and querying knowledge

When the user wants to **store** knowledge into, or **query** knowledge from, an
OKF bundle, use the purpose-built customizations below rather than improvising.
There is one copy of each, under `.claude/`, and both Claude Code and GitHub
Copilot (VS Code) load it.

- **Agents** (`.claude/agents/`) — Claude Code delegates to these as
  subagents; in Copilot Chat pick them from the agent dropdown:
  - **okf-librarian** — captures information and writes it as OKF concept
    documents (the enrichment / storage side). Can read and edit files.
  - **okf-researcher** — answers questions by retrieving from OKF bundles,
    read-only (the consumption / query side). Cannot edit files.

- **Skills** (`.claude/skills/`) — invoke as slash commands in either tool:
  - `/okf-add-concept` — create a new concept and wire it into the bundle.
  - `/okf-query` — answer a question from the knowledge base with citations.
  - `/okf-index` — generate or refresh `index.md` directory listings.
  - `/okf-log` — append a dated entry to a bundle's `log.md`.
  - `/okf-validate` — check a bundle for OKF v0.1 conformance.

- **Rules** (`.claude/rules/okf.md`) — OKF authoring rules, applied
  automatically when editing bundle markdown files.

See [`README.md`](README.md) for setup and usage in each tool.

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

## The Iceberg bundle in this repo

`knowledge/iceberg/` is an OKF bundle about Apache Iceberg and its
PySpark / PyIceberg ecosystem. It has these sections: `architecture/`,
`catalogs/`, `pyspark/`, `pyiceberg/`, `maintenance/`, `performance/`,
`tutorials/`, plus `cheat-sheet.md`. Concept links are bundle-relative,
starting from `knowledge/iceberg/` (e.g. `/performance/index.md`).
`.firecrawl/` holds raw doc scrapes used as source material. It is not part
of the bundle.

Concepts in this bundle follow a house style. Match it when adding or
editing:

- Frontmatter: `type`, `title`, `description`, `aliases` (the phrases a
  user might search for), `tags`, `timestamp`, `resource`.
- Body sections in order: `# Retrieval Notes` (when to read this note and
  links to neighbouring concepts), then `# Summary` (bullet takeaways), then
  topic sections with runnable PySpark/SQL, then `# Citations` (numbered
  source links).
- After adding a concept: list it in the section `index.md`, cross-link it
  from related concepts in both directions, and add a dated entry to
  `knowledge/iceberg/log.md` (newest first).

## Researching new knowledge

- When asked to research the web, use the tool the user names (Exa or
  Firecrawl). Prefer official Iceberg/Spark docs and source code over blog
  posts, and say in the concept which practitioner sources you used.
- **Verify claims before storing them.** That includes claims in text the
  user pastes and claims from blog posts. Check option names, defaults, and
  SQL syntax against the docs or source code. Example: `INSERT OVERWRITE ...
  REPLACE WHERE` is Delta Lake syntax, not Iceberg's, and
  `write.*.isolation-level` does not govern Spark overwrites. When you
  correct a misconception, record the correction in the concept itself.
- Note in the concept that option defaults change across releases, and
  mention the Iceberg/Spark version when a claim depends on it.
