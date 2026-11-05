import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

// The app's Projects tab, local: a pane that lists the workspace's projects, shows each one's
// instructions, memory and chats (the desktop app's session list), and asks for a new local chat.
const PANE = 'cos-projects'
const view = atom({ plugin: 'chief-of-staff', key: 'view' } as const, '', { shape: 'view-1' })
const busy = atom({ plugin: 'chief-of-staff', key: 'busy' } as const, '', { shape: 'busy-1' })
const error = atom({ plugin: 'chief-of-staff', key: 'error' } as const, '', { shape: 'error-1' })
const DONE = /^(done|delivered|closed|cancelled|dropped|paused)$/
// A project's coordinator (a session in projects/<slug>/) gets the Threads pane: the sessions it started.
const THREADS = 'cos-threads'
const coord = atom({ plugin: 'chief-of-staff', key: 'coord' } as const, '', { shape: 'coord-1' })

type Project = { slug: string; dir: string; status: string; updated: string; next: string; goal: string }
type Chat = { id: string; title: string; at: string; link?: string }

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

async function projects($: EngineInterface, r: string): Promise<Project[]> {
  if (!r || !(await $.fs.exists(`${r}/projects`))) return []
  const out: Project[] = []
  for (const e of await $.fs.list(`${r}/projects`)) {
    if (e.kind !== 'dir') continue
    const dir = `${r}/projects/${e.name}`
    const s = await $.fs.read(`${dir}/STATE.md`).catch(() => '')
    const c = await $.fs.read(`${dir}/CLAUDE.md`).catch(() => '')
    const goal = (c.match(/handles \*\*one thing only\*\*: (.*)/)?.[1] ?? '').trim()
    out.push({ slug: e.name, dir, status: fm(s, 'status') || 'new', updated: fm(s, 'updated'), next: fm(s, 'next'), goal })
  }
  return out.sort((a, b) => b.updated.localeCompare(a.updated))
}

async function chats($: EngineInterface, dir: string, slug: string): Promise<Chat[]> {
  const r = await $.mcp.call('ccd_session_mgmt', 'list_sessions', { limit: 100 })
  let rows: any[] = []
  try { rows = JSON.parse(text(r)) } catch { return [] }
  return rows
    .filter(s => s.cwd === dir || String(s.cwd ?? '').startsWith(dir + '/') || s.group?.name === slug)
    .map(s => ({ id: s.sessionId, title: s.title || 'Untitled', at: String(s.lastActivityAt ?? '').slice(0, 16).replace('T', ' '), link: s.link }))
}

// The app starts a session only on a request the owner sends: the press writes that request in the prompt
// box as a draft, and the owner sends it (or edits it, or clears it).
export const newChatDraft = (p: Project): string =>
  `Open a new chat in the project "${p.slug}": a local session in ${p.dir} (no worktree), ` +
  `detached to top level and filed in the sidebar group "${p.slug}", shown in the main pane. Its first step: the arrival steps in CLAUDE.md.`

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
  const out: string[] = []
  for (const e of await $.fs.list(`${r}/board`).catch(() => [])) {
    if (e.kind !== 'file' || !e.name.endsWith('.md')) continue
    const c = await $.fs.read(`${r}/board/${e.name}`).catch(() => '')
    if (fm(c, 'project') === slug && fm(c, 'status') === 'waiting-owner') out.push(...ownerQuestions(c))
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

export const ago = (ms: number, now: number): string => {
  const m = Math.max(0, Math.round((now - ms) / 60000))
  return m < 60 ? `${m}m` : m < 1440 ? `${Math.round(m / 60)}h` : `${Math.round(m / 1440)}d`
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const ran = await next(e)
    const r = await findRoot($, e.cwd)
    if (r) await $.store.set('root', r)
    await $.command.register({ name: 'projects', description: 'Show the workspace projects and open their chats', argumentHint: '[workspace folder]' })
    const rel = r ? e.cwd.slice(r.length) : ''
    if (r && /^\/central(\/|$)/.test(rel)) void $.ui.open({ id: PANE, title: 'Projects' })
    const slug = rel.match(/^\/projects\/([^/]+)/)?.[1]
    if (slug) { await update($, coord, () => slug); void $.ui.open({ id: THREADS, title: 'Threads' }) }
    return ran
  })

  on('command.run', { command: 'projects' }, async ($, e) => {
    let arg = e.args.trim()
    if (arg.startsWith('~')) arg = ((await $.env.get('HOME')) ?? '') + arg.slice(1)
    if (arg) {
      if (!arg.startsWith('/')) return { text: `Give the workspace folder as a full path, like ~/chief-of-staff.` }
      const r = await findRoot($, arg)
      if (!r) return { text: `No chief-of-staff workspace at ${arg}.` }
      await $.store.set('root', r)
    }
    await $.ui.open({ id: PANE, title: 'Projects' })
    return { text: 'Projects pane opened.' }
  })

  // a thread started, a message sent, a turn ended: the Threads pane reads the app's list again
  on('turn.complete', async ($, e, next) => { const ran = await next(e); $.ui.invalidate('ui.render'); return ran })

  on('ui.render', { component: 'Pane', requestId: THREADS }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const slug = await read($, coord), r = await root($)
    const [ts, asks, now] = await Promise.all([threads($).catch(() => [] as Thread[]), r && slug ? waitingOnOwner($, r, slug) : [], $.clock.now()])
    const err = await read($, error)
    const show = async (t: Thread) => {
      await update($, error, () => '')
      try {
        const res = await $.mcp.call('ccd_window', 'open_session_in', { session_id: t.id, target: 'focus' })
        if (res.isError || /^Refused/.test(text(res))) throw new Error(text(res))
      } catch (x) { await update($, error, () => `Couldn't show "${t.title}": ${String((x as Error)?.message ?? x).slice(0, 120)}`) }
    }
    const group = (label: string, list: Thread[]) => (
      <Box flexDirection="column">
        <Text dimColor>{label} · {list.length}</Text>
        {list.map(t => (
          <Button key={t.id} plain onPress={() => void show(t)}>{t.title} <Text dimColor>{t.pr ? `· PR #${t.pr} ` : ''}· {ago(t.at, now)}</Text></Button>))}
      </Box>)
    const by = (s: Thread['state']) => ts.filter(t => t.state === s).sort((a, b) => b.at - a.at)
    return (
      <Box flexDirection="column" gap={1}>
        <Box flexDirection="row" gap={1}>
          <Text bold>{slug || 'Threads'}</Text>
          <Button key="refresh" dimColor onPress={() => $.ui.invalidate('ui.render')}>Refresh</Button>
        </Box>
        {by('review').length > 0 && group('Ready for review', by('review'))}
        <Box flexDirection="column">
          <Text dimColor>Waiting on you · {asks.length}</Text>
          {asks.length === 0 && <Text dimColor>Decisions show here.</Text>}
          {asks.map(q => <Text>- {q.slice(0, 200)}</Text>)}
        </Box>
        {group('Working', by('working'))}
        {group('Idle', by('idle'))}
        {by('resolved').length > 0 && group('Resolved', by('resolved'))}
        {ts.length === 0 && <Text dimColor>No threads yet. Ask for work here; long tasks become threads.</Text>}
        {err && <Text color="error">{err}</Text>}
      </Box>)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button, Markdown } = $.ui.resolve(e)
    const r = await root($)
    if (!r) return (
      <Box flexDirection="column"><Text bold>No workspace</Text>
        <Text dimColor>Open a chat in your chief-of-staff folder once.</Text></Box>)
    const list = await projects($, r)
    const sel = await read($, view)
    const p = list.find(x => x.slug === sel)

    if (!p) {
      const open = list.filter(x => !DONE.test(x.status)), done = list.filter(x => DONE.test(x.status))
      return (
        <Box flexDirection="column" gap={1}>
          {list.length === 0 && <Box flexDirection="column"><Text bold>No projects</Text><Text dimColor>Ask central for one.</Text></Box>}
          {open.map(x => (
            <Button key={`p-${x.slug}`} plain onPress={() => void update($, view, () => x.slug)}>
              {x.slug} <Text dimColor>· {x.status}{x.next ? ` · next: ${x.next.slice(0, 80)}` : ''}</Text>
            </Button>))}
          {done.length > 0 && <Text dimColor>Done ({done.length}): {done.map(x => x.slug).join(', ')}</Text>}
        </Box>)
    }

    const dc = decisions(await $.fs.read(`${p.dir}/DECISIONS.md`).catch(() => '')).slice(-5)
    const cs = await chats($, p.dir, p.slug).catch(() => [] as Chat[])
    const instr = (await $.fs.read(`${p.dir}/CLAUDE.md`).catch(() => '')).split('\n').slice(0, 30).join('\n')
    const b = await read($, busy), err = await read($, error)
    const start = async () => {
      if (await read($, busy)) return
      await update($, error, () => '')
      await update($, busy, () => p.slug)
      try {
        const f = await $.prompt.fill({ text: newChatDraft(p) })
        if (!f.isFilled) throw new Error('the prompt box is not available')
      }
      catch (x) { await update($, error, () => `Couldn't write the request: ${String((x as Error)?.message ?? x).slice(0, 160)}. Type it yourself: open a new chat in ${p.slug}.`) }
      finally { await update($, busy, () => '') }
    }
    // A chat opens in the main pane through the app's window tool, which serves only chats this
    // conversation started (the ones New chat asked for here); any other is found in the sidebar group.
    const show = async (c: Chat) => {
      await update($, error, () => '')
      try {
        const r = await $.mcp.call('ccd_window', 'open_session_in', { session_id: c.id, target: 'focus' })
        if (r.isError || /^Refused/.test(text(r))) throw new Error(text(r))
      } catch (x) {
        await update($, error, () => `Couldn't show "${c.title}" here: ${String((x as Error)?.message ?? x).slice(0, 120)}. Open it from the sidebar group ${p.slug}.`)
      }
    }
    return (
      <Box flexDirection="column" gap={1}>
        <Box flexDirection="row" gap={1}>
          <Button key="back" dimColor onPress={() => void update($, view, () => '')}>Back</Button>
          <Text bold>{p.slug}</Text>
        </Box>
        {p.goal && <Text>{p.goal}</Text>}
        <Button key="new" variant="primary" onPress={() => void start()}>{b ? 'Writing…' : 'New chat'}</Button>
        <Text dimColor>Writes the request below; press Enter to send it.</Text>
        {err && <Text color="error">{err}</Text>}
        <Text bold>Memory</Text>
        <Text dimColor>{p.status} · updated {p.updated || '-'}</Text>
        {p.next && <Text>next: {p.next}</Text>}
        {dc.map(d => <Text dimColor>- {d}</Text>)}
        <Text bold>Chats</Text>
        {cs.length === 0 && <Text dimColor>No chats yet</Text>}
        {cs.map(c => (
          <Button key={c.id} plain onPress={() => void show(c)}>{c.title} <Text dimColor>· {c.at}</Text></Button>))}
        <Text bold>Instructions</Text>
        <Markdown text={instr} />
      </Box>)
  })
}
