# Roadmap

Vibe Engineering is in **beta**. This page says where it is going and in what
order. It's a plan, so it will change as we learn; nothing here has a date.

## The goal

Help teams build **agent-first projects**: projects where AI agents do most of
the building, and people decide what gets built and approve each step.

That takes two things, and the plugin should provide both:

- **Solid ideas.** A feature is understood, designed and specified before any
  code is written.
- **An engineering process.** The result is real, stable, scalable and
  reliable, because every change is small, reviewed and traceable.

## What we build by

1. **The board is the memory.** Context lives in the board item, never only in
   a chat, so any person or agent can continue the work.
2. **People decide, agents do.** A skill asks before anything that can't be
   undone: merging, posting, deleting.
3. **One standard, checked everywhere.** A single description of a well-set-up
   project is used to create projects, to check them and to fix them.
4. **Plain words first.** A skill explains what it's doing in words a person
   without an engineering background can follow.
5. **Every skill proves itself.** A skill is tested on a throwaway board before
   it's released.

## Tracks

Each track is a group of skills. Skill names are working names.

| Track | What it gives you | Status |
|---|---|---|
| **1. Deliver** | A feature goes from idea to merged pull request on the board. | In progress |
| **2. Assess** | A report of what a repository is missing to work well with agents. | Planned |
| **3. Set up** | A project configured for agents: instructions, rules, hooks, quality checks. | Planned |
| **4. Start** | A new repository that is set up correctly from day zero. | Planned |
| **5. Guide** | A guided path for people with no software engineering background. | Planned |
| **6. Team** | Planning, status and learning for a team of people and agents. | Proposed |
| **7. Trust** | Tests and checks that keep the plugin itself reliable. | Proposed |

"Proposed" tracks are suggestions that still need a decision.

### 1. Deliver: from idea to merged pull request

The backbone. Every other track feeds it or prepares a project for it.

- [x] `create-board`: the board, with six columns, iterations and views
- [x] `create-item`: an idea, refined by conversation, saved as a Draft item
- [ ] `promote-backlog`: the high-level design
- [ ] `promote-ready`: the spec, the size, and splitting until one item is one PR
- [ ] `develop`: the code, on a branch, following the repository's own rules
- [ ] `push`: the pull request, linked to the item
- [ ] `review`: inline comments the user selects
- [ ] `approve`: the merge

The design is in [concept.md](concept.md).

### 2. Assess: find what's missing

- [ ] **The project standard.** One reference file that lists what an
  agent-ready project has: instructions for agents, rules, a way to run tests
  with one command, CI, a pull request template, branch protection, an
  architecture description, a linked board.
- [ ] `assess`: reads a repository, compares it with the standard, and reports
  the gaps in order of importance. It changes nothing.
- [ ] *Proposal:* each gap can be saved as a Draft item, so closing gaps goes
  through the same Deliver flow as any feature.

### 3. Set up: a project configured for agents

- [ ] `setup-ai`: writes or reviews the project's AI patterns: `CLAUDE.md`,
  rules, hooks, permissions, and the skills this project needs for itself.
- [ ] *Proposal:* `setup-architecture`: records the architecture and the
  patterns to follow, and keeps a log of decisions. `promote-backlog` and
  `develop` read it, which is what keeps the code consistent as it grows.
- [ ] *Proposal:* `setup-quality`: one command for tests and lint, a CI
  workflow, a pull request template, branch protection. This gives `approve`
  real checks to rely on.

Each of these fixes what `assess` finds, and is checked by it afterwards.

### 4. Start: right from day zero

- [ ] `new-project`: creates a repository from a template, with everything from
  Set up already in place and a board linked to it.
- [ ] Templates: a general one first, then one per stack, chosen by demand.

A template is the project standard applied before the first commit.

### 5. Guide: no engineering background needed

- [ ] `start-here`: a guided path from "I have an idea for an app" to a
  repository, a board and a first item. It explains each concept the first
  time it appears and picks safe defaults.
- [ ] A glossary in the help page: board, branch, pull request, review.
- [ ] *Proposal:* a plain-language check on every skill, so the whole plugin
  stays usable for this audience, not only the guide.

### 6. Team: people and agents working together (proposed)

- [ ] `plan-iteration`: picks Ready items for the next iteration, by priority,
  estimate and capacity.
- [ ] `status`: what moved, what is blocked, and what is waiting for a person.
- [ ] `retro`: turns what went wrong in an iteration into changes to the
  project's rules, so the process improves itself.
- [ ] Parallel work: several agents each build a different Ready item. The
  one-item-one-PR rule already makes this safe.

### 7. Trust: a plugin you can rely on (proposed)

- [ ] Automated tests for the shared scripts, run on every push to this
  repository.
- [ ] An eval suite that runs each skill against a throwaway board.
- [ ] A changelog, and a rule for what a version number means.
- [ ] A listing in Anthropic's plugin directory.

## Order

1. **Finish Deliver**, with the first Trust items alongside it, because every
   new skill adds risk.
2. **Assess.** It only reads, so it's safe; it's useful on any existing
   repository from the first day; and writing it forces us to define the
   project standard that Set up and Start depend on.
3. **Set up**, then **Start.** Set up fixes what Assess finds. Start is the
   same standard applied to a new repository.
4. **Guide.** It drives Start and Set up, so they must exist first.
5. **Team.**

### Version 1.0 means

- The full Deliver flow has shipped a real feature, from idea to merge, on a
  real project.
- Assess and Set up exist and agree with each other.
- The eval suite passes.
- The plugin is listed in Anthropic's directory.

## Open questions

- After Deliver, does Assess come before Set up, as proposed above?
- Which stacks get the first templates?
- Is Guide one skill that drives the others, or a mode of every skill?
- GitHub only, or other trackers later? The proposal is GitHub only until 1.0.
- Do the Team and Trust tracks stay in?
