# Claude Code guide — open-knowledge-langchain

This repository defines the **Open Knowledge Format (OKF)** — an open,
human- and agent-friendly format for storing knowledge as a directory of
markdown files with YAML frontmatter. The specification is
[`.github/okf/SPEC.md`](.github/okf/SPEC.md) — read it if you're unsure about a
detail; it wins over any summary here.

## Storing and querying knowledge

When the user wants to **store** knowledge into, or **query** knowledge from, an
OKF bundle, use the purpose-built customizations below rather than improvising.

- **Subagents** (`.claude/agents/`) — Claude Code delegates to these
  automatically based on the request, or you can invoke them explicitly:
  - **okf-librarian** — captures information and writes it as OKF concept
    documents (the enrichment / storage side). Can read and edit files.
  - **okf-researcher** — answers questions by retrieving from OKF bundles,
    read-only (the consumption / query side). Cannot edit files.

- **Skills** (`.claude/skills/`) — invoke as slash commands:
  - `/okf-add-concept` — create a new concept and wire it into the bundle.
  - `/okf-query` — answer a question from the knowledge base with citations.
  - `/okf-index` — generate or refresh `index.md` directory listings.
  - `/okf-log` — append a dated entry to a bundle's `log.md`.
  - `/okf-validate` — check a bundle for OKF v0.1 conformance.

There is also a parallel **GitHub Copilot Chat** integration under `.github/`
(agents, prompt files, an auto-injected instructions file) for VS Code users.
Both toolchains read the same canonical spec and are meant to stay equivalent —
if you change behavior in one, consider whether the other needs the same update.

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
