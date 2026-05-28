# CLAUDE.md — qa-harness (Reusable Claude Code Plugin for Playwright Projects)

> Context bắt buộc đọc cho mọi session làm việc trên repo này.

## 1. Repo identity

- **Tên:** `qa-harness` — **Claude Code plugin tái sử dụng** cho mọi project Playwright (KHÔNG tied to riêng project nào).
- **Mục đích:** đóng khung Claude vào quy trình QA-driven chuẩn hoá → bất kỳ team nào dùng Playwright + TypeScript đều có thể plug-in để Claude sinh test suite consistent, đúng pattern, đủ chất lượng.
- **Cơ chế:** hooks (runtime gates) + BMAD agents (workflow) + docs (standards) — tất cả **project-agnostic**.
- **sprouX-testing là một CONSUMER** của harness, không phải target duy nhất. Mọi reference đến "sprouX" trong docs/ chỉ là **ví dụ minh hoạ**.

## 2. Plug-in model (Claude Code Plugin spec)

```
bmad-harness-plugin/             (= repo này, packaged as Claude Code plugin)
├── .claude-plugin/
│   └── plugin.json              Plugin manifest (BẮT BUỘC)
├── commands/                    Slash commands
├── agents/                      Sub-agents (PM, Dev, QA, ...)
├── skills/                      Skills (qa-engineer, qa-test-case)
├── hooks/                       Event hooks (gates, scoring, logging)
├── _bmad/                       BMAD framework resources (workflows, config, tasks)
├── docs/                        Templates + example architecture
├── .mcp.json                    MCP servers (rỗng — consumer override)
└── README.md
```

**Cách dùng:** consumer thêm vào `~/.claude/settings.json`:
```json
{ "enabledPlugins": { "bmad-harness-plugin@<marketplace>": true } }
```
Claude Code tự load `commands/`, `agents/`, `skills/`, `hooks/` từ plugin khi enabled.

## 3. Kiến trúc 3-layer (project-agnostic)

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: HOOKS (hooks/) — runtime gates                    │
│  Inject context, block bad actions, score quality, log      │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: BMAD AGENTS (agents/ + _bmad/) — workflow         │
│  dev, sm, architect, pm, tea, ux-designer, analyst, ...     │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: DOCS (docs/) — standards (generic) + examples     │
│  test-design templates, quality rules, technique catalog    │
└─────────────────────────────────────────────────────────────┘
        ↓ outputs
   Bất kỳ Playwright + TS project nào của consumer
```

## 4. Hooks (Layer 1) — generic gates

| Hook | Event | Vai trò |
|------|-------|---------|
| `session-start.sh` | SessionStart | Preload state, init telemetry |
| `check-consumer-setup.sh` | SessionStart (startup only) | Nhắc consumer tạo các file/folder bắt buộc nếu thiếu (BMAD config, roadmap, playwright config, src/constants, src/fixtures, tests/). Tự skip khi chạy trên plugin source. Env override: `CONSUMER_REQUIRED_PATHS`, `CONSUMER_SETUP_SKIP_DEFAULTS=1`. Bypass: `SKIP_SETUP_CHECK=1` |
| `session-logger-init.sh` | UserPromptSubmit | Bắt đầu log session |
| `enforce-roadmap-reading.sh` | UserPromptSubmit | Ép đọc roadmap doc (nếu consumer có) trước khi code |
| `orchestrate-test-automation.sh` | UserPromptSubmit | 2-mode: (1) LOGIC keyword (viết/create/add test) → inject full QA orchestration checklist (Rule #6, factory, skill reads). (2) TEXT-ONLY edit (rename/fix typo/update string) → downgrade, chỉ inject nhắc giữ tags + import structure. Bypass: `SKIP_TEST_ORCHESTRATION=1` |
| `preload-qa-context.sh` | UserPromptSubmit | Load QA context relevant |
| `enforce-bmad-output-consistency.sh` | UserPromptSubmit | Gate BMAD agent activation ≤ 250 tokens |
| `enforce-bmad-config-priority.sh` | UserPromptSubmit | Ép đọc `_bmad/*` ưu tiên consumer (`./_bmad/`) > plugin (`${CLAUDE_PLUGIN_ROOT}/_bmad/`). Detect overrides + inject context. Bypass: `SKIP_BMAD_PRIORITY=1` |
| `run-test-mark-fixme.sh` | PostToolUse Write|Edit (async) | Sau khi Write/Edit `tests/**/*.spec.ts` → chạy `npx playwright test <file>` → mark fail tests bằng `test.fixme()` để không break CI. Cần `playwright.config.ts` + `npx`. Timeout 120s. Bypass: `SKIP_RUN_TEST=1`
| `langfuse-score-detector.sh` | UserPromptSubmit | Detect scoring opportunity |
| `enforce-fixture-helper-prerequisite.sh` | PreToolUse Write\|Edit | Block viết test spec nếu import service/factory/fixture/helper CHƯA tồn tại. Buộc tạo prerequisite trước. Bypass: `SKIP_FIXTURE_PREREQ=1` |
| `enforce-spec-tags.sh` | PreToolUse Write\|Edit | Block spec thiếu/sai tag CICD. 3 category: PRIORITY (@P0-P3 — match file name), LAYER (@BE/@FE — match path), TYPE (≥1 của @Smoke/@Sanity/@Regression/@Function/@UI/@UX). Bypass: `SKIP_SPEC_TAGS=1` |
| `enforce-test-quality-checklist.sh` | PreToolUse Write\|Edit | Block test code vi phạm 9 rules |
| `enforce-read-dedup.sh` | PreToolUse Read | Block đọc trùng file (cost control) |
| `session-logger-tool.sh` | PostToolUse | Log tool execution |
| `session-stop.sh` / `session-cleanup.sh` | Stop / SessionEnd | Flush logs, push langfuse |

**Bypass:** `SKIP_<HOOK_NAME>=1` (per-hook) hoặc `SKIP_HOOKS=1` (master).

## 5. BMAD Agents (Layer 2) — project-agnostic workflow

Invoke qua `/bmad:bmm:agents:<name>`:

| Agent | Role | Workflow chính |
|-------|------|----------------|
| `analyst` | Business analyst | `create-product-brief`, `research`, `brainstorming` |
| `pm` | Product Manager | `create-prd`, `create-epics-and-stories` |
| `architect` | System architect | `create-architecture`, `create-tech-spec` |
| `ux-designer` | UX | `create-ux-design`, excalidraw wireframes |
| `sm` | Scrum Master | `create-story`, `sprint-planning`, `sprint-status` |
| `dev` | Developer | `dev-story`, `code-review` |
| `tea` | Test Engineer Architect | `testarch-atdd`, `testarch-automate`, `testarch-framework`, `testarch-nfr`, `testarch-test-design`, `testarch-trace` |
| `tech-writer` | Tech writer | `document-project`, `generate-project-context` |
| `quick-flow-solo-dev` | Solo dev flow | `quick-dev` |

**Activation contract** (enforce-bmad-output-consistency):
- Output ≤ 250 tokens, KHÔNG dump session vars, KHÔNG flourish/emoji thừa
- Menu items giữ exact wording từ `<menu>` agent YAML — KHÔNG translate
- Greeting: `{icon} Xin chào **{user_name}**! Tôi là **{agent}** — {role}.`
- STOP sau menu, WAIT user input — KHÔNG auto-execute

## 6. Standards (Layer 3) — reusable

| File | Vai trò | Project-specific? |
|------|---------|-------------------|
| `skills/test-quality-checklist/SKILL.md` | 9 rules + 41 items — quality contract | ❌ Generic |
| `skills/qa-test-case/SKILL.md` | Test design entry point (Claude Code skill) | ❌ Generic |
| `skills/qa-test-case/common/{happy,bad,edge}-case.md` | Case taxonomy | ❌ Generic |
| `skills/qa-test-case/common/{equivalence-partition,boundary-value,decision-table}.md` | Test design techniques | ❌ Generic |
| `skills/qa-test-case/{backend,frontend}/*.md` | API vs E2E patterns | ❌ Generic |
| `skills/qa-engineer/SKILL.md` + 6 bundled (architecture, patterns-api, patterns-e2e, helpers, module-creation, conventions) | Full-stack code patterns (POM/COM/Service/Factory/Fixture/Helper) | ❌ Generic |
| `docs/templates/log-bug-api-template.md` | Bug log template | ❌ Generic |
| `docs/PROJECT-STRUCTURE.md` | **Example** cho 1 consumer (sprouX) | ✅ Tham khảo |
| `docs/roadmap/**` | **Example** state machine của 1 consumer | ✅ Tham khảo |

Khi adapt cho consumer mới: giữ nguyên Generic files, **thay** Example files bằng docs của consumer đó.

## 7. Hierarchy of Truth (universal cho mọi consumer)

1. **Test Design Document** = requirement (HIGHEST)
2. **Test Code** = verification
3. **Backend response** = implementation (có thể bug)
4. **API-DOC** = documentation (có thể outdated)

Test fail ≠ test sai. KHÔNG sửa test để pass khi BE sai → log bug theo template.

## 8. Test code generation contracts (áp dụng mọi consumer)

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

## 9. Onboarding một consumer mới

1. Install plugin: `/plugin install bmad-harness-plugin@<marketplace>` HOẶC clone repo + thêm vào `enabledPlugins` trong `~/.claude/settings.json`
2. Tạo `_bmad/bmm/config.yaml` ở consumer repo: `project_name`, `user_name`, `communication_language`, `output_folder`
3. Tạo docs riêng cho consumer (`docs/PROJECT-STRUCTURE.md`, `docs/roadmap/`). Kiến trúc generic đã có sẵn ở `skills/qa-engineer/architecture.md`.
4. (Optional) Tạo `.mcp.json` ở consumer root nếu cần MCP — auto-approve qua `enableAllProjectMcpServers: true`
5. Verify hooks fire: chạy `claude` → kiểm `.claude/session-logs/` có entry mới
6. Smoke test: `/bmad:bmm:agents:dev` → verify activation ≤ 250 tokens

## 10. Output discipline (cost control — áp dụng mọi session)

Observed: trace 89fee3f7 waste ~$0.90 (12K tokens) cho narrate "thinking out loud".

**HARD RULES:**
- Status message giữa actions: ≤ 50 tokens, KHÔNG recap đã làm gì
- Action TRƯỚC, explain SAU (chỉ khi user hỏi)
- Final summary: 1-2 sentences + file list, KHÔNG re-explain strategy
- KHÔNG repeat hook context đã có trong additionalContext
- Read dedup: file đã đọc → dùng Grep với pattern thay vì Read full

## 11. Config & language (per-consumer)

- `_bmad/bmm/config.yaml` — `user_name`, `communication_language`, `output_folder`
- Settings layers:
  - `~/.claude/settings.json` — user-global (deniedMcpServers, plugins)
  - `.claude/settings.json` — project (hooks, plugins, MCP scope)
  - `.claude/settings.local.json` — local overrides (gitignored)

## 12. MCP policy (default)

- `enableAllProjectMcpServers: true` — `.mcp.json` ở consumer root auto-approve
- 10 claude.ai remote MCPs (Drive, Miro, Context7, Vercel, Supabase, Calendar, Gmail, ClickUp, Gamma, Figma) block sẵn qua `deniedMcpServers` (serverUrl wildcards)
- Plugin `playwright@claude-plugins-official` toggle qua `enabledPlugins`

## 13. Critical guardrails

- Repo này shape **BEHAVIOR của Claude**, không phải runtime code → edit hooks/agents/docs cẩn thận, pipe-test trước khi commit
- Hook fail silent = settings.json malformed → validate JSON sau mọi edit
- BMAD agent activation phải theo template — vi phạm bị `enforce-bmad-output-consistency.sh` flag
- Output project (consumer Playwright suite) là **target**, không tạo `src/`, `tests/`, `package.json` ở repo này
- Khi update standards trong `skills/qa-test-case/` → version bump + ghi changelog, vì consumers downstream phụ thuộc
