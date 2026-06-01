# bmad-workflows

Full BMAD layer for Claude Code: agents, workflows, QA skills, slash commands, and runtime guards — bundled into one plugin.

## What it does

Shapes Claude into specialized roles (dev, pm, architect, etc.) and enforces correct behavior at runtime. Three hooks run automatically on every session:

| Hook | Event | Role |
|------|-------|------|
| `enforce-bmad-config-priority.sh` | UserPromptSubmit | Forces `_bmad/*` reads to check consumer override (`./_bmad/`) before plugin default |
| `enforce-bmad-output-consistency.sh` | UserPromptSubmit | Gates agent activation to ≤ 250 tokens — no verbose preamble |
| `enforce-bmad-agent-scope.sh` | PreToolUse Write\|Edit | Blocks agents from editing files outside their role (pm/sm can't edit code; dev can't edit PRDs) |

## Agents

Invoke via `/bmad:bmm:agents:<name>`:

| Agent | Role |
|-------|------|
| `dev` | Developer — implements stories, writes code |
| `pm` | Product Manager — creates PRDs, epics, stories |
| `architect` | System Architect — creates architecture docs, tech specs |
| `sm` | Scrum Master — sprint planning, sprint status, story creation |
| `tea` | Test Engineer Architect — ATDD, test frameworks, NFR |
| `analyst` | Business Analyst — research, product briefs, brainstorming |
| `ux-designer` | UX Designer — UX design, wireframes, Excalidraw diagrams |
| `tech-writer` | Tech Writer — project docs, context generation |
| `quick-flow-solo-dev` | Solo dev flow — quick-dev workflow |
| `bmad-master` | Orchestrator — delegates across all agents |

## Skills

| Skill | Invoke | Description |
|-------|--------|-------------|
| `qa-engineer` | `/qa-engineer` | Full Playwright + TypeScript code patterns (architecture, POM, fixtures, helpers, factories) |
| `qa-test-case` | `/qa-test-case` | Test design toolkit — happy/bad/edge case taxonomy + 7 design techniques |
| `test-quality-checklist` | `/test-quality-checklist` | 9 rules + 41 items — quality contract for all test code |

## BMAD config priority

The `enforce-bmad-config-priority` hook enforces a two-level lookup for all `_bmad/*` files:

1. `./_bmad/<path>` — consumer override (wins)
2. `${CLAUDE_PLUGIN_ROOT}/_bmad/<path>` — plugin default fallback

Create `_bmad/bmm/config.yaml` in your consumer project to override:

```yaml
project_name: "Your project"
user_name: "Your name"
communication_language: "Vietnamese"
output_folder: "docs"
```

## Agent activation contract

Enforced by `enforce-bmad-output-consistency`:

- Greeting: `{icon} Xin chào **{user_name}**! Tôi là **{agent}** — {role}.`
- Output ≤ 250 tokens — show menu, stop, wait for user input
- Menu item wording must match exact strings in agent YAML — no translation

## Bypass

| Env | Scope |
|-----|-------|
| `SKIP_BMAD_PRIORITY=1` | Skip config priority enforcement |
| `SKIP_BMAD_SCOPE=1` | Skip agent role scope check |
| `SKIP_HOOKS=1` | Disable all hooks |

## Install

```json
{
  "enabledPlugins": {
    "bmad-workflows@qa-harness-dev": true
  }
}
```

Enable this plugin first — other plugins in the harness depend on BMAD knowledge being active.
