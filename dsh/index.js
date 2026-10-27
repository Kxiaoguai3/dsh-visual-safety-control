// dsh-desktop-guard — DeepSeek Harness plugin (fork of qingying012/dsh-desktop-control, MIT)
//
// Adds two things to the upstream desktop tool while keeping its zero-Python,
// single PowerShell implementation:
//   1. Content policy (dsh/policy.js): dangerous target labels, sensitive windows,
//      credential-looking payloads and denied key combos are refused in Node before
//      PowerShell is spawned. The model cannot opt out through arguments.
//   2. Action verification (assets/gui.ps1 -verify): `type` checks the focused
//      control is editable before pasting and reads it back afterwards; `click`
//      hit-tests the point against the target window and reports the focused control.
//
// Registers one `desktop` tool that lets the model see the screen and drive
// the mouse/keyboard: screenshot, window list, UIA element list, local OCR,
// click, move, drag, scroll, type, key, activate, cursor position, wait, and
// a batched `sequence` that runs several actions in a single PowerShell start.
//
// Implementation: every call spawns the bundled `assets/gui.ps1` (Windows
// PowerShell 5.1) and parses its output. Keeping the Win32 work in PowerShell
// avoids a native addon, keeps the package tiny, and reuses the script that
// was already battle-tested on this machine.
//
// Accuracy model (why the extras exist):
//   * `screenshot` now stamps a labelled coordinate grid and the cursor onto
//     the PNG, so the labels ARE screen pixels — read them, do not eyeball.
//   * Large screens are scaled down (default long edge 1440) and the exact
//     `scale` is returned, so on-image pixels can be converted back.
//   * `elements` returns a UIA text tree (name + centre point), which needs no
//     image at all: cheapest and most precise way to hit a real control.
//   * `ocr` runs Windows.Media.Ocr locally (no quota, no network) and returns
//     text + bounding boxes for painted UIs that UIA cannot see.
//   * `sequence` collapses click/type/wait/shot chains into one process start
//     and one tool round-trip, which is the single biggest token saver.
//
// Safety: this is full desktop control. It can click anything and type
// anything. Every call is a normal tool call, so the host's tool policy and
// the user's judgement are the only gates. Do not enable it on an unattended
// machine.
import { spawn } from 'node:child_process'
import { existsSync, mkdirSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { isAbsolute, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { DEFAULT_POLICY, evaluatePolicy, normalizePolicy } from './policy.js'

export const name = 'desktop-guard'

// `tools` is the registry this plugin contributes the `desktop` tool to.
export const inject = ['tools']

const SCRIPT = fileURLToPath(new URL('../assets/gui.ps1', import.meta.url))
const DSH_HOME = process.env.DSH_HOME || join(homedir(), '.dsh')
const SHOT_DIR = join(DSH_HOME, 'desktop-control')

const DEFAULTS = {
  enabled: true,
  // Override only if powershell.exe is not on PATH.
  powershellPath: 'powershell.exe',
  timeoutMs: 30_000,
  // Keep the most recent screenshots in the DSH home so read_image can open them.
  screenshotDir: SHOT_DIR,
  // Long edge cap for screenshots. 0 disables scaling (image keeps 1:1 pixels).
  screenshotMaxWidth: 1440,
  // Stamp the labelled coordinate grid. Off by default: grid labels get picked up
  // by OCR/vision-to-text engines and add tokens. Turn on when reading the image directly.
  screenshotGrid: false,
  // Stamp the cursor crosshair on every screenshot.
  screenshotCursor: true,
  // Keep at most this many PNGs; older ones are pruned after a new shot.
  keepShots: 40,
  // Truncate `elements` output to this many rows (the rest is summarised).
  elementsMaxRows: 140,
  // --- fork additions: content policy + action verification ---
  // Refuse dangerous labels, sensitive windows, credential payloads and denied keys
  // before PowerShell is ever spawned. See dsh/policy.js.
  policy: DEFAULT_POLICY,
  // `type` refuses to paste when the focused control is provably not editable, and
  // reads the control back afterwards.
  verifyType: true,
  // `click` hit-tests the point against the target window before clicking and reports
  // the focused control afterwards.
  verifyClick: true,
}

const ACTIONS = [
  'screenshot',
  'windows',
  'elements',
  'find',
  'ocr',
  'click',
  'move',
  'drag',
  'scroll',
  'type',
  'key',
  'activate',
  'pos',
  'wait',
  'sequence',
]

const ACTION_SET = new Set(ACTIONS)

const PARAMETERS = {
  type: 'object',
  additionalProperties: false,
  properties: {
    action: {
      type: 'string',
      enum: ACTIONS,
      description:
        'screenshot (save a PNG and return its path), windows (list visible windows), elements (UIA control list for a window: name + centre point, no image needed), find (locate text on screen with local OCR and return its exact coordinates — cheapest way to hit a labelled button), ocr (local OCR of an image: text + boxes), click, move, drag, scroll, type (paste text), key (press a combo such as ctrl+s), activate (bring a window to front), pos (cursor position), wait, sequence (run several actions in one call).',
    },
    x: { type: 'number', description: 'Target X in physical screen pixels.' },
    y: { type: 'number', description: 'Target Y in physical screen pixels.' },
    x2: { type: 'number', description: 'Drag end X.' },
    y2: { type: 'number', description: 'Drag end Y.' },
    text: { type: 'string', description: 'Text for action=type, or the on-screen label to look for in action=find. Unicode is fine.' },
    key: { type: 'string', description: 'Combo for action=key, e.g. "ctrl+s", "alt+f4", "enter".' },
    window: {
      type: 'string',
      description: 'Window title or process name substring, for screenshot/elements/click/activate.',
    },
    region: {
      type: 'string',
      description: 'Screenshot region "x,y,width,height" in physical pixels. Prefer screenshotting one window or a small region: far fewer tokens than a full screen.',
    },
    button: { type: 'string', enum: ['left', 'right', 'middle'], description: 'Mouse button for click/drag.' },
    count: { type: 'integer', description: 'Click count, 1-3.' },
    amount: { type: 'integer', description: 'Scroll notches; positive is up. 1 = one wheel notch.' },
    waitMs: { type: 'integer', description: 'Milliseconds for action=wait.' },
    print: {
      type: 'boolean',
      description: 'For screenshot with a window: capture it with PrintWindow even when occluded.',
    },
    grid: {
      type: 'boolean',
      description: 'screenshot: stamp a labelled coordinate grid (default on). Grid labels are screen-pixel coordinates — click those numbers directly.',
    },
    maxWidth: {
      type: 'integer',
      description: 'screenshot: cap the long edge in pixels (default 1440, 0 = no scaling). The reply states the exact scale factor.',
    },
    cursor: {
      type: 'boolean',
      description: 'screenshot: stamp the current cursor position (default on).',
    },
    depth: { type: 'integer', description: 'elements: max UIA tree depth (default 9).' },
    filter: {
      type: 'string',
      description: 'elements/ocr: only keep rows whose name or text contains this substring.',
    },
    all: {
      type: 'boolean',
      description: 'elements: also keep unnamed container rows and skip row truncation.',
    },
    exact: {
      type: 'boolean',
      description: 'find: only accept lines that equal the text exactly (recommended for 2-character labels).',
    },
    index: {
      type: 'integer',
      description:
        'find with click: 1-based match to click when several lines match. Without it an ambiguous match refuses to click and lists the candidates.',
    },
    verify: {
      type: 'boolean',
      description:
        'type/click: refuse when focus/hit-test proves the action would miss, and report a verification verdict. Defaults to config.verifyType / verifyClick.',
    },
    expect: {
      type: 'string',
      description:
        'click by coordinates: OCR a small region around the point and refuse the click unless this text is there (guards against stale coordinates after layout shifts).',
    },
    verifyText: {
      type: 'string',
      description:
        'click/find: after the action, OCR the window again and require this text to be visible; the verdict is attached to the result. Recommended for irreversible actions.',
    },
    threshold: {
      type: 'number',
      description: 'find: minimum match score 0-1 (default 0.55). Lower it when OCR mangles the label.',
    },
    click: {
      type: 'boolean',
      description: 'find: click the best match immediately, saving a round-trip.',
    },
    screen: {
      type: 'boolean',
      description:
        'find: capture the real screen instead of the window bitmap. Use when the window is in the foreground and the app renders on the GPU.',
    },
    uia: {
      type: 'string',
      description: 'click: click the control whose UIA name/id contains this text instead of using x/y. Much more reliable than pixel hunting.',
    },
    invoke: {
      type: 'boolean',
      description: 'click with uia: use the UIA Invoke pattern (no mouse movement) when available.',
    },
    imagePath: {
      type: 'string',
      description: 'ocr: image to read — normally the imagePath returned by an earlier screenshot.',
    },
    top: { type: 'integer', description: 'windows: only the first N windows.' },
    steps: {
      type: 'array',
      description:
        'sequence: actions to run in order, each an object with the same fields as a normal call, e.g. [{"action":"click","x":10,"y":20},{"action":"wait","waitMs":300},{"action":"screenshot"}]. Saves process starts and tool round-trips.',
      items: { type: 'object' },
    },
  },
  required: ['action'],
}

const OUTPUT = {
  type: 'object',
  additionalProperties: false,
  properties: {
    ok: { type: 'boolean' },
    action: { type: 'string' },
    output: { type: 'string' },
    imagePath: { type: 'string' },
    width: { type: 'integer' },
    height: { type: 'integer' },
    scale: { type: 'number' },
    gridStep: { type: 'integer' },
    verification: { type: 'object' },
    hitTest: { type: 'object' },
    focus: { type: 'object' },
    ambiguous: { type: 'array', items: { type: 'string' } },
  },
  required: ['ok', 'action'],
}

function requireNumber(args, key) {
  const value = args[key]
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new Error(`desktop action "${args.action}" requires a numeric "${key}"`)
  }
  return value
}

function requireString(args, key) {
  const value = args[key]
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`desktop action "${args.action}" requires a non-empty "${key}"`)
  }
  return value
}

function absolutePath(value) {
  return isAbsolute(value) ? value : join(process.cwd(), value)
}

function shotPath(config) {
  const dir = config.screenshotDir
  mkdirSync(dir, { recursive: true })
  const d = new Date()
  const pad = (n, w = 2) => String(n).padStart(w, '0')
  const stamp =
    `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}` +
    `-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}-${pad(d.getMilliseconds(), 3)}`
  return join(dir, `shot-${stamp}.png`)
}

/** Keep the screenshot directory bounded so a long session cannot fill the disk. */
function pruneShots(config) {
  const keep = Number(config.keepShots)
  if (!Number.isFinite(keep) || keep <= 0) return
  try {
    const dir = config.screenshotDir
    const files = readdirSync(dir)
      .filter((f) => f.startsWith('shot-') && f.endsWith('.png'))
      .map((f) => join(dir, f))
    if (files.length <= keep) return
    const stats = files.map((f) => ({ f, t: statSync(f).mtimeMs })).sort((a, b) => a.t - b.t)
    for (const { f } of stats.slice(0, stats.length - keep)) {
      try {
        rmSync(f, { force: true })
      } catch {
        /* ignore */
      }
    }
  } catch {
    /* ignore */
  }
}

/**
 * Translate one tool call into gui.ps1 argv.
 * Exported for the self-test; not part of the public plugin API.
 */
export function buildArgs(args, config = DEFAULTS) {
  const action = args.action
  if (!ACTION_SET.has(action)) throw new Error(`desktop: unknown action "${action}"`)
  switch (action) {
    case 'screenshot': {
      const path = shotPath(config)
      const argv = ['shot', path]
      if (typeof args.window === 'string' && args.window.length > 0) argv.push('-window', args.window)
      if (typeof args.region === 'string' && args.region.length > 0) argv.push('-region', args.region)
      if (args.print === true) argv.push('-print')

      const grid = args.grid === undefined ? config.screenshotGrid !== false : args.grid === true
      if (grid) argv.push('-grid')

      const cursor = args.cursor === undefined ? config.screenshotCursor !== false : args.cursor === true
      if (cursor) argv.push('-cursor')

      const maxWidth =
        typeof args.maxWidth === 'number' ? args.maxWidth : Number(config.screenshotMaxWidth)
      if (Number.isFinite(maxWidth) && maxWidth > 0) argv.push('-maxwidth', String(Math.round(maxWidth)))
      return { argv, json: true }
    }
    case 'windows': {
      const argv = ['windows']
      if (typeof args.top === 'number' && args.top > 0) argv.push('-top', String(Math.round(args.top)))
      return { argv, json: false }
    }
    case 'elements': {
      const argv = ['elements']
      if (typeof args.window === 'string' && args.window.length > 0) argv.push('-window', args.window)
      if (typeof args.filter === 'string' && args.filter.length > 0) argv.push('-filter', args.filter)
      if (typeof args.depth === 'number' && args.depth > 0) argv.push('-depth', String(Math.round(args.depth)))
      if (args.all === true) argv.push('-all')
      return { argv, json: false }
    }
    case 'find': {
      const argv = ['find', requireString(args, 'text')]
      if (typeof args.window === 'string' && args.window.length > 0) argv.push('-window', args.window)
      if (typeof args.region === 'string' && args.region.length > 0) argv.push('-region', args.region)
      if (typeof args.threshold === 'number') argv.push('-threshold', String(args.threshold))
      if (args.exact === true) argv.push('-exact')
      if (typeof args.index === 'number' && args.index > 0) argv.push('-index', String(Math.round(args.index)))
      if (args.click === true) argv.push('-click')
      if (args.screen === true) argv.push('-screen')
      if (args.button !== undefined) argv.push('-button', String(args.button))
      return { argv, json: false }
    }
    case 'ocr': {
      const argv = ['ocr', absolutePath(requireString(args, 'imagePath'))]
      if (typeof args.filter === 'string' && args.filter.length > 0) argv.push('-filter', args.filter)
      return { argv, json: false }
    }
    case 'click': {
      const verify = args.verify === undefined ? config.verifyClick !== false : args.verify === true
      if (typeof args.uia === 'string' && args.uia.length > 0) {
        const argv = ['click', '-uia', args.uia]
        if (typeof args.window === 'string' && args.window.length > 0) argv.push('-window', args.window)
        if (args.invoke === true) argv.push('-invoke')
        if (verify) argv.push('-verify')
        return { argv, json: true }
      }
      const argv = ['click', requireNumber(args, 'x'), requireNumber(args, 'y')]
      if (args.button !== undefined) argv.push('-button', String(args.button))
      if (args.count !== undefined) argv.push('-count', String(args.count))
      if (typeof args.window === 'string' && args.window.length > 0) argv.push('-window', args.window)
      if (typeof args.expect === 'string' && args.expect.length > 0) argv.push('-expect', args.expect)
      if (verify) argv.push('-verify')
      return { argv, json: verify }
    }
    case 'move':
      return { argv: ['move', requireNumber(args, 'x'), requireNumber(args, 'y')], json: false }
    case 'drag':
      return {
        argv: [
          'drag',
          requireNumber(args, 'x'),
          requireNumber(args, 'y'),
          requireNumber(args, 'x2'),
          requireNumber(args, 'y2'),
        ],
        json: false,
      }
    case 'scroll': {
      const amount = typeof args.amount === 'number' ? args.amount : 3
      if (typeof args.x === 'number' && typeof args.y === 'number') {
        return { argv: ['scroll', args.x, args.y, amount], json: false }
      }
      return { argv: ['scroll', amount], json: false }
    }
    case 'type': {
      // PowerShell's `-File` binding rejects a literal `--`, and bare positional text
      // starting with "-" is indistinguishable from a flag. Base64 the payload so both
      // problems disappear.
      const plain = requireString(args, 'text')
      const b64 = Buffer.from(plain, 'utf8').toString('base64')
      const argv = ['type', '-b64', b64]
      if (typeof args.window === 'string' && args.window.length > 0) argv.push('-window', args.window)
      const verify = args.verify === undefined ? config.verifyType !== false : args.verify === true
      if (verify) argv.push('-verify')
      return { argv, json: verify }
    }
    case 'key':
      return { argv: ['key', requireString(args, 'key')], json: false }
    case 'activate':
      return { argv: ['activate', requireString(args, 'window')], json: false }
    case 'pos':
      return { argv: ['pos'], json: false }
    case 'wait': {
      const ms = typeof args.waitMs === 'number' ? args.waitMs : 500
      return { argv: ['wait', ms], json: false }
    }
    case 'sequence': {
      const steps = Array.isArray(args.steps) ? args.steps : []
      if (steps.length === 0) throw new Error('desktop action "sequence" requires a non-empty "steps" array')
      if (steps.length > 24) throw new Error('desktop action "sequence" accepts at most 24 steps')
      const ops = steps.map((step, index) => {
        if (!step || typeof step !== 'object') throw new Error(`desktop sequence step ${index + 1} is not an object`)
        if (step.action === 'sequence') throw new Error('desktop sequence cannot nest another sequence')
        const built = buildArgs(step, config)
        return { ...argvToOp(built.argv), delayMs: typeof step.delayMs === 'number' ? step.delayMs : undefined }
      })
      // argv is materialised in execute(): the plan needs a temp file path.
      return { argv: null, json: false, seqOps: ops }
    }
    default:
      throw new Error(`desktop: unknown action "${action}"`)
  }
}

/** Split a gui.ps1 argv back into the {cmd,rest,opt} shape gui.ps1 seq expects. */
function argvToOp(argv) {
  const cmd = String(argv[0])
  const rest = []
  const opt = {}
  for (let i = 1; i < argv.length; i++) {
    const a = argv[i]
    const isFlag =
      typeof a === 'string' && a.length > 1 && a.startsWith('-') && !/^-?\d/.test(a) && a !== '--'
    if (isFlag) {
      const name = a.replace(/^-+/, '').toLowerCase()
      const next = argv[i + 1]
      const nextIsFlag =
        typeof next === 'string' &&
        next.length > 1 &&
        next.startsWith('-') &&
        !/^-?\d/.test(next) &&
        next !== '--'
      if (next === undefined || nextIsFlag) {
        opt[name] = true
      } else {
        opt[name] = next
        i++
      }
    } else {
      rest.push(a)
    }
  }
  return { cmd, rest, opt }
}

function runPowerShell(argv, config, signal) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      config.powershellPath,
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', SCRIPT, ...argv.map(String)],
      { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
    )
    let stdout = ''
    let stderr = ''
    let settled = false
    const finish = (error, value) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      signal?.removeEventListener('abort', onAbort)
      if (error) reject(error)
      else resolve(value)
    }
    const onAbort = () => {
      child.kill()
      finish(new Error('desktop: cancelled'))
    }
    const timer = setTimeout(() => {
      child.kill()
      finish(new Error(`desktop: timed out after ${config.timeoutMs} ms`))
    }, config.timeoutMs)
    signal?.addEventListener('abort', onAbort, { once: true })

    child.stdout.setEncoding('utf8')
    child.stderr.setEncoding('utf8')
    child.stdout.on('data', (chunk) => {
      stdout += chunk
    })
    child.stderr.on('data', (chunk) => {
      stderr += chunk
    })
    child.on('error', (error) => finish(error))
    child.on('close', (code) => {
      if (code !== 0) {
        finish(new Error(`desktop: gui.ps1 exited ${code}: ${(stderr || stdout).trim()}`))
        return
      }
      finish(undefined, { stdout: stdout.replace(/\r\n/g, "\n").trim(), stderr: stderr.replace(/\r\n/g, "\n").trim() })
    })
  })
}

/** `elements` returns one header + one row per control; cap the row count. */
function truncateRows(text, maxRows) {
  const lines = text.split('\n')
  if (!Number.isFinite(maxRows) || maxRows <= 0 || lines.length <= maxRows + 3) return text
  const header = lines.slice(0, 3)
  const rows = lines.slice(3)
  const kept = rows.slice(0, maxRows)
  const hidden = rows.length - kept.length
  return [...header, ...kept, `… ${hidden} more rows hidden (narrow with filter, or pass all:true)`].join('\n')
}

export function apply(ctx, userConfig = {}) {
  const config = { ...DEFAULTS, ...(userConfig || {}) }
  if (!config.enabled) return
  if (!existsSync(SCRIPT)) throw new Error(`desktop: bundled script missing at ${SCRIPT}`)
  const policy = normalizePolicy(config.policy)

  // Ask before irreversible actions (publish/send/submit). Without approval support the
  // host turns `ask` into a denial, which is the safe default.
  ctx.on('tools/pre-execute', async (exec, next) => {
    if (exec?.name !== 'desktop') return next()
    const decision = evaluatePolicy(policy, exec.arguments)
    if (decision?.kind === 'deny') {
      return {
        kind: 'deny',
        reason: decision.message,
        info: { name: 'DesktopActionPolicy', code: decision.code, reason: decision.code },
      }
    }
    if (decision?.kind === 'ask') return { kind: 'ask', reason: decision.message }
    return next()
  })

  /** OCR-based post-action check: after click/find, require args.verifyText to be visible. */
  async function attachPostCheck(args, result, signal) {
    if (typeof args.verifyText !== 'string' || args.verifyText.length === 0) return result
    try {
      const findArgs = { action: 'find', text: args.verifyText }
      if (typeof args.window === 'string' && args.window.length > 0) findArgs.window = args.window
      const built = buildArgs(findArgs, config)
      const { stdout } = await runPowerShell(built.argv, config, signal)
      const hits = stdout.split('\n').filter((line) => /^\d+,\d+,\d+,\d+\|/.test(line)).length
      result.verification = {
        status: hits > 0 ? 'verified' : 'unverified',
        method: 'post-action-find',
        detail:
          hits > 0
            ? `动作后 OCR 找到 ${hits} 处「${args.verifyText}」`
            : `动作后没有找到「${args.verifyText}」，结果可能未生效`,
        hits,
      }
    } catch (error) {
      result.verification = {
        status: 'unknown',
        method: 'post-action-find',
        detail: `动作后校验失败：${String(error.message).slice(0, 120)}`,
      }
    }
    return result
  }

  ctx.tools.register({
    name: 'desktop',
    description:
      'See and control the Windows desktop. Cheapest first: action=find locates on-screen text with local OCR and returns its exact coordinates (~30 tokens, no image, no network) — add click:true to hit it in the same call; action=elements gives UIA names + centre points for native controls; action=windows lists windows. Only then consider action=screenshot, which saves a PNG (cursor crosshair stamped, optional grid) and returns its path plus any scale factor — read grid labels as screen pixels, and if a scale is mentioned, convert with it. action=ocr dumps text + boxes from an image. Use action=sequence to chain several actions in ONE call — much cheaper than one call per action. Coordinates are physical pixels. Typical loop: find -> click (or find click:true) -> screenshot only to verify. Content policy is enforced before any action: dangerous target labels (支付/删除/delete…), sensitive windows (银行/Password…), credential-looking type payloads and denied key combos are refused. type checks the focused control is editable, refuses when it provably is not, and reads the value back; click hit-tests the point against the named window and reports the focused control. Use it only when a task truly has no CLI or API path.',
    parameters: PARAMETERS,
    output: {
      schema: OUTPUT,
      render(_args, value) {
        const parts = []
        if (value.imagePath) {
          parts.push(`Screenshot saved: ${value.imagePath}`)
          if (typeof value.width === 'number' && typeof value.height === 'number') {
            parts.push(`Size: ${value.width}x${value.height}`)
          }
          if (typeof value.scale === 'number' && value.scale > 0 && Math.abs(value.scale - 1) > 1e-6) {
            const factor = 1 / value.scale
            parts.push(
              `Scaled ${value.scale.toFixed(3)}x: on-image coordinates must be multiplied by ${factor.toFixed(3)} to become screen pixels.`,
            )
          }
          if (typeof value.gridStep === 'number' && value.gridStep > 0) {
            parts.push(
              `Blue grid lines are labelled with screen-pixel coordinates (every ${value.gridStep}px) — click those numbers directly.`,
            )
          }
        }
        if (value.output) parts.push(value.output)
        if (value.verification) {
          const v = value.verification
          parts.push(
            `Verification: ${v.status}${v.method ? ` (${v.method})` : ''}${v.detail ? ` — ${v.detail}` : ''}`,
          )
        }
        if (value.hitTest) parts.push(`Hit-test: ${value.hitTest.match === true ? 'ok' : 'FAILED'}`)
        if (Array.isArray(value.ambiguous) && value.ambiguous.length > 0) {
          parts.push(`Ambiguous, not clicked: ${value.ambiguous.join(' | ')}`)
        }
        return [{ type: 'text', text: parts.join('\n') || 'ok' }]
      },
    },
    isConcurrencySafe: () => false,
    timeoutMs: config.timeoutMs + 5_000,
    async execute(args, exec) {
      // `ask` decisions are handled by the pre-execute listener (approved ⇒ execute runs);
      // here only hard denials stop the call as a backstop.
      const decision = evaluatePolicy(policy, args)
      if (decision?.kind === 'deny') {
        const error = new Error(decision.message)
        error.code = decision.code
        throw error
      }
      const built = buildArgs(args, config)
      const { json, seqOps } = built

      let argv = built.argv
      let tempFile
      if (seqOps) {
        tempFile = join(tmpdir(), `dsh-desktop-seq-${process.pid}-${Date.now()}.json`)
        writeFileSync(tempFile, JSON.stringify(seqOps), 'utf8')
        argv = ['seq', '-file', tempFile]
      }

      let stdout
      try {
        ;({ stdout } = await runPowerShell(argv, config, exec?.signal))
      } finally {
        if (tempFile) {
          try {
            rmSync(tempFile, { force: true })
          } catch {
            /* ignore */
          }
        }
      }

      if (json) {
        let parsed
        try {
          parsed = JSON.parse(stdout)
        } catch {
          throw new Error(`desktop: gui.ps1 returned non-JSON for ${args.action}: ${stdout.slice(0, 400)}`)
        }
        const isShot = typeof parsed.path === 'string'
        if (args.action === 'screenshot') pruneShots(config)
        // Build the result without `undefined` fields: the host requires lossless JSON.
        const result = { ok: true, action: args.action }
        if (isShot) {
          result.imagePath = parsed.path
          if (typeof parsed.width === 'number') result.width = parsed.width
          if (typeof parsed.height === 'number') result.height = parsed.height
          if (typeof parsed.scale === 'number') result.scale = parsed.scale
          if (typeof parsed.gridStep === 'number') result.gridStep = parsed.gridStep
        } else {
          // Structured action result: click-by-UIA, or a verification-carrying
          // click/type. Verification refusals are honest failures, not successes.
          if (parsed.ok === false) {
            throw new Error(`desktop ${args.action}: ${parsed.reason ?? 'verification refused to act'}`)
          }
          if (parsed.verification !== undefined) result.verification = parsed.verification
          if (parsed.hitTest !== undefined) result.hitTest = parsed.hitTest
          if (parsed.focus !== undefined) result.focus = parsed.focus
          if (Array.isArray(parsed.ambiguous)) result.ambiguous = parsed.ambiguous
          if (typeof parsed.typed === 'number') result.output = `pasted ${parsed.typed} chars`
          else if (parsed.clicked !== undefined) result.output = `clicked ${JSON.stringify(parsed.clicked)}`
          else result.output = stdout
        }
        return attachPostCheck(args, result, exec?.signal)
      }

      let output = stdout
      if (args.action === 'elements') {
        const cap = args.all === true ? 0 : Number(config.elementsMaxRows)
        output = truncateRows(stdout, cap)
      }
      return attachPostCheck(args, { ok: true, action: args.action, output }, exec?.signal)
    },
  })
}
