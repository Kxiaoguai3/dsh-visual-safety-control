/**
 * dsh-visual-safety-control — browser half.
 *
 * One contribution: the "视觉安全" page inside Settings → Plugins. It edits the
 * plugin's volatile `policy` config through the Host half's same-origin JSON
 * route, so a save lands in the profile patch and applies on the next tool call.
 *
 * Hand-written for the Web module loader: the file the registry serves is the
 * file the browser executes, no build step.
 */
window.__ModuleLoader__.load({
  id: 'dsh-visual-safety-control',
  factory: (require) => {
    const module = { exports: {} }
    const exports = module.exports
    Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' })

    const React = require('react')
    const h = React.createElement

    /** Host route prefix. */
    const BASE = '/dsh-visual-safety-control'
    /** Dictionary namespace owned by this plugin. */
    const NS = 'visualSafetyControl'

    const zh = {
      'tab.label': '视觉安全',
      'title': '视觉安全控制',
      'subtitle': '控制桌面工具的内容策略。修改保存后，下一次工具调用立即生效，不需要重启。',
      'section.basic': '基本',
      'field.enabled': '启用内容策略',
      'field.enabledHint': '关闭后危险标签、敏感窗口等检查全部失效，仅建议在隔离的测试机上使用。',
      'field.refuseSecrets': '拒绝疑似凭据的输入',
      'field.refuseSecretsHint': '输入内容像 API key、访问令牌或密码时直接拒绝。',
      'section.labels': '拦截词表',
      'field.denyLabels': '危险标签',
      'field.denyLabelsHint': '每行一个。点击或查找这些文字会被拒绝，例如：支付、删除、卸载。',
      'field.sensitiveWindows': '敏感窗口',
      'field.sensitiveWindowsHint': '每行一个。标题包含这些词的窗口不会被读取或操作，例如：银行、密码。',
      'field.irreversibleLabels': '不可逆动作标签',
      'field.irreversibleLabelsHint': '每行一个。匹配到这些标签时按下面的方式处理，例如：发布、发送、提交。',
      'field.irreversibleMode': '不可逆动作的处理方式',
      'mode.ask': '请求确认',
      'mode.deny': '直接拒绝',
      'mode.allow': '允许执行',
      'field.denyKeys': '拒绝的快捷键',
      'field.denyKeysHint': '每行一个组合键，例如：alt+f4、ctrl+shift+delete。',
      'field.maxSequenceDepth': '序列最大嵌套层数',
      'field.maxSequenceDepthHint': 'sequence 动作递归检查的最大深度，超过即拒绝。',
      'action.save': '保存',
      'action.saving': '保存中…',
      'action.reset': '恢复默认',
      'status.saved': '已保存，下一次工具调用生效。',
      'status.loading': '加载中…',
      'status.reset': '已填入默认值，点保存后生效。',
      'footer': '策略在 PowerShell 启动前生效；模型无法通过工具参数关闭它。值保存在当前 profile 的插件配置里。',
    }

    const en = {
      'tab.label': 'Visual safety',
      'title': 'Visual safety control',
      'subtitle': 'Content policy for the desktop tool. Saves apply on the next tool call — no restart.',
      'section.basic': 'Basics',
      'field.enabled': 'Enable content policy',
      'field.enabledHint': 'Turning this off disables every label, window and secret check. Use it only on an isolated test machine.',
      'field.refuseSecrets': 'Refuse credential-looking input',
      'field.refuseSecretsHint': 'Reject typed payloads that look like API keys, access tokens or passwords.',
      'section.labels': 'Lists',
      'field.denyLabels': 'Dangerous labels',
      'field.denyLabelsHint': 'One per line. Clicking or locating these labels is refused, e.g. pay, delete, uninstall.',
      'field.sensitiveWindows': 'Sensitive windows',
      'field.sensitiveWindowsHint': 'One per line. Windows whose title contains these words are never read or driven, e.g. Bank, Password.',
      'field.irreversibleLabels': 'Irreversible labels',
      'field.irreversibleLabelsHint': 'One per line. Matching labels are handled by the mode below, e.g. publish, send, submit.',
      'field.irreversibleMode': 'Irreversible action mode',
      'mode.ask': 'Ask for confirmation',
      'mode.deny': 'Refuse',
      'mode.allow': 'Allow',
      'field.denyKeys': 'Refused key combos',
      'field.denyKeysHint': 'One per line, e.g. alt+f4.',
      'field.maxSequenceDepth': 'Max sequence depth',
      'field.maxSequenceDepthHint': 'Nesting depth the sequence action inspects before refusing.',
      'action.save': 'Save',
      'action.saving': 'Saving…',
      'action.reset': 'Restore defaults',
      'status.saved': 'Saved; applies on the next tool call.',
      'status.loading': 'Loading…',
      'status.reset': 'Defaults filled in — press Save to apply.',
      'footer': 'The policy runs before PowerShell is spawned; tool arguments cannot disable it. Values live in the current profile\u2019s plugin config.',
    }

    const css = [
      '.dshVsc_root{display:flex;flex-direction:column;gap:16px;font:inherit;color:var(--dsw-alias-label-primary);max-width:760px}',
      '.dshVsc_head{display:flex;flex-direction:column;gap:4px}',
      '.dshVsc_title{font-size:15px;font-weight:600;line-height:22px}',
      '.dshVsc_sub{color:var(--dsw-alias-label-tertiary);font-size:12px;line-height:18px}',
      '.dshVsc_group{border:.5px solid var(--dsw-alias-border-l4);border-radius:var(--dsw-radius-lg);background:var(--dsw-alias-bg-layer-1);padding:14px 16px;display:flex;flex-direction:column;gap:14px}',
      '.dshVsc_groupTitle{font-size:12px;font-weight:600;color:var(--dsw-alias-label-secondary);letter-spacing:.02em}',
      '.dshVsc_row{display:flex;gap:12px;align-items:flex-start;justify-content:space-between}',
      '.dshVsc_rowCol{display:flex;flex-direction:column;gap:4px;flex:1;min-width:0}',
      '.dshVsc_label{font-size:13px;line-height:18px}',
      '.dshVsc_hint{color:var(--dsw-alias-label-caption);font-size:11px;line-height:16px}',
      '.dshVsc_area{width:100%;box-sizing:border-box;min-height:74px;resize:vertical;border:.5px solid var(--dsw-alias-border-l4);border-radius:var(--dsw-radius-sm);background:var(--dsw-alias-bg-layer-2);color:var(--dsw-alias-label-primary);font:inherit;font-size:12px;line-height:18px;padding:8px 10px}',
      '.dshVsc_input{border:.5px solid var(--dsw-alias-border-l4);border-radius:var(--dsw-radius-sm);background:var(--dsw-alias-bg-layer-2);color:var(--dsw-alias-label-primary);font:inherit;font-size:12px;line-height:18px;height:28px;padding:0 8px;width:90px}',
      '.dshVsc_select{border:.5px solid var(--dsw-alias-border-l4);border-radius:var(--dsw-radius-sm);background:var(--dsw-alias-bg-layer-2);color:var(--dsw-alias-label-primary);font:inherit;font-size:12px;line-height:18px;height:28px;padding:0 8px}',
      '.dshVsc_btn{border:.5px solid var(--dsw-alias-border-l4);border-radius:var(--dsw-radius-sm);height:28px;padding:0 12px;font:inherit;font-size:12px;line-height:18px;color:var(--dsw-alias-label-primary);background:0 0;cursor:pointer}',
      '.dshVsc_btn:hover:not(:disabled){background:var(--dsw-alias-interactive-bg-hover)}',
      '.dshVsc_btn:disabled{opacity:.4;cursor:default}',
      '.dshVsc_btnPrimary{border-color:var(--dsw-alias-button-primary-fill);background:var(--dsw-alias-button-primary-fill);color:var(--dsw-alias-label-primary-foreground)}',
      '.dshVsc_actions{display:flex;gap:8px;align-items:center}',
      '.dshVsc_status{font-size:12px;line-height:18px;color:var(--dsw-alias-label-caption)}',
      '.dshVsc_statusError{color:var(--dsw-alias-state-error-primary)}',
      '.dshVsc_switch{position:relative;width:36px;height:20px;border-radius:999px;border:.5px solid var(--dsw-alias-border-l4);background:var(--dsw-alias-bg-layer-2);cursor:pointer;flex-shrink:0;padding:0}',
      '.dshVsc_switchOn{border-color:var(--dsw-alias-button-primary-fill);background:var(--dsw-alias-button-primary-fill)}',
      '.dshVsc_knob{position:absolute;top:2px;left:2px;width:16px;height:16px;border-radius:50%;background:var(--dsw-alias-label-primary-foreground);transition:left .12s}',
      '.dshVsc_switchOn .dshVsc_knob{left:18px}',
      '.dshVsc_footer{color:var(--dsw-alias-label-caption);font-size:11px;line-height:16px}',
    ].join('')

    const tagId = 'dsh-visual-safety-control/ui.css'
    if (typeof document !== 'undefined' && document.querySelector('style[data-plugin-css=' + JSON.stringify(tagId) + ']') === null) {
      const tag = document.createElement('style')
      tag.dataset.plugin = 'dsh-visual-safety-control'
      tag.dataset.pluginCss = tagId
      tag.textContent = css
      document.head.appendChild(tag)
    }

    /** Fetch the current policy. */
    async function loadPolicy() {
      const response = await fetch(`${BASE}/policy.json`, { headers: { accept: 'application/json' } })
      const value = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(value?.error ?? `HTTP ${response.status}`)
      return value
    }

    /** Persist one policy object. */
    async function savePolicy(policy) {
      const response = await fetch(`${BASE}/policy.json`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ policy }),
      })
      const value = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(value?.error ?? `HTTP ${response.status}`)
      return value
    }

    const toLines = (list) => (Array.isArray(list) ? list.join('\n') : '')
    const toList = (text) =>
      String(text ?? '')
        .split('\n')
        .map((line) => line.trim())
        .filter((line) => line.length > 0)

    /** One switch control. */
    function Switch({ checked, onChange, label }) {
      return h(
        'button',
        {
          type: 'button',
          role: 'switch',
          'aria-checked': checked === true,
          'aria-label': label,
          className: `dshVsc_switch${checked === true ? ' dshVsc_switchOn' : ''}`,
          onClick: () => onChange(checked !== true),
        },
        h('span', { className: 'dshVsc_knob' }),
      )
    }

    /** The Settings → Plugins → 视觉安全 page. */
    function PolicyPage(props) {
      const dict = props?.t === undefined ? (key) => zh[key] ?? key : (key) => props.t(key)
      const text = (key) => dict(key)

      const [state, setState] = React.useState({ phase: 'loading', error: null, message: null })
      const [draft, setDraft] = React.useState(null)
      const [defaults, setDefaults] = React.useState(null)

      const apply = (value) => {
        setDraft({
          enabled: value.policy.enabled !== false,
          refuseSecrets: value.policy.refuseSecrets !== false,
          denyLabels: toLines(value.policy.denyLabels),
          sensitiveWindows: toLines(value.policy.sensitiveWindows),
          irreversibleLabels: toLines(value.policy.irreversibleLabels),
          irreversibleMode: ['ask', 'deny', 'allow'].includes(value.policy.irreversibleMode) ? value.policy.irreversibleMode : 'ask',
          denyKeys: toLines(value.policy.denyKeys),
          maxSequenceDepth: String(value.policy.maxSequenceDepth ?? 5),
        })
        setDefaults(value.defaults ?? null)
        setState({ phase: 'ready', error: null, message: null })
      }

      React.useEffect(() => {
        let alive = true
        loadPolicy()
          .then((value) => {
            if (alive) apply(value)
          })
          .catch((error) => {
            if (alive) setState({ phase: 'ready', error: String(error?.message ?? error), message: null })
          })
        return () => {
          alive = false
        }
      }, [])

      if (draft === null) {
        return h(
          'div',
          { className: 'dshVsc_root' },
          h('div', { className: 'dshVsc_title' }, text('title')),
          h('div', { className: 'dshVsc_status' + (state.error ? ' dshVsc_statusError' : '') }, state.error ?? text('status.loading')),
        )
      }

      const set = (key, value) => setDraft({ ...draft, [key]: value })

      const save = async (policy) => {
        setState({ phase: 'saving', error: null, message: null })
        try {
          const value = await savePolicy(policy)
          apply(value)
        } catch (error) {
          setState({ phase: 'ready', error: String(error?.message ?? error), message: null })
        }
      }

      const currentPolicy = () => ({
        enabled: draft.enabled,
        refuseSecrets: draft.refuseSecrets,
        denyLabels: toList(draft.denyLabels),
        sensitiveWindows: toList(draft.sensitiveWindows),
        irreversibleLabels: toList(draft.irreversibleLabels),
        irreversibleMode: draft.irreversibleMode,
        denyKeys: toList(draft.denyKeys),
        maxSequenceDepth: Number(draft.maxSequenceDepth) > 0 ? Number(draft.maxSequenceDepth) : 5,
      })

      const row = (key, hintKey, control) =>
        h('div', { className: 'dshVsc_row', key }, [
          h('div', { className: 'dshVsc_rowCol', key: 'text' }, [
            h('div', { className: 'dshVsc_label', key: 'label' }, text(key)),
            h('div', { className: 'dshVsc_hint', key: 'hint' }, text(hintKey)),
          ]),
          h('div', { key: 'control' }, control),
        ])

      const area = (key, onChange) =>
        h('textarea', {
          className: 'dshVsc_area',
          value: draft[key],
          spellCheck: false,
          onChange: (event) => onChange(event.target.value),
        })

      return h('div', { className: 'dshVsc_root' }, [
        h('div', { className: 'dshVsc_head', key: 'head' }, [
          h('div', { className: 'dshVsc_title', key: 'title' }, text('title')),
          h('div', { className: 'dshVsc_sub', key: 'sub' }, text('subtitle')),
        ]),
        h('div', { className: 'dshVsc_group', key: 'basic' }, [
          h('div', { className: 'dshVsc_groupTitle', key: 'gt' }, text('section.basic')),
          row(
            'field.enabled',
            'field.enabledHint',
            h(Switch, { checked: draft.enabled, label: text('field.enabled'), onChange: (v) => set('enabled', v) }),
          ),
          row(
            'field.refuseSecrets',
            'field.refuseSecretsHint',
            h(Switch, { checked: draft.refuseSecrets, label: text('field.refuseSecrets'), onChange: (v) => set('refuseSecrets', v) }),
          ),
        ]),
        h('div', { className: 'dshVsc_group', key: 'labels' }, [
          h('div', { className: 'dshVsc_groupTitle', key: 'gt' }, text('section.labels')),
          row(
            'field.denyLabels',
            'field.denyLabelsHint',
            h('div', { style: { flex: 1, minWidth: 0, width: '100%' } }, area('denyLabels', (v) => set('denyLabels', v))),
          ),
          row(
            'field.sensitiveWindows',
            'field.sensitiveWindowsHint',
            h('div', { style: { flex: 1, minWidth: 0, width: '100%' } }, area('sensitiveWindows', (v) => set('sensitiveWindows', v))),
          ),
          row(
            'field.irreversibleLabels',
            'field.irreversibleLabelsHint',
            h('div', { style: { flex: 1, minWidth: 0, width: '100%' } }, area('irreversibleLabels', (v) => set('irreversibleLabels', v))),
          ),
          row(
            'field.irreversibleMode',
            'field.irreversibleLabelsHint',
            h(
              'select',
              { className: 'dshVsc_select', value: draft.irreversibleMode, onChange: (event) => set('irreversibleMode', event.target.value) },
              ['ask', 'deny', 'allow'].map((mode) => h('option', { key: mode, value: mode }, text(`mode.${mode}`))),
            ),
          ),
          row(
            'field.denyKeys',
            'field.denyKeysHint',
            h('div', { style: { flex: 1, minWidth: 0, width: '100%' } }, area('denyKeys', (v) => set('denyKeys', v))),
          ),
          row(
            'field.maxSequenceDepth',
            'field.maxSequenceDepthHint',
            h('input', {
              className: 'dshVsc_input',
              type: 'number',
              min: 1,
              value: draft.maxSequenceDepth,
              onChange: (event) => set('maxSequenceDepth', event.target.value),
            }),
          ),
        ]),
        h('div', { className: 'dshVsc_actions', key: 'actions' }, [
          h(
            'button',
            {
              className: 'dshVsc_btn dshVsc_btnPrimary',
              type: 'button',
              disabled: state.phase === 'saving',
              onClick: () => void save(currentPolicy()),
            },
            state.phase === 'saving' ? text('action.saving') : text('action.save'),
          ),
          h(
            'button',
            {
              className: 'dshVsc_btn',
              type: 'button',
              disabled: state.phase === 'saving' || defaults === null,
              onClick: () => {
                apply({ policy: defaults ?? {}, defaults })
                setState({ phase: 'ready', error: null, message: text('status.reset') })
              },
            },
            text('action.reset'),
          ),
          h(
            'span',
            { className: 'dshVsc_status' + (state.error ? ' dshVsc_statusError' : '') },
            state.error ?? state.message ?? '',
          ),
        ]),
        h('div', { className: 'dshVsc_footer', key: 'footer' }, text('footer')),
      ])
    }

    /**
     * Client plugin body.
     * @param {any} ctx Client root context.
     */
    function apply(ctx) {
      ctx.effect(() => ctx.locale.register(NS, { zh, en }), 'visual-safety-control: dictionaries')
      const bound = ctx.locale.bind(NS)
      ctx.slots.inject('settings.plugins.tab', () =>
        ctx.slots.register(
          {
            name: 'settings.plugins.tab',
            id: 'visual-safety-control',
            order: 30,
            locale: NS,
            label: () => bound('tab.label'),
          },
          PolicyPage,
        ),
      )
    }

    exports.apply = apply
    exports.inject = ['slots', 'locale']
    return module.exports
  },
})
