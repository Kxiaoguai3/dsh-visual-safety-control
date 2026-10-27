// Pure unit tests for argv construction, policy evaluation and argument validation.
// Nothing here touches the real desktop: no screenshots, no mouse, no keyboard.
import assert from 'node:assert/strict'
import { buildArgs } from '../dsh/index.js'
import { DEFAULT_POLICY, evaluatePolicy, normalizePolicy } from '../dsh/policy.js'

const CFG = {
  screenshotDir: 'C:\\shots',
  screenshotMaxWidth: 1440,
  screenshotGrid: false,
  screenshotCursor: true,
  verifyType: true,
  verifyClick: true,
}

// screenshot: absolute .png path + cursor; the grid is opt-in (its labels are read
// as text by OCR/vision-to-text engines and cost tokens).
{
  const { argv, json } = buildArgs({ action: 'screenshot' }, CFG)
  assert.equal(argv[0], 'shot')
  assert.match(argv[1], /C:\\shots\\shot-\d{8}-\d{6}-\d{3}\.png$/)
  assert.deepEqual(argv.slice(2), ['-cursor', '-maxwidth', '1440'])
  assert.equal(json, true)
}

// grid:true turns the coordinate grid on.
{
  const { argv } = buildArgs({ action: 'screenshot', grid: true }, CFG)
  assert.ok(argv.includes('-grid'))
}

// find: local OCR lookup, optionally clicking the hit; exact/index are fork additions.
{
  assert.deepEqual(buildArgs({ action: 'find', text: '保存' }).argv, ['find', '保存'])
  assert.deepEqual(
    buildArgs({ action: 'find', text: '保存', window: '记事本', threshold: 0.4, click: true }).argv,
    ['find', '保存', '-window', '记事本', '-threshold', '0.4', '-click'],
  )
  assert.deepEqual(buildArgs({ action: 'find', text: '插入', screen: true, button: 'right' }).argv, [
    'find',
    '插入',
    '-screen',
    '-button',
    'right',
  ])
  assert.deepEqual(buildArgs({ action: 'find', text: '发送', exact: true }).argv, ['find', '发送', '-exact'])
  assert.deepEqual(buildArgs({ action: 'find', text: '发送', click: true, index: 2 }).argv, [
    'find',
    '发送',
    '-index',
    '2',
    '-click',
  ])
  assert.throws(() => buildArgs({ action: 'find' }), /requires a non-empty "text"/)
}

// screenshot: everything can be switched off, and window/region/print still pass through.
{
  const { argv } = buildArgs(
    {
      action: 'screenshot',
      window: '记事本',
      region: '0,0,800,600',
      print: true,
      grid: false,
      cursor: false,
      maxWidth: 0,
    },
    CFG,
  )
  assert.deepEqual(argv.slice(2), ['-window', '记事本', '-region', '0,0,800,600', '-print'])
}

// screenshot: explicit maxWidth overrides the configured default.
{
  const { argv } = buildArgs({ action: 'screenshot', maxWidth: 900 }, CFG)
  assert.equal(argv.at(-1), '900')
  assert.equal(argv.at(-2), '-maxwidth')
}

// elements: no image involved; window/filter/depth/all flags.
{
  assert.deepEqual(buildArgs({ action: 'elements' }).argv, ['elements'])
  assert.deepEqual(buildArgs({ action: 'elements', window: '记事本', filter: '保存', depth: 5 }).argv, [
    'elements',
    '-window',
    '记事本',
    '-filter',
    '保存',
    '-depth',
    '5',
  ])
  assert.deepEqual(buildArgs({ action: 'elements', all: true }).argv, ['elements', '-all'])
}

// ocr: image path is absolutised so gui.ps1 (different cwd) still finds it.
{
  const { argv } = buildArgs({ action: 'ocr', imagePath: 'shot.png' })
  assert.equal(argv[0], 'ocr')
  assert.match(argv[1], /[\\/]shot\.png$/)
  assert.ok(argv[1].includes(':'), 'expected an absolute Windows path')
  assert.deepEqual(buildArgs({ action: 'ocr', imagePath: 'C:\\a\\b.png', filter: '保存' }).argv, [
    'ocr',
    'C:\\a\\b.png',
    '-filter',
    '保存',
  ])
  assert.throws(() => buildArgs({ action: 'ocr' }), /requires a non-empty "imagePath"/)
}

// windows: optional row cap.
{
  assert.deepEqual(buildArgs({ action: 'windows' }).argv, ['windows'])
  assert.deepEqual(buildArgs({ action: 'windows', top: 5 }).argv, ['windows', '-top', '5'])
}

// click: coordinates stay the default path; a uia name switches to control lookup.
{
  const plain = buildArgs({ action: 'click', x: 10, y: 20, button: 'right', count: 2 }, CFG)
  assert.deepEqual(plain.argv, ['click', 10, 20, '-button', 'right', '-count', '2', '-verify'])
  assert.equal(plain.json, true, 'verification returns structured JSON')
  assert.throws(() => buildArgs({ action: 'click', x: 10 }), /requires a numeric "y"/)

  const byName = buildArgs({ action: 'click', uia: '保存', window: '记事本', invoke: true }, CFG)
  assert.deepEqual(byName.argv, ['click', '-uia', '保存', '-window', '记事本', '-invoke', '-verify'])
  assert.equal(byName.json, true)

  // uia wins over x/y when both are present.
  assert.deepEqual(buildArgs({ action: 'click', uia: '保存', x: 1, y: 2 }, CFG).argv, [
    'click',
    '-uia',
    '保存',
    '-verify',
  ])

  // hit-test needs the window name; verify can be switched off per call.
  const hit = buildArgs({ action: 'click', x: 10, y: 20, window: '记事本' }, CFG)
  assert.deepEqual(hit.argv, ['click', 10, 20, '-window', '记事本', '-verify'])
  const noVerify = buildArgs({ action: 'click', x: 10, y: 20, verify: false }, CFG)
  assert.deepEqual(noVerify.argv, ['click', 10, 20])
  assert.equal(noVerify.json, false)

  // expect guards against stale coordinates by OCR-checking the landing area.
  const guarded = buildArgs({ action: 'click', x: 10, y: 20, expect: '发布' }, CFG)
  assert.deepEqual(guarded.argv, ['click', 10, 20, '-expect', '发布', '-verify'])
}

// sequence: becomes an ops list for gui.ps1 seq (file is written at execute time).
{
  const { argv, seqOps } = buildArgs(
    {
      action: 'sequence',
      steps: [
        { action: 'click', x: 10, y: 20, verify: false },
        { action: 'wait', waitMs: 300, delayMs: 0 },
        { action: 'screenshot', maxWidth: 800, grid: false },
      ],
    },
    CFG,
  )
  assert.equal(argv, null)
  assert.equal(seqOps.length, 3)
  assert.deepEqual(seqOps[0], { cmd: 'click', rest: [10, 20], opt: {}, delayMs: undefined })
  assert.deepEqual(seqOps[1], { cmd: 'wait', rest: [300], opt: {}, delayMs: 0 })
  assert.equal(seqOps[2].cmd, 'shot')
  assert.equal(seqOps[2].opt.maxwidth, '800')
  assert.equal(seqOps[2].opt.grid, undefined)

  assert.throws(() => buildArgs({ action: 'sequence' }), /non-empty "steps"/)
  assert.throws(() => buildArgs({ action: 'sequence', steps: [{ action: 'sequence', steps: [] }] }), /cannot nest/)
}

// type: the payload rides in base64 (`-File` binding rejects `--`, and bare text
// starting with "-" looks like a flag); verification and an optional window are
// fork additions.
{
  const b64 = (text) => Buffer.from(text, 'utf8').toString('base64')
  const plain = buildArgs({ action: 'type', text: '-not-a-flag 中文' }, CFG)
  assert.deepEqual(plain.argv, ['type', '-b64', b64('-not-a-flag 中文'), '-verify'])
  assert.equal(plain.json, true)
  const withWindow = buildArgs({ action: 'type', text: '你好', window: '记事本' }, CFG)
  assert.deepEqual(withWindow.argv, ['type', '-b64', b64('你好'), '-window', '记事本', '-verify'])
  const noVerify = buildArgs({ action: 'type', text: '你好', verify: false }, CFG)
  assert.deepEqual(noVerify.argv, ['type', '-b64', b64('你好')])
  assert.equal(noVerify.json, false)
}

// scroll has both positional and point forms.
{
  assert.deepEqual(buildArgs({ action: 'scroll', amount: -2 }).argv, ['scroll', -2])
  assert.deepEqual(buildArgs({ action: 'scroll', x: 5, y: 6, amount: 3 }).argv, ['scroll', 5, 6, 3])
}

// move / drag / key / activate / pos / wait.
{
  assert.deepEqual(buildArgs({ action: 'move', x: 1, y: 2 }).argv, ['move', 1, 2])
  assert.deepEqual(buildArgs({ action: 'drag', x: 1, y: 2, x2: 3, y2: 4 }).argv, ['drag', 1, 2, 3, 4])
  assert.deepEqual(buildArgs({ action: 'key', key: 'ctrl+s' }).argv, ['key', 'ctrl+s'])
  assert.deepEqual(buildArgs({ action: 'activate', window: 'DeepSeek' }).argv, ['activate', 'DeepSeek'])
  assert.deepEqual(buildArgs({ action: 'pos' }).argv, ['pos'])
  assert.deepEqual(buildArgs({ action: 'wait', waitMs: 600 }).argv, ['wait', 600])
}

// unknown action is rejected.
assert.throws(() => buildArgs({ action: 'teleport' }), /unknown action/)

/* ------------------------------------------------------------------ */
/* content policy                                                      */
/* ------------------------------------------------------------------ */

const POLICY = normalizePolicy({
  denyLabels: ['删除', 'delete', '转账', 'pay'],
  sensitiveWindows: ['银行', 'Password'],
  denyKeys: ['alt+f4'],
  irreversibleMode: 'allow',
  maxSequenceDepth: 2,
})
const check = (args) => evaluatePolicy(POLICY, args)

// Dangerous labels, normalized across spaces/width/case, in text and UIA names.
{
  assert.match(check({ action: 'click', text: '删除' }).code, /DANGEROUS_LABEL/)
  assert.match(check({ action: 'click', text: '删 除' }).code, /DANGEROUS_LABEL/)
  assert.match(check({ action: 'click', text: 'ＤＥＬＥＴＥ' }).code, /DANGEROUS_LABEL/)
  assert.match(check({ action: 'click', uia: 'Delete all messages' }).code, /DANGEROUS_LABEL/)
  assert.match(check({ action: 'find', text: '确认转账' }).code, /DANGEROUS_LABEL/)
}

// Harmless targets and non-target actions pass.
{
  assert.equal(check({ action: 'click', text: '发送', window: '微信' }), undefined)
  assert.equal(check({ action: 'click', x: 10, y: 20 }), undefined)
  assert.equal(check({ action: 'windows' }), undefined)
  assert.equal(check({ action: 'type', text: '把这句话删掉' }), undefined, 'type payload is not a target')
}

// Sensitive windows block reading and driving, but not window listing.
{
  for (const action of ['screenshot', 'elements', 'find', 'click', 'type', 'activate']) {
    assert.match(check({ action, text: '确定', window: '招商银行' }).code, /SENSITIVE_WINDOW/)
  }
  assert.equal(check({ action: 'windows', window: '银行' }), undefined)
}

// Credential-looking payloads are refused; plain typing is allowed.
{
  assert.match(check({ action: 'type', text: 'sk-live-abcdefghijkl' }).code, /SECRET_TEXT/)
  assert.match(check({ action: 'type', text: 'password=abc' }).code, /SECRET_TEXT/)
  assert.equal(check({ action: 'type', text: '你好，今天天气不错' }), undefined)
}

// Configured key combos are denied order-insensitively.
{
  assert.match(check({ action: 'key', key: 'alt+f4' }).code, /DENY_KEY/)
  assert.match(check({ action: 'key', key: 'F4+ALT' }).code, /DENY_KEY/)
  assert.equal(check({ action: 'key', key: 'ctrl+s' }), undefined)
}

// Sequence: nested steps are inspected, the parent window is inherited, and deep
// nesting is refused instead of silently allowed.
{
  assert.match(check({ action: 'sequence', steps: [{ action: 'click', text: '删除' }] }).message, /steps\[0\]/)
  assert.match(
    check({ action: 'sequence', window: '某银行', steps: [{ action: 'click', x: 1, y: 2 }] }).code,
    /SENSITIVE_WINDOW/,
  )
  let deep = { action: 'click', x: 1, y: 2 }
  for (let i = 0; i < 4; i += 1) deep = { action: 'sequence', steps: [deep] }
  assert.match(check(deep).code, /SEQUENCE_DEPTH/)
}

// Malformed arguments never throw.
{
  assert.equal(check(undefined), undefined)
  assert.equal(check('nope'), undefined)
  assert.equal(check({ action: 42 }), undefined)
  assert.equal(check({ action: 'sequence', steps: 'nope' }), undefined)
}

// Disabled policy allows everything; user lists replace the defaults.
{
  assert.equal(evaluatePolicy(normalizePolicy({ enabled: false }), { action: 'click', text: '删除' }), undefined)
  const custom = normalizePolicy({ denyLabels: ['关机'] })
  assert.equal(evaluatePolicy(custom, { action: 'click', text: '删除' }), undefined)
  assert.match(evaluatePolicy(custom, { action: 'click', text: '关机' }).code, /DANGEROUS_LABEL/)
  assert.ok(DEFAULT_POLICY.denyLabels.length > 0)
  assert.ok(normalizePolicy(undefined).denyLabels.includes('删除'))
}

// Irreversible actions: ask by default, deny when configured, allow when opted out.
{
  const ask = normalizePolicy({ irreversibleMode: 'ask' })
  const askDecision = evaluatePolicy(ask, { action: 'click', text: '发布' })
  assert.equal(askDecision.kind, 'ask')
  assert.match(askDecision.code, /IRREVERSIBLE/)
  assert.equal(evaluatePolicy(ask, { action: 'click', text: '发送' }).kind, 'ask')

  const deny = normalizePolicy({ irreversibleMode: 'deny' })
  assert.equal(evaluatePolicy(deny, { action: 'click', text: '发布' }).kind, 'deny')

  const allow = normalizePolicy({ irreversibleMode: 'allow' })
  assert.equal(evaluatePolicy(allow, { action: 'click', text: '发布' }), undefined)

  // A hard-denied label still wins over the irreversible gate.
  const both = normalizePolicy({ irreversibleMode: 'allow', denyLabels: ['删除'] })
  assert.equal(evaluatePolicy(both, { action: 'click', text: '删除' }).kind, 'deny')

  // Sequence steps inherit the same gate and keep the diagnostic path.
  const nested = evaluatePolicy(ask, { action: 'sequence', steps: [{ action: 'click', text: '发布' }] })
  assert.equal(nested.kind, 'ask')
  assert.match(nested.message, /steps\[0\]/)
}

console.log('selftest ok: argv construction, policy evaluation and validation behave as expected')
