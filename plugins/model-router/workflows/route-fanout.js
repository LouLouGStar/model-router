/*
 * model-router: route-fanout
 * Runs independent, heterogeneous tasks on tier-matched workers (haiku / sonnet / opus), verifies
 * each result with a fresh-context reviewer and escalates one tier up on failure: easy→medium→hard,
 * at most one attempt per tier (so at most two re-runs); a hard signal (security, production, money,
 * unclear cause, …) in the escalate reason or the reviewer findings jumps straight to hard; a failure
 * at hard is reported as failed. The escalated worker is told which files the failed attempt changed.
 * A worker or reviewer that returned no result (user skip / terminal API error) is never retried.
 *
 * args = {
 *   tasks: [{ id: 't1', title: 'Translate strings', tier: 'easy' | 'medium' | 'hard', brief: '<full handoff brief>',
 *             files?: ['path'], oracle?: 'exact check command', isolation?: 'worktree' }],   // ids must be unique
 *   review?: 'auto' | 'always' | 'never',   // default 'auto': easy tasks that ran their oracle skip the reviewer;
 *                                           // 'always' reviews every finished attempt, 'never' none (project hint default-review maps here)
 *   reviewer_model?: 'sonnet' | 'opus',      // default: sonnet for easy tasks, the reviewer's own model (opus) otherwise
 *   max_agents?: number,                     // default 10 (soft cap: logged, tasks still run queued)
 *   language?: string                        // language for user-facing text, e.g. 'de'
 * }
 * Example: Workflow({ name: 'model-router:route-fanout', args: { tasks: [{ id: 't1', title: 'Translate 3 sentences', tier: 'easy', brief: 'OBJECTIVE: ...' }], review: 'auto' } })
 * Returns { routing: [{ id, title, tier_requested, tier_used, status, verdict, escalated, changed_files }],
 *           results: [{ id, worker, verdict, attempts: [{ tier, worker, verdict }] }],   // same order as tasks
 *           summary_counts: { done, unverified, failed, escalated, review_fail } }
 * status: done (worker done + review passed) | unverified (worker done, no reviewer ran) | failed | error (stage threw)
 * verdict: pass | pass_with_notes | fail | skipped (no reviewer ran — never reported as pass) | none
 * review_fail counts tasks whose last review failed.
 */
export const meta = {
  name: 'route-fanout',
  description: 'Run independent tasks on tier-matched model-router workers, verify each with a fresh reviewer, escalate one tier on failure',
  whenToUse: 'Invoked by the model-router route skill for five or more independent tasks of different difficulty, or for two or more when the run must verify and escalate unattended. Needs args {tasks:[{id,title,tier,brief,...}]}.',
  phases: [
    { title: 'Work', detail: 'one worker per task, tier-matched' },
    { title: 'Verify', detail: 'fresh-context reviewer per task' },
    { title: 'Escalate', detail: 're-run one tier up (or straight to hard on a hard signal) and re-review, one attempt per tier' },
  ],
}

const TIERS = ['easy', 'medium', 'hard']
const WORKER = {
  easy: 'model-router:quick-worker',
  medium: 'model-router:standard-worker',
  hard: 'model-router:expert-worker',
}
const REVIEWER = 'model-router:reviewer'
const HARD_SIGNAL = /security|sicherheit|production|produktion|prod\b|migration|root cause|unknown cause|unclear cause|cause (is )?unclear|ursache|architect|architektur|concurrency|money|geld|payment|zahlung/i

const WORKER_SCHEMA = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['done', 'escalate', 'failed'] },
    summary: { type: 'string', description: 'What changed or the answer itself (data, not prose)' },
    changed_files: { type: 'array', items: { type: 'string' } },
    evidence: { type: 'string', description: 'Exact check command(s) and trimmed output, or sources' },
    not_verified: { type: 'string' },
    open_questions: { type: 'array', items: { type: 'string' } },
    escalate_reason: { type: 'string' },
  },
  required: ['status', 'summary', 'evidence'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['pass', 'pass_with_notes', 'fail'] },
    findings: { type: 'array', items: { type: 'string' }, description: 'file:line — defect — concrete failure scenario' },
    evidence: { type: 'string', description: 'Oracle command and trimmed output you reproduced yourself' },
  },
  required: ['verdict', 'evidence'],
}

function normalizeArgs(raw) {
  if (typeof raw === 'string') {
    try { return JSON.parse(raw) } catch (e) { return raw }
  }
  return raw
}

function nextTier(tier) {
  const i = TIERS.indexOf(tier)
  return i >= 0 && i < TIERS.length - 1 ? TIERS[i + 1] : null
}

function clip(text, n) {
  const s = text == null ? '' : String(text)
  return s.length > n ? s.slice(0, n) + ' …[truncated]' : s
}

function workerPrompt(task, tier, language, failure) {
  const parts = []
  parts.push(task.brief)
  parts.push('')
  parts.push('Task id: ' + task.id + ' — ' + task.title + ' (tier: ' + tier + ')')
  if (Array.isArray(task.files) && task.files.length) parts.push('Files you may edit (nothing else): ' + task.files.join(', '))
  if (task.oracle) parts.push('DONE MEANS — run exactly this check before you report and include its output: ' + task.oracle)
  if (language) parts.push('User-facing text must be written in: ' + language)
  if (failure) {
    parts.push('')
    parts.push('A previous attempt at a lower tier did not pass. Its evidence, so you do not repeat it:')
    parts.push(clip(failure, 2500))
  }
  parts.push('')
  parts.push('Reply as structured data: status (done | escalate | failed), summary, changed_files, evidence (command + trimmed output), not_verified, open_questions, escalate_reason. Use status "escalate" with a reason instead of guessing when the task needs a design decision, more files than listed, has an unclear cause, or touches security/production/money.')
  return parts.join('\n')
}

function reviewerPrompt(task, record) {
  const w = record.worker || {}
  return [
    'You are the fresh-context reviewer. You see only the brief and the worker\'s claimed result; verify it with evidence, skip style.',
    '',
    'BRIEF:',
    task.brief,
    task.oracle ? '\nORACLE (run it yourself and quote the trimmed output): ' + task.oracle : '',
    Array.isArray(task.files) && task.files.length ? 'Files the worker was allowed to edit: ' + task.files.join(', ') : '',
    '',
    'WORKER CLAIM (tier ' + record.tier_used + '):',
    'summary: ' + clip(w.summary, 3000),
    'changed_files: ' + (Array.isArray(w.changed_files) ? w.changed_files.join(', ') : 'none reported'),
    'evidence: ' + clip(w.evidence, 3000),
    'not_verified: ' + clip(w.not_verified, 800),
    '',
    'Return verdict pass | pass_with_notes | fail, findings (file:line — defect — concrete failure scenario), evidence.',
  ].join('\n')
}

const ARGS = normalizeArgs(args)
if (!ARGS || !Array.isArray(ARGS.tasks) || ARGS.tasks.length === 0) {
  throw new Error('route-fanout needs args { tasks: [{ id, title, tier: easy|medium|hard, brief, files?, oracle?, isolation? }], review?: auto|always|never, max_agents?, language? } with at least one task.')
}
const seenIds = new Set()
ARGS.tasks.forEach(function (t, i) {
  if (!t || typeof t.brief !== 'string' || !t.brief.trim()) throw new Error('route-fanout: tasks[' + i + '] needs a non-empty brief')
  if (TIERS.indexOf(t.tier) < 0) throw new Error('route-fanout: tasks[' + i + '].tier must be easy, medium or hard (got ' + JSON.stringify(t.tier) + ')')
  if (!t.id) t.id = 't' + (i + 1)
  if (seenIds.has(t.id)) throw new Error('route-fanout: duplicate task id ' + JSON.stringify(t.id) + ' (ids must be unique)')
  seenIds.add(t.id)
  if (!t.title) t.title = t.id
})
const REVIEW = ['auto', 'always', 'never'].indexOf(ARGS.review) >= 0 ? ARGS.review : 'auto'
const MAX_AGENTS = typeof ARGS.max_agents === 'number' && ARGS.max_agents > 0 ? ARGS.max_agents : 10
const LANGUAGE = typeof ARGS.language === 'string' ? ARGS.language : ''

const tierCounts = { easy: 0, medium: 0, hard: 0 }
ARGS.tasks.forEach(function (t) { tierCounts[t.tier] += 1 })
log('route-fanout: ' + ARGS.tasks.length + ' tasks → haiku ×' + tierCounts.easy + ', sonnet ×' + tierCounts.medium + ', opus ×' + tierCounts.hard + ' · review: ' + REVIEW)
if (ARGS.tasks.length > MAX_AGENTS) log('route-fanout: ' + ARGS.tasks.length + ' tasks exceed max_agents=' + MAX_AGENTS + '; all run, but queued — consider splitting the batch')

function runWorker(task, tier, failure) {
  const opts = { label: tier + ':' + task.id, phase: failure ? 'Escalate' : 'Work', schema: WORKER_SCHEMA, agentType: WORKER[tier] }
  if (task.isolation === 'worktree') opts.isolation = 'worktree'
  return agent(workerPrompt(task, tier, LANGUAGE, failure), opts).then(function (w) {
    // a worker that followed its prose protocol (first line "ESCALATE: <reason>") instead of status 'escalate'
    if (w && w.status === 'done' && /^\s*ESCALATE:/i.test(w.summary || '')) {
      w.status = 'escalate'
      if (!w.escalate_reason) w.escalate_reason = w.summary.replace(/^\s*ESCALATE:\s*/i, '')
    }
    return w
  })
}

function runReviewer(task, record, escalated) {
  const opts = { label: 'review:' + task.id + ':' + record.tier_used, phase: escalated ? 'Escalate' : 'Verify', schema: VERDICT_SCHEMA, agentType: REVIEWER }
  if (ARGS.reviewer_model === 'sonnet' || ARGS.reviewer_model === 'opus') {
    opts.model = ARGS.reviewer_model
  } else if (record.tier_used === 'easy') {
    opts.model = 'sonnet'
  }
  return agent(reviewerPrompt(task, record), opts)
}

function needsReview(task, record) {
  if (REVIEW === 'never') return false
  if (!record.worker || record.worker.status !== 'done') return false   // nothing finished to review
  if (REVIEW === 'always') return true
  // auto: an easy task that ran its mechanical oracle is already checked; everything else gets a reviewer
  if (record.tier_used === 'easy' && task.oracle && record.worker.evidence && record.worker.evidence.length > 20) return false
  return true
}

function skippedVerdict(record) {
  const w = record.worker
  const why = !w ? 'no worker result' : (w.status !== 'done' ? 'worker status ' + w.status : 'review ' + REVIEW + (REVIEW === 'auto' ? ', easy task ran its oracle' : ''))
  return { verdict: 'skipped', findings: [], evidence: 'review skipped: ' + why }
}

function setVerdict(record, verdict) {
  record.verdict = verdict || { verdict: 'skipped', findings: [], evidence: 'review skipped: reviewer returned no result' }
  record.attempts[record.attempts.length - 1].verdict = record.verdict
}

async function reviewAttempt(record, escalated) {
  if (needsReview(record.task, record)) setVerdict(record, await runReviewer(record.task, record, escalated))
  else setVerdict(record, skippedVerdict(record))
}

function needsEscalation(record) {
  if (!record.worker) return false   // user skip or terminal API error: report as failed, do not retry one tier up
  if (record.worker.status === 'escalate' || record.worker.status === 'failed') return true
  return !!(record.verdict && record.verdict.verdict === 'fail')
}

function hardSignal(record) {
  const w = record.worker || {}
  const v = record.verdict || {}
  return HARD_SIGNAL.test([w.escalate_reason || '', Array.isArray(v.findings) ? v.findings.join('\n') : ''].join('\n'))
}

function failureText(record) {
  const w = record.worker || {}
  const v = record.verdict || {}
  return [
    'previous tier: ' + record.tier_used,
    'worker status: ' + (w.status || 'no result'),
    w.escalate_reason ? 'escalate reason: ' + w.escalate_reason : '',
    Array.isArray(w.changed_files) && w.changed_files.length ? 'files the previous attempt already changed (its edits are still in the working tree — inspect and fix or revert them): ' + w.changed_files.join(', ') : '',
    w.summary ? 'worker summary: ' + clip(w.summary, 800) : '',
    v.verdict ? 'reviewer verdict: ' + v.verdict : '',
    Array.isArray(v.findings) && v.findings.length ? 'reviewer findings: ' + v.findings.join(' | ') : '',
    v.evidence ? 'reviewer evidence: ' + clip(v.evidence, 800) : '',
  ].filter(Boolean).join('\n')
}

async function stageWork(prev, task) {
  const worker = await runWorker(task, task.tier, null)
  return { task: task, tier_requested: task.tier, tier_used: task.tier, worker: worker, attempts: [{ tier: task.tier, worker: worker, verdict: null }], escalated: false, verdict: null, final_status: null }
}

async function stageVerify(record) {
  if (!record) return null
  await reviewAttempt(record, false)
  return record
}

async function stageEscalate(record) {
  if (!record) return null
  while (needsEscalation(record)) {   // bounded: the tier only goes up and 'hard' has no next tier → at most two re-runs
    let target = nextTier(record.tier_used)
    if (target && hardSignal(record)) target = 'hard'
    if (!target) {
      record.final_status = 'failed'
      return record
    }
    log('route-fanout: escalating ' + record.task.id + ' ' + record.tier_used + ' → ' + target)
    const worker = await runWorker(record.task, target, failureText(record))
    record.attempts.push({ tier: target, worker: worker, verdict: null })
    record.tier_used = target
    record.worker = worker
    record.escalated = true
    await reviewAttempt(record, true)
  }
  return record
}

phase('Work')
const records = await pipeline(ARGS.tasks, stageWork, stageVerify, stageEscalate)

const routing = []
const results = []
const counts = { done: 0, unverified: 0, failed: 0, escalated: 0, review_fail: 0 }
records.forEach(function (r, i) {
  const task = ARGS.tasks[i]
  if (!r) {
    routing.push({ id: task.id, title: task.title, tier_requested: task.tier, tier_used: task.tier, status: 'error', verdict: 'none', escalated: false, changed_files: [] })
    results.push({ id: task.id, worker: null, verdict: null, attempts: [] })
    counts.failed += 1
    return
  }
  const workerOk = r.worker && r.worker.status === 'done'
  const v = r.verdict ? r.verdict.verdict : 'none'
  const status = (!workerOk || r.final_status === 'failed' || v === 'fail') ? 'failed' : ((v === 'pass' || v === 'pass_with_notes') ? 'done' : 'unverified')
  counts[status] += 1
  if (r.escalated) counts.escalated += 1
  if (v === 'fail') counts.review_fail += 1
  routing.push({
    id: task.id,
    title: task.title,
    tier_requested: r.tier_requested,
    tier_used: r.tier_used,
    status: status,
    verdict: v,
    escalated: r.escalated,
    changed_files: r.worker && Array.isArray(r.worker.changed_files) ? r.worker.changed_files : [],
  })
  results.push({ id: task.id, worker: r.worker, verdict: r.verdict, attempts: r.attempts })
})
log('route-fanout: done ' + counts.done + '/' + ARGS.tasks.length + ' · unverified ' + counts.unverified + ' · escalated ' + counts.escalated + ' · failed ' + counts.failed)
return { routing: routing, results: results, summary_counts: counts }
