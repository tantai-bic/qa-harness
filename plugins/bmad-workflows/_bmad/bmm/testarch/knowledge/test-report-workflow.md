# Test Report Workflow

## Rules

### PLAYWRIGHT_HTML_OPEN
- **ALWAYS** set `PLAYWRIGHT_HTML_OPEN=never` when running tests
- Never let the HTML report auto-open in browser — it blocks the terminal

### Output Directory

**Primary:** Reports are saved to **Google Drive** (if `G:/My Drive/` exists):
```
G:/My Drive/Playwright Report/{ENV_LABEL}/[Epic-{id}] {Epic Name}/{BE|FE}/{YYYYMMDD}/{user-story}/
  ├── playwright-report-{YYYY-MM-DD}-{layer}-{user-story}/
  └── test-report-{YYYY-MM-DD}-{layer}-{user-story}.md
```

**Fallback:** If Google Drive is not available (`G:/My Drive/` does not exist), save to local project:
```
.local/reports/{ENV_LABEL}/[Epic-{id}] {Epic Name}/{BE|FE}/{YYYYMMDD}/{user-story}/
  ├── playwright-report-{YYYY-MM-DD}-{layer}-{user-story}/
  └── test-report-{YYYY-MM-DD}-{layer}-{user-story}.md
```

**Detection:** Before running, check if `G:/My Drive/` directory exists. If yes → use Google Drive path. If no → use `.local/reports/` path.

### Two Report Modes

#### Mode 1: "Create report" (run tests first)
When user says "create report" (without mentioning "from playwright-report"):
1. **Run tests** with trace on, PLAYWRIGHT_HTML_OPEN=never, and PLAYWRIGHT_HTML_OUTPUT_DIR to save HTML report directly to target dir:
   ```bash
   # Google Drive (primary)
   PLAYWRIGHT_HTML_OPEN=never PLAYWRIGHT_HTML_OUTPUT_DIR="G:/My Drive/Playwright Report/{ENV_LABEL}/[Epic-{id}] {Epic Name}/{BE|FE}/{YYYYMMDD}/{user-story}/playwright-report-{YYYY-MM-DD}-{layer}-{user-story}" npx playwright test {test-path} --project={project} --trace on --reporter=list,html

   # Local fallback (if no Google Drive)
   PLAYWRIGHT_HTML_OPEN=never PLAYWRIGHT_HTML_OUTPUT_DIR=".local/reports/{ENV_LABEL}/[Epic-{id}] {Epic Name}/{BE|FE}/{YYYYMMDD}/{user-story}/playwright-report-{YYYY-MM-DD}-{layer}-{user-story}" npx playwright test {test-path} --project={project} --trace on --reporter=list,html
   ```
   - No need to copy `playwright-report/` — PLAYWRIGHT_HTML_OUTPUT_DIR writes directly to the target
2. **Generate markdown report** from results using template at `docs/templates/test-report-template.md`
3. **Save report** at the same story dir as `test-report-{YYYY-MM-DD}-{layer}-{user-story}.md`

#### Mode 2: "Create from playwright-report" (copy existing results)
When user says "create report from playwright-report" or "create from playwright-report":
1. **Copy** the current `playwright-report/` contents to target dir (Google Drive or `.local/reports/` fallback)
2. **Generate markdown report** from the test output/results
3. **Save report** at the same story dir

### Naming Convention
- `{ENV_LABEL}` = mapped from TEST_ENV in `.env`: `stg` → `STAGING`, `rel` → `PREVIEW`, `prod` → `PRODUCTION`
- `{BE|FE}` = `BE` for API tests (`tests/api/`), `FE` for E2E tests (`tests/e2e/`)
- `{YYYYMMDD}` = date directory (e.g., `20260325`)
- `{user-story}` = kebab-case story name (e.g., `story-04.7.1-backer-question-submission`)
- `{Epic Name}` = human-readable epic name (e.g., `Campaign Q&A`)
- `{layer}` in file names = `api` or `e2e`
- File names use `{YYYY-MM-DD}` format (e.g., `2026-03-25`), directory uses `{YYYYMMDD}`

### Multi-Story Split Rule
When the test path contains **multiple user stories** (e.g., `tests/e2e/campaign-qa/` has `story-04.7.1-*`, `story-04.7.3-*`, etc.):
1. **Split** test runs by user story — run each story folder separately
2. Each story gets its **own report** under the same `{YYYYMMDD}/` directory
3. Run sequentially: finish one story → generate report → next story
4. If user explicitly says "run all together" or specifies a single path, skip splitting

### Report Format
Always use Vietnamese markdown structure with 7 mandatory sections:
1. **Header**: `# BÁO CÁO KẾT QUẢ KIỂM THỬ — {Feature} ({Type})`
2. **TỔNG QUAN**: Summary metrics table (Tổng test cases, Passed, Failed, Flaky, Skipped, Errors, Pass Rate)
3. **CHI TIẾT THEO TEST SUITE**: Per-suite breakdown with per-test tables
4. **PHÂN BỐ THEO PRIORITY**: P0/P1/P2/P3 breakdown
5. **PHÂN BỐ THEO PROVIDER**: Matrix by provider/category (adjust columns per feature)
6. **CẢNH BÁO & KHUYẾN NGHỊ**: Flakiness alerts, performance notes, technical observations
7. **KẾT LUẬN**: 2-3 sentence summary

Full template file: `docs/templates/test-report-template.md`
