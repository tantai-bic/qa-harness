#!/usr/bin/env node
/**
 * Langfuse integration helper.
 *
 * Modes:
 *   require('./langfuse-helper.js')                         → library (exports enqueueTrace / enqueueSpan / flushSync)
 *   node langfuse-helper.js trace <sessionId> < json        → enqueue trace-create
 *   node langfuse-helper.js span  <sessionId> < json        → enqueue span-create
 *   node langfuse-helper.js flush <sessionId>               → POST queued events, truncate on success
 *   node langfuse-helper.js configured                      → exit 0 nếu LANGFUSE_PUBLIC_KEY + SECRET_KEY set, else 1
 *
 * Env:
 *   LANGFUSE_PUBLIC_KEY   (required to enable push)
 *   LANGFUSE_SECRET_KEY   (required)
 *   LANGFUSE_HOST         (default https://cloud.langfuse.com)
 *   LANGFUSE_DEBUG=1      (print flush result to stderr)
 *
 * Queue layout:
 *   .claude/hooks/.langfuse-queue/<safeSessionId>.jsonl     (JSONL — 1 event per line)
 *
 * Truncate-on-success: nếu POST fail, queue file giữ nguyên → flush sau retry.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');
const crypto = require('crypto');
const { spawn } = require('child_process');

const PROJECT_ROOT = process.cwd();
const QUEUE_DIR = path.join(PROJECT_ROOT, '.claude', 'hooks', '.langfuse-queue');

// Load .env from project root — .env ưu tiên cao hơn process.env,
// nhưng nếu .env thiếu key hoặc value rỗng thì fallback về process.env.
(function loadDotEnv() {
    const envFile = path.join(PROJECT_ROOT, '.env');
    try {
        const raw = fs.readFileSync(envFile, 'utf-8');
        for (const line of raw.split(/\r?\n/)) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('#')) continue;
            const eqIdx = trimmed.indexOf('=');
            if (eqIdx < 1) continue;
            const key = trimmed.slice(0, eqIdx).trim();
            const val = trimmed.slice(eqIdx + 1).trim().replace(/^(['"])(.*)\1$/, '$2');
            if (!key) continue;
            // .env wins nếu có giá trị; nếu rỗng → giữ nguyên process.env (fallback)
            if (val) process.env[key] = val;
        }
    } catch (e) { /* .env không tồn tại hoặc không đọc được — bỏ qua */ }
})();

const PUBLIC_KEY = process.env.LANGFUSE_PUBLIC_KEY || '';
const SECRET_KEY = process.env.LANGFUSE_SECRET_KEY || '';
const HOST = (process.env.LANGFUSE_HOST || 'https://cloud.langfuse.com').replace(/\/+$/, '');
const DEBUG = process.env.LANGFUSE_DEBUG === '1';

const MAX_INPUT_BYTES = 10 * 1024;
const MAX_OUTPUT_BYTES = 20 * 1024;
const HTTP_TIMEOUT_MS = 10000;

// ─── Model pricing (USD per 1M tokens) ─────────────────────────────────────
// Anthropic Claude pricing — auto-compute costDetails khi enqueueGeneration
// được gọi với usageDetails + model.
//
// Keys MATCH với key trong usageDetails để Langfuse map đúng.
// Override hoặc thêm model mới qua env LANGFUSE_PRICING_JSON (object literal JSON).
const DEFAULT_PRICING = {
    // Opus 4.x
    'claude-opus-4-7':   { input: 15.00, output: 75.00, cache_read_input_tokens: 1.50,  cache_creation_input_tokens: 18.75 },
    'claude-opus-4-6':   { input: 15.00, output: 75.00, cache_read_input_tokens: 1.50,  cache_creation_input_tokens: 18.75 },
    // Sonnet 4.x
    'claude-sonnet-4-7': { input: 3.00,  output: 15.00, cache_read_input_tokens: 0.30,  cache_creation_input_tokens: 3.75  },
    'claude-sonnet-4-6': { input: 3.00,  output: 15.00, cache_read_input_tokens: 0.30,  cache_creation_input_tokens: 3.75  },
    'claude-sonnet-4-5': { input: 3.00,  output: 15.00, cache_read_input_tokens: 0.30,  cache_creation_input_tokens: 3.75  },
    // Haiku 4.x
    'claude-haiku-4-5':  { input: 1.00,  output: 5.00,  cache_read_input_tokens: 0.10,  cache_creation_input_tokens: 1.25  },
};

let MODEL_PRICING = DEFAULT_PRICING;
if (process.env.LANGFUSE_PRICING_JSON) {
    try {
        MODEL_PRICING = { ...DEFAULT_PRICING, ...JSON.parse(process.env.LANGFUSE_PRICING_JSON) };
    } catch (e) {
        if (DEBUG) console.error('[langfuse] LANGFUSE_PRICING_JSON parse failed:', e.message);
    }
}

function lookupPricing(model) {
    if (!model) return null;
    const m = String(model);
    if (MODEL_PRICING[m]) return MODEL_PRICING[m];
    // Prefix match (vd "claude-sonnet-4-6-20251001" → "claude-sonnet-4-6")
    for (const key of Object.keys(MODEL_PRICING)) {
        if (m.startsWith(key) || key.startsWith(m)) return MODEL_PRICING[key];
    }
    // Family fallback
    if (/opus/i.test(m)) return MODEL_PRICING['claude-opus-4-7'];
    if (/sonnet/i.test(m)) return MODEL_PRICING['claude-sonnet-4-6'];
    if (/haiku/i.test(m)) return MODEL_PRICING['claude-haiku-4-5'];
    return null;
}

function computeCostDetails(model, usageDetails) {
    const prices = lookupPricing(model);
    if (!prices || !usageDetails) return null;
    const costs = {};
    let total = 0;
    for (const [key, tokens] of Object.entries(usageDetails)) {
        if (typeof tokens !== 'number' || tokens <= 0) continue;
        const pricePerMillion = prices[key];
        if (typeof pricePerMillion !== 'number') continue;
        const cost = (tokens / 1_000_000) * pricePerMillion;
        costs[key] = Number(cost.toFixed(8));
        total += cost;
    }
    if (Object.keys(costs).length === 0) return null;
    costs.total = Number(total.toFixed(8));
    return costs;
}

function isConfigured() {
    // SKIP_LANGFUSE=1 → caller treats Langfuse as not configured → HTTP push
    // bị bypass (postBatch / flushSync / spawnBackgroundFlush all early-return)
    // nhưng enqueue + archiveLocally vẫn chạy → session log local KHÔNG bị ảnh hưởng.
    // Master SKIP_HOOKS=1 cũng kích hoạt cùng hành vi để consistent với các hook khác.
    if (process.env.SKIP_LANGFUSE === '1' || process.env.SKIP_HOOKS === '1') return false;
    return !!(PUBLIC_KEY && SECRET_KEY);
}

function safeSession(sid) {
    return String(sid || '').replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 64) || 'unknown';
}

function uuid() {
    if (crypto.randomUUID) return crypto.randomUUID();
    const b = crypto.randomBytes(16);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    const h = b.toString('hex');
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

function queueFile(sessionId) {
    fs.mkdirSync(QUEUE_DIR, { recursive: true });
    return path.join(QUEUE_DIR, safeSession(sessionId) + '.jsonl');
}

function truncatePayload(val, maxBytes) {
    if (val == null) return val;
    const s = typeof val === 'string' ? val : JSON.stringify(val);
    if (Buffer.byteLength(s, 'utf-8') <= maxBytes) return val;
    return s.slice(0, maxBytes) + `\n… [truncated, total ${Buffer.byteLength(s, 'utf-8')} bytes]`;
}

function enqueueEvent(sessionId, event) {
    // KHÔNG gate by isConfigured() — buffer events locally để khi user set env
    // sau và flush, không bị mất event. Trade-off: queue tích lũy nếu Langfuse
    // mãi không config — chấp nhận, kích thước nhỏ.
    try {
        const file = queueFile(sessionId);
        fs.appendFileSync(file, JSON.stringify(event) + '\n', 'utf-8');
    } catch (e) {
        if (DEBUG) console.error('[langfuse] enqueue failed:', e.message);
    }
    // Đồng thời archive vào session-logs để user xem offline (kể cả khi Langfuse configured).
    // Disable: LANGFUSE_LOCAL_ARCHIVE=0
    if (process.env.LANGFUSE_LOCAL_ARCHIVE !== '0') {
        archiveLocally(sessionId, event);
    }
}

/**
 * Lưu event vào archive local dưới .claude/session-logs/<sessionId>/_archive/
 * → user có thể inspect offline kể cả khi Langfuse chưa configured / POST fail.
 *
 * Layout:
 *   _archive/traces.jsonl
 *   _archive/generations.jsonl
 *   _archive/spans.jsonl
 *   _archive/scores.jsonl     ← user yêu cầu: session_score local fallback
 *   _archive/INDEX.md         ← human-readable summary (auto-updated)
 */
function archiveLocally(sessionId, event) {
    try {
        const safe = safeSession(sessionId);
        const archiveDir = path.join(PROJECT_ROOT, '.claude', 'session-logs', safe, '_archive');
        fs.mkdirSync(archiveDir, { recursive: true });

        // Map event type → archive file
        const typeToFile = {
            'trace-create':      'traces.jsonl',
            'span-create':       'spans.jsonl',
            'generation-create': 'generations.jsonl',
            'score-create':      'scores.jsonl',
        };
        const fileName = typeToFile[event.type];
        if (!fileName) return;

        const archiveFile = path.join(archiveDir, fileName);
        const line = JSON.stringify({
            archivedAt: new Date().toISOString(),
            sessionId,
            ...event,
        });
        fs.appendFileSync(archiveFile, line + '\n', 'utf-8');

        // Update human-readable INDEX.md
        updateArchiveIndex(archiveDir, event);
    } catch (e) {
        if (DEBUG) console.error('[langfuse] local archive failed:', e.message);
    }
}

function updateArchiveIndex(archiveDir, event) {
    try {
        const indexFile = path.join(archiveDir, 'INDEX.md');
        const body = event.body || {};
        const now = new Date().toISOString();

        let line = '';
        switch (event.type) {
            case 'trace-create':
                line = `- 🧵 **trace** \`${body.id}\` "${body.name || ''}" @ ${now}`;
                break;
            case 'span-create':
                line = `  - 🔧 span \`${body.name}\` (trace=\`${body.traceId}\`) @ ${now}`;
                break;
            case 'generation-create': {
                const usage = body.usageDetails || {};
                const cost = body.costDetails || {};
                const tokens = `in=${usage.input || 0} out=${usage.output || 0}` +
                    (usage.cache_read_input_tokens ? ` cache_read=${usage.cache_read_input_tokens}` : '') +
                    (usage.cache_creation_input_tokens ? ` cache_write=${usage.cache_creation_input_tokens}` : '');
                const usd = cost.total != null ? ` | $${cost.total.toFixed(6)}` : '';
                line = `  - 🤖 gen \`${body.model || '?'}\` (trace=\`${body.traceId}\`) — ${tokens}${usd} @ ${now}`;
                break;
            }
            case 'score-create':
                line = `- 📊 **score** \`${body.name}\` = ${JSON.stringify(body.value)} (${body.dataType}) on trace \`${body.traceId}\` @ ${now}` +
                    (body.comment ? `\n      └─ ${body.comment.slice(0, 120)}${body.comment.length > 120 ? '…' : ''}` : '');
                break;
            default:
                return;
        }

        // First-time header
        if (!fs.existsSync(indexFile)) {
            const header = [
                '# Langfuse Local Archive — Session Events',
                '',
                'Tự ghi mỗi event (trace / span / generation / score) trước khi push sang Langfuse.',
                'Dùng cho offline review hoặc khi Langfuse chưa configured.',
                '',
                'Disable: `LANGFUSE_LOCAL_ARCHIVE=0`',
                '',
                '---',
                '',
            ].join('\n');
            fs.writeFileSync(indexFile, header, 'utf-8');
        }
        fs.appendFileSync(indexFile, line + '\n', 'utf-8');
    } catch (e) {
        if (DEBUG) console.error('[langfuse] index update failed:', e.message);
    }
}

function enqueueTrace(sessionId, { traceId, name, input, metadata, tags }) {
    enqueueEvent(sessionId, {
        id: uuid(),
        type: 'trace-create',
        timestamp: new Date().toISOString(),
        body: {
            id: traceId,
            sessionId: String(sessionId),
            name: name || 'Prompt',
            input: truncatePayload(input, MAX_INPUT_BYTES),
            metadata: metadata || {},
            tags: Array.isArray(tags) && tags.length ? tags : undefined,
            timestamp: new Date().toISOString(),
        },
    });
}

function enqueueSpan(sessionId, { traceId, spanId, name, input, output, startTime, endTime, metadata }) {
    enqueueEvent(sessionId, {
        id: uuid(),
        type: 'span-create',
        timestamp: new Date().toISOString(),
        body: {
            id: spanId || uuid(),
            traceId: traceId,
            name: name || 'tool',
            input: truncatePayload(input, MAX_INPUT_BYTES),
            output: truncatePayload(output, MAX_OUTPUT_BYTES),
            startTime: startTime || new Date().toISOString(),
            endTime: endTime || new Date().toISOString(),
            metadata: metadata || {},
        },
    });
}

/**
 * Enqueue Langfuse generation-create event. Use cho LLM calls — Langfuse sẽ
 * auto-tính cost USD nếu `model` match price table của Langfuse.
 *
 * @param {string} sessionId
 * @param {object} params
 * @param {string} params.traceId
 * @param {string} [params.generationId]
 * @param {string} [params.name="claude-chat"]
 * @param {string} params.model                 - vd "claude-sonnet-4-6"
 * @param {any}    [params.input]
 * @param {any}    [params.output]
 * @param {object} [params.usage]               - {input, output, total, cache_read_input_tokens, cache_creation_input_tokens}
 * @param {string} [params.startTime]
 * @param {string} [params.endTime]
 * @param {object} [params.metadata]
 */
/**
 * Enqueue Langfuse score-create event. Numeric scores (0–1, hoặc bất kỳ scale).
 * dataType auto-detect: number → NUMERIC, "true"/"false" → BOOLEAN, else CATEGORICAL.
 *
 * @param {string} sessionId
 * @param {object} params
 * @param {string} params.traceId             - bắt buộc — trace ID cần đánh giá
 * @param {string} [params.scoreId]           - optional UUID (idempotent if cùng id)
 * @param {string} params.name                - vd "user-satisfaction"
 * @param {number|string|boolean} params.value
 * @param {string} [params.comment]
 * @param {string} [params.dataType]          - "NUMERIC" | "BOOLEAN" | "CATEGORICAL"
 * @param {string} [params.observationId]     - optional — score 1 observation cụ thể trong trace
 */
function enqueueScore(sessionId, { traceId, scoreId, name, value, comment, dataType, observationId }) {
    if (!traceId || !name || value === undefined || value === null) {
        throw new Error('enqueueScore requires traceId, name, value');
    }
    let dt = dataType;
    if (!dt) {
        if (typeof value === 'number') dt = 'NUMERIC';
        else if (typeof value === 'boolean') dt = 'BOOLEAN';
        else dt = 'CATEGORICAL';
    }
    enqueueEvent(sessionId, {
        id: uuid(),
        type: 'score-create',
        timestamp: new Date().toISOString(),
        body: {
            id: scoreId || uuid(),
            traceId: traceId,
            observationId: observationId || undefined,
            name: name,
            value: value,
            comment: comment || undefined,
            dataType: dt,
        },
    });
}

function enqueueGeneration(
    sessionId,
    { traceId, generationId, name, model, input, output, usageDetails, costDetails, usage, startTime, endTime, metadata }
) {
    // Backward-compat: accept old `usage` shape, normalize sang usageDetails (v3 internal)
    let ud = usageDetails;
    if (!ud && usage) {
        ud = {
            input: usage.input || 0,
            output: usage.output || 0,
        };
        if (usage.cache_read_input_tokens) ud.cache_read_input_tokens = usage.cache_read_input_tokens;
        if (usage.cache_creation_input_tokens) ud.cache_creation_input_tokens = usage.cache_creation_input_tokens;
    }

    // Auto-compute costDetails từ model + usageDetails nếu user không truyền
    let cd = costDetails;
    if (!cd && ud && model) {
        cd = computeCostDetails(model, ud);
    }

    // Langfuse self-hosted v2.x (vd 2.95.11) KHÔNG support v3 `usageDetails`/`costDetails` —
    // sẽ silently drop → token/cost stored 0. Cần emit v2 `usage` object thay vào đó.
    //
    // Strategy: emit BOTH (v2 primary + v3 in metadata for future migration).
    // - v2 `usage.input/output` = input mới + output (non-cached counts)
    // - v2 `usage.total` = sum tất cả (input + output + cache_read + cache_creation)
    // - v2 `usage.unit` = "TOKENS"
    // - v2 `usage.inputCost`  = cd.input + cd.cache_read_input_tokens + cd.cache_creation_input_tokens
    // - v2 `usage.outputCost` = cd.output
    // - v2 `usage.totalCost`  = cd.total
    // - Cache breakdown chi tiết → đẩy vào metadata để không mất thông tin.
    let v2Usage;
    if (ud) {
        const inToken     = Number(ud.input || 0);
        const outToken    = Number(ud.output || 0);
        const cacheRead   = Number(ud.cache_read_input_tokens || 0);
        const cacheCreate = Number(ud.cache_creation_input_tokens || 0);
        v2Usage = {
            input: inToken + cacheRead + cacheCreate,  // gộp để hiển thị tổng input tokens
            output: outToken,
            total: inToken + outToken + cacheRead + cacheCreate,
            unit: 'TOKENS',
        };
        if (cd) {
            const inCost   = Number(cd.input || 0)
                           + Number(cd.cache_read_input_tokens || 0)
                           + Number(cd.cache_creation_input_tokens || 0);
            const outCost  = Number(cd.output || 0);
            const totCost  = Number(cd.total || (inCost + outCost));
            if (inCost  > 0) v2Usage.inputCost  = Number(inCost.toFixed(8));
            if (outCost > 0) v2Usage.outputCost = Number(outCost.toFixed(8));
            if (totCost > 0) v2Usage.totalCost  = Number(totCost.toFixed(8));
        }
    }

    // Merge cache breakdown + v3 raw payload vào metadata để future migration / debug
    const mergedMetadata = { ...(metadata || {}) };
    if (ud) mergedMetadata._usageDetails = ud;
    if (cd) mergedMetadata._costDetails  = cd;

    enqueueEvent(sessionId, {
        id: uuid(),
        type: 'generation-create',
        timestamp: new Date().toISOString(),
        body: {
            id: generationId || uuid(),
            traceId: traceId,
            name: name || 'claude-chat',
            model: model || undefined,
            input: truncatePayload(input, MAX_INPUT_BYTES),
            output: truncatePayload(output, MAX_OUTPUT_BYTES),
            usage: v2Usage || undefined,           // ← v2 schema (primary, server hiểu)
            usageDetails: ud || undefined,         // ← v3 (forward-compat, server v2 ignore)
            costDetails: cd || undefined,          // ← v3 (forward-compat, server v2 ignore)
            startTime: startTime || new Date().toISOString(),
            endTime: endTime || new Date().toISOString(),
            metadata: mergedMetadata,
        },
    });
}

function postBatch(events, cb) {
    if (!isConfigured() || !events.length) return cb(null, { sent: 0 });

    const u = new URL(HOST + '/api/public/ingestion');
    const lib = u.protocol === 'http:' ? http : https;
    const payload = JSON.stringify({ batch: events });
    const auth = Buffer.from(PUBLIC_KEY + ':' + SECRET_KEY).toString('base64');

    const req = lib.request(
        {
            hostname: u.hostname,
            port: u.port || (u.protocol === 'http:' ? 80 : 443),
            path: u.pathname + u.search,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: 'Basic ' + auth,
                'Content-Length': Buffer.byteLength(payload),
            },
        },
        (res) => {
            let body = '';
            res.on('data', (c) => (body += c));
            res.on('end', () => {
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    cb(null, { sent: events.length, status: res.statusCode });
                } else {
                    cb(new Error(`HTTP ${res.statusCode}: ${body.slice(0, 300)}`));
                }
            });
        }
    );
    req.on('error', cb);
    req.setTimeout(HTTP_TIMEOUT_MS, () => req.destroy(new Error('timeout')));
    req.write(payload);
    req.end();
}

function flushSync(sessionId, cb) {
    cb = cb || (() => {});
    if (!isConfigured()) return cb(null, { skipped: 'not-configured' });

    const file = queueFile(sessionId);
    if (!fs.existsSync(file)) return cb(null, { sent: 0 });

    const lines = fs.readFileSync(file, 'utf-8').split('\n').filter((l) => l.trim());
    if (!lines.length) {
        try { fs.unlinkSync(file); } catch (e) {}
        return cb(null, { sent: 0 });
    }

    const events = [];
    for (const l of lines) {
        try { events.push(JSON.parse(l)); } catch (e) {}
    }

    postBatch(events, (err, result) => {
        if (!err) {
            try { fs.unlinkSync(file); } catch (e) {}
            if (DEBUG) console.error(`[langfuse] flushed ${events.length} events for ${safeSession(sessionId)}`);
            cb(null, result);
        } else {
            if (DEBUG) console.error(`[langfuse] flush failed (${safeSession(sessionId)}): ${err.message} — will retry next flush`);
            cb(err);
        }
    });
}

function spawnBackgroundFlush(sessionId) {
    if (!isConfigured()) return;
    try {
        const child = spawn(process.execPath, [__filename, 'flush', String(sessionId)], {
            cwd: PROJECT_ROOT,
            detached: true,
            stdio: 'ignore',
            env: process.env,
        });
        child.unref();
    } catch (e) {
        if (DEBUG) console.error('[langfuse] background flush spawn failed:', e.message);
    }
}

module.exports = {
    isConfigured,
    safeSession,
    uuid,
    enqueueTrace,
    enqueueSpan,
    enqueueGeneration,
    enqueueScore,
    flushSync,
    spawnBackgroundFlush,
    lookupPricing,
    computeCostDetails,
    archiveLocally,
};

// ─── CLI dispatch ──────────────────────────────────────────────────────────
if (require.main === module) {
    const sub = process.argv[2] || '';
    const sessionId = process.argv[3] || '';

    function readStdinJSON() {
        try { return JSON.parse(fs.readFileSync(0, 'utf-8')); } catch (e) { return null; }
    }

    switch (sub) {
        case 'configured':
            process.exit(isConfigured() ? 0 : 1);
        case 'trace': {
            const d = readStdinJSON();
            if (d) enqueueTrace(sessionId, d);
            break;
        }
        case 'span': {
            const d = readStdinJSON();
            if (d) enqueueSpan(sessionId, d);
            break;
        }
        case 'generation': {
            const d = readStdinJSON();
            if (d) enqueueGeneration(sessionId, d);
            break;
        }
        case 'score': {
            const d = readStdinJSON();
            if (!d) process.exit(0);
            try { enqueueScore(sessionId, d); }
            catch (e) { console.error('[langfuse] score validation failed:', e.message); process.exit(2); }
            // Flush ngay sau score (user thấy score xuất hiện trên Langfuse ngay)
            flushSync(sessionId, () => process.exit(0));
            return;
        }
        case 'flush': {
            flushSync(sessionId, () => process.exit(0));
            return;
        }
        default:
            process.exit(0);
    }
}
