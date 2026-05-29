# qa-harness

> **Claude Code plugin marketplace** — 7 plugin độc lập đóng khung Claude vào quy trình QA-driven chuẩn hoá cho project **Playwright + TypeScript**. Consumer pick-and-choose từng plugin theo nhu cầu.

`qa-harness` KHÔNG phải runtime code. Nó shape **hành vi của Claude** qua 3 layer:
- **Hooks** (runtime gates) — 6 plugin có hook
- **BMAD agents** (workflow) — `bmad-workflows` plugin
- **Skills/Docs** (standards) — `bmad-workflows` plugin

Bất kỳ team Playwright nào cũng plug-in được — KHÔNG tied vào 1 project cụ thể.

---

## Vì sao cần?

| Vấn đề khi để Claude tự sinh test | Plugin giải |
|---|---|
| Mỗi prompt ra 1 style → test suite tạp | `bmad-workflows` (skills) ép pattern POM/COM/Service/Factory/Fixture/Helper |
| Mix P0/P1/P2 trong 1 file → CI không grep được | `test-enforcement` block + Rule #6 trong checklist |
| Hard-code payload → fail parallel | `test-enforcement` (fixture-helper-prereq) ép Factory discipline |
| Đọc trùng file → đốt token | `cost-control` block + cảnh báo cost |
| Token output BMAD agent activation lệch 2× cùng 1 prompt | `bmad-workflows` (output-consistency guard) ép ≤250 tokens |
| Sửa test để pass khi BE bug | Hierarchy of Truth — test = requirement, không phải verification |
| Không observe được Claude làm gì | `session` + `langfuse` ghi span + push Langfuse |

---

## Marketplace structure

```
qa-harness/
├── .claude-plugin/marketplace.json   ← Marketplace index (8 plugins)
├── plugins/
│   ├── bmad-workflows/                ← Core: BMAD agents + skills + commands + 3 guards
│   ├── test-enforcement/              ← Pre-write quality gates (5 hooks)
│   ├── qa-context/                    ← UserPromptSubmit context injectors (3 hooks)
│   ├── consumer-setup/                ← Onboarding check (1 hook)
│   ├── cost-control/                  ← Read dedup (1 hook)
│   ├── session/                       ← Lifecycle + logging (5 hooks + langfuse-helper.js)
│   └── langfuse/                      ← Telemetry + scoring (3 hooks + langfuse-helper.js)
├── README.md / CLAUDE.md / MEMORY.md
└── scripts/                            ← Install + maintenance utilities
```

Mỗi plugin **self-contained:** có `.claude-plugin/plugin.json` riêng + `hooks/hooks.json` riêng + scripts riêng + `_hook-span-emit.sh` riêng. `langfuse-helper.js` được bundle vào cả `session` + `langfuse` để khỏi cross-plugin dependency.

---

## Plugin catalog

| Plugin | Loại | Hooks | Mục đích chính |
|---|---|---|---|
| **bmad-workflows** | Knowledge + Guard | 3 (UserPromptSubmit + PreToolUse W\|E) | BMAD framework: agents, skills, commands, `_bmad/` + 3 runtime guards (agent scope, output consistency, config priority) |
| **test-enforcement** | Quality Gate | 4 PreToolUse + 1 PostToolUse async | Spec tags, 9-rule quality checklist, fixture/helper prereq, security reminder, run-then-fixme |
| **qa-context** | Context Injection | 3 UserPromptSubmit | Roadmap reading, test orchestration checklist, QA skill preload |
| **consumer-setup** | Onboarding | 1 SessionStart startup | Nhắc consumer tạo file/folder bắt buộc nếu thiếu |
| **cost-control** | Cost Optim | 1 PreToolUse Read | Block đọc trùng file (compact-aware + escape valve) |
| **session** | Lifecycle | SessionStart, UserPromptSubmit, PostToolUse, Stop, SessionEnd | Log session, push langfuse trace, archive |
| **langfuse** | Observability | 1 UserPromptSubmit + utilities | Score detection, score flush, accuracy/efficiency scoring |

---

## Cài đặt cho consumer

### Bước 1 — Cấu trúc consumer repo tối thiểu

```
your-playwright-project/
├── _bmad/bmm/config.yaml         ★ BẮT BUỘC (override plugin default)
├── .env                           ★ Langfuse credentials (optional)
├── package.json                   Playwright deps
├── playwright.config.ts
├── src/{constants,fixtures,utils}/
└── tests/{api,e2e}/
```

### Bước 2 — `_bmad/bmm/config.yaml` (BẮT BUỘC)

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

> **Config priority** (enforced bởi `enforce-bmad-config-priority.sh` — `bmad-workflows` plugin):
> 1. `./_bmad/<path>` ← **Consumer override (wins)**
> 2. `${CLAUDE_PLUGIN_ROOT}/_bmad/<path>` ← **Plugin default fallback**
>
> Áp dụng cho mọi file dưới `_bmad/`: `config.yaml`, `agents/*.md`, `workflows/**/*.{yaml,md}`, `tasks/*.md`, `core/**`. Consumer override 1 agent/workflow riêng cho project mà KHÔNG cần fork — chỉ tạo file ở `./_bmad/<same-relative-path>`.

### Bước 3 — Enable plugins (selective)

**Cách A — Official command** (recommended) — trong Claude session:

```bash
cd your-playwright-project
claude
# Trong session:
/plugin marketplace add tantai-bic/qa-harness
/plugin install bmad-workflows@qa-harness
/plugin install test-enforcement@qa-harness
/plugin install qa-context@qa-harness
/plugin install consumer-setup@qa-harness
/plugin install session@qa-harness
# Optional: cost-control, langfuse
/reload-plugins
```

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
    "bmad-workflows@qa-harness": true,
    "test-enforcement@qa-harness": true,
    "qa-context@qa-harness": true,
    "consumer-setup@qa-harness": true,
    "session@qa-harness": true,
    "cost-control@qa-harness": true,
    "langfuse@qa-harness": true
  }
}
```

**Recommended minimum:** `bmad-workflows` + `test-enforcement` + `qa-context` + `consumer-setup` + `session`. Thêm `cost-control` + `langfuse` cho cost/observability.

**Cách C — Ad-hoc local** (dev, không cần marketplace):

```bash
cd your-playwright-project
claude --plugin-dir /path/to/qa-harness/plugins/bmad-workflows
# Hoặc clone toàn bộ marketplace + install riêng từng plugin
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
claude --debug hooks
# /plugin list                          → 7 plugin enabled
# /bmad-workflows:bmad:bmm:agents:dev   → menu Amelia hiện ≤250 tokens
```

---

## Layer 1 — Hooks inventory (map mỗi script → plugin chủ)

| Plugin | Hook script | Event | Vai trò | Bypass |
|---|---|---|---|---|
| `consumer-setup` | `check-consumer-setup.sh` | SessionStart startup | Nhắc file/folder thiếu | `SKIP_SETUP_CHECK=1` |
| `session` | `session-start.sh` | SessionStart (startup\|resume\|clear\|compact) | Preload state, init telemetry | — |
| `session` | `session-logger-init.sh` | UserPromptSubmit | Bắt đầu log session | — |
| `session` | `session-logger-tool.sh` | PostToolUse | Log tool execution | — |
| `session` | `session-stop.sh` | Stop | Flush hook spans + push langfuse | — |
| `session` | `session-cleanup.sh` | SessionEnd | Final archive | — |
| `langfuse` | `langfuse-score-detector.sh` | UserPromptSubmit | Detect scoring opportunity | `SKIP_SCORE_DETECTOR=1` |
| `langfuse` | `langfuse-push-score.sh` | (manual utility) | Flush queued scores | — |
| `langfuse` | `langfuse-score-accuracy-efficiency.sh` | (manual utility) | Compute metric | — |
| `bmad-workflows` | `enforce-bmad-config-priority.sh` | UserPromptSubmit | Ép `_bmad/*` ưu tiên consumer | `SKIP_BMAD_PRIORITY=1` |
| `bmad-workflows` | `enforce-bmad-output-consistency.sh` | UserPromptSubmit | Gate agent activation ≤250 tokens | `SKIP_BMAD_OUTPUT=1` |
| `bmad-workflows` | `enforce-bmad-agent-scope.sh` | PreToolUse Write\|Edit | Block agent làm sai role | `SKIP_BMAD_SCOPE=1` |
| `qa-context` | `enforce-roadmap-reading.sh` | UserPromptSubmit | Ép đọc roadmap | `SKIP_ROADMAP_READING=1` |
| `qa-context` | `orchestrate-test-automation.sh` | UserPromptSubmit | Inject test-writing checklist | `SKIP_TEST_ORCHESTRATION=1` |
| `qa-context` | `preload-qa-context.sh` | UserPromptSubmit | Load QA context | `SKIP_QA_PRELOAD=1` |
| `test-enforcement` | `enforce-fixture-helper-prerequisite.sh` | PreToolUse Write\|Edit | Block thiếu fixture/helper | `SKIP_FIXTURE_PREREQ=1` |
| `test-enforcement` | `enforce-spec-tags.sh` | PreToolUse Write\|Edit | Block spec thiếu tag CICD | `SKIP_SPEC_TAGS=1` |
| `test-enforcement` | `enforce-security-test-presence.sh` | PreToolUse Write\|Edit | Warn thiếu security coverage | `SKIP_SECURITY_REMINDER=1` |
| `test-enforcement` | `enforce-test-quality-checklist.sh` | PreToolUse Write\|Edit | Block vi phạm 9 rules | `SKIP_QUALITY_CHECKLIST=1` |
| `test-enforcement` | `run-test-mark-fixme.sh` | PostToolUse Write\|Edit (async) | Run test → mark fail bằng fixme() | `SKIP_RUN_TEST=1` |
| `cost-control` | `enforce-read-dedup.sh` | PreToolUse Read | Block đọc trùng file | `SKIP_READ_DEDUP=1` |

**Master kill switch:** `SKIP_HOOKS=1` — tắt mọi hook ở mọi plugin.

---

## Layer 2 — BMAD Agents (`bmad-workflows` plugin)

Invoke qua `/bmad-workflows:bmad:bmm:agents:<name>`:

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
- Menu items giữ exact wording từ `<menu>` YAML — KHÔNG translate
- STOP sau menu, WAIT user input — KHÔNG auto-execute

---

## Layer 3 — Skills (`bmad-workflows/skills/`)

| Skill | Mục đích |
|---|---|
| `test-quality-checklist` | 9 rules + 41 items — quality contract cho mọi test code |
| `qa-test-case` | Thiết kế test case (happy/bad/edge + 4 technique: equivalence, boundary, decision-table, state-transition) |
| `qa-engineer` | Full-stack code patterns (POM/COM/Service/Factory/Fixture/Helper) |

> Skills generic — KHÔNG phụ thuộc 1 consumer cụ thể. Adapt cho consumer mới: giữ nguyên skills, chỉ thay docs/example trong `bmad-workflows/docs/`.

---

## Hierarchy of Truth (universal)

1. **Test Design Document** = requirement (HIGHEST)
2. **Test Code** = verification
3. **Backend response** = implementation (có thể bug)
4. **API-DOC** = documentation (có thể outdated)

→ Test fail ≠ test sai. KHÔNG sửa test để pass khi BE sai → log bug theo `plugins/bmad-workflows/docs/templates/log-bug-api-template.md`.

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
- Error assertion: `parseErrorResponse`/`isApiErrorResponse`/`getApiErrorCode`. Assert `error.error.code` match `/^ERR_\d+$/`
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
| `LANGFUSE_PROJECT_TAG` | _(auto: `_bmad/bmm/config.yaml#project_name`)_ | Override `project:<slug>` tag |
| `CONSUMER_REQUIRED_PATHS` | _(default list)_ | CSV path bắt buộc check ở SessionStart |
| `CONSUMER_SETUP_SKIP_DEFAULTS` | — | `=1` bỏ default list |
| `CLAUDE_PLUGIN_ROOT` | _(auto, per-plugin)_ | Claude set khi load plugin — KHÔNG override |

**Combo debug:**

```bash
LANGFUSE_DEBUG=1 claude                                # Verbose
LANGFUSE_VERIFY_SCORES=0 LANGFUSE_DEBUG=1 claude       # Tắt verify
SKIP_HOOKS=1 claude                                    # Panic — tắt mọi hook
SKIP_TEST_ENFORCEMENT=1 claude                         # (nếu cần tắt per-plugin — TBD)
```

---

## Output discipline (cost control)

Observed: trace lãng phí ~$0.90 (12K tokens) cho narrate "thinking out loud".

**HARD RULES** (enforced qua `qa-context/orchestrate-test-automation.sh`):
- Status message giữa actions: ≤50 tokens, KHÔNG recap đã làm gì
- Action TRƯỚC, explain SAU (chỉ khi user hỏi)
- Final summary: 1-2 sentences + file list, KHÔNG re-explain strategy
- KHÔNG repeat hook context đã có trong additionalContext
- Read dedup: file đã đọc → Grep với pattern thay vì Read full

---

## Onboarding 1 consumer mới (TL;DR)

1. Install plugins (Cách A hoặc B) — minimum 5 plugin (`bmad-workflows` + `test-enforcement` + `qa-context` + `consumer-setup` + `session`)
2. Tạo `_bmad/bmm/config.yaml` ở consumer root
3. (Optional) Tạo `.env` Langfuse credentials + enable `langfuse` plugin
4. Tạo docs riêng cho consumer (`docs/PROJECT-STRUCTURE.md`, `docs/roadmap/`) — kiến trúc generic đã có sẵn ở `plugins/bmad-workflows/skills/qa-engineer/architecture.md`
5. (Optional) `.mcp.json` ở consumer root nếu cần MCP — auto-approve qua `enableAllProjectMcpServers: true`
6. Verify: `claude --debug hooks` → kiểm `.claude/session-logs/` có entry mới
7. Smoke test: `/bmad-workflows:bmad:bmm:agents:dev` → activation ≤250 tokens

---

## Critical guardrails

- Repo này shape **BEHAVIOR của Claude**, không phải runtime code → edit hooks/agents/skills cẩn thận, pipe-test trước khi commit
- Hook fail silent = `hooks.json` malformed → validate JSON sau mọi edit
- BMAD agent activation phải theo template — vi phạm bị `enforce-bmad-output-consistency.sh` flag
- Output project (consumer Playwright suite) là **target**, KHÔNG tạo `src/`, `tests/`, `package.json` ở repo này
- Khi update standards trong `plugins/bmad-workflows/skills/qa-test-case/` → version bump + ghi changelog
- **Cross-plugin shared lib:** `langfuse-helper.js` được copy vào CẢ `session/` và `langfuse/` plugin — sửa lib phải sửa đồng bộ cả 2 file
- `_hook-span-emit.sh` được bundle riêng vào mỗi plugin có hook (pattern identical)

---

## License

Internal — see repo owner.
