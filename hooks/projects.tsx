import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

// A project is the folder the owner creates (marker kind: project, scripts/project.sh); its coordinator is the
// owner's conversation at the folder's root and gets the Threads pane: the sessions it started. The older layout
// (a workspace with central/ and projects/<slug>/) works the same until its projects move out.
const error = atom({ plugin: 'chief-of-staff', key: 'error' } as const, '', { shape: 'error-1' })
const THREADS = 'cos-threads'
const coord = atom({ plugin: 'chief-of-staff', key: 'coord' } as const, '', { shape: 'coord-1' })
// this conversation's folder: /threads makes it a project
const here = atom({ plugin: 'chief-of-staff', key: 'here' } as const, '', { shape: 'here-2' })
// the owner closed the Threads pane by hand: it stays closed until /threads
const shut = atom({ plugin: 'chief-of-staff', key: 'threadsShut' } as const, false, { shape: 'shut-1' })

type Project = { slug: string; dir: string; status: string; updated: string; next: string; goal: string }

// front matter value, as lib.sh fm_get reads it
export const fm = (text: string, key: string): string => {
  const lines = text.replace(/\r/g, '').split('\n')
  if (lines[0] !== '---') return ''
  for (const l of lines.slice(1)) {
    if (l === '---') break
    if (l.startsWith(key + ':')) return l.slice(key.length + 1).trim()
  }
  return ''
}

// decisions in force, as lib.sh cos_decisions: "- YYYY-MM-DD HH:MM | text | who | replaces: id"
export const decisions = (text: string): string[] => {
  const rows: { id: string; d: string; who: string }[] = []
  const gone = new Set<string>()
  for (const l of text.replace(/\r/g, '').split('\n')) {
    if (!/^- \d{4}-[01]\d-[0-3]\d [0-2]\d:[0-5]\d \| /.test(l)) continue
    const [a = '', d = '', who = '', r = ''] = l.split(' | ')
    const rep = r.replace(/^ *replaces: */, '').trim()
    if (rep && rep !== '-') gone.add(rep)
    rows.push({ id: a.slice(2), d, who })
  }
  return rows.filter(x => !gone.has(x.id) && !x.d.startsWith('revoked:')).map(x => `${x.d} (${x.who})`)
}

const base = (dir: string) => dir.split('/').filter(Boolean).pop() ?? 'chat'
const text = (r: { content?: { type: string; text?: string }[] }) => (r.content ?? []).map(c => c.text ?? '').join('\n')

async function findRoot($: EngineInterface, cwd: string): Promise<string> {
  for (let d = cwd; d && d !== '/'; d = d.slice(0, d.lastIndexOf('/'))) {
    if (await $.fs.exists(`${d}/.chief-of-staff`)) return d
  }
  return ''
}

async function root($: EngineInterface): Promise<string> {
  return ((await $.store.get('root')) as string) || ''
}

// a project folder: its marker says kind: project (lib.sh cos_isproj)
async function isProject($: EngineInterface, r: string): Promise<boolean> {
  return /^kind: project$/m.test(await $.fs.read(`${r}/.chief-of-staff`).catch(() => ''))
}

// the coordinator's project: the folder itself, or projects/<slug> in the older layout
async function project($: EngineInterface, r: string, slug: string): Promise<Project | undefined> {
  const dir = (await isProject($, r)) ? r : `${r}/projects/${slug}`
  const s = await $.fs.read(`${dir}/STATE.md`).catch(() => null)
  if (s === null) return undefined
  const c = await $.fs.read(`${dir}/CLAUDE.md`).catch(() => '')
  const goal = (c.match(/handles \*\*one thing only\*\*: (.*)/)?.[1] ?? '').trim()
  return { slug, dir, status: fm(s, 'status') || 'new', updated: fm(s, 'updated'), next: fm(s, 'next'), goal }
}

// a thread: a session another session started and kept linked. It runs in its coordinator's folder, so the folder
// does not tell them apart; the app's own record does. Unknown (the app does not answer): not a thread, and the
// hooks' folder and registration checks still hold (scripts/ask-guard.sh, protocol.sh)
export async function isThread($: EngineInterface): Promise<boolean> {
  return (await hasParent($)) === true
}

// true: a thread; false: the app says this chat has no parent; undefined: the app did not answer
async function hasParent($: EngineInterface): Promise<boolean | undefined> {
  try {
    const s = JSON.parse(text(await $.mcp.call('ccd_session_mgmt', 'get_session', { session_id: 'self' })))
    if (!s || typeof s !== 'object' || !s.sessionId) return undefined
    return !!s.parentSessionId && !s.detached
  } catch { return undefined }
}

// what a thread may not run in a project folder: the owner's OK (track.sh ok) and project.sh (registers a
// coordinator). ponytail: a word match on the command; the hooks parse it fully and the owner approves every OK
export const ownerCommand = (cmd: string): boolean =>
  /project\.sh(?![\s'"]+list([^a-z]|$))/.test(cmd) || (/track/.test(cmd) && /(^|[^a-z0-9_.-])ok([^a-z0-9_.-]|$)/.test(cmd))

// a shell word in single quotes: a folder name with " or $( ) stays one literal argument
const sq = (s: string): string => `'${s.replace(/'/g, `'\\''`)}'`

// what /threads tells the conversation once the folder is a project: open its web panel in the app's browser
export const panelAsk = (pluginRoot: string, dir: string): string =>
  `Open this project's web panel now: run python3 ${sq(`${pluginRoot}/scripts/panel.py`)} ${sq(dir)} in the background, ` +
  'then open the "Panel:" link it prints in the app\'s built-in browser. Tell the owner in one line that it is open.'

// the open questions of a card: the lines under "## For the owner to decide", without their asked-stamp
export const ownerQuestions = (card: string): string[] => {
  const out: string[] = []
  let on = false
  for (const l of card.replace(/\r/g, '').split('\n')) {
    if (l.startsWith('## ')) { on = l.toLowerCase().startsWith('## for the owner to decide'); continue }
    if (on && /^[-*] /.test(l)) out.push(l.replace(/^[-*] +/, '').replace(/^\(asked [^)]*\) */, ''))
  }
  return out
}

async function waitingOnOwner($: EngineInterface, r: string, slug: string): Promise<string[]> {
  const out: string[] = [], all = await isProject($, r)   // a project folder's board is all its own
  for (const e of await $.fs.list(`${r}/board`).catch(() => [])) {
    if (e.kind !== 'file' || !e.name.endsWith('.md')) continue
    const c = await $.fs.read(`${r}/board/${e.name}`).catch(() => '')
    if ((all || fm(c, 'project') === slug) && fm(c, 'status') === 'waiting-owner') out.push(...ownerQuestions(c))
  }
  return out
}

type Thread = { id: string; title: string; state: 'review' | 'working' | 'idle' | 'resolved'; at: number; pr?: number }
const WEEK = 7 * 24 * 3600 * 1000

// the sessions this conversation started (linked, not detached), newest first
// The states of claude.ai Projects that a local session can show: a thread with its pull request open is
// Ready for review; merged or closed, or archived, or a week with no activity, it is Resolved.
export const threadState = (s: { isArchived?: boolean; isRunning?: boolean; prState?: string; lastActivityAt?: string }, now: number): Thread['state'] => {
  if (s.isArchived || /^(MERGED|CLOSED)$/.test(s.prState ?? '')) return 'resolved'
  if (s.isRunning) return 'working'
  if (s.prState === 'OPEN') return 'review'
  return now - (Date.parse(s.lastActivityAt ?? '') || now) > WEEK ? 'resolved' : 'idle'
}

export async function threads($: EngineInterface): Promise<Thread[]> {
  const now = await $.clock.now()
  const me = JSON.parse(text(await $.mcp.call('ccd_session_mgmt', 'get_session', { session_id: 'self' }))).sessionId
  let rows: any[] = []
  try { rows = JSON.parse(text(await $.mcp.call('ccd_session_mgmt', 'list_sessions', { linked: true, include_archived: true, limit: 100 }))) } catch { return [] }
  return rows.filter(s => s.startedBy === me).map(s => ({
    id: s.sessionId, title: s.title || 'Untitled', at: Date.parse(s.lastActivityAt ?? '') || 0, pr: s.prNumber,
    state: threadState(s, now),
  }))
}

// how each state reads, as claude.ai Projects marks it
export const MARK: Record<Thread['state'], { label: string; mark: string; color: string }> = {
  review: { label: 'Ready for review', mark: '◆', color: 'suggestion' },
  working: { label: 'Working', mark: '◐', color: 'claude' },
  idle: { label: 'Idle', mark: '○', color: 'subtle' },
  resolved: { label: 'Resolved', mark: '✓', color: 'success' },
}

// the session a start_session call opened, read off its result (`local_…`)
export const startedId = (output: unknown): string =>
  (typeof output === 'string' ? output : JSON.stringify(output ?? '')).match(/local_[0-9a-f][0-9a-f-]{7,}/)?.[0] ?? ''

export const COORDINATOR =
  'From now on this conversation is a project coordinator, like a claude.ai project chat. Talk with the owner here; ' +
  'run every piece of work longer than a few tool calls as a thread: one start_session call per independent piece ' +
  '(initiation "user_asked", context "fresh", the same folder, a short title, a full brief with files and what done ' +
  'looks like), several at once when the pieces are independent, never detached. Keep this conversation short: ' +
  'answer, start threads, read their reports when they end a turn, check the result, and bring results and questions ' +
  'back to the owner here. Steer a running thread with SendMessage to its session id instead of starting a new one. ' +
  // the rules a grant run with six threads broke: the owner asked from many places, facts drifted, a thread
  // pushed unapproved, a video rendered 8 times, a host proposed before asking, no thread used a specialist
  'Only you talk to the owner: threads report to you and never ask the owner; put everything that needs the owner ' +
  'in one message, all questions at once. Shared facts (slogan, amounts, names, roles, links) live in DECISIONS.md: ' +
  'the project\'s own, or create DECISIONS.md in this folder now ("- YYYY-MM-DD HH:MM | decision | who | replaces: -"). ' +
  'Only you write it; a decision the owner makes in a thread reaches you, you record it and tell the other threads. ' +
  'Every brief opens with the thread rules (no Save or Submit in an external form, no push, no deploy, no message ' +
  'sent, without the owner\'s approval relayed by you; the plugin adds them); check every report for those actions ' +
  'before you relay it. Review before production: tone and facts are reviewed on the text (application, script, copy) ' +
  'before any thread renders video or images or deploys, so the costly output is made once. Before you propose where ' +
  'something runs or is hosted, ask the owner where it runs today (their own servers, domains, accounts); before you ' +
  'build anything that changes where the work runs (cloud or this computer, a new service), get the owner\'s yes or no ' +
  'first. To match an existing look, read the real thing first (its files, a screenshot), list every difference and ' +
  'change them all in one pass, not one per release. Each thread ' +
  'starts with its specialist: pick the role card from ROUTING.md (the workspace\'s, else the plugin\'s templates/ROUTING.md) and give the brief the lines ' +
  '"Role card: <role>", "Library: <notes, or none found for <terms>>" and "Ambition: <goal behind the goal> | judge: ' +
  '<outside judge>"; the thread follows the specialists skill. Anything that goes outside (a submission, a video, a ' +
  'text to a partner) passes the reviewer role before it reaches the owner.'

// what every thread brief opens with; the start_session check below adds it when the coordinator left it out
export const THREAD_RULES =
  'Thread rules (from the coordinator): never, without the owner\'s explicit approval relayed by the coordinator, ' +
  'press Save or Submit in an external form, push, deploy, or send a message. Never ask the owner directly: report ' +
  'to the coordinator, questions included. Read DECISIONS.md before you use a shared fact (slogan, amounts, names, ' +
  'roles); a decision you hear goes to the coordinator, who records it. Follow the specialists skill with the role ' +
  'card below.'

const AMBITION = /Ambition: [^|\n]{12,}\| *judge: [^\n]{8,}/
// what a coordinator's thread brief lacks, as protocol.sh checks an Agent brief: '' when it is complete.
// A role is a name or a card path; with the workspace's cards known, the role must be one of them.
export const briefGaps = (brief: string, cards?: string[]): string => {
  const m = brief.match(/Role card: *(?:[^\n]*\/specialists\/([a-z-]+)\.md|([a-z-]+))/)
  const role = m?.[1] ?? m?.[2] ?? ''
  if (!role) return `the line "Role card: <role>" (the right card from ROUTING.md${cards?.length ? `: ${cards.join(', ')}` : ''})`
  if (role === 'utility') return ''
  if (cards && !cards.includes(role)) return `a role card that exists (no specialists/${role}.md; cards: ${cards.join(', ') || 'none'})`
  if (!brief.includes('Library:')) return 'the line "Library: [[id]] ..." with the notes from library.sh search, or "Library: none found for <terms>"'
  if (!AMBITION.test(brief)) return 'the line "Ambition: <the goal behind the goal> | judge: <what measures that goal from outside>"'
  return ''
}

// The icons the app's own thread list draws, in its colors (read from the app's stylesheet: --cds-fill-warning
// #fbb315, --cds-fill-accent #2a78d6, --cds-fill-success #10a122, --cds-text-muted gray). A surface with Svg
// (desktop, mobile) draws these; the terminal draws MARK's character in the theme color.
const ring = (stroke: string, extra = '') => `<circle cx="8" cy="8" r="6.25" fill="none" stroke="${stroke}" stroke-width="1.5"${extra}/>`
const svg = (body: string) => `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">${body}</svg>`
export const ICON: Record<Thread['state'] | 'waiting', string> = {
  waiting: svg(ring('#fbb315') + '<rect x="5.9" y="5" width="1.4" height="6" rx=".7" fill="#fbb315"/><rect x="8.7" y="5" width="1.4" height="6" rx=".7" fill="#fbb315"/>'),
  review: svg(ring('#2a78d6') + '<circle cx="8" cy="8" r="3" fill="#2a78d6"/>'),
  working: svg(ring('#7b7974', ' opacity=".35"') + '<path d="M8 1.75a6.25 6.25 0 0 1 6.25 6.25" fill="none" stroke="#7b7974" stroke-width="1.5" stroke-linecap="round"><animateTransform attributeName="transform" type="rotate" from="0 8 8" to="360 8 8" dur="1s" repeatCount="indefinite"/></path>'),
  idle: svg(ring('#7b7974', ' stroke-dasharray="2.2 2.2"')),
  resolved: svg('<circle cx="8" cy="8" r="7" fill="#10a122"/><path d="M5 8.2l2 2 4-4.2" fill="none" stroke="#fff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>'),
}

export const ago = (ms: number, now: number): string => {
  const m = Math.max(0, Math.round((now - ms) / 60000))
  return m < 60 ? `${m}m` : m < 1440 ? `${Math.round(m / 60)}h` : `${Math.round(m / 1440)}d`
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const ran = await next(e)
    await update($, here, () => e.cwd)
    const r = await findRoot($, e.cwd)
    if (r) await $.store.set('root', r)
    await $.command.register({ name: 'threads', description: 'Make this folder a project and this chat its coordinator: work runs in threads, shown in the Threads pane' })
    // a new conversation at the root of a project folder carries on as its coordinator: only when the app says it
    // has no parent. A thread, or a chat the app cannot place yet, is not (/threads makes the owner's chat one)
    const slug = r && r === e.cwd && (await isProject($, r)) ? ((await hasParent($)) === false ? base(r) : '')
      : (r ? e.cwd.slice(r.length) : '').match(/^\/projects\/([^/]+)/)?.[1]
    if (slug) { await update($, coord, () => slug); void $.ui.open({ id: THREADS, title: 'Threads' }) }
    return ran
  })

  // An open with no ask behind it waits undrawn in a narrow window; the owner's message is an ask, so the
  // coordinator's pane comes up with it, unless the owner closed it.
  on('prompt.submit', async ($, e, next) => {
    if ((await read($, coord)) && !(await read($, shut)) && !(await $.ui.panes()).some(x => x.id === THREADS && x.isPlaced))
      void $.ui.open({ id: THREADS, title: 'Threads' })
    return next(e)
  })
  on('ui.close', async ($, e, next) => {
    if (e.id === THREADS && e.origin.kind === 'person') await update($, shut, () => true)
    return next(e)
  })
  // Any chat becomes a coordinator, as a claude.ai project chat is: the pane, the thread cards, and the rule
  // that long work runs in threads.
  // /threads makes this conversation's folder a project (scripts/project.sh init: marker, board/, STATE.md,
  // DECISIONS.md when new; registered in <plugin data>/projects) and the conversation its coordinator.
  on('command.run', { command: 'threads' }, async $ => {
    const dir = await read($, here)
    if (!dir) return { text: 'This chat has no folder to make a project. Open a chat in the project folder and run /threads there.' }
    if (await isThread($)) return { text: 'This chat is a thread another chat started: run /threads in the project\'s own chat.' }
    // inside a workspace of the older layout the folder belongs to it: the chat only becomes a coordinator
    const ws = await findRoot($, dir)
    if (ws && !(await isProject($, ws))) {
      await $.store.set('root', ws)
      await update($, coord, () => base(dir)); await update($, shut, () => false)
      await $.ui.open({ id: THREADS, title: 'Threads' })
      return { text: 'This chat is now the coordinator. Threads pane opened.', context: [COORDINATOR] }
    }
    const run = await $.process.run(['sh', `${$.plugin.root}/scripts/project.sh`, 'init', dir], { timeoutMs: 15000 })
      .catch(x => ({ exitCode: 1, stdout: '', stderr: String((x as Error)?.message ?? x) }))
    if (run.exitCode !== 0) return { text: `Couldn't make ${dir} a project: ${(run.stderr || run.stdout).trim().slice(0, 300) || 'project.sh failed'}. Fix that, then run /threads again.` }
    const r = await findRoot($, dir)
    if (r) await $.store.set('root', r)
    await update($, coord, () => base(dir))
    await update($, shut, () => false)
    await $.ui.open({ id: THREADS, title: 'Threads' })
    return { text: `This chat is now the coordinator of ${base(dir)}. Threads pane opened.`, context: [COORDINATOR, panelAsk($.plugin.root, dir)] }
  })

  // In a project folder only the coordinator asks the owner or records the owner's OK; a thread it started runs in
  // the same folder, so the hooks' folder check passes it, and this stops it
  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e, next) => {
    const r = await root($)
    if (r && (await isProject($, r)) && (await isThread($)))
      return { deny: 'chief-of-staff: a thread does not ask the owner. Report the question to the coordinator, which asks the owner.' }
    return next(e)
  })
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const cmd = String((e as { command?: unknown }).command ?? '')
    const r = await root($), dir = await read($, here)
    if (r && ownerCommand(cmd) && (await isProject($, r)) && (await isThread($)))
      return { deny: 'chief-of-staff: a thread does not record the owner\'s OK or register projects. Report it to the coordinator.' }
    const ran = await next(e)
    // new-project ends with project.sh init: the conversation at the new project's root becomes its coordinator
    if (/project\.sh/.test(cmd) && dir && !(await read($, coord)) && (await findRoot($, dir)) === dir && (await isProject($, dir)) && !(await isThread($))) {
      await $.store.set('root', dir)
      await update($, coord, () => base(dir))
      void $.ui.open({ id: THREADS, title: 'Threads' })
    }
    return ran
  })

  // A coordinator's thread brief carries its specialist's lines, as an Agent brief does (protocol.sh), and opens
  // with the thread rules. A start with no brief (an offer card, a proposal started by id) has nothing to check.
  on('tool.call', { tool: /start_session$/ }, async ($, e, next) => {
    const brief = (e as { prompt?: unknown }).prompt
    if (typeof brief !== 'string' || !brief.trim() || !(await read($, coord))) return next(e)
    // the workspace's role cards, or the plugin's own (a project folder without specialists/)
    const r = await root($)
    const sp = r && (await $.fs.exists(`${r}/specialists`)) ? `${r}/specialists` : `${$.plugin.root}/templates/specialists`
    const cards = (await $.fs.exists(sp))
      ? (await $.fs.list(sp)).filter(x => x.kind === 'file' && x.name.endsWith('.md')).map(x => x.name.slice(0, -3))
      : undefined
    const gap = briefGaps(brief, cards)
    if (gap) return { deny: `chief-of-staff: a thread starts with its specialist. Add to the brief ${gap}, then start it again.` }
    return next({ ...e, prompt: brief.includes(THREAD_RULES) ? brief : `${THREAD_RULES}\n\n${brief}` } as typeof e)
  })

  // a thread started, a message sent, a turn ended: the Threads pane reads the app's list again
  on('turn.complete', async ($, e, next) => { const ran = await next(e); $.ui.invalidate('ui.render'); return ran })

  on('ui.render', { component: 'Pane', requestId: THREADS }, async ($, e) => {
    const { Box, Text, Button, Markdown, Svg: S } = $.ui.resolve(e) as ReturnType<typeof $.ui.resolve> & { Svg?: any }
    const Svg = e.surface === 'terminal' ? undefined : S   // the terminal has no Svg
    const icon = (k: Thread['state'] | 'waiting') => Svg
      ? <Svg source={ICON[k]} alt={k === 'waiting' ? 'Waiting on you' : MARK[k].label} width={16} height={16} />
      : <Text color={k === 'waiting' ? 'warning' : MARK[k].color}>{k === 'waiting' ? '●' : MARK[k].mark}</Text>
    const slug = await read($, coord), r = await root($)
    const [ts, asks, now] = await Promise.all([threads($).catch(() => [] as Thread[]), r && slug ? waitingOnOwner($, r, slug) : [], $.clock.now()])
    // under the threads, the project's memory and instructions, as the Projects side panel shows them
    const p = r && slug ? await project($, r, slug) : undefined
    const dc = p ? decisions(await $.fs.read(`${p.dir}/DECISIONS.md`).catch(() => '')).slice(-5) : []
    const instr = p ? (await $.fs.read(`${p.dir}/CLAUDE.md`).catch(() => '')).split('\n').slice(0, 30).join('\n') : ''
    const err = await read($, error)
    const show = async (t: Thread) => {
      await update($, error, () => '')
      try {
        const res = await $.mcp.call('ccd_window', 'open_session_in', { session_id: t.id, target: 'split' })
        if (res.isError || /^Refused/.test(text(res))) throw new Error(text(res))
      } catch (x) { await update($, error, () => `Couldn't show "${t.title}": ${String((x as Error)?.message ?? x).slice(0, 120)}`) }
    }
    // a row as claude.ai Projects draws it: the state's mark, the title, then when and the pull request
    // laid out as the claude.ai Projects side panel: "Label · n" headers, one row per thread with its mark,
    // title and age on the right, the pull request under it
    const head = (label: string, n: number) => <Text color="subtle">{label} · {n}</Text>
    const row = (t: Thread) => (
      <Box key={`row-${t.id}`} flexDirection="column">
        <Box flexDirection="row" justifyContent="space-between" gap={1}>
          {/* the mark sits outside the Button: a desktop draws a Button natively, in its own text color */}
          <Box flexDirection="row" gap={1}>
            {icon(t.state)}
            <Button key={t.id} plain onPress={() => void show(t)}>{t.title}</Button>
          </Box>
          <Text dimColor>{ago(t.at, now)}</Text>
        </Box>
        {t.pr ? <Text dimColor>  PR #{t.pr}</Text> : null}
      </Box>)
    const by = (s: Thread['state']) => ts.filter(t => t.state === s).sort((a, b) => b.at - a.at)
    const group = (st: Thread['state']) => by(st).length > 0 && (
      <Box flexDirection="column" gap={1}>{head(MARK[st].label, by(st).length)}{by(st).map(row)}</Box>)
    return (
      <Box flexDirection="column" gap={2}>
        <Box flexDirection="row" justifyContent="space-between">
          <Text dimColor>{slug || 'Threads'}</Text>
          <Button key="refresh" plain dimColor onPress={() => $.ui.invalidate('ui.render')}>Refresh</Button>
        </Box>
        <Box flexDirection="column" gap={1}>
          {head('Waiting on you', asks.length)}
          {asks.map(q => <Box flexDirection="row" gap={1}>{icon('waiting')}<Text>{q.slice(0, 200)}</Text></Box>)}
        </Box>
        {group('review')}
        {group('working')}
        {group('idle')}
        <Box flexDirection="column" gap={1}>
          {head('Resolved', by('resolved').length)}
          {by('resolved').length === 0
            ? <Box borderStyle="round" borderColor="subtle" paddingX={1} justifyContent="center"><Text dimColor>Completed threads.</Text></Box>
            : by('resolved').map(row)}
        </Box>
        {ts.length === 0 && <Text dimColor>No threads yet.</Text>}
        {err && <Text color="error">{err}</Text>}
        {p && <Box flexDirection="column">
          {head('Memory', dc.length)}
          <Text dimColor>{p.status} · updated {p.updated || '-'}</Text>
          {p.next && <Text>next: {p.next}</Text>}
          {dc.map(d => <Text dimColor>- {d}</Text>)}
        </Box>}
        {p && instr && <Box flexDirection="column"><Text color="subtle">Instructions</Text><Markdown text={instr} /></Box>}
      </Box>)
  })

  // The coordinator's start_session row draws as a thread card, as claude.ai Projects puts one under the
  // message: the thread's title, its state now and a press that opens it. ctrl+o shows the engine's row.
  on('ui.render', { component: 'ToolUse' }, async ($, e, next) => {
    const p = e.props
    if (!/start_session$/.test(p.tool) || p.isExpanded || !(await read($, coord))) return next(e)
    const { Box, Text, Button, Svg: S } = $.ui.resolve(e) as ReturnType<typeof $.ui.resolve> & { Svg?: any }
    const Svg = e.surface === 'terminal' ? undefined : S
    const input = (p.input ?? {}) as { title?: string; prompt?: string }
    const id = p.isRunning || p.isErrored ? '' : startedId(p.output)
    const t = id ? (await threads($).catch(() => [] as Thread[])).find(x => x.id === id) : undefined
    const st = t ? MARK[t.state] : undefined
    const brief = String(input.prompt ?? '').replace(/\s+/g, ' ').slice(0, 140)
    const open = async () => {
      const res = await $.mcp.call('ccd_window', 'open_session_in', { session_id: id, target: 'split' }).catch(() => undefined)
      if (!res || res.isError || /^Refused/.test(text(res))) await update($, error, () => `Couldn't show "${t?.title ?? 'the thread'}". Open it from the Threads pane.`)
    }
    return (
      <Box flexDirection="column" borderStyle="round" borderColor="subtle" paddingX={1}>
        <Box flexDirection="row" gap={1}>
          {t && Svg ? <Svg source={ICON[t.state]} alt={MARK[t.state].label} width={16} height={16} /> : st ? <Text color={st.color}>{st.mark}</Text> : <Text dimColor>○</Text>}
          <Text><Text bold>{t?.title || input.title || 'Thread'}</Text> <Text dimColor>· {p.isRunning ? 'Starting' : p.isErrored ? 'Not started' : st ? st.label : id ? 'Thread' : 'Proposed'}</Text></Text>
        </Box>
        {brief && <Text dimColor>{brief}</Text>}
        {id && <Button key={`open-${p.tool_use_id}`} plain onPress={() => void open()}>Open thread</Button>}
      </Box>)
  })
}
