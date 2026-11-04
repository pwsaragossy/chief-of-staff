import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

// The app's Projects tab, local: a pane that lists the workspace's projects, shows each one's
// instructions, memory and chats (the desktop app's session list), and asks for a new local chat.
const PANE = 'cos-projects'
const view = atom({ plugin: 'chief-of-staff', key: 'view' } as const, '', { shape: 'view-1' })
const busy = atom({ plugin: 'chief-of-staff', key: 'busy' } as const, '', { shape: 'busy-1' })
const error = atom({ plugin: 'chief-of-staff', key: 'error' } as const, '', { shape: 'error-1' })
const DONE = /^(done|delivered|closed|cancelled|dropped|paused)$/

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

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const ran = await next(e)
    const r = await findRoot($, e.cwd)
    if (r) await $.store.set('root', r)
    await $.command.register({ name: 'projects', description: 'Show the workspace projects and open their chats', argumentHint: '[workspace folder]' })
    if (r && /\/central(\/|$)/.test(e.cwd.slice(r.length))) void $.ui.open({ id: PANE, title: 'Projects' })
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

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button, Link, Markdown } = $.ui.resolve(e)
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
        {cs.map(c => c.link
          ? <Link key={c.id} href={c.link}>{c.title} · {c.at}</Link>
          : <Text>{c.title} · {c.at}</Text>)}
        <Text bold>Instructions</Text>
        <Markdown text={instr} />
      </Box>)
  })
}
