// The vibe-engineering side panel: a pane beside the chat that lists the
// board's items by column, with a button for each item's next step. A button
// sends an ordinary prompt that names the skill, the item and the board, so
// the skill runs exactly as if the person had typed it, with its own checks
// and questions. The panel only reads the board, through scripts/next.sh;
// every change still goes through a skill.
//
// The ui skill opens it by calling the tool this module registers
// (mcp__vibe-engineering__show_board). Where this module doesn't load
// (Claude Code before 2.1.287, cloud sessions) that tool doesn't exist, and
// the skill guides in the chat instead.
import type { EngineInterface, Register } from 'claude-code'

const PANE = 'vibe-board'
const TOOL = 'show_board'
const COLUMNS = ['Draft', 'Backlog', 'Ready', 'In progress', 'In review', 'Done']

export type Board = { id: string; title: string; url: string }
export type Step = { skill: string; label: string }
export type Item = {
  id: string
  status: string
  type: string
  number: string
  repo: string
  subDone: number
  subTotal: number
  steps: Step[]
  title: string
}
type View =
  | { kind: 'empty' }
  | { kind: 'loading'; items: Item[] }
  | { kind: 'ready'; items: Item[]; at: string }
  | { kind: 'error'; message: string }

// Module variables: they start over when the plugin reloads, and the board is
// read back from the store then. $.state would keep them through a reload, but
// needs a contract file named in plugin.json, which this small state isn't worth.
let cwd = ''
let board: Board | undefined
let view: View = { kind: 'empty' }
let isBusy = false
let loads = 0

/** Undoes the escapes gh's @tsv writes into a field. */
const untsv = (field: string) =>
  field.replace(/\\(.)/g, (_, c: string) =>
    c === 't' ? '\t' : c === 'n' ? '\n' : c === 'r' ? '\r' : c,
  )

/** Reads next.sh's `board` output, one item per line. */
export const parseRows = (stdout: string): Item[] =>
  stdout
    .split('\n')
    .filter(line => line.trim() !== '')
    .map(line => {
      const [id = '', status = '', type = '', number = '-', repo = '-', subs = '0/0', steps = '-', ...rest] =
        line.split('\t')
      const [done = '0', total = '0'] = subs.split('/')
      return {
        id,
        status,
        type,
        number,
        repo,
        subDone: Number(done) || 0,
        subTotal: Number(total) || 0,
        steps:
          steps === '-'
            ? []
            : steps.split(',').map(pair => {
                const [skill = '', label = skill] = pair.split(':')
                return { skill, label }
              }),
        title: untsv(rest.join('\t')),
      }
    })

/** The words a button sends, as the person's own prompt. */
export const promptFor = (target: Board, step: Step, item?: Item): string => {
  const skill = `vibe-engineering:${step.skill}`
  const where = `on the board ${target.url}`
  if (step.skill === 'ui') return `Use ${skill} to show a different board in the panel. Ask me which one.`
  if (!item) return `Use ${skill} ${where}.`
  const named =
    item.number === '-'
      ? `the draft item "${item.title}"`
      : `the item "${item.title}" (${item.repo}#${item.number})`
  if (step.skill === 'develop' && item.status.toLowerCase() === 'in review')
    return `Use ${skill} to fix the review comments on ${named} ${where}.`
  return `Use ${skill} for ${named} ${where}.`
}

/** Groups items into the board's columns, in its order; unknown ones last. */
export const columnsOf = (items: readonly Item[]) => {
  const known = COLUMNS.map(name => ({
    name,
    items: items.filter(item => item.status.toLowerCase() === name.toLowerCase()),
  }))
  const other = items.filter(
    item => !COLUMNS.some(name => name.toLowerCase() === item.status.toLowerCase()),
  )
  return other.length > 0 ? [...known, { name: 'No status', items: other }] : known
}

const storeKey = () => `board:${cwd}`

const redraw = ($: EngineInterface) => $.ui.invalidate('ui.render')

const run = async ($: EngineInterface, script: string, args: string[]) => {
  // On Windows a bare `bash` can be WSL's; Claude Code's own Git Bash is named here.
  const bash = (await $.env.get('CLAUDE_CODE_GIT_BASH_PATH')) || 'bash'
  return $.process.run([bash, `${$.plugin.root}/scripts/${script}`, ...args], {
    timeoutMs: 60_000,
  })
}

/** Reads the board again; a newer load wins over one still running. */
const load = async ($: EngineInterface) => {
  if (!board) return
  const mine = ++loads
  const before = view.kind === 'ready' || view.kind === 'loading' ? view.items : []
  view = { kind: 'loading', items: before }
  redraw($)
  let next: View
  try {
    const out = await run($, 'next.sh', ['board', board.id])
    if (out.exitCode === 0) {
      const at = new Date().toTimeString().slice(0, 5)
      next = { kind: 'ready', items: parseRows(out.stdout), at }
    } else {
      // The access check says what to do in words the skills already use.
      const auth = await run($, 'check-auth.sh', []).catch(() => undefined)
      const fix = auth?.stdout.split('\n').find(line => line.startsWith('FIX='))
      const said = out.stderr.trim().split('\n').at(-1)
      next = {
        kind: 'error',
        message: fix ? fix.slice(4) : said || 'The board could not be read.',
      }
    }
  } catch (error) {
    next = { kind: 'error', message: `The board could not be read: ${String(error)}` }
  }
  if (mine !== loads) return
  view = next
  redraw($)
}

/** Sends a step's prompt, unless Claude is already working. */
const start = ($: EngineInterface, step: Step, item?: Item) => {
  if (!board) return
  if (isBusy) {
    $.ui.toast('Claude is still working. Try again when it finishes.')
    return
  }
  isBusy = true
  redraw($)
  void $.prompt.submit({ text: promptFor(board, step, item), asUser: true })
}

const summary = (items: readonly Item[]) =>
  columnsOf(items)
    .filter(column => column.items.length > 0)
    .map(column => {
      const lines = column.items.map(item => {
        const ref = item.number === '-' ? 'draft' : `${item.repo}#${item.number}`
        const next =
          item.subTotal > 0
            ? `${item.subDone} of ${item.subTotal} sub-issues done`
            : item.steps.map(step => `${step.label} (${step.skill})`).join(', ') || 'nothing to start'
        return `  - ${item.title} [${ref}]: ${next}`
      })
      return `${column.name} (${column.items.length})\n${lines.join('\n')}`
    })
    .join('\n')

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    cwd = e.cwd
    const kept = (await $.store.get(storeKey())) as Board | undefined
    if (kept && typeof kept.id === 'string') board = kept
    await $.tool.register({
      name: TOOL,
      description:
        'Opens the vibe-engineering side panel beside the chat: the board\'s items by column, each with a button for its next step. Call it from the vibe-engineering:ui skill, with the board the user named (projectId, title and url from `projects.sh board`). Without a board it shows the one last shown in this folder, if any. Returns whether the panel is shown, and the items with their next steps.',
      inputSchema: {
        type: 'object',
        properties: {
          projectId: { type: 'string', description: 'The project ID from projects.sh board' },
          title: { type: 'string', description: 'The board title' },
          url: { type: 'string', description: 'The board URL' },
        },
      },
      isDeferred: false,
    })
    return started
  })

  on('tool.run', { tool: 'mcp__vibe-engineering__show_board' }, async ($, e) => {
    const input = e as unknown as { projectId?: string; title?: string; url?: string }
    if (input.projectId && input.url) {
      board = { id: input.projectId, title: input.title || input.url, url: input.url }
      await $.store.set(storeKey(), board)
    }
    if (!board) {
      return {
        result:
          'NO_BOARD: no board was named and none was shown in this folder before. Ask the user which board to show.',
      }
    }
    const opened = await $.ui.open({ id: PANE, title: 'Vibe Engineering' })
    await load($)
    const shown = opened.isPlaced
      ? 'PANEL=shown'
      : `PANEL=not_shown (${opened.reason}). Guide the user in the chat instead.`
    const items =
      view.kind === 'ready'
        ? summary(view.items) || 'The board has no items yet.'
        : view.kind === 'error'
          ? `ERROR=${view.message}`
          : ''
    return { result: `${shown}\nBOARD=${board.title} ${board.url}\n${items}` }
  }).catch(() => ({
    result: 'PANEL=not_shown (the panel failed to open). Guide the user in the chat instead.',
  }))

  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) {
      isBusy = true
      redraw($)
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId === undefined) {
      isBusy = false
      const open = (await $.ui.panes()).some(pane => pane.id === PANE)
      if (open) void load($)
      else redraw($)
    }
    return done
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)

    if (!board) {
      return (
        <Box flexDirection="column">
          <Text>No board is shown yet.</Text>
          <Text dimColor>Run /vibe-engineering:ui and name your board.</Text>
        </Box>
      )
    }

    const shown = board
    const status = isBusy
      ? 'Claude is working. The buttons wake up when it finishes.'
      : view.kind === 'loading'
        ? 'Reading the board...'
        : view.kind === 'ready'
          ? `Updated at ${view.at}`
          : ''
    const items = view.kind === 'ready' || view.kind === 'loading' ? view.items : []

    return (
      <Box flexDirection="column" gap={1}>
        <Box flexDirection="column">
          <Text bold>{shown.title}</Text>
          {status !== '' && <Text dimColor>{status}</Text>}
        </Box>
        <Box flexDirection="row" flexWrap="wrap" columnGap={1}>
          <Button key="new-idea" variant="primary" dimColor={isBusy} onPress={() => start($, { skill: 'create-item', label: 'New idea' })}>
            New idea
          </Button>
          <Button key="refresh" dimColor={isBusy} onPress={() => load($)}>
            Refresh
          </Button>
          <Button key="change-board" dimColor={isBusy} onPress={() => start($, { skill: 'ui', label: 'Change board' })}>
            Change board
          </Button>
        </Box>
        {view.kind === 'error' && (
          <Box flexDirection="column">
            <Text color="error">The board could not be read.</Text>
            <Text>{view.message}</Text>
          </Box>
        )}
        {view.kind !== 'error' && items.length === 0 && view.kind === 'ready' && (
          <Text dimColor>The board has no items yet. Press New idea to add one.</Text>
        )}
        {columnsOf(items)
          .filter(column => column.items.length > 0)
          .map(column =>
            column.name === 'Done' ? (
              <Box key="col-Done">
                <Text bold dimColor>
                  DONE ({column.items.length})
                </Text>
              </Box>
            ) : (
              <Box key={`col-${column.name}`} flexDirection="column">
                <Text bold>
                  {column.name.toUpperCase()} ({column.items.length})
                </Text>
                {column.items.map(item => (
                  <Box key={item.id} flexDirection="column" paddingLeft={1}>
                    <Text wrap="truncate-end">
                      {item.number === '-' ? '' : `#${item.number} `}
                      {item.title}
                    </Text>
                    {item.subTotal > 0 ? (
                      <Text dimColor>
                        {item.subDone} of {item.subTotal} sub-issues done
                      </Text>
                    ) : (
                      <Box flexDirection="row" flexWrap="wrap" columnGap={1}>
                        {item.steps.map(step => (
                          <Button
                            key={`${item.id}-${step.skill}-${step.label}`}
                            dimColor={isBusy}
                            onPress={() => start($, step, item)}
                          >
                            {step.label}
                          </Button>
                        ))}
                      </Box>
                    )}
                  </Box>
                ))}
              </Box>
            ),
          )}
      </Box>
    )
  })
}
