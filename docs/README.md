# FinBot Canonical Design Artifacts

This directory contains the latest source-controlled design and implementation
plans for FinBot. Each problem or cohesive feature has one canonical Markdown
artifact that records the decisions, contracts, implementation tickets, and
handoff requirements agreed during design discussions.

## Document strategy

Use **one canonical artifact per cohesive problem**, even when implementation
crosses `finbot-api`, `finbot`, and this parent infrastructure repository.

Do not split a design into separate API and frontend documents merely because
the code lives in separate repositories. Doing so duplicates shared decisions,
state machines, and contracts and makes drift more likely. Instead, keep
repo-scoped ticket tracks in the same artifact:

- `API-*` for `finbot-api`
- `APP-*` for `finbot`
- `INFRA-*` for this parent `finbot-app` repository

Create separate canonical artifacts only when the subjects can be designed,
approved, replaced, and implemented independently.

## Ticket sizing and execution

Every implementation ticket should:

- fit one agent run and one reviewable pull request;
- normally modify only one repository;
- have no unresolved product or architecture decision;
- name its dependencies and safe parallel work;
- define observable acceptance criteria and required tests;
- identify the contract or artifact it produces for downstream tickets.

The artifact must define a dependency graph and delivery gates. Numbering is
for stable references, not necessarily strict execution order. Agents may work
in parallel only when the dependency graph explicitly permits it.

## Canonical status

Artifacts use frontmatter with a `status` value:

- `draft` — still contains unresolved decisions;
- `canonical` — approved source of truth for implementation;
- `superseded` — retained for history and linked to its replacement.

Update the existing canonical artifact when the same design evolves. Do not
create names such as `final-v2`, `latest`, or `new-plan`.

## Diagrams and supporting designs

Keep diagrams and extended design material in an appendix so the main plan
remains readable. The main body should link to each appendix diagram by its
Markdown anchor.

- Prefer Mermaid for version-controlled architecture, sequence, state, and
  dependency diagrams.
- Put large or externally produced files under
  `docs/assets/<artifact-slug>/` and link to them with relative paths.
- Give every diagram a title and explain what is normative about it.

## Creating an artifact

1. Copy [TEMPLATE.md](TEMPLATE.md) to `docs/<descriptive-kebab-case-name>.md`.
2. Resolve or explicitly record every decision in **Decision record**.
3. Separate system design from implementation tickets.
4. Give each ticket a stable ID, dependencies, acceptance criteria, and tests.
5. Put diagrams in the linked appendix.
6. Mark the document `canonical` only when unresolved items do not block work.

The current financial onboarding design is documented in
[financial-onboarding-and-transaction-analysis.md](financial-onboarding-and-transaction-analysis.md).
