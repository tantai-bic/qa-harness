# CLAUDE.md — qa-harness (Plugin Marketplace for Playwright QA)

> Context bắt buộc đọc cho mọi session làm việc trên repo này.

## 1. Repo identity

- **Tên:** `qa-harness` — **Claude Code plugin marketplace** chứa 6 plugin độc lập, mỗi plugin shape 1 mảng behavior của Claude cho project Playwright + TypeScript.
- **Mục đích:** đóng khung Claude vào quy trình QA-driven chuẩn hoá → consumer chọn enable từng plugin tuỳ nhu cầu (toàn bộ harness, hoặc chỉ subset).
- **Cơ chế:** hooks (runtime gates) + BMAD agents/skills (workflow + standards) — tất cả **project-agnostic**, phân thành 6 plugin để compose linh hoạt.
- **Consumer là project Playwright bất kỳ** — không tied to project nào. Ví dụ minh hoạ trong `plugins/bmad-workflows/docs/` (roadmap/PROJECT-STRUCTURE) chỉ là tham khảo.

## 2. Marketplace structure (Claude Code Plugin spec)

```
qa-harness/                          (= repo này, packaged as marketplace)
├── .claude-plugin/
│   └── marketplace.json             Marketplace index (BẮT BUỘC) — list 6 plugins
├── plugins/                         6 plugin con, mỗi cái self-contained
│   ├── bmad-workflows/              BMAD agents + skills + commands + _bmad + runtime guards (3 hooks)
│   ├── test-enforcement/            Pre-write quality gates (5 hooks)
│   ├── cost-control/                Read dedup (1 hook)
│   └── playwright-qa-engineer/      All-in-one Playwright QA: setup (1 hook) + roadmap/orchestrate/preload (3 hooks) + 3 skill docs
├── .mcp.json                        MCP servers (rỗng — consumer override)
└── README.md
```

**Structure mỗi plugin:**
```
plugins/<name>/
├── .claude-plugin/plugin.json       Plugin manifest riêng
├── hooks/
│   ├── hooks.json                   Hook event registration
│   ├── <script>.sh                  Hook scripts
│   └── _hook-span-emit.sh           Shared helper (copy vào mỗi plugin có hook → self-contained)
├── commands/  skills/  agents/      (bmad-workflows only)
└── README.md (TODO per plugin)
```

**Cách install (consumer):**
```json
// ~/.claude/settings.json
{
  "enabledPlugins": {
    "bmad-workflows@qa-harness": true,
    "test-enforcement@qa-harness": true,
    "playwright-qa-engineer@qa-harness": true,
    "cost-control@qa-harness": true
  }
}
```
Enable selective: pick chỉ những plugin cần. `bmad-workflows` chứa cả BMAD knowledge + runtime guards — nên enable đầu tiên. Hook plugins khác (playwright-qa-engineer, test-enforcement, ...) opt-in tuỳ workflow.

## 3. Plugin map (Layer × Plugin)

```
┌────────────────────────────────────────────────────────────────────────┐
│  Layer 1: RUNTIME GATES (hooks)                                        │
│    test-enforcement   — PreToolUse Write|Edit + PostToolUse async      │
│    cost-control       — PreToolUse Read                                │
│    playwright-qa-engineer — SessionStart startup                       │
│                           + UserPromptSubmit(×3: roadmap/orchestrate/preload) │
│    bmad-workflows     — UserPromptSubmit + PreToolUse Write|Edit       │
│                         (BMAD guards bundled with workflows)           │
├────────────────────────────────────────────────────────────────────────┤
│  Layer 2: WORKFLOW (BMAD agents)                                       │
│    bmad-workflows     — dev, sm, architect, pm, tea, ux-designer, ... │
├────────────────────────────────────────────────────────────────────────┤
│  Layer 3: STANDARDS (skills + docs)                                    │
│    bmad-workflows     — qa-engineer, qa-test-case, test-quality-checklist │
└────────────────────────────────────────────────────────────────────────┘
        ↓ outputs
   Bất kỳ Playwright + TS project nào của consumer
```

## 4. Hooks — map mỗi script → plugin chủ

| Plugin | Hook script | Event | Vai trò |
|--------|-------------|-------|---------|
| `playwright-qa-engineer` | `check-playwright-setup.sh` | SessionStart (startup) | Validate Playwright project structure + toolchain (playwright.config, @playwright/test, tests/, lint-staged, eslint, prettier). Tự skip trên plugin source. Bypass: `SKIP_PLAYWRIGHT_SETUP=1` |
| `bmad-workflows` | `enforce-bmad-config-priority.sh` | UserPromptSubmit | Ép đọc `_bmad/*` ưu tiên consumer (`./_bmad/`) > plugin (`${CLAUDE_PLUGIN_ROOT}/_bmad/`). Bypass: `SKIP_BMAD_PRIORITY=1` |
| `bmad-workflows` | `enforce-bmad-output-consistency.sh` | UserPromptSubmit | Gate BMAD agent activation ≤ 250 tokens |
| `bmad-workflows` | `enforce-bmad-agent-scope.sh` | PreToolUse Write\|Edit | Block khi BMAD agent active làm SAI ROLE (pm/sm/architect/ux-designer/tech-writer không edit code; dev không edit PRD/architecture; tea chỉ test code + test-design). Bypass: `SKIP_BMAD_SCOPE=1` |
| `playwright-qa-engineer` | `enforce-roadmap-reading.sh` | UserPromptSubmit | Ép đọc roadmap doc (nếu consumer có) trước khi code. Bypass: `SKIP_ROADMAP_READING=1` |
| `playwright-qa-engineer` | `orchestrate-test-automation.sh` | UserPromptSubmit | 2-mode: LOGIC (viết test) → full QA checklist; TEXT-ONLY → giữ tags + import structure. Bypass: `SKIP_TEST_ORCHESTRATION=1` |
| `playwright-qa-engineer` | `preload-playwright-context.sh` | UserPromptSubmit | Preload 3 local skill docs (playwright-setup/test-organization/qa-workflow) 1×/session. Bypass: `SKIP_PLAYWRIGHT_PRELOAD=1` |
| `test-enforcement` | `enforce-fixture-helper-prerequisite.sh` | PreToolUse Write\|Edit | Block viết spec nếu import service/factory/fixture/helper CHƯA tồn tại. Bypass: `SKIP_FIXTURE_PREREQ=1` |
| `test-enforcement` | `enforce-spec-tags.sh` | PreToolUse Write\|Edit | Block spec thiếu/sai tag CICD (PRIORITY @P0-P3, LAYER @BE/@FE, TYPE ≥1 @Smoke/@Sanity/...). Bypass: `SKIP_SPEC_TAGS=1` |
| `test-enforcement` | `enforce-security-test-presence.sh` | PreToolUse Write\|Edit | Warn (không block) khi spec test user-input thiếu security coverage. Bypass: `SKIP_SECURITY_REMINDER=1` |
| `test-enforcement` | `enforce-test-quality-checklist.sh` | PreToolUse Write\|Edit | Block test code vi phạm 9 rules |
| `test-enforcement` | `run-test-mark-fixme.sh` | PostToolUse Write\|Edit (async) | Sau Write/Edit `tests/**/*.spec.ts` → chạy `npx playwright test <file>` → mark fail tests `test.fixme()`. Timeout 120s. Bypass: `SKIP_RUN_TEST=1` |
| `cost-control` | `enforce-read-dedup.sh` | PreToolUse Read | Block đọc trùng file. v2 compact-aware. Escape valve: nếu Edit/Write báo "File has not been read" → auto-allow. Bypass: `SKIP_READ_DEDUP=1` |

**Bypass cấp:**
- **Plugin level:** disable cả plugin qua `enabledPlugins`
- **Hook level:** `SKIP_<HOOK_NAME>=1`
- **Master:** `SKIP_HOOKS=1`

## 5. BMAD Agents (`bmad-workflows` plugin)

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

**Activation contract** (enforce-bmad-output-consistency — `bmad-workflows` plugin):
- Output ≤ 250 tokens, KHÔNG dump session vars, KHÔNG flourish/emoji thừa
- Menu items giữ exact wording từ `<menu>` agent YAML — KHÔNG translate
- Greeting: `{icon} Xin chào **{user_name}**! Tôi là **{agent}** — {role}.`
- STOP sau menu, WAIT user input — KHÔNG auto-execute

## 6. Standards (`bmad-workflows/skills/`)

| File | Vai trò | Project-specific? |
|------|---------|-------------------|
| `skills/test-quality-checklist/SKILL.md` | 9 rules + 41 items — quality contract | ❌ Generic |
| `skills/qa-test-case/SKILL.md` | Test design entry point | ❌ Generic |
| `skills/qa-test-case/common/{happy,bad,edge}-case.md` | Case taxonomy | ❌ Generic |
| `skills/qa-test-case/common/{equivalence-partition,boundary-value,decision-table,state-transition}.md` | Test design techniques | ❌ Generic |
| `skills/qa-test-case/{backend,frontend}/*.md` | API vs E2E patterns | ❌ Generic |
| `skills/qa-engineer/SKILL.md` + 6 bundled (architecture, patterns-api, patterns-e2e, helpers, module-creation, conventions) | Full-stack code patterns | ❌ Generic |
| `docs/templates/log-bug-api-template.md` | Bug log template | ❌ Generic |
| `docs/PROJECT-STRUCTURE.md` | **Example** cho 1 consumer | ✅ Tham khảo |
| `docs/roadmap/**` | **Example** state machine của 1 consumer | ✅ Tham khảo |

Tất cả paths trên relative tới `plugins/bmad-workflows/`. Consumer adapt: thay Example files bằng docs của mình, giữ Generic.

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
- **Execute-before-complete (Rule #10):** sau khi Write/Edit `*.spec.*`, PHẢI chạy framework test (detect từ `package.json`: `@playwright/test` → `npx playwright test <file>`, `jest` → `npx jest`, `vitest` → `npx vitest run`) **trước khi báo task hoàn thành**. Hook `run-test-mark-fixme.sh` auto-fire PostToolUse, Claude vẫn phải verify + summarize với evidence (`N pass / M fixme / K fail`).

## 9. Onboarding một consumer mới

1. Install marketplace + chọn plugins enable trong `~/.claude/settings.json`:
   ```json
   {
     "enabledPlugins": {
       "bmad-workflows@qa-harness": true,
       "test-enforcement@qa-harness": true,
       "playwright-qa-engineer@qa-harness": true
     }
   }
   ```
   (Thêm `cost-control` tuỳ nhu cầu.)
2. Tạo `_bmad/bmm/config.yaml` ở consumer repo: `project_name`, `user_name`, `communication_language`, `output_folder`
3. Tạo docs riêng cho consumer (`docs/PROJECT-STRUCTURE.md`, `docs/roadmap/`). Kiến trúc generic đã có sẵn trong `bmad-workflows/skills/qa-engineer/architecture.md`.
4. (Optional) Tạo `.mcp.json` ở consumer root nếu cần MCP — auto-approve qua `enableAllProjectMcpServers: true`
5. Verify hooks fire: `claude --debug hooks`
6. Smoke test: `/bmad:bmm:agents:dev` → verify activation ≤ 250 tokens

## 10. Output discipline (cost control — áp dụng mọi session)

Observed: trace 89fee3f7 waste ~$0.90 (12K tokens) cho narrate "thinking out loud".

**HARD RULES:**
- Status message giữa actions: ≤ 50 tokens, KHÔNG recap đã làm gì
- Action TRƯỚC, explain SAU (chỉ khi user hỏi)
- Final summary: 1-2 sentences + file list, KHÔNG re-explain strategy
- KHÔNG repeat hook context đã có trong additionalContext
- **Pre-Read context scan (CRITICAL — hook block prevention):** TRƯỚC mỗi Read call, mental-scan tool_result trước đó.
  - ✅ Đã Read/Write/Edit trong session → nội dung VẪN trong context. Cần phần cụ thể → **Grep targeted**, KHÔNG Read full.
  - ✅ Chưa từng touch HOẶC đã Read xong rồi Write/Edit overwrite sau đó → Read OK (context outdated).
  - ❌ Re-Read file đã đọc chưa modify → bị `enforce-read-dedup.sh` (cost-control plugin) block.
  - Mental check 3 câu trước Read: (1) Đã xuất hiện trong tool_result? (2) Sau đó có Edit/Write? (3) Cần FULL content hay vài dòng (→ Grep)?
  - Edge cases: sau compact → hook v2 reset counter. Edit báo "File has not been read" → hook auto-allow. File đổi external → `SKIP_READ_DEDUP=1`.
- **Parallel tool calls (CRITICAL — cost driver):** mọi Bash/Read/Grep/Glob/Edit **độc lập** PHẢI gom vào 1 message. Observed: 23 sequential calls = $15.68/turn, gom 5 parallel batches = **-60% cost**.
  - ✅ Độc lập = không phụ thuộc output call trước (đọc 5 file khác, grep 3 pattern, `git status` + `diff` + `log`)
  - ❌ Tuần tự = call B cần output A (`git rev-parse HEAD` → `git diff <SHA>`)
  - Quy tắc: trước mỗi tool call, hỏi "cần output call trước không?" — KHÔNG → gom chung message

## 11. Config & language (per-consumer)

- `_bmad/bmm/config.yaml` — `user_name`, `communication_language`, `output_folder` (consumer side, hoặc `plugins/bmad-workflows/_bmad/bmm/config.yaml` cho plugin default)
- Settings layers:
  - `~/.claude/settings.json` — user-global (deniedMcpServers, plugins)
  - `.claude/settings.json` — project (hooks, plugins, MCP scope)
  - `.claude/settings.local.json` — local overrides (gitignored)

## 12. MCP policy (default)

- `enableAllProjectMcpServers: true` — `.mcp.json` ở consumer root auto-approve
- 10 claude.ai remote MCPs (Drive, Miro, Context7, Vercel, Supabase, Calendar, Gmail, ClickUp, Gamma, Figma) block sẵn qua `deniedMcpServers` (serverUrl wildcards)
- Plugin `playwright@claude-plugins-official` toggle qua `enabledPlugins`

## 13. Critical guardrails

- Repo này shape **BEHAVIOR của Claude**, không phải runtime code → edit hooks/agents/skills cẩn thận, pipe-test trước khi commit
- Hook fail silent = settings.json/hooks.json malformed → validate JSON sau mọi edit
- BMAD agent activation phải theo template — vi phạm bị `enforce-bmad-output-consistency.sh` flag
- Output project (consumer Playwright suite) là **target**, KHÔNG tạo `src/`, `tests/`, `package.json` ở repo này
- Khi update standards trong `plugins/bmad-workflows/skills/qa-test-case/` → version bump + ghi changelog, vì consumers downstream phụ thuộc
- **`_hook-span-emit.sh`:** mỗi plugin có hook đều có copy riêng — pattern identical
- Plugin `observability` (session lifecycle + Langfuse telemetry, tạo `.claude/session-logs/` + cost-tracking files) đã bị **remove khỏi marketplace** — KHÔNG tái tạo hooks này trừ khi được yêu cầu lại
