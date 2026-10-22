---
description: 'Open Knowledge Format (OKF) authoring rules — applied automatically when editing knowledge bundle files.'
paths:
  - "**/bundles/**/*.md"
  - "**/catalog/**/*.md"
  - "**/knowledge/**/*.md"
---

# Open Knowledge Format (OKF) — authoring rules

You are editing a file inside an **OKF knowledge bundle**. A bundle is a
directory tree of markdown files that is human-readable, agent-parseable, and
diffable in git. The canonical specification is [`.claude/okf/SPEC.md`](../okf/SPEC.md);
these rules are a working summary. When the two disagree, `SPEC.md` wins.

## Concept documents

Every non-reserved `.md` file is a **concept** — one unit of knowledge. Its
**concept ID** is its bundle-relative path without the `.md` suffix
(`tables/orders.md` → `tables/orders`).

A concept has YAML frontmatter followed by a markdown body:

```markdown
---
type: <Type name>                # REQUIRED — short, descriptive, self-explanatory
title: <Human-readable name>     # Recommended
description: <One-sentence summary>   # Recommended — used in indexes & search snippets
resource: <Canonical URI>        # Optional — omit for abstract concepts
tags: [<tag>, <tag>]             # Optional
timestamp: <ISO 8601 datetime>   # Optional — last meaningful change
---

# Schema | Examples | Citations | <any heading>

Body: prefer structural markdown (headings, tables, lists, fenced code)
over prose. Structure aids both human reading and agent retrieval.
```

### Hard requirements (conformance)

1. Every non-reserved `.md` file MUST have a parseable YAML frontmatter block
   delimited by `---` on its own line at the very top and a closing `---`.
2. The frontmatter MUST contain a non-empty **`type`** field. Everything else is
   optional.
3. `type` values are NOT registered centrally. Pick descriptive values
   (`BigQuery Table`, `API Endpoint`, `Metric`, `Playbook`, `Reference`).

### Recommended fields (in priority order)

`title` → `description` → `resource` → `tags` → `timestamp`.

- Include a `description`: it is what index generators and search previews show.
- Set `resource` only when the concept describes a real addressable asset.
- Use `timestamp` in ISO 8601 (`2026-05-28T14:30:00Z`).
- You MAY add any additional producer-defined keys; never drop unknown keys when
  editing an existing file.

## Cross-linking

Relate concepts with standard markdown links. The relationship kind
(parent/child, joins-with, depends-on) is conveyed by the surrounding prose, not
the link.

- **Prefer bundle-relative absolute links** beginning with `/`:
  `[customers](/tables/customers.md)` — stable when files move within a subdir.
- Relative links (`./other.md`) are also valid.
- Broken links are allowed — they may represent not-yet-written knowledge. Never
  delete a link just because its target is missing.

## Conventional body headings

Use these when applicable (they are conventions, not requirements):

| Heading       | Purpose                                              |
|---------------|------------------------------------------------------|
| `# Schema`    | Columns/fields of an asset, usually as a table.      |
| `# Examples`  | Concrete usage examples, often fenced code blocks.   |
| `# Citations` | Numbered external sources backing claims in the body.|

Citations go at the bottom, numbered:

```markdown
# Citations

[1] [Source title](https://example.com/source)
```

## Reserved files (never use these names for concepts)

- **`index.md`** — a directory listing for progressive disclosure. No
  frontmatter (except an optional `okf_version: "0.1"` in the bundle-root index).
  Body is one or more `# Section` headings, each a bullet list of
  `* [Title](relative-url) - description` entries. Descriptions SHOULD come from
  the linked concept's `description` frontmatter.
- **`log.md`** — chronological change history, newest first, grouped by ISO date:

  ```markdown
  # Directory Update Log

  ## 2026-05-22
  * **Creation**: Established the [Dataplex Playbook](/playbooks/dataplex.md).
  * **Update**: Refreshed the schema for [orders](/tables/orders.md).
  ```

## Consumption is permissive

Never reject or "fix" a bundle for: missing optional fields, unknown `type`
values, extra frontmatter keys, broken links, or missing `index.md`. Tolerate
them and keep going.
