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

function workspace(on: any, calls: { tool: string; args: any }[], fillFails = false) {
  on('prompt.fill', (_: any, e: any) => { calls.push({ tool: 'prompt.fill', args: e }); return { isFilled: !fillFails } })
  on('store.get', () => ({ value: '/ws' }))
  on('fs.exists', (_: any, e: any) => ({ value: e.path === '/ws/projects' || e.path in FILES }))
  on('fs.list', () => ({ value: ['dock', 'old', 'README.md'].map(name => ({ name, kind: name.endsWith('.md') ? 'file' : 'dir', size: 0, mtimeMs: 0, isLink: false })) }))
  on('fs.read', (_: any, e: any) => (e.path in FILES ? { value: FILES[e.path] } : { deny: 'ENOENT' }))
  on('mcp.call', (_: any, e: any) => {
    calls.push({ tool: `${e.server}.${e.tool}`, args: e.args })
    const t = (text: string) => ({ value: { content: [{ type: 'text', text }], isError: false } })
    if (e.tool === 'list_sessions') return t(JSON.stringify([{ sessionId: 'local_1', title: 'Spike', cwd: '/ws/projects/dock', lastActivityAt: '2026-11-04T10:00:00Z' }, { sessionId: 'local_2', title: 'Other', cwd: '/elsewhere' }]))
    if (e.tool === 'list_groups') return t('[]')
    if (e.tool === 'create_group') return t('cg-0a1b2c3d-0000-4000-8000-000000000002')
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
  await ui.unmount()
})

test('New chat writes the request in the prompt box and starts nothing itself', async ($, on) => {
  const calls: { tool: string; args: any }[] = []
  workspace(on, calls)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'p-dock' })
  expect(await ui.find({ type: 'Text', text: /build Dock Folders/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Spike · 2026-11-04 10:00/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Other/ })).toBeUndefined()
  await ui.press({ key: 'new' })
  const fill = calls.find(c => c.tool === 'prompt.fill')!
  expect(fill.args.text).toMatch(/project "dock": a local session in \/ws\/projects\/dock \(no worktree\), detached to top level and filed in the sidebar group "dock"/)
  expect(calls.some(c => c.tool.startsWith('ccd_session.start') || c.tool.startsWith('ccd_sidebar.create'))).toBe(false)
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
