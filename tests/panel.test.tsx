// Tests for the side panel (hooks/panel.tsx). Run with:
//   claude plugin test .
// Nothing here reaches GitHub: the hooks below stand for the engine and
// answer the scripts the panel runs with canned output.
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const TOOL = 'mcp__vibe-engineering__show_board'
const BOARD = {
  projectId: 'PVT_1',
  title: 'Shop board',
  url: 'https://github.com/users/me/projects/3',
}
const ROWS = [
  'PVTI_1\tDraft\tDRAFT_ISSUE\t-\t-\t0/0\tpromote-backlog:Design it\tStock per warehouse',
  'PVTI_2\tBacklog\tISSUE\t14\tme/shop\t1/3\t-\tLow-stock alerts',
  'PVTI_3\tIn review\tISSUE\t9\tme/shop\t0/0\treview:Review,develop:Fix comments,approve:Merge\tProduct page shows stock',
  'PVTI_4\tDone\tISSUE\t2\tme/shop\t0/0\t-\tFirst item',
].join('\n')

const PANE = {
  plugin: 'vibe-engineering',
  component: 'Pane',
  requestId: 'vibe-board',
  props: {
    title: 'Vibe Engineering',
    isFocused: false,
    bodyColumns: 40,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

type Ran = { argv: readonly string[] }

/** The engine beneath the panel: a session, a store, the scripts' output. */
const engine = (
  on: On,
  scripts: { next?: [number, string, string]; auth?: string; store?: Record<string, unknown> } = {},
) => {
  const ran: Ran[] = []
  const sent: { text: string; asUser?: true }[] = []
  const toasts: string[] = []
  mock.store(on, scripts.store)
  mock.env(on, {})
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('turn.start', (_, e) => ({ turnId: e.turnId }))
  on('tool.register', (_, e) => ({ value: { tool: `mcp__vibe-engineering__${e.name}` } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.panes', () => ({
    value: [{ id: 'vibe-board', title: 'Vibe Engineering', isShown: true, isFocused: false, isPlaced: true }],
  }))
  on('ui.toast', (_, e) => {
    toasts.push(e.text)
    return { value: undefined }
  })
  on('process.run', (_, e) => {
    ran.push({ argv: e.argv })
    const script = String(e.argv.at(1) ?? '')
    const [exitCode, stdout, stderr] = script.endsWith('next.sh')
      ? (scripts.next ?? [0, ROWS, ''])
      : [6, scripts.auth ?? '', '']
    return { value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('prompt.submit', (_, e) => {
    sent.push({ text: e.text, asUser: (e.origin as { asUser?: true } | undefined)?.asUser })
    return { text: e.text }
  })
  return { ran, sent, toasts }
}

test('the tool opens the panel and reports the board', async ($, on) => {
  const { ran } = engine(on)
  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })

  const out = await $.tool.call({ tool: TOOL, ...BOARD })
  const text = String(out.result)

  expect(text).toContain('PANEL=shown')
  expect(text).toContain('BOARD=Shop board https://github.com/users/me/projects/3')
  expect(text).toContain('Stock per warehouse [draft]: Design it (promote-backlog)')
  expect(text).toContain('Low-stock alerts [me/shop#14]: 1 of 3 sub-issues done')
  expect(ran.at(0)?.argv.slice(2)).toEqual(['board', 'PVT_1'])
  expect(String(ran.at(0)?.argv.at(1))).toMatch(/scripts\/next\.sh$/)
})

test('without a board named or kept, the tool asks for one', async ($, on) => {
  engine(on)
  await $.session.start({ cwd: '/elsewhere', surface: 'desktop', isInteractive: true })

  const out = await $.tool.call({ tool: TOOL })

  expect(String(out.result)).toContain('NO_BOARD')
})

test('the board shown last in a folder is shown again without a name', async ($, on) => {
  engine(on, {
    store: { 'board:/work': { id: 'PVT_1', title: 'Shop board', url: BOARD.url } },
  })
  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })

  const out = await $.tool.call({ tool: TOOL })

  expect(String(out.result)).toContain('BOARD=Shop board')
})

test('the pane lists items by column, on every surface', async ($, on) => {
  engine(on)
  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })
  await $.tool.call({ tool: TOOL, ...BOARD })

  for (const surface of ['terminal', 'desktop', 'vscode', 'mobile'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /^Shop board$/ }))?.text).toBe('Shop board')
    expect(await ui.find({ type: 'Text', text: 'DRAFT (1)' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: '1 of 3 sub-issues done' })).toBeDefined()
    expect(await ui.find({ key: 'PVTI_3-approve-Merge' })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: 'DONE (1)' })).toBeDefined()
    // A Done item shows only in the count, and a parent has no button.
    expect(await ui.find({ type: 'Text', text: /First item/ })).toBeUndefined()
    expect(await ui.find({ key: 'PVTI_2-promote-ready-Write the spec' })).toBeUndefined()
    await ui.unmount()
  }
})

test('a button sends the skill, the item and the board as the person', async ($, on) => {
  const { sent } = engine(on)
  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })
  await $.tool.call({ tool: TOOL, ...BOARD })

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'PVTI_1-promote-backlog-Design it' })

  expect(sent.at(0)?.text).toBe(
    'Use vibe-engineering:promote-backlog for the draft item "Stock per warehouse" on the board https://github.com/users/me/projects/3.',
  )
  expect(sent.at(0)?.asUser).toBe(true)
  await ui.unmount()
})

test('fixing comments asks develop for the review comments', async ($, on) => {
  const { sent } = engine(on)
  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })
  await $.tool.call({ tool: TOOL, ...BOARD })

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'PVTI_3-develop-Fix comments' })

  expect(sent.at(0)?.text).toBe(
    'Use vibe-engineering:develop to fix the review comments on the item "Product page shows stock" (me/shop#9) on the board https://github.com/users/me/projects/3.',
  )
  await ui.unmount()
})

test('new idea asks create-item for the board shown', async ($, on) => {
  const { sent } = engine(on)
  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })
  await $.tool.call({ tool: TOOL, ...BOARD })

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'new-idea' })

  expect(sent.at(0)?.text).toBe(
    'Use vibe-engineering:create-item on the board https://github.com/users/me/projects/3.',
  )
  await ui.unmount()
})

test('change board asks the person which board, and picks none', async ($, on) => {
  const { sent } = engine(on)
  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })
  await $.tool.call({ tool: TOOL, ...BOARD })

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'change-board' })

  expect(sent.at(0)?.text).toBe(
    'Use vibe-engineering:ui to show a different board in the panel. Ask me which one.',
  )
  await ui.unmount()
})

test('a second press waits for the first prompt to finish', async ($, on) => {
  const { sent, toasts } = engine(on)
  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })
  await $.tool.call({ tool: TOOL, ...BOARD })

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'new-idea' })
  await ui.press({ key: 'refresh' })
  await ui.press({ key: 'PVTI_1-promote-backlog-Design it' })

  expect(sent).toHaveLength(1)
  expect(toasts).toHaveLength(1)
  await ui.unmount()
})

test('while Claude works, a button waits and says so', async ($, on) => {
  const { sent, toasts } = engine(on)
  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })
  await $.tool.call({ tool: TOOL, ...BOARD })
  await $.turn.start({ text: 'busy', turnId: 't1' })

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'new-idea' })

  expect(sent).toHaveLength(0)
  expect(toasts.at(0)).toContain('still working')
  await ui.unmount()
})

test('a board that cannot be read shows the fix from the access check', async ($, on) => {
  engine(on, {
    next: [1, '', 'gh: GraphQL is not available'],
    auth: 'STATUS=not_logged_in\nFIX=Run: gh auth login --hostname github.com -s project\n',
  })
  await $.session.start({ cwd: '/work', surface: 'desktop', isInteractive: true })
  const out = await $.tool.call({ tool: TOOL, ...BOARD })

  expect(String(out.result)).toContain('ERROR=Run: gh auth login')
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /gh auth login/ })).toBeDefined()
  await ui.unmount()
})
