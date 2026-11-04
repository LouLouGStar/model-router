/*
 * model-router: verify-findings
 * Adversarial verification of findings (bug lists, audit results, research claims): each finding is
 * attacked by N independent read-only refuters with different lenses; it survives only with a strict
 * majority of non-refuted votes. Refuters default to "refuted" when uncertain.
 *
 * args = {
 *   findings: [{ id: 'f1', claim: 'route X lacks auth', evidence?: 'src/routes/x.ts:12 ...', location?: 'src/routes/x.ts' }],   // ids must be unique
 *   refuters?: number,                 // default 3 (one per lens, lenses cycle when refuters > lenses)
 *   lenses?: string[],                 // default ['correctness', 'security', 'reproducibility']; duplicates are dropped
 *   tier?: 'medium' | 'hard',          // default 'hard' → reviewer on its own model (opus); 'medium' → reviewer on sonnet
 *   context?: string                   // shared background every refuter gets (repo, constraints, how to reproduce)
 * }
 * Example: Workflow({ name: 'model-router:verify-findings', args: { findings: [{ id: 'f1', claim: '...', evidence: '...' }], refuters: 3 } })
 * Returns { confirmed: [...], refuted: [...], undecided: [...] }
 */
export const meta = {
  name: 'verify-findings',
  description: 'Adversarially verify findings with independent refuters (strict majority must fail to refute)',
  whenToUse: 'Invoked by the model-router route skill after audits, bug hunts or research produce claims that must survive cross-checking. Needs args {findings:[{id,claim,...}]}.',
  phases: [
    { title: 'Refute', detail: 'N read-only refuters per finding, distinct lenses' },
  ],
}

const REVIEWER = 'model-router:reviewer'
const DEFAULT_LENSES = ['correctness', 'security', 'reproducibility']

const VOTE_SCHEMA = {
  type: 'object',
  properties: {
    refuted: { type: 'boolean', description: 'true when the finding does not hold or cannot be substantiated' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    reasoning: { type: 'string' },
    evidence: { type: 'string', description: 'file:line or command output that supports the vote' },
  },
  required: ['refuted', 'confidence', 'reasoning', 'evidence'],
}

function normalizeArgs(raw) {
  if (typeof raw === 'string') {
    try { return JSON.parse(raw) } catch (e) { return raw }
  }
  return raw
}

function clip(text, n) {
  const s = text == null ? '' : String(text)
  return s.length > n ? s.slice(0, n) + ' …[truncated]' : s
}

const ARGS = normalizeArgs(args)
if (!ARGS || !Array.isArray(ARGS.findings) || ARGS.findings.length === 0) {
  throw new Error('verify-findings needs args { findings: [{ id, claim, evidence?, location? }], refuters?: 3, lenses?: [...], tier?: medium|hard, context? } with at least one finding.')
}
const seenIds = new Set()
ARGS.findings.forEach(function (f, i) {
  if (!f || typeof f.claim !== 'string' || !f.claim.trim()) throw new Error('verify-findings: findings[' + i + '] needs a non-empty claim')
  if (!f.id) f.id = 'f' + (i + 1)
  if (seenIds.has(f.id)) throw new Error('verify-findings: duplicate finding id ' + JSON.stringify(f.id) + ' (ids must be unique)')
  seenIds.add(f.id)
})
const REFUTERS = typeof ARGS.refuters === 'number' && ARGS.refuters >= 1 ? Math.floor(ARGS.refuters) : 3
const LENSES = (Array.isArray(ARGS.lenses) && ARGS.lenses.length ? ARGS.lenses.map(String) : DEFAULT_LENSES).filter(function (l, i, a) { return a.indexOf(l) === i })
const TIER = ARGS.tier === 'medium' ? 'medium' : 'hard'
const CONTEXT = typeof ARGS.context === 'string' ? ARGS.context : ''

log('verify-findings: ' + ARGS.findings.length + ' findings × ' + REFUTERS + ' refuters (' + LENSES.join('/') + ') on ' + (TIER === 'medium' ? 'sonnet' : 'opus'))

function refuterPrompt(finding, lens) {
  return [
    'You are an independent, skeptical verifier. Try to REFUTE the finding below through the ' + lens + ' lens.',
    'Default to refuted=true if you cannot substantiate it with concrete evidence (file:line, reproduced command output). Confident speculation is not evidence.',
    CONTEXT ? '\nCONTEXT:\n' + clip(CONTEXT, 4000) : '',
    '',
    'FINDING ' + finding.id + ':',
    'claim: ' + finding.claim,
    finding.location ? 'location: ' + finding.location : '',
    finding.evidence ? 'claimed evidence: ' + clip(finding.evidence, 3000) : 'claimed evidence: none given',
    '',
    'Check the actual files/commands yourself where possible. Return refuted (boolean), confidence, reasoning, evidence.',
  ].join('\n')
}

function decide(votes) {
  const valid = votes.filter(Boolean)
  if (valid.length === 0) return 'undecided'
  const notRefuted = valid.filter(function (v) { return v.refuted === false }).length
  return notRefuted * 2 > REFUTERS ? 'confirmed' : 'refuted'
}

phase('Refute')
const judged = await pipeline(ARGS.findings, function (prev, finding) {
  const thunks = []
  for (let k = 0; k < REFUTERS; k++) {
    const lens = LENSES[k % LENSES.length]
    thunks.push(function () {
      const opts = { label: 'refute:' + finding.id + ':' + lens + (k >= LENSES.length ? '#' + k : ''), phase: 'Refute', schema: VOTE_SCHEMA, agentType: REVIEWER }
      if (TIER === 'medium') opts.model = 'sonnet'
      return agent(refuterPrompt(finding, lens), opts).then(function (v) { return v ? Object.assign({ lens: lens }, v) : null })
    })
  }
  return parallel(thunks).then(function (votes) {
    return { finding: finding, votes: votes.filter(Boolean), outcome: decide(votes) }
  })
})

const confirmed = []
const refuted = []
const undecided = []
judged.forEach(function (j, i) {
  if (!j) { undecided.push({ finding: ARGS.findings[i], votes: [], outcome: 'undecided' }); return }
  if (j.outcome === 'confirmed') confirmed.push(j)
  else if (j.outcome === 'refuted') refuted.push(j)
  else undecided.push(j)
})
log('verify-findings: confirmed ' + confirmed.length + ' · refuted ' + refuted.length + ' · undecided ' + undecided.length)
return { confirmed: confirmed, refuted: refuted, undecided: undecided }
