import { expect, test } from 'claude-code/testing'
import { decisions, fm } from '../hooks/projects'

const PANE = {
  plugin: 'chief-of-staff', component: 'Pane', requestId: 'cos-projects',
  props: { title: 'Projects', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} },
} as const

const FILES: Record<string, string> = {
  '/ws/projects/dock/STATE.md': '---\nstatus: in-progress\nupdated: 2026-11-04\nnext: spike the panel\n---\n# Dock',
  '/ws/projects/dock/CLAUDE.md': '# Dock — project agent\n\nA conversation opened here handles **one thing only**: build Dock Folders.\n',
  '/ws/projects/dock/DECISIONS.md': '- 2026-11-04 01:15 | Waitlist only | Pedro | -\n- 2026-11-04 01:16 | old | Pedro | -\n- 2026-11-04 01:17 | new one | Pedro | replaces: 2026-11-04 01:16\n',
  '/ws/projects/old/STATE.md': '---\nstatus: delivered\nupdated: 2026-10-01\n---\n',
}

const SESSIONS = [{ sessionId: 'local_1', title: 'Spike', cwd: '/ws/projects/dock', lastActivityAt: '2026-11-04T10:00:00Z' }, { sessionId: 'local_2', title: 'Other', cwd: '/elsewhere' }]
function workspace(on: any, calls: { tool: string; args: any }[], fillFails = false, sessions: unknown[] = SESSIONS) {
  on('prompt.fill', (_: any, e: any) => { calls.push({ tool: 'prompt.fill', args: e }); return { isFilled: !fillFails } })
  on('store.get', () => ({ value: '/ws' }))
  on('fs.exists', (_: any, e: any) => ({ value: e.path === '/ws/projects' || e.path in FILES }))
  on('fs.list', () => ({ value: ['dock', 'old', 'README.md'].map(name => ({ name, kind: name.endsWith('.md') ? 'file' : 'dir', size: 0, mtimeMs: 0, isLink: false })) }))
  on('fs.read', (_: any, e: any) => (e.path in FILES ? { value: FILES[e.path] } : { deny: 'ENOENT' }))
  on('mcp.call', (_: any, e: any) => {
    calls.push({ tool: `${e.server}.${e.tool}`, args: e.args })
    const t = (text: string) => ({ value: { content: [{ type: 'text', text }], isError: false } })
    if (e.tool === 'list_sessions') return t(JSON.stringify(sessions))
    if (e.tool === 'list_groups') return t('[]')
    if (e.tool === 'create_group') return t('cg-0a1b2c3d-0000-4000-8000-000000000002')
    if (e.tool === 'open_session_in') return t('Refused: not a session this one started')
    return t('ok')
  })
}

test('front matter and decisions read like lib.sh', () => {
  expect(fm(FILES['/ws/projects/dock/STATE.md']!, 'next')).toBe('spike the panel')
  expect(decisions(FILES['/ws/projects/dock/DECISIONS.md']!)).toEqual(['Waitlist only (Pedro)', 'new one (Pedro)'])
})

test('the list shows open projects and folds delivered ones', async ($, on) => {
  workspace(on, [])
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ key: 'p-dock' }))?.text).toMatch(/dock · in-progress · next: spike the panel/)
  expect(await ui.find({ key: 'p-old' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /Done \(1\): old/ })).toBeDefined()
  expect(await ui.find({ key: 'c-dock' })).toBeUndefined()
  await ui.unmount()
})

test('a project with no session in its folder is offered a coordinator', async ($, on) => {
  const calls: { tool: string; args: any }[] = []
  workspace(on, calls, false, [])
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /^No coordinator 1$/ })).toBeDefined()
  await ui.press({ key: 'c-dock' })
  expect(calls.find(c => c.tool === 'prompt.fill')?.args.text).toMatch(/Start the coordinator of the project "dock"/)
  expect(calls.some(c => c.tool.startsWith('ccd_session.start'))).toBe(false)
  await ui.unmount()
})

test('New chat writes the request in the prompt box and starts nothing itself', async ($, on) => {
  const calls: { tool: string; args: any }[] = []
  workspace(on, calls)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'p-dock' })
  expect(await ui.find({ type: 'Text', text: /build Dock Folders/ })).toBeDefined()
  expect((await ui.find({ key: 'local_1' }))?.text).toMatch(/Spike · 2026-11-04 10:00/)
  expect(await ui.find({ key: 'local_2' })).toBeUndefined()
  await ui.press({ key: 'new' })
  const fill = calls.find(c => c.tool === 'prompt.fill')!
  expect(fill.args.text).toMatch(/coordinator of the project "dock": a local session in \/ws\/projects\/dock \(no worktree\), titled "dock: chat", kept as a sub-conversation of this one \(not detached\)/)
  expect(calls.some(c => c.tool.startsWith('ccd_session.start') || c.tool.startsWith('ccd_sidebar.create'))).toBe(false)
  await ui.unmount()
})

test('a chat opens in the main pane, and a refusal points to the sidebar group', async ($, on) => {
  const calls: { tool: string; args: any }[] = []
  workspace(on, calls)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'p-dock' })
  await ui.press({ key: 'local_1' })
  expect(calls.find(c => c.tool === 'ccd_window.open_session_in')?.args).toEqual({ session_id: 'local_1', target: 'focus' })
  expect((await ui.find({ type: 'Text', text: /Couldn't show/ }))?.text).toMatch(/Refused.*sidebar group dock/)
  await ui.unmount()
})

test('a prompt box that cannot be filled says what to type', async ($, on) => {
  workspace(on, [], true)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'p-dock' })
  await ui.press({ key: 'new' })
  expect((await ui.find({ type: 'Text', text: /Couldn't write the request/ }))?.text).toMatch(/prompt box is not available.*open a new chat in dock/)
  await ui.unmount()
})

const THREADS = { ...PANE, requestId: 'cos-threads', props: { ...PANE.props, title: 'Threads' } } as const

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
  expect((await ui.find({ key: 'local_a' }))?.text).toMatch(/◐ Build slice 1/)
  expect(await ui.find({ type: 'Text', text: /^ +21m$/ })).toBeDefined()
  expect((await ui.find({ key: 'local_b' }))?.text).toMatch(/○ Spec the app/)
  expect((await ui.find({ key: 'local_r' }))?.text).toMatch(/◆ Fix login/)
  expect(await ui.find({ type: 'Text', text: /^ +2h · PR #12$/ })).toBeDefined()
  const order = (await ui.findAll({ type: 'Text' })).map(x => x.text).filter(t => /^[A-Z][a-z ]+ \d+$/.test(t))
  expect(order).toEqual(['Ready for review 1', 'Waiting on you 1', 'Working 1', 'Idle 1', 'Resolved 3'])
  expect(await ui.find({ key: 'local_x' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: 'next: ship v1' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Local only \(owner\)/ })).toBeDefined()
  expect(await ui.find({ type: 'Markdown' })).toBeDefined()
  await ui.press({ key: 'local_a' })
  expect(calls.find(c => c.tool === 'ccd_window.open_session_in')?.args).toEqual({ session_id: 'local_a', target: 'focus' })
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
  expect(await ui.find({ type: 'Text', text: /◐ Daily build · Working/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^Build the daily-use version\.$/ })).toBeDefined()
  await ui.press({ key: 'open-tu1' })
  expect(calls.find(c => c.tool === 'ccd_window.open_session_in')?.args).toEqual({ session_id: 'local_0a1b2c3d-1111', target: 'focus' })
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
