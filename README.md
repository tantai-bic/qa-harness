# qa-harness

> Reusable **Claude Code plugin** đóng khung Claude vào quy trình QA-driven chuẩn hoá cho mọi project **Playwright + TypeScript** — sinh test suite consistent, đúng pattern, đủ chất lượng.

`qa-harness` KHÔNG phải runtime code. Nó shape **hành vi của Claude** qua 3 layer: **Hooks** (runtime gates) + **BMAD agents** (workflow) + **Skills/Docs** (standards). Bất kỳ team Playwright nào cũng plug-in được — không tied vào 1 project cụ thể.

---

## Vì sao cần?

| Vấn đề khi để Claude tự sinh test | Cách qa-harness giải |
|---|---|
| Mỗi prompt ra 1 style → test suite tạp | BMAD agents + skills ép pattern POM/COM/Service/Factory/Fixture/Helper |
| Mix P0/P1/P2 trong 1 file → CI không grep được | `enforce-test-quality-checklist.sh` block + Rule #6 trong checklist |
| Hard-code payload → fail parallel | Factory discipline ép `create<Module>Payload()` |
| Đọc trùng file → đốt token | `enforce-read-dedup.sh` block + cảnh báo cost |
| Token output BMAD agent activation lệch 2× (cùng 1 prompt) | `enforce-bmad-output-consistency.sh` ép ≤250 tokens |
| Sửa test để pass khi BE bug | Hierarchy of Truth doc — test = requirement, không phải verification |
| Không observe được Claude làm gì | Hooks ghi span + push Langfuse (generation + 6 enforcement spans per prompt) |

---

## Kiến trúc 3-layer

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: HOOKS (hooks/) — runtime gates                    │
│  Inject context, block bad actions, score quality, log      │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: BMAD AGENTS (agents/ + _bmad/) — workflow         │
│  dev, sm, architect, pm, tea, ux-designer, analyst, ...     │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: SKILLS + DOCS — standards (generic) + examples    │
│  test-quality-checklist, qa-test-case, qa-engineer          │
└─────────────────────────────────────────────────────────────┘
        ↓ outputs
   Playwright + TS suite của consumer
```

```
qa-harness/
├── .claude-plugin/plugin.json     Plugin manifest
├── commands/                      Slash commands (/bmad:bmm:agents:dev, ...)
├── agents/                        Sub-agents (auto-discovered)
├── skills/                        Skills (qa-engineer, qa-test-case, test-quality-checklist)
├── hooks/                         Event hooks + langfuse-helper.js
│   ├── hooks.json                 Hook declarations (6 events, 13 commands)
│   ├── check-consumer-setup.sh    SessionStart — nhắc setup file thiếu
│   ├── enforce-*.sh               Quality gates
│   ├── orchestrate-test-automation.sh
│   ├── preload-qa-context.sh
│   ├── session-{start,stop,cleanup,logger-*}.sh
│   └── langfuse-{helper.js,push-score.sh,score-*.sh}
├── _bmad/                         BMAD framework (agents YAML, workflows)
└── docs/                          Templates + example (sprouX consumer)
```

---

## Cài đặt cho consumer

### Bước 1 — Cấu trúc consumer repo tối thiểu

```
your-playwright-project/
├── _bmad/bmm/config.yaml         ★ BẮT BUỘC
├── .env                           ★ Langfuse credentials (optional)
├── package.json                   Playwright deps
├── playwright.config.ts
├── src/{constants,fixtures,utils}/
└── tests/{api,e2e}/
```

### Bước 2 — `_bmad/bmm/config.yaml` (BẮT BUỘC, agents đọc đầu tiên)

```yaml
project_name: your-project
user_name: your-name
communication_language: vietnamese        # or english
document_output_language: vietnamese
output_folder: "{project-root}/_bmad-output"
user_skill_level: beginner
planning_artifacts: "{project-root}/_bmad-output/project-planning-artifacts"
implementation_artifacts: "{project-root}/_bmad-output/implementation-artifacts"
project_knowledge: "{project-root}/docs"
tea_use_mcp_enhancements: true
tea_use_playwright_utils: true
```

> **Config priority** (enforced bởi `enforce-bmad-config-priority.sh` hook):
> 1. `./_bmad/<path>` ← **Consumer override (wins)** — file ở consumer cwd
> 2. `${CLAUDE_PLUGIN_ROOT}/_bmad/<path>` ← **Plugin default fallback**
>
> Áp dụng cho mọi file dưới `_bmad/`: `config.yaml`, `agents/*.md`, `workflows/**/*.{yaml,md}`, `tasks/*.md`, `core/**`. Consumer có thể override 1 agent / 1 workflow riêng cho project mà KHÔNG cần fork plugin — chỉ tạo file ở `./_bmad/<same-relative-path>`. Hook tự scan + report cho Claude mỗi prompt nào đang override.

### Bước 3 — Enable plugin

**Cách A — Official command (recommended)** — trong Claude session:

```bash
cd your-playwright-project
claude
# Trong session:
/plugin marketplace add tantai-bic/qa-harness
/plugin install bmad-harness-plugin@qa-harness
/reload-plugins                         # apply ngay (hoặc restart claude)
```

Plugin tự enable sau install. Không cần edit settings.json thủ công.

**Cách B — settings.json permanent** — `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "qa-harness": {
      "type": "github",
      "repository": "tantai-bic/qa-harness"
    }
  },
  "enabledPlugins": {
    "bmad-harness-plugin@qa-harness": true
  }
}
```

**Cách C — Ad-hoc local** (dev plugin, không cần marketplace):

```bash
cd your-playwright-project
claude --plugin-dir /path/to/qa-harness
```

**Cách D — Tarball offline** (air-gap, bulk provisioning) — dùng `scripts/install-consumer.sh`:

```bash
bash scripts/install-consumer.sh latest ~/.qa-harness
claude --plugin-dir ~/.qa-harness
```

### Bước 4 — `.env` cho Langfuse (optional)

```ini
LANGFUSE_HOST=https://cloud.langfuse.com
LANGFUSE_PUBLIC_KEY=pk-lf-xxxx
LANGFUSE_SECRET_KEY=sk-lf-xxxx
```

> ⚠ `.env` của consumer **wins** > shell env > plugin `.env` (plugin .env bị ignore).

### Bước 5 — Verify

```bash
claude --debug hooks --plugin-dir /path/to/qa-harness
# /plugin list                       → bmad-harness-plugin: enabled
# /bmad-harness-plugin:bmad:bmm:agents:dev → menu Amelia hiện ≤250 tokens
```

---

## Layer 1 — Hooks inventory

| Hook | Event | Vai trò | Bypass |
|---|---|---|---|
| `check-consumer-setup.sh` | SessionStart (startup) | Nhắc file/folder thiếu | `SKIP_SETUP_CHECK=1` |
| `session-start.sh` | SessionStart (any) | Push trace `session-init` + env snapshot | — |
| `session-logger-init.sh` | UserPromptSubmit | Bắt đầu log session, queue Langfuse event | — |
| `enforce-roadmap-reading.sh` | UserPromptSubmit | Ép đọc roadmap trước khi code | `SKIP_ROADMAP_READING=1` |
| `orchestrate-test-automation.sh` | UserPromptSubmit | Inject test-writing checklist (Rule #6, factory, terseness) | `SKIP_TEST_ORCHESTRATION=1` |
| `preload-qa-context.sh` | UserPromptSubmit | Load QA context relevant | `SKIP_QA_PRELOAD=1` |
| `enforce-bmad-output-consistency.sh` | UserPromptSubmit | Gate BMAD agent activation ≤250 tokens | `SKIP_BMAD_OUTPUT=1` |
| `langfuse-score-detector.sh` | UserPromptSubmit | Detect scoring opportunity | `SKIP_SCORE_DETECTOR=1` |
| `enforce-test-quality-checklist.sh` | PreToolUse Write\|Edit | Block test code vi phạm 9 rules | `SKIP_QUALITY_CHECKLIST=1` |
| `enforce-read-dedup.sh` | PreToolUse Read | Block đọc trùng file | `SKIP_READ_DEDUP=1` |
| `session-logger-tool.sh` | PostToolUse | Log tool execution |  — |
| `session-stop.sh` | Stop | Flush hook spans + generation lên Langfuse | — |
| `session-cleanup.sh` | SessionEnd | Final cleanup, archive | — |

**Master kill switch:** `SKIP_HOOKS=1` — tắt mọi hook.

---

## Layer 2 — BMAD Agents

Invoke qua `/bmad-harness-plugin:bmad:bmm:agents:<name>`:

| Agent | Role | Workflow chính |
|---|---|---|
| `analyst` | Business analyst | create-product-brief, research, brainstorming |
| `pm` | Product Manager | create-prd, create-epics-and-stories |
| `architect` | System architect | create-architecture, create-tech-spec |
| `ux-designer` | UX | create-ux-design, excalidraw wireframes |
| `sm` | Scrum Master | create-story, sprint-planning, sprint-status |
| `dev` | Developer (Amelia) | dev-story, code-review |
| `tea` | Test Engineer Architect | testarch-atdd/automate/framework/nfr/test-design/trace |
| `tech-writer` | Tech writer | document-project, generate-project-context |
| `quick-flow-solo-dev` | Solo dev flow | quick-dev |

**Activation contract** (enforced bởi `enforce-bmad-output-consistency.sh`):
- Output ≤250 tokens, KHÔNG dump session vars, KHÔNG flourish/emoji thừa
- Menu items giữ exact wording từ `<menu>` agent YAML — KHÔNG translate
- STOP sau menu, WAIT user input — KHÔNG auto-execute

---

## Layer 3 — Skills (standards)

| Skill | Mục đích |
|---|---|
| `test-quality-checklist` | 9 rules + 41 items — quality contract cho mọi test code |
| `qa-test-case` | Entry point thiết kế test case (happy/bad/edge + 3 technique: equivalence, boundary, decision-table) |
| `qa-engineer` | Full-stack code patterns (POM/COM/Service/Factory/Fixture/Helper) |

> Skills generic — KHÔNG phụ thuộc 1 consumer cụ thể. Adapt cho consumer mới: giữ nguyên skills, chỉ thay docs/example.

---

## Hierarchy of Truth (universal)

1. **Test Design Document** = requirement (HIGHEST)
2. **Test Code** = verification
3. **Backend response** = implementation (có thể bug)
4. **API-DOC** = documentation (có thể outdated)

→ Test fail ≠ test sai. KHÔNG sửa test để pass khi BE sai → log bug theo `docs/templates/log-bug-api-template.md`.

---

## Test code generation contracts

- **Rule #6 — Split priority:** mỗi priority 1 file riêng
  ```
  tests/<api|e2e>/{domain}/{story-folder}/P0-{feature}.spec.ts
  tests/<api|e2e>/{domain}/{story-folder}/P1-{feature}.spec.ts
  tests/<api|e2e>/{domain}/{story-folder}/P2-{feature}.spec.ts
  ```
- **Service + Factory per-module** (KHÔNG generic): `<Module>Service.<action>` + `create<Module>Payload()`
- Mọi payload qua **factory** (parallel-safe), KHÔNG hard-code
- Mọi API call qua **`*.service.ts`** (KHÔNG `request.post` trực tiếp)
- Truyền `testName` param vào mọi service call (traceability)
- Endpoint từ `API_ENDPOINTS` constant, KHÔNG hardcode URL
- Import path: `@src/*` alias
- Error assertion: dùng helper `parseErrorResponse`/`isApiErrorResponse`/`getApiErrorCode`. Assert `error.error.code` match `/^ERR_\d+$/` — KHÔNG hardcode code cụ thể
- 401/403 test: fresh context + `*WithoutAuth()` / dedicated test user login
- Type safety: KHÔNG `any`/`unknown`, cast inline interface

---

## Env vars debug & config

| Var | Default | Mục đích |
|---|---|---|
| `LANGFUSE_DEBUG` | — | `=1` in `[langfuse] flushed N / failed ...` ra stderr |
| `LANGFUSE_LOCAL_ARCHIVE` | `1` | `=0` tắt archive event local |
| `LANGFUSE_VERIFY_SCORES` | `1` | `=0` skip verify sau push score |
| `LANGFUSE_VERIFY_RETRY` | `3` | Số retry push nếu verify fail |
| `LANGFUSE_VERIFY_WAIT` | `2` | Sleep giữa retry (giây) |
| `LANGFUSE_TOKEN_TARGET/_MAX` | — | Ngưỡng scoring token usage |
| `LANGFUSE_COST_TARGET/_MAX` | — | Ngưỡng scoring USD cost |
| `LANGFUSE_W_ACCURACY/_COST/_TOKEN/_QUALITY` | — | Weight composite score |
| `LANGFUSE_PRICING_JSON` | — | Override model pricing JSON |
| `LANGFUSE_PROJECT_TAG` | _(auto: `_bmad/bmm/config.yaml#project_name` → cwd basename)_ | Override `project:<slug>` tag gắn vào mọi trace |
| `CONSUMER_REQUIRED_PATHS` | _(default list)_ | CSV path bắt buộc check ở SessionStart |
| `CONSUMER_SETUP_SKIP_DEFAULTS` | — | `=1` bỏ default list, chỉ check `CONSUMER_REQUIRED_PATHS` |
| `CLAUDE_PLUGIN_ROOT` | _(auto)_ | Claude set khi load plugin — KHÔNG override |

**Combo debug recommended:**

```bash
# Verbose
LANGFUSE_DEBUG=1 claude --plugin-dir /path/to/qa-harness

# Tắt verify (Langfuse self-host chậm)
LANGFUSE_VERIFY_SCORES=0 LANGFUSE_DEBUG=1 claude --plugin-dir ...

# Panic
SKIP_HOOKS=1 claude --plugin-dir ...
```

---

## Output discipline (cost control)

Observed: trace lãng phí ~$0.90 (12K tokens) cho narrate "thinking out loud".

**HARD RULES** (enforced qua orchestrate hook):
- Status message giữa actions: ≤50 tokens, KHÔNG recap đã làm gì
- Action TRƯỚC, explain SAU (chỉ khi user hỏi)
- Final summary: 1-2 sentences + file list, KHÔNG re-explain strategy
- KHÔNG repeat hook context đã có trong additionalContext
- Read dedup: file đã đọc → dùng Grep với pattern thay vì Read full

---

## Onboarding 1 consumer mới (TL;DR)

1. Install plugin (Cách A hoặc B ở trên)
2. Tạo `_bmad/bmm/config.yaml` ở consumer root
3. (Optional) Tạo `.env` Langfuse credentials
4. Tạo docs riêng cho consumer (`docs/PROJECT-STRUCTURE.md`, `docs/roadmap/`) — kiến trúc generic đã có sẵn ở `skills/qa-engineer/architecture.md`
5. (Optional) `.mcp.json` ở consumer root nếu cần MCP — auto-approve qua `enableAllProjectMcpServers: true`
6. Verify: `claude --debug hooks` → kiểm `.claude/session-logs/` có entry mới
7. Smoke test: `/bmad-harness-plugin:bmad:bmm:agents:dev` → activation ≤250 tokens

---

## Critical guardrails

- Repo này shape **BEHAVIOR của Claude**, không phải runtime code → edit hooks/agents/docs cẩn thận, pipe-test trước khi commit
- Hook fail silent = settings.json malformed → validate JSON sau mọi edit
- BMAD agent activation phải theo template — vi phạm bị `enforce-bmad-output-consistency.sh` flag
- Output project (consumer Playwright suite) là **target**, không tạo `src/`, `tests/`, `package.json` ở repo này
- Khi update standards trong `skills/qa-test-case/` → version bump + ghi changelog, consumers downstream phụ thuộc

---

## License

Internal — see repo owner.
