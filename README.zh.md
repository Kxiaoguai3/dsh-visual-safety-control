# dsh-desktop-guard

一个 [DeepSeek Harness](https://github.com/deepseek-ai) 插件：Windows 桌面 `desktop` 工具
（截图 / OCR 找文字 / UIA 控件 / 鼠标键盘），**在 fork 里加了内容策略和动作校验**。

> **Fork 声明**：基于 [qingying012/dsh-desktop-control](https://github.com/qingying012/dsh-desktop-control)
> v0.1.3（MIT）。上游的 `assets/gui.ps1`、Windows OCR、UIA、网格截图、`sequence` 批处理全部保留；
> 原始版权声明见 [LICENSE](LICENSE)，改动清单见 [NOTICE](NOTICE) 与 [CHANGELOG.md](CHANGELOG.md)。

为什么 fork 而不是重写：上游已经把脏活做完了（一个 PowerShell 文件搞定 OCR/UIA/截图/输入，零 Python），
但**没有安全策略、也没有校验**——这正是本 fork 补的两件事。

> 仅 Windows。`assets/gui.ps1` **必须保持 UTF-8 BOM**，否则 PowerShell 5.1 按 ANSI 解析中文会直接报错。

## 本 fork 新增什么

| 新增 | 作用 |
|---|---|
| **内容策略**（`dsh/policy.js`） | 在启动 PowerShell **之前**拦截：危险目标词（支付/删除/delete/pay…）、敏感窗口（银行/密码/Password…）、疑似机密的 `type` 内容、禁用快捷键。模型无法用参数绕过。 |
| **`type` 校验** | 激活目标窗口；**切不到前台就拒绝输入**；焦点明显不可编辑时拒绝；粘贴后通过 UIA **读回内容**并给出结论。 |
| **`click` 校验** | 坐标点击前用 `WindowFromPoint` 做 hit-test，落点不属于目标窗口就拒绝；结束后报告焦点控件。 |
| **`find` 精确化** | `exact:true` 只认整行；多命中时**拒绝点击**并列出候选；`index:N` 明确指定第几个。 |
| **激活保障** | `activate` / `type` 使用"SetForegroundWindow → 点标题栏制造真实输入 → 再校验"的序列，不再"调完就走"。 |

## 安装

本地目录（开发/首发）：

```js
plugin_manager({ action: "install_bundle", target: "<本包绝对路径>" })
```

npm（发布后）：`plugin_manager({ action: "install_bundle", target: "dsh-desktop-guard" })`

**不要和 `dsh-desktop-control` 同时启用**：两者都注册名为 `desktop` 的工具，同名注册会失败。先停用另一个。

## 动作与新增参数

原有动作不变（`find` / `elements` / `ocr` / `screenshot` / `windows` / `click` / `move` / `drag` /
`scroll` / `type` / `key` / `activate` / `pos` / `wait` / `sequence`），坐标仍是**物理像素**。新增：

| 参数 | 用于 | 说明 |
|---|---|---|
| `exact` | `find` | 只接受整行完全一致（短标签推荐） |
| `index` | `find` + `click` | 多命中时点第几个（不给就拒绝点击） |
| `window` | `type` / `click` | `type` 用它激活并校验；`click` 用它做 hit-test |
| `verify` | `type` / `click` | 覆盖 `verifyType` / `verifyClick` 默认值 |
| `expect` | `click`（坐标） | 点击前 OCR 落点附近，必须出现该文字才点（防坐标过期） |
| `verifyText` | `click` / `find` | 动作后再 OCR，要求该文字可见，结论附在结果里 |

## 内容策略

默认开启；匹配忽略大小写/全半角/空格（`删 除`、`ＤＥＬＥＴＥ`、`Delete all messages` 都命中）。
用户配置**整表替换**默认值。

```yaml
config:
  policy:
    enabled: true
    denyLabels: ['支付', '转账', '删除', 'delete', 'pay']
    sensitiveWindows: ['银行', 'Password', 'Bank']
    refuseSecrets: true
    denyKeys: ['alt+f4']
    irreversibleLabels: ['发布', '发送', '提交', '发表', 'publish', 'send', 'submit']
    irreversibleMode: ask        # ask | deny | allow
    maxSequenceDepth: 5
  verifyType: true
  verifyClick: true
```

命中后返回普通工具错误，消息明确写"这是安全策略拦截，不是工具故障"，并提示模型不要换说法重试。
**不可逆动作**（发布/发送/提交…）默认 `ask`：交给宿主询问用户批准，没有批准支持时按拒绝处理；
`deny` 直接拒绝，`allow` 仅保留 `denyLabels`。硬性 `denyLabels` 优先于不可逆门禁。

**坐标点击**：`click` 的 `x`/`y` 支持 `expect`（落点附近必须出现该文字，OCR 目标窗口或落点所在的
弹窗）与 `verifyText`（点击后要求该文字可见）。不可逆动作请优先用文字/UIA 目标 + `verifyText`。

## 校验结论

`type` / `click` 返回 `verification`：

| status | 含义 |
|---|---|
| `verified` | `type` 读回内容包含刚输入的文本；`verifyText` 动作后找到了要求的文字（`method: post-action-find`） |
| `unverified` | 读回成功但不含该文本（输入可能被丢弃）；或 `verifyText` 动作后没找到该文字 |
| `unknown` | `click` 已送达并通过 hit-test，但应用侧结果未做机器校验；或 UIA 读不到控件 |
| `refused` | 拒绝执行（焦点不对 / 切不到前台 / hit-test 不匹配 / `expect` 失配 / 策略 ask 被拒），**什么都没输入/点击** |

校验从不重试动作，也不会把 `unknown` 升级成 `verified`。

## 开发注意（踩过的坑）

- `assets/gui.ps1` **必须 UTF-8 BOM**；编辑后若 BOM 丢失，PowerShell 5.1 解析中文会崩。
- **不要通过 `-File` 传 `--`**：PS 5.1 参数绑定直接失败；`type` 因此用 `-b64 <base64>` 传文本。
- `npm run selftest` 只测 argv/策略/参数校验，不碰桌面，可进 CI。
- 改 `dsh/index.js` 要重载插件；改 `assets/gui.ps1` 下次调用即生效。

## 实验室测试

见 [TESTING.md](TESTING.md)：安全用例、校验用例、需要留的证据、已知易碎点。

## 已知限制

- `find` 依赖 OCR，短标签会误读（实测 `AB01`→`ABOI`、`hello`→`he110`）；用 `exact`、长文本或调 `threshold`。
- **纯坐标点击无法判断目标**（策略只看 `text`/`uia`），优先用 `uia` 或 `find`。
- 激活可能失败（前台锁、提权窗口、无人值守会话）——`type`/`activate` 会拒绝，而不是乱打。
- UIA 对 Chromium/Electron/Qt 自绘内容基本盲；用 `find`/截图。
- 部分 GPU 渲染应用的后台截图（PrintWindow）是空白，先 `activate`。
- UAC 安全桌面、锁屏、部分游戏/反作弊/终端无法驱动。

## 操作铁律

**每次动作之前先截图，截图是操作的许可证。** 每次操作前重新获取窗口矩形（窗口会移动、控件会随内容位移），
优先用 OCR/UIA 定位而不是裸坐标；不可逆动作要"动作前截图 → 文字/UIA 定位 + verify → 动作后截图核对"。
完整规则见 [OPERATING-RULES.md](OPERATING-RULES.md)。

## License

MIT，保留上游版权声明。见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。
