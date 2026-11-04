/*
 * model-router: route-sweep
 * Runs the SAME brief over many same-shape items on one worker tier (default haiku), spot-checks a
 * deterministic, evenly spaced sample with a fresh-context reviewer (each sampled item is reviewed as
 * soon as it finishes; a sampled item without a result, or a reviewer without a result, is logged as a
 * shortfall and never counted as checked) and synthesizes one compact report.
 *
 * args = {
 *   items: ['file-a.md', 'file-b.md', ...] | [{...}],   // objects are JSON-stringified into the slot
 *   brief_template: 'OBJECTIVE: summarize {{item}} in 3 bullets ... DONE MEANS ...',  // must contain {{item}}
 *   tier?: 'easy' | 'medium' | 'hard' | 'review',   // default 'easy'; 'review' runs model-router:reviewer (read-only) per item — e.g. user-requested reviews of > ~15 files; its default item schema is the verdict schema
 *   item_schema?: { JSON schema },           // per-item structured result; default {result, evidence, confidence};
 *                                            // must be { type: 'object', properties, required? ⊆ properties } or the run throws
 *   spot_check?: number,                     // default min(3, items.length)
 *   reviewer_model?: 'sonnet' | 'opus',      // default sonnet for easy, reviewer default (opus) otherwise
 *   max_agents?: number,                     // default 10 (soft cap, logged)
 *   isolation?: 'worktree'                   // only when items edit files concurrently
 * }
 * Example: Workflow({ name: 'model-router:route-sweep', args: { items: ['notes/a.md', 'notes/b.md'], brief_template: 'OBJECTIVE: Fasse {{item}} in 3 Stichpunkten zusammen. ...', tier: 'easy', spot_check: 3 } })
 * Returns { items: [{ index, item, result }], spot_check: [{ index, item, verdict }], synthesis: { summary, anomalies, failed_items },
 *           counts: { items, returned, failed, spot_sampled, spot_checked, spot_failed } }
 */
export const meta = {
  name: 'route-sweep',
  description: 'Run one brief over many same-shape items on a tier-matched model-router worker, spot-check a sample with a reviewer, synthesize a report',
  whenToUse: 'Invoked by the model-router route skill for 5+ same-shape independent items (summarize/convert/migrate each X; tier review = one read-only reviewer per item for large review requests). Needs args {items:[...], brief_template:"... {{item}} ..."}.',
  phases: [
    { title: 'Sweep', detail: 'one worker per item' },
    { title: 'Spot-check', detail: 'reviewer on an evenly spaced sample, as each sampled item finishes' },
    { title: 'Synthesize', detail: 'one standard-worker merges all results' },
  ],
}

const TIERS = ['easy', 'medium', 'hard', 'review']
const WORKER = {
  easy: 'model-router:quick-worker',
  medium: 'model-router:standard-worker',
  hard: 'model-router:expert-worker',
  review: 'model-router:reviewer',
}
const REVIEWER = 'model-router:reviewer'

const DEFAULT_ITEM_SCHEMA = {
  type: 'object',
  properties: {
    result: { type: 'string' },
    evidence: { type: 'string' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
  },
  required: ['result'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['pass', 'pass_with_notes', 'fail'] },
    findings: { type: 'array', items: { type: 'string' } },
    evidence: { type: 'string' },
  },
  required: ['verdict', 'evidence'],
}

const SYNTHESIS_SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string', description: 'Compact report over all items, in the language of the brief' },
    anomalies: { type: 'array', items: { type: 'string' } },
    failed_items: { type: 'array', items: { type: 'string' } },
  },
  required: ['summary', 'anomalies', 'failed_items'],
}

function normalizeArgs(raw) {
  if (typeof raw === 'string') {
    try { return JSON.parse(raw) } catch (e) { return raw }
  }
  return raw
}

function itemText(item) {
  return typeof item === 'string' ? item : JSON.stringify(item)
}

function clip(text, n) {
  const s = text == null ? '' : String(text)
  return s.length > n ? s.slice(0, n) + ' …[truncated]' : s
}

function sampleIndexes(total, wanted) {
  const n = Math.max(0, Math.min(wanted, total))
  const out = []
  for (let k = 0; k < n; k++) {
    const idx = Math.floor((k * total) / n)
    if (out.indexOf(idx) < 0) out.push(idx)
  }
  return out
}

const ARGS = normalizeArgs(args)
if (!ARGS || !Array.isArray(ARGS.items) || ARGS.items.length === 0) {
  throw new Error('route-sweep needs args { items: [...], brief_template: "... {{item}} ...", tier?: easy|medium|hard|review, item_schema?, spot_check?, reviewer_model?, max_agents?, isolation? } with at least one item.')
}
if (typeof ARGS.brief_template !== 'string' || ARGS.brief_template.indexOf('{{item}}') < 0) {
  throw new Error('route-sweep: brief_template must be a string containing the placeholder {{item}}')
}
const TIER = TIERS.indexOf(ARGS.tier) >= 0 ? ARGS.tier : 'easy'
let ITEM_SCHEMA = TIER === 'review' ? VERDICT_SCHEMA : DEFAULT_ITEM_SCHEMA
if (ARGS.item_schema !== undefined) {
  const s = ARGS.item_schema
  const props = s && typeof s === 'object' && s.properties && typeof s.properties === 'object' ? s.properties : null
  const missing = props && Array.isArray(s.required) ? s.required.filter(function (k) { return !(k in props) }) : []
  if (!props || s.type !== 'object' || missing.length) throw new Error('route-sweep: item_schema must be { type: "object", properties: {...}, required?: [keys ⊆ properties] }' + (missing.length ? ' — required keys missing from properties: ' + missing.join(', ') : ''))
  ITEM_SCHEMA = s
}
const SPOT = typeof ARGS.spot_check === 'number' && ARGS.spot_check >= 0 ? Math.floor(ARGS.spot_check) : Math.min(3, ARGS.items.length)
const MAX_AGENTS = typeof ARGS.max_agents === 'number' && ARGS.max_agents > 0 ? ARGS.max_agents : 10
const SAMPLE = sampleIndexes(ARGS.items.length, SPOT)

log('route-sweep: ' + ARGS.items.length + ' items → ' + WORKER[TIER] + ' · spot-check ' + SAMPLE.length + ' · synthesis: standard-worker')
if (ARGS.items.length > MAX_AGENTS) log('route-sweep: ' + ARGS.items.length + ' items exceed max_agents=' + MAX_AGENTS + '; all run, but queued')

function fillBrief(item) {
  return ARGS.brief_template.split('{{item}}').join(itemText(item))
}

function workerBrief(item) {
  return fillBrief(item) +
    '\n\nReply as structured data matching the requested schema. Include evidence (command + trimmed output, or the source lines) where the brief asks for a check. If the item cannot be processed as specified, say so in the result instead of guessing.'
}

function spotPrompt(item, result) {
  return [
    'You are the fresh-context reviewer. Verify ONE item result of a sweep against its brief, with evidence; skip style.',
    '',
    'BRIEF:',
    fillBrief(item),
    '',
    'WORKER RESULT (JSON):',
    clip(JSON.stringify(result), 4000),
    '',
    'Open the source item yourself where possible and check meaning, completeness and the requested format. Return verdict pass | pass_with_notes | fail, findings, evidence.',
  ].join('\n')
}

function stageSweep(prev, item, index) {
  const opts = { label: 'item:' + index, phase: 'Sweep', schema: ITEM_SCHEMA, agentType: WORKER[TIER] }
  if (ARGS.isolation === 'worktree') opts.isolation = 'worktree'
  return agent(workerBrief(item), opts)
}

function stageSpot(result, item, index) {
  if (!result || SAMPLE.indexOf(index) < 0) return { result: result, spot: null }
  const opts = { label: 'spot:' + index, phase: 'Spot-check', schema: VERDICT_SCHEMA, agentType: REVIEWER }
  if (ARGS.reviewer_model === 'sonnet' || ARGS.reviewer_model === 'opus') opts.model = ARGS.reviewer_model
  else if (TIER === 'easy') opts.model = 'sonnet'
  return agent(spotPrompt(item, result), opts)
    .then(function (v) { return { result: result, spot: v ? { index: index, item: itemText(item), verdict: v } : null } })
    .catch(function () { return { result: result, spot: null } })   // a failed review must not drop the item result
}

phase('Sweep')
const swept = await pipeline(ARGS.items, stageSweep, stageSpot)
const itemResults = swept.map(function (s) { return s ? s.result : null })
const spotOk = swept.map(function (s) { return s && s.spot }).filter(Boolean)

const failedIdx = []
itemResults.forEach(function (r, i) { if (!r) failedIdx.push(i) })
log('route-sweep: ' + (ARGS.items.length - failedIdx.length) + '/' + ARGS.items.length + ' items returned a result' + (failedIdx.length ? ' · failed: ' + failedIdx.join(', ') : ''))
const spotFailed = spotOk.filter(function (s) { return s.verdict.verdict === 'fail' }).length
log('route-sweep: spot-checked ' + spotOk.length + ' of ' + ARGS.items.length + ' · fails: ' + spotFailed)
if (spotOk.length < SAMPLE.length) log('route-sweep: ' + (SAMPLE.length - spotOk.length) + ' of ' + SAMPLE.length + ' sampled items not spot-checked (no item result or reviewer returned no result) — not replaced')

phase('Synthesize')
const lines = itemResults.map(function (r, i) {
  return '[' + i + '] ' + clip(itemText(ARGS.items[i]), 120) + ' → ' + (r ? clip(JSON.stringify(r), 600) : 'NO RESULT')
})
const spotLines = spotOk.map(function (s) {
  return '[' + s.index + '] ' + s.verdict.verdict + (s.verdict.findings && s.verdict.findings.length ? ': ' + s.verdict.findings.join(' | ') : '')
})
const synthesis = await agent([
  'Synthesize the results of a sweep into one compact report for the user, in the language of the brief below. Data, not prose padding.',
  '',
  'ORIGINAL BRIEF TEMPLATE:',
  ARGS.brief_template,
  '',
  'PER-ITEM RESULTS (' + ARGS.items.length + '):',
  lines.join('\n'),
  '',
  'SPOT-CHECK VERDICTS (' + spotOk.length + ' of ' + SAMPLE.length + ' sampled):',
  spotLines.length ? spotLines.join('\n') : 'none',
  '',
  'Return: summary (what was done, overall quality, anything the user must know), anomalies (items whose result looks inconsistent, incomplete or contradicts the spot-check), failed_items (indexes/items with no result or a failing verdict).',
].join('\n'), { label: 'synthesis', phase: 'Synthesize', schema: SYNTHESIS_SCHEMA, agentType: 'model-router:standard-worker' })

return {
  items: itemResults.map(function (r, i) { return { index: i, item: ARGS.items[i], result: r } }),
  spot_check: spotOk,
  synthesis: synthesis || { summary: 'synthesis agent returned no result', anomalies: [], failed_items: failedIdx.map(String) },
  counts: { items: ARGS.items.length, returned: ARGS.items.length - failedIdx.length, failed: failedIdx.length, spot_sampled: SAMPLE.length, spot_checked: spotOk.length, spot_failed: spotFailed },
}
