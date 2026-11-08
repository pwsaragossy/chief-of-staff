import { expect, test } from 'claude-code/testing'
import { briefGaps, COORDINATOR, decisions, fm, ownerCommand, panelAsk, THREAD_RULES } from '../hooks/projects'


const FILES: Record<string, string> = {
  '/ws/projects/dock/STATE.md': '---\nstatus: in-progress\nupdated: 2026-11-04\nnext: spike the panel\n---\n# Dock',
  '/ws/projects/dock/DECISIONS.md': '- 2026-11-04 01:15 | Waitlist only | Pedro | -\n- 2026-11-04 01:16 | old | Pedro | -\n- 2026-11-04 01:17 | new one | Pedro | replaces: 2026-11-04 01:16\n',
}

test('front matter and decisions read like lib.sh', () => {
  expect(fm(FILES['/ws/projects/dock/STATE.md']!, 'next')).toBe('spike the panel')
  expect(decisions(FILES['/ws/projects/dock/DECISIONS.md']!)).toEqual(['Waitlist only (Pedro)', 'new one (Pedro)'])
})

const THREADS = {
  plugin: 'chief-of-staff', component: 'Pane', requestId: 'cos-threads',
  props: { title: 'Threads', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} },
} as const

test('the Threads pane groups the threads this conversation started and lists the card questions', async ($, on) => {
  const calls: { tool: string; args: any }[] = []
  const card = '---\nproject: dock\nstatus: waiting-owner\n---\n# Dock\n\n## For the owner to decide (central asks, all at once)\n- (asked 2026-11-04 01:33 -0300) Approve target and check? Recommend: yes.\n\n## Decided\n- 2026-11-04: old\n'
  const opened: string[] = []
  on('store.get', () => ({ value: '/ws' }))
  on('store.set', () => ({ value: undefined }))
  on('fs.exists', (_: any, e: any) => ({ value: ['/ws/.chief-of-staff', '/ws/projects'].includes(e.path) }))
  on('command.register', () => ({ value: { command: 'projects' } }))
  on('ui.open', (_: any, e: any) => { opened.push(e.id); return { value: { isPlaced: true } } })
  on('session.start', (_: any, e: any) => ({ cwd: e.cwd }))
  on('clock.now', () => ({ value: Date.parse('2026-11-05T12:00:00Z') }))
  const files: Record<string, string> = {
    '/ws/board/Dock.md': card,
    '/ws/projects/dock/STATE.md': '---\nstatus: active\nupdated: 2026-11-05\nnext: ship v1\n---\n',
    '/ws/projects/dock/DECISIONS.md': '- 2026-11-04 10:00 | Local only | owner | replaces: -\n',
    '/ws/projects/dock/CLAUDE.md': '# Dock\nKeep the dock fast.\n',
  }
  on('fs.list', (_: any, e: any) => ({ value: e.path === '/ws/projects'
    ? [{ name: 'dock', kind: 'dir', size: 0, mtimeMs: 0, isLink: false }]
    : [{ name: 'Dock.md', kind: 'file', size: 0, mtimeMs: 0, isLink: false }] }))
  on('fs.read', (_: any, e: any) => (e.path in files ? { value: files[e.path] } : { deny: 'ENOENT' }))
  on('mcp.call', (_: any, e: any) => {
    calls.push({ tool: `${e.server}.${e.tool}`, args: e.args })
    const t = (text: string) => ({ value: { content: [{ type: 'text', text }], isError: false } })
    if (e.tool === 'get_session') return t(JSON.stringify({ sessionId: 'local_me' }))
    if (e.tool === 'list_sessions') return t(JSON.stringify([
      { sessionId: 'local_a', title: 'Build slice 1', startedBy: 'local_me', isRunning: true, lastActivityAt: '2026-11-05T11:39:00Z' },
      { sessionId: 'local_b', title: 'Spec the app', startedBy: 'local_me', isRunning: false, lastActivityAt: '2026-10-31T12:00:00Z' },
      { sessionId: 'local_c', title: 'Old', startedBy: 'local_me', isArchived: true, lastActivityAt: '2026-10-30T12:00:00Z' },
      { sessionId: 'local_r', title: 'Fix login', startedBy: 'local_me', isRunning: false, prState: 'OPEN', prNumber: 12, lastActivityAt: '2026-11-05T10:00:00Z' },
      { sessionId: 'local_o', title: 'Stale', startedBy: 'local_me', isRunning: false, lastActivityAt: '2026-10-20T12:00:00Z' },
      { sessionId: 'local_m', title: 'Merged', startedBy: 'local_me', isRunning: false, prState: 'MERGED', lastActivityAt: '2026-11-05T09:00:00Z' },
      { sessionId: 'local_x', title: 'Not mine', startedBy: 'local_other', isRunning: true },
    ]))
    return t('Opened')
  })
  on('prompt.fill', (_: any, e: any) => { calls.push({ tool: 'prompt.fill', args: e }); return { isFilled: true } })
  await $.session.start({ cwd: '/ws/projects/dock', surface: 'desktop', isInteractive: true })
  expect(opened).toEqual(['cos-threads'])
  const ui = await $.ui.mount({ ...THREADS, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /^dock$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Approve target and check\? Recommend: yes\.$/ })).toBeDefined()
  expect((await ui.find({ key: 'local_a' }))?.text).toMatch(/Build slice 1/)
  expect([...new Set((await ui.findAll({ type: 'Svg' })).map(x => x.props.alt))].sort()).toEqual(['Idle', 'Ready for review', 'Resolved', 'Waiting on you', 'Working'])
  expect(await ui.find({ type: 'Text', text: /^21m$/ })).toBeDefined()
  expect((await ui.find({ key: 'local_b' }))?.text).toMatch(/Spec the app/)
  expect((await ui.find({ key: 'local_r' }))?.text).toMatch(/Fix login/)
  expect(await ui.find({ type: 'Text', text: /^ +PR #12$/ })).toBeDefined()
  const order = (await ui.findAll({ type: 'Text' })).map(x => x.text).filter(t => /^[A-Z][a-z ]+ · \d+$/.test(t))
  expect(order).toEqual(['Waiting on you · 1', 'Ready for review · 1', 'Working · 1', 'Idle · 1', 'Resolved · 3', 'Memory · 1'])
  expect(await ui.find({ key: 'local_x' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'next: ship v1' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Local only \(owner\)/ })).toBeDefined()
  expect(await ui.find({ type: 'Markdown' })).toBeDefined()
  await ui.press({ key: 'local_a' })
  expect(calls.find(c => c.tool === 'ccd_window.open_session_in')?.args).toEqual({ session_id: 'local_a', target: 'split' })
  await ui.unmount()
})

test('the coordinator start_session row draws as a thread card that opens the thread', async ($, on) => {
  const calls: { tool: string; args: any }[] = []
  on('clock.now', () => ({ value: Date.parse('2026-11-05T12:00:00Z') }))
  on('store.get', () => ({ value: '/ws' }))
  on('store.set', () => ({ value: undefined }))
  on('fs.exists', (_: any, e: any) => ({ value: e.path === '/ws/.chief-of-staff' }))
  on('fs.list', () => ({ value: [] }))
  on('command.register', () => ({ value: { command: 'projects' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_: any, e: any) => ({ cwd: e.cwd }))
  on('mcp.call', (_: any, e: any) => {
    calls.push({ tool: `${e.server}.${e.tool}`, args: e.args })
    const t = (text: string) => ({ value: { content: [{ type: 'text', text }], isError: false } })
    if (e.tool === 'get_session') return t(JSON.stringify({ sessionId: 'local_me' }))
    if (e.tool === 'list_sessions') return t(JSON.stringify([{ sessionId: 'local_0a1b2c3d-1111', title: 'Daily build', startedBy: 'local_me', isRunning: true, lastActivityAt: '2026-11-05T11:59:00Z' }]))
    return t('Opened')
  })
  await $.session.start({ cwd: '/ws/projects/dock', surface: 'desktop', isInteractive: true })
  const row = (props: any) => $.ui.mount({ plugin: 'chief-of-staff', surface: 'desktop', component: 'ToolUse', requestId: props.tool_use_id, props } as any)
  const base = { tool_use_id: 'tu1', tool: 'mcp__ccd_session__start_session', input: { title: 'Daily build', prompt: 'Build the daily-use version.' }, isErrored: false, isInterrupted: false }
  const ui = await row({ ...base, isRunning: false, output: 'Started session local_0a1b2c3d-1111 (df-daily-build).' })
  expect(await ui.find({ type: 'Text', text: /^Daily build · Working$/ })).toBeDefined()
  expect((await ui.findAll({ type: 'Svg' })).map(x => x.props.alt)).toEqual(['Working'])
  expect(await ui.find({ type: 'Text', text: /^Build the daily-use version\.$/ })).toBeDefined()
  await ui.press({ key: 'open-tu1' })
  expect(calls.find(c => c.tool === 'ccd_window.open_session_in')?.args).toEqual({ session_id: 'local_0a1b2c3d-1111', target: 'split' })
  await ui.unmount()
  const starting = await row({ ...base, tool_use_id: 'tu2', isRunning: true })
  expect(await starting.find({ type: 'Text', text: /Daily build · Starting/ })).toBeDefined()
  expect(await starting.find({ key: 'open-tu2' })).toBeUndefined()
  await starting.unmount()
})

test('the coordinator pane comes up with the owner message', async ($, on) => {
  const opened: string[] = []
  on('store.get', () => ({ value: '/ws' }))
  on('store.set', () => ({ value: undefined }))
  on('fs.exists', (_: any, e: any) => ({ value: e.path === '/ws/.chief-of-staff' }))
  on('command.register', () => ({ value: { command: 'x' } }))
  on('ui.open', (_: any, e: any) => { opened.push(e.id); return { value: { isPlaced: false, reason: 'narrow' } } })
  on('ui.panes', () => ({ value: [] }))
  on('session.start', (_: any, e: any) => ({ cwd: e.cwd }))
  on('prompt.submit', (_: any, e: any) => e)
  await $.session.start({ cwd: '/ws/projects/dock', surface: 'desktop', isInteractive: true })
  await $.prompt.submit({ text: 'hi' } as any)
  expect(opened).toEqual(['cos-threads', 'cos-threads'])
})

// a project folder at /p/Alpha: marker kind: project, its own board and STATE.md
function folder(on: any, opts: { thread?: boolean; marker?: boolean; runs?: { argv: readonly string[] }[]; initFails?: boolean; registered?: string[]; opened?: string[] } = {}) {
  let marker = opts.marker ?? true
  const files = (): Record<string, string> => ({
    ...(marker ? { '/p/Alpha/.chief-of-staff': 'chief-of-staff project v0.1\nkind: project\n' } : {}),
    '/p/Alpha/STATE.md': '---\nstatus: in-progress\nupdated: 2026-11-08\nnext: first slice\n---\n',
    '/p/Alpha/DECISIONS.md': '- 2026-11-08 10:00 | Name is Alpha | Pedro | replaces: -\n',
    '/p/Alpha/board/Q.md': '---\nstatus: waiting-owner\n---\n# Q\n\n## For the owner to decide\n- Ship it? Recommended: yes\n',
  })
  let rootv = ''
  on('store.get', () => ({ value: rootv }))
  on('store.set', (_: any, e: any) => { rootv = e.value; return { value: undefined } })
  on('fs.exists', (_: any, e: any) => ({ value: e.path in files() }))
  on('fs.read', (_: any, e: any) => (e.path in files() ? { value: files()[e.path] } : { deny: 'ENOENT' }))
  on('fs.list', (_: any, e: any) => ({ value: e.path === '/p/Alpha/board' ? [{ name: 'Q.md', kind: 'file', size: 0, mtimeMs: 0, isLink: false }] : [] }))
  on('command.register', (_: any, e: any) => { (opts.registered ?? []).push(e.name); return { value: { command: e.name } } })
  on('ui.open', (_: any, e: any) => { (opts.opened ?? []).push(e.id); return { value: { isPlaced: true } } })
  on('session.start', (_: any, e: any) => ({ cwd: e.cwd }))
  on('clock.now', () => ({ value: Date.parse('2026-11-08T12:00:00Z') }))
  on('process.run', (_: any, e: any) => {
    opts.runs?.push(e); if (!opts.initFails) marker = true
    return { value: opts.initFails ? { exitCode: 1, stdout: '', stderr: 'project.sh: /p/Alpha is not a folder' } : { exitCode: 0, stdout: 'Project: /p/Alpha (new)', stderr: '' } }
  })
  on('mcp.call', (_: any, e: any) => {
    const t = (text: string) => ({ value: { content: [{ type: 'text', text }], isError: false } })
    if (e.tool === 'get_session') return t(JSON.stringify(opts.thread ? { sessionId: 'local_t', parentSessionId: 'local_me', detached: false } : { sessionId: 'local_me' }))
    return t('[]')
  })
  return { make: () => { marker = true } }
}

test('/threads makes the folder a project, the chat its coordinator, and asks for the web panel', async ($, on) => {
  const opened: string[] = [], runs: { argv: readonly string[] }[] = [], registered: string[] = []
  folder(on, { marker: false, runs, opened, registered })
  await $.session.start({ cwd: '/p/Alpha', surface: 'desktop', isInteractive: true })
  expect(opened).toEqual([])
  expect(registered).toEqual(['threads'])   // the Projects pane and /projects are gone
  const r: any = await $.command.run({ command: 'threads', args: '' } as any)
  expect(runs.map(x => x.argv.slice(2))).toEqual([['init', '/p/Alpha']])
  expect(String(runs[0]!.argv[1])).toMatch(/\/scripts\/project\.sh$/)
  expect(opened).toEqual(['cos-threads'])
  expect(r.text).toMatch(/coordinator of Alpha/)
  expect(String(r.context)).toMatch(/start_session/)
  expect(String(r.context)).toMatch(/panel\.py' '\/p\/Alpha'/)
  const ui = await $.ui.mount({ ...THREADS, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /Ship it\? Recommended: yes/ })).toBeDefined()   // every card of the folder's board
  expect(await ui.find({ type: 'Text', text: 'next: first slice' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Name is Alpha \(Pedro\)/ })).toBeDefined()
  await ui.unmount()
})

test('/threads that cannot make the project says why and opens nothing', async ($, on) => {
  const opened: string[] = []
  folder(on, { marker: false, initFails: true, opened, runs: [] })
  await $.session.start({ cwd: '/p/Alpha', surface: 'desktop', isInteractive: true })
  const r: any = await $.command.run({ command: 'threads', args: '' } as any)
  expect(r.text).toMatch(/Couldn't make \/p\/Alpha a project: project\.sh: \/p\/Alpha is not a folder/)
  expect(opened).toEqual([])
})

test('/threads inside a workspace of the older layout makes the chat its coordinator and registers nothing', async ($, on) => {
  const opened: string[] = [], runs: unknown[] = []
  const files: Record<string, string> = { '/w/.chief-of-staff': 'chief-of-staff workspace v0.1\n' }
  on('store.get', () => ({ value: '' })); on('store.set', () => ({ value: undefined }))
  on('fs.exists', (_: any, e: any) => ({ value: e.path in files }))
  on('fs.read', (_: any, e: any) => (e.path in files ? { value: files[e.path] } : { deny: 'ENOENT' }))
  on('fs.list', () => ({ value: [] }))
  on('command.register', (_: any, e: any) => ({ value: { command: e.name } }))
  on('ui.open', (_: any, e: any) => { opened.push(e.id); return { value: { isPlaced: true } } })
  on('session.start', (_: any, e: any) => ({ cwd: e.cwd }))
  on('process.run', (_: any, e: any) => { runs.push(e); return { value: { exitCode: 1, stdout: '', stderr: 'inside a workspace' } } })
  on('mcp.call', () => ({ value: { content: [{ type: 'text', text: JSON.stringify({ sessionId: 'local_me' }) }], isError: false } }))
  await $.session.start({ cwd: '/w/notes', surface: 'desktop', isInteractive: true })
  const r: any = await $.command.run({ command: 'threads', args: '' } as any)
  expect(runs).toEqual([])
  expect(r.text).toMatch(/now the coordinator/)
  expect(opened).toEqual(['cos-threads'])
})

test('a new chat at a project root carries on as its coordinator; a thread there does not', async ($, on) => {
  const opened: string[] = []
  folder(on, { opened })
  await $.session.start({ cwd: '/p/Alpha', surface: 'desktop', isInteractive: true })
  expect(opened).toEqual(['cos-threads'])
})

test('a thread in a project folder does not ask the owner nor record the owner OK', async ($, on) => {
  const opened: string[] = [], ran: any[] = []
  folder(on, { thread: true, opened })
  on('tool.call', (_: any, e: any) => { ran.push(e); return { result: 'ok' } })
  await $.session.start({ cwd: '/p/Alpha', surface: 'desktop', isInteractive: true })
  expect(opened).toEqual([])
  expect(String(((await $.tool.call({ tool: 'AskUserQuestion', questions: [] } as any)) as any).deny)).toMatch(/does not ask the owner/)
  expect(String(((await $.tool.call({ tool: 'Bash', command: 'sh /x/track.sh ok /p/Alpha scope yes' } as any)) as any).deny)).toMatch(/owner.s OK/)
  expect(String(((await $.tool.call({ tool: 'Bash', command: 'sh /x/project.sh init /p/Alpha/.claude/worktrees/t' } as any)) as any).deny)).toMatch(/register projects/)
  await $.tool.call({ tool: 'Bash', command: 'sh /x/track.sh check /p/Alpha' } as any)
  expect(ran.map(x => x.command)).toEqual(['sh /x/track.sh check /p/Alpha'])
})

test('the coordinator itself asks and records the OK', async ($, on) => {
  const ran: any[] = []
  folder(on, {})
  on('tool.call', (_: any, e: any) => { ran.push(e.tool); return { result: 'ok' } })
  await $.session.start({ cwd: '/p/Alpha', surface: 'desktop', isInteractive: true })
  await $.tool.call({ tool: 'AskUserQuestion', questions: [] } as any)
  await $.tool.call({ tool: 'Bash', command: 'sh /x/track.sh ok /p/Alpha scope yes' } as any)
  expect(ran).toEqual(['AskUserQuestion', 'Bash'])
})

test('new-project ending in project.sh init makes the chat the coordinator', async ($, on) => {
  const opened: string[] = []
  const f = folder(on, { marker: false, opened, runs: [] })
  let made = false
  on('tool.call', () => { made = true; f.make(); return { result: 'Project: /p/Alpha (new)' } })
  await $.session.start({ cwd: '/p/Alpha', surface: 'desktop', isInteractive: true })
  expect(opened).toEqual([])
  await $.tool.call({ tool: 'Bash', command: 'sh "/x/scripts/project.sh" init /p/Alpha' } as any)
  expect(made).toBe(true)
  expect(opened).toEqual(['cos-threads'])
})

test('ownerCommand names the OK and the registration, not other track commands', () => {
  expect(ownerCommand('sh track.sh ok p scope yes')).toBe(true)
  expect(ownerCommand('T=track.sh; sh "$T" ok p x')).toBe(true)
  expect(ownerCommand('sh project.sh init /x')).toBe(true)
  expect(ownerCommand('sh track.sh check /p')).toBe(false)
  expect(ownerCommand('sh project.sh list')).toBe(false)
  expect(ownerCommand('sh project.sh list; sh project.sh init /x')).toBe(true)
  expect(ownerCommand('git commit -m "looks ok"')).toBe(false)
})

test('a coordinator thread brief needs its specialist and opens with the thread rules', async ($, on) => {
  const ran: any[] = []
  on('store.get', () => ({ value: '/ws' }))
  on('store.set', () => ({ value: undefined }))
  on('fs.exists', (_: any, e: any) => ({ value: e.path === '/ws/.chief-of-staff' || e.path === '/ws/specialists' }))
  on('fs.list', () => ({ value: ['researcher.md', 'reviewer.md', 'ROUTING.md'].map(name => ({ name, kind: 'file', size: 0, mtimeMs: 0, isLink: false })) }))
  on('command.register', () => ({ value: { command: 'x' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.start', (_: any, e: any) => ({ cwd: e.cwd }))
  on('tool.call', (_: any, e: any) => { ran.push(e); return { result: 'Started session local_0a1b2c3d-2222' } })
  const call = (prompt?: string) => $.tool.call({ tool: 'mcp__ccd_session__start_session', title: 'Video', ...(prompt === undefined ? {} : { prompt }) } as any) as Promise<any>
  const ok = 'Role card: researcher\nLibrary: none found for scf video\nAmbition: a panel reviewer funds it on the first watch | judge: the scf-reviewer rubric score\nCut the video.'
  // not a coordinator yet: any brief passes, untouched
  await call('Cut the video.')
  expect(ran.pop().prompt).toBe('Cut the video.')
  await $.session.start({ cwd: '/ws/projects/dock', surface: 'desktop', isInteractive: true })
  const bare: any = await call('Cut the video.')
  expect(typeof bare.deny).toBe('string')
  expect(String(bare.deny)).toMatch(/Role card: <role>.*researcher, reviewer/)
  expect(String((await call('Role card: astrologer\nLibrary: x\nAmbition: a panel reviewer funds it | judge: the rubric score')).deny)).toMatch(/no specialists\/astrologer\.md/)
  expect(String((await call('Role card: researcher\nLibrary: none found for x')).deny)).toMatch(/Ambition:/)
  expect(ran).toEqual([])
  await call(ok)
  expect(ran.pop().prompt).toBe(`${THREAD_RULES}\n\n${ok}`)
  await call(`${THREAD_RULES}\n\n${ok}`)
  expect(ran.pop().prompt).toBe(`${THREAD_RULES}\n\n${ok}`)
  // starting an offer or a proposal by id carries no brief
  await call()
  expect(ran.pop().prompt).toBeUndefined()
})

test('the coordinator text carries the six thread rules', () => {
  for (const rule of [/Only you talk to the owner/, /DECISIONS\.md/, /no push, no deploy/, /Review before production/, /ask the owner where it runs today/, /ROUTING\.md/, /reviewer role/, /yes or no/, /in one pass/])
    expect(COORDINATOR).toMatch(rule)
  expect(briefGaps('Role card: utility find the file')).toBe('')
  expect(briefGaps('Role card: /My Drive/ws/specialists/researcher.md Library: [[a]] Ambition: the goal behind it | judge: npm test passes', ['researcher'])).toBe('')
})

test('the terminal, which has no Svg, draws the state as a colored character', async ($, on) => {
  on('clock.now', () => ({ value: Date.parse('2026-11-05T12:00:00Z') }))
  on('store.get', () => ({ value: '' }))
  on('mcp.call', (_: any, e: any) => {
    const t = (text: string) => ({ value: { content: [{ type: 'text', text }], isError: false } })
    if (e.tool === 'get_session') return t(JSON.stringify({ sessionId: 'local_me' }))
    return t(JSON.stringify([{ sessionId: 'local_a', title: 'Build', startedBy: 'local_me', isRunning: true, lastActivityAt: '2026-11-05T11:59:00Z' }]))
  })
  const ui = await $.ui.mount({ ...THREADS, surface: 'terminal' })
  expect(await ui.findAll({ type: 'Svg' })).toEqual([])
  expect(await ui.find({ type: 'Text', text: '◐' })).toBeDefined()
  await ui.unmount()
})

test('panelAsk quotes the folder so a name with quotes or $( ) stays one argument', () => {
  const ask = panelAsk('/plug in', '/x/a"$(touch pwn)\'b')
  expect(ask).toContain(`python3 '/plug in/scripts/panel.py' '/x/a"$(touch pwn)'\\''b'`)
})
