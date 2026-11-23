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
//
// Claude Code places a pane at any width only when the person asked for it
// (their prompt, command or press); an open from a tool call waits for a
// terminal 144 columns wide. So the pane also opens on the person's own prompt
// for the panel, and on the /vibe-board command.
import type { EngineInterface, Register } from 'claude-code'

const PANE = 'vibe-board'
const TOOL = 'show_board'
// Most urgent first: an item in review waits on the person, and a short pane
// must show what to act on before what can wait. Done is a count, last.
const COLUMNS = ['In review', 'In progress', 'Ready', 'Backlog', 'Draft', 'Done']
// A background agent that never reports back stops counting as busy after this.
const AGENT_STALE_MS = 30 * 60_000

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
let isTurnRunning = false
const agents = new Map<string, number>()
let loads = 0

/** Claude is working: the main turn, or a background agent it started. */
const isBusy = () => {
  const now = Date.now()
  for (const [id, since] of agents) if (now - since > AGENT_STALE_MS) agents.delete(id)
  return isTurnRunning || agents.size > 0
}

/** Whether a prompt asks for the panel: the ui skill's command, or in words. */
export const wantsPanel = (text: string, command?: string) =>
  command === 'vibe-engineering:ui' ||
  /(^|\s)\/vibe-engineering:ui\b/.test(text) ||
  (/vibe[- ]?engineering/i.test(text) && /\b(ui|panel|dashboard)\b/i.test(text))

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

/** Groups items by column, most urgent first; no status before Done. */
export const columnsOf = (items: readonly Item[]) => {
  const named = (name: string) => ({
    name,
    items: items.filter(item => item.status.toLowerCase() === name.toLowerCase()),
  })
  const other = items.filter(
    item => !COLUMNS.some(name => name.toLowerCase() === item.status.toLowerCase()),
  )
  const open = COLUMNS.filter(name => name !== 'Done').map(named)
  return [...open, ...(other.length > 0 ? [{ name: 'No status', items: other }] : []), named('Done')]
}

/** Rows the pane's body needs, as drawn at that width. */
export const rowsFor = (items: readonly Item[], columns: number) => {
  const shown = columnsOf(items).filter(column => column.items.length > 0)
  const perItem = columns >= 70 ? 1 : 2
  const listed = shown
    .filter(column => column.name !== 'Done')
    .reduce((sum, column) => sum + 1 + column.items.length * perItem, 0)
  return 2 + listed + (shown.some(column => column.name === 'Done') ? 1 : 0)
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

/** Opens the pane, asking for as many rows as the board needs. */
const openPane = ($: EngineInterface) => {
  const items = view.kind === 'ready' || view.kind === 'loading' ? view.items : []
  const rows = Math.min(60, Math.max(8, rowsFor(items, 0) + 1))
  return $.ui.open({ id: PANE, title: 'Vibe Engineering', rows })
}

/** Sends a step's prompt, unless Claude is already working. */
const start = ($: EngineInterface, step: Step, item?: Item) => {
  if (!board) return
  if (isBusy()) {
    $.ui.toast('Claude is still working. Try again when it finishes.')
    return
  }
  isTurnRunning = true
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
    await $.command.register({
      name: 'vibe-board',
      description: 'Show the vibe-engineering board panel beside the chat',
    })
    return started
  })

  // The person's own prompt for the panel: an open here is placed at any width.
  on('prompt.submit', async ($, e, next) => {
    if (wantsPanel(e.text, e.command?.name)) {
      await openPane($)
      if (board && view.kind === 'empty') void load($)
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  on('command.run', { command: 'vibe-board' }, async $ => {
    const opened = await openPane($)
    if (!board) return { text: 'No board yet. Run /vibe-engineering:ui and name your board.' }
    void load($)
    return {
      text: opened.isPlaced
        ? `Showing ${board.title} beside the chat.`
        : `The panel couldn't be shown here: ${opened.reason}.`,
    }
  })

  // The panel's own tool only reads the board: let it run without a prompt,
  // unless the person's rules deny it.
  on('tool.check', { tool: 'mcp__vibe-engineering__show_board' }, async ($, e, next) => {
    const verdict = await next(e)
    return verdict.decision === 'ask' ? { decision: 'allow' } : verdict
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
    await load($)
    const opened = await openPane($)
    const shown = opened.isPlaced
      ? 'PANEL=shown'
      : `PANEL=not_shown (${opened.reason}). Guide the user in the chat, and tell them /vibe-board opens the panel.`
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

  // Busy while the main turn runs or any agent it started (a review's
  // background agents run on after the main turn has ended).
  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) isTurnRunning = true
    else agents.set(e.agentId, Date.now())
    redraw($)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId === undefined) isTurnRunning = false
    else agents.delete(e.agentId)
    if (isBusy()) {
      redraw($)
      return done
    }
    const open = (await $.ui.panes()).some(pane => pane.id === PANE)
    if (open) void load($)
    else redraw($)
    return done
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)

    if (!board) {
      return (
        <Box flexDirection="column">
          <Text>No board is shown yet.</Text>
          <Text dimColor>Name your board in the chat, or run /vibe-engineering:ui.</Text>
        </Box>
      )
    }

    const busy = isBusy()
    const status = busy
      ? 'Claude is working'
      : view.kind === 'loading'
        ? 'reading...'
        : view.kind === 'ready'
          ? `updated ${view.at}`
          : ''
    const items = view.kind === 'ready' || view.kind === 'loading' ? view.items : []
    const wide = e.props.bodyColumns >= 70
    const room = e.props.scroll?.bodyRows ?? 0
    const isCut = room > 0 && rowsFor(items, e.props.bodyColumns) > room

    const stepButtons = (item: Item) =>
      item.steps.map(step => (
        <Button key={`${item.id}-${step.skill}-${step.label}`} dimColor={busy} onPress={() => start($, step, item)}>
          {step.label}
        </Button>
      ))
    const name = (item: Item) => `${item.number === '-' ? '' : `#${item.number} `}${item.title}`

    return (
      <Box flexDirection="column">
        <Box flexDirection="row" columnGap={1}>
          <Text bold wrap="truncate-end">
            {board.title}
          </Text>
          {status !== '' && <Text dimColor>{status}</Text>}
        </Box>
        <Box flexDirection="row" flexWrap="wrap" columnGap={1}>
          <Button key="new-idea" variant="primary" dimColor={busy} onPress={() => start($, { skill: 'create-item', label: 'New idea' })}>
            New idea
          </Button>
          <Button key="refresh" dimColor={busy} onPress={() => load($)}>
            Refresh
          </Button>
          <Button key="change-board" dimColor={busy} onPress={() => start($, { skill: 'ui', label: 'Change board' })}>
            Change board
          </Button>
        </Box>
        {isCut && <Text dimColor>More below: scroll the panel to see every column.</Text>}
        {view.kind === 'error' && (
          <Box flexDirection="column">
            <Text color="error">The board could not be read.</Text>
            <Text>{view.message}</Text>
          </Box>
        )}
        {view.kind === 'ready' && items.length === 0 && (
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
                {column.items.map(item => {
                  const next =
                    item.subTotal > 0 ? (
                      <Text dimColor>
                        {item.subDone} of {item.subTotal} sub-issues done
                      </Text>
                    ) : (
                      stepButtons(item)
                    )
                  return wide ? (
                    <Box key={item.id} flexDirection="row" columnGap={1} paddingLeft={1}>
                      <Box flexShrink={1}>
                        <Text wrap="truncate-end">{name(item)}</Text>
                      </Box>
                      {next}
                    </Box>
                  ) : (
                    <Box key={item.id} flexDirection="column" paddingLeft={1}>
                      <Text wrap="truncate-end">{name(item)}</Text>
                      <Box flexDirection="row" flexWrap="wrap" columnGap={1}>
                        {next}
                      </Box>
                    </Box>
                  )
                })}
              </Box>
            ),
          )}
      </Box>
    )
  })
}
