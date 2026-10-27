// Content policy for the desktop tool.
//
// The model can read untrusted screen text (a chat message, a web page, a window
// title) and then ask the tool to click or type. This module inspects the pending
// call before PowerShell is spawned and refuses dangerous targets, sensitive
// windows, credential-looking payloads and forbidden key combos.
//
// Pure functions only: no desktop access, no spawning, fully unit-testable.

export const DEFAULT_POLICY = {
  // Master switch. A deployment that wants the old behaviour sets enabled: false.
  enabled: true,
  // Target text / UIA control names that must never be clicked or located.
  denyLabels: [
    '支付', '转账', '确认支付', '确认购买', '充值', '提现',
    '删除', '卸载', '格式化', '清空', '退出登录', '注销',
    '购买', '下单',
    'pay', 'transfer', 'checkout', 'purchase', 'withdraw', 'recharge',
    'delete', 'uninstall', 'format', 'wipe', 'log out', 'sign out',
  ],
  // Window-title fragments whose content must not be read or driven.
  sensitiveWindows: [
    '银行', '支付', '钱包', '密码', 'Password', 'Bank', 'Wallet', '凭证', 'Authenticator',
  ],
  // Refuse `type` payloads that look like credentials.
  refuseSecrets: true,
  // Key combos to refuse, order-insensitive.
  denyKeys: [],
  // Irreversible click/find targets. `irreversibleMode`:
  //   'ask'   — ask the host/user to approve (falls back to denial without approval support)
  //   'deny'  — always refuse
  //   'allow' — no extra gate (denyLabels still apply)
  irreversibleLabels: ['发布', '发送', '提交', '发表', '上架', 'publish', 'send', 'submit'],
  irreversibleMode: 'ask',
  // Sequence nesting level above which a call is refused instead of inspected.
  maxSequenceDepth: 5,
}

const READ_ACTIONS = new Set(['screenshot', 'elements', 'find', 'ocr'])
const DRIVE_ACTIONS = new Set(['click', 'type', 'activate', 'move', 'drag', 'scroll'])
const LABEL_ACTIONS = new Set(['click', 'find'])

const SECRET_PATTERNS = [
  /^\s*sk-[A-Za-z0-9_-]{10,}/u,
  /\b(?:api[_\-\s]?key|access[_\-\s]?token|secret[_\-\s]?key|bearer)\b\s*[:=]/iu,
  /(?:密码|口令|password|passwd)\s*[:：=]/iu,
]

/** Normalize text for matching: case, width and whitespace insensitive. */
export function normalizeText(value) {
  return String(value ?? '')
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[\s\u200b-\u200f\u2060\ufeff\u3000]+/gu, '')
}

/** Normalize a key combo so order does not matter. */
export function normalizeCombo(combo) {
  return String(combo ?? '')
    .toLowerCase()
    .split('+')
    .map((part) => part.trim())
    .filter(Boolean)
    .sort()
    .join('+')
}

function asStringArray(value, fallback) {
  if (!Array.isArray(value)) return fallback
  const kept = value.filter((item) => typeof item === 'string' && item.length > 0)
  return kept.length > 0 ? kept : fallback
}

/** Merge user policy over the defaults (user lists replace, not merge). */
export function normalizePolicy(raw) {
  const config = { ...DEFAULT_POLICY, ...(raw && typeof raw === 'object' ? raw : {}) }
  config.enabled = config.enabled !== false
  config.denyLabels = asStringArray(config.denyLabels, DEFAULT_POLICY.denyLabels)
  config.sensitiveWindows = asStringArray(config.sensitiveWindows, DEFAULT_POLICY.sensitiveWindows)
  config.denyKeys = asStringArray(config.denyKeys, DEFAULT_POLICY.denyKeys)
  config.irreversibleLabels = asStringArray(config.irreversibleLabels, DEFAULT_POLICY.irreversibleLabels)
  config.irreversibleMode = ['ask', 'deny', 'allow'].includes(config.irreversibleMode)
    ? config.irreversibleMode
    : DEFAULT_POLICY.irreversibleMode
  config.refuseSecrets = config.refuseSecrets !== false
  const depth = Number(config.maxSequenceDepth)
  config.maxSequenceDepth = Number.isFinite(depth) && depth > 0 ? Math.trunc(depth) : DEFAULT_POLICY.maxSequenceDepth
  return config
}

function matchedWord(words, text) {
  const hay = normalizeText(text)
  if (hay.length === 0) return undefined
  for (const word of words) {
    const needle = normalizeText(word)
    if (needle.length > 0 && hay.includes(needle)) return word
  }
  return undefined
}

function refusal(kind, code, message, path) {
  const where = path ? `（位置 ${path}）` : ''
  return {
    kind,
    code,
    message:
      `桌面操作策略${kind === 'ask' ? '需要确认' : '拒绝'}${where}：${message}。` +
      (kind === 'ask'
        ? '这是不可逆动作，需要用户批准；没有批准支持时按拒绝处理。'
        : '这是安全策略拦截，不是工具故障；不要换个说法重试；确需操作请让用户调整插件配置（policy.*）。'),
  }
}

/**
 * Inspect one pending desktop call.
 * @param {object} policy resolved policy (see normalizePolicy)
 * @param {object} args tool arguments
 * @param {number} [depth] sequence nesting depth
 * @param {string} [inheritedWindow] window inherited from a parent sequence step
 * @param {string} [path] diagnostic path such as "steps[1]"
 * @returns {{kind: 'deny'|'ask', code: string, message: string}|undefined} decision, or undefined to allow
 */
export function evaluatePolicy(policy, args, depth = 0, inheritedWindow, path = '') {
  if (!policy || policy.enabled !== true) return undefined
  if (!args || typeof args !== 'object' || Array.isArray(args)) return undefined

  const action = typeof args.action === 'string' ? args.action : ''
  const ownWindow = typeof args.window === 'string' && args.window.length > 0 ? args.window : undefined
  const window = ownWindow ?? inheritedWindow

  if (depth > policy.maxSequenceDepth) {
    return refusal('deny', 'POLICY_SEQUENCE_DEPTH', `sequence 嵌套超过 ${policy.maxSequenceDepth} 层，无法逐层审查`, path)
  }

  if (window !== undefined && (READ_ACTIONS.has(action) || DRIVE_ACTIONS.has(action))) {
    const hit = matchedWord(policy.sensitiveWindows, window)
    if (hit !== undefined) {
      return refusal('deny', 'POLICY_SENSITIVE_WINDOW', `目标窗口标题命中敏感窗口词「${hit}」，不读取也不操作`, path)
    }
  }

  if (LABEL_ACTIONS.has(action)) {
    for (const source of ['text', 'uia']) {
      const value = args[source]
      if (typeof value !== 'string') continue
      const hit = matchedWord(policy.denyLabels, value)
      if (hit !== undefined) {
        const target = value.trim().replace(/\s+/gu, ' ')
        const shown = target.length > 48 ? `${target.slice(0, 48)}…` : target
        return refusal('deny', 'POLICY_DANGEROUS_LABEL', `目标文字「${shown}」命中禁止操作词「${hit}」（${source}）`, path)
      }
    }
  }

  if (LABEL_ACTIONS.has(action) && policy.irreversibleMode !== 'allow') {
    for (const source of ['text', 'uia']) {
      const value = args[source]
      if (typeof value !== 'string') continue
      const hit = matchedWord(policy.irreversibleLabels, value)
      if (hit !== undefined) {
        const target = value.trim().replace(/\s+/gu, ' ')
        const shown = target.length > 48 ? `${target.slice(0, 48)}…` : target
        return refusal(
          policy.irreversibleMode === 'deny' ? 'deny' : 'ask',
          'POLICY_IRREVERSIBLE_ACTION',
          `目标文字「${shown}」是不可逆动作（${hit}），需要确认`,
          path,
        )
      }
    }
  }

  if (action === 'key' && typeof args.key === 'string' && policy.denyKeys.length > 0) {
    const wanted = normalizeCombo(args.key)
    const hit = policy.denyKeys.find((combo) => normalizeCombo(combo) === wanted)
    if (hit !== undefined) return refusal('deny', 'POLICY_DENY_KEY', `快捷键「${hit}」在禁止列表里`, path)
  }

  if (action === 'type' && policy.refuseSecrets && typeof args.text === 'string') {
    if (SECRET_PATTERNS.some((pattern) => pattern.test(args.text))) {
      return refusal('deny', 'POLICY_SECRET_TEXT', '要输入的内容看起来是密钥/密码类机密，不代输', path)
    }
  }

  if (action === 'sequence' && Array.isArray(args.steps)) {
    for (let index = 0; index < args.steps.length; index += 1) {
      const nestedPath = path.length > 0 ? `${path}.steps[${index}]` : `steps[${index}]`
      const nested = evaluatePolicy(policy, args.steps[index], depth + 1, window, nestedPath)
      if (nested !== undefined) return nested
    }
  }

  return undefined
}
