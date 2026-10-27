# dsh-visual-safety-control

[![npm](https://img.shields.io/npm/v/dsh-visual-safety-control)](https://www.npmjs.com/package/dsh-visual-safety-control)
[![CI](https://github.com/Kxiaoguai3/dsh-visual-safety-control/actions/workflows/selftest.yml/badge.svg)](https://github.com/Kxiaoguai3/dsh-visual-safety-control/actions/workflows/selftest.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

DeepSeek Harness 的 Windows 桌面控制插件。给模型一个 `desktop` 工具：截图、OCR、UIA 定位控件、鼠标键盘输入，并带有内容策略和动作校验。

本仓库基于 [qingying012/dsh-desktop-control](https://github.com/qingying012/dsh-desktop-control) v0.1.3（MIT）修改。

## 功能

| 能力 | 说明 |
| :-- | :-- |
| 截图 | 全屏、指定窗口或区域截图，可选坐标网格和光标标记 |
| OCR | 本地 Windows OCR，返回文字内容和坐标 |
| 找控件 | 按 OCR 文字或 UIA 控件名定位，可按窗口过滤；多命中时拒绝点击并列出候选 |
| 鼠标 | 坐标点击、UIA 控件点击、移动、拖拽、滚轮 |
| 键盘 | 文本粘贴、组合键；输入前确认窗口在前台、控件可编辑，输入后回读内容 |
| 窗口 | 列出窗口（HWND / PID / 位置 / 标题），激活指定窗口 |
| 序列 | 一次调用执行多个步骤，减少往返 |

### 内容策略

- 危险标签（支付、转账、删除、卸载等）不点击、不查找
- 敏感窗口（银行、密码、钱包、凭据管理器）不读取、不操作
- 疑似凭据的输入内容拒绝发送
- 危险组合键拒绝执行
- 不可逆动作（发布、发送、提交、购买）默认请求用户确认

### 动作校验

- 点击前用 `expect` 校验落点处的文字，防止坐标过期
- 点击后用 `verifyText` 校验窗口里出现预期结果
- 点击做 hit-test，支持同进程弹窗和 UWP 窗口，避免误判
- 输入后通过 UI Automation 回读，确认文字真的写进去了

## 安装

本地目录：

```js
plugin_manager({ action: "install_bundle", target: "<本仓库的绝对路径>" })
```

npm（发布后）：

```js
plugin_manager({ action: "install_bundle", target: "dsh-visual-safety-control" })
```

不要和 `dsh-desktop-control` 同时启用：两者都会注册名为 `desktop` 的工具，重名会导致加载失败。

## 用法

| action | 作用 | 主要参数 |
| :-- | :-- | :-- |
| `find` | OCR 定位文字并返回屏幕坐标，可直接点击 | `text` / `window` / `click` / `exact` / `index` / `threshold` |
| `elements` | UIA 控件列表（名称 + 中心坐标） | `window` / `filter` / `depth` / `all` |
| `ocr` | 对图片做 OCR | `imagePath` / `filter` |
| `screenshot` | 保存截图并返回路径 | `window` / `region` / `print` / `grid` / `cursor` / `maxWidth` |
| `windows` | 列出窗口 | `top` |
| `click` | 点击坐标或 UIA 控件 | `x` `y` / `uia` `invoke` / `window` / `expect` / `verifyText` / `button` `count` |
| `move` / `drag` / `scroll` | 移动、拖拽、滚轮 | `x` `y` / `x2` `y2` / `amount` |
| `type` | 粘贴文本 | `text` / `window` / `verify` |
| `key` | 组合键，例如 `ctrl+s` | `key` |
| `activate` | 把窗口切到前台 | `window` |
| `pos` / `wait` | 读取光标位置 / 等待 | — / `waitMs` |
| `sequence` | 一次执行多个步骤 | `steps` |

坐标都是物理像素。

```js
// 找控件
desktop { action: "find", text: "保存", window: "记事本" }

// 点击前校验文字，点击后校验结果
desktop { action: "click", x: 812, y: 460, window: "记事本", expect: "保存", verifyText: "已保存" }

// 输入并回读
desktop { action: "type", text: "hello", window: "记事本" }
```

## 设置

装好插件后，打开 **设置 → 插件 → 视觉安全**，可以直接编辑策略：

- 启用/关闭内容策略
- 危险标签、敏感窗口、不可逆动作标签（每行一个）
- 不可逆动作的处理方式：请求确认 / 直接拒绝 / 允许
- 拒绝的快捷键、序列最大嵌套层数

点保存后写入当前 profile 的插件配置，**下一次工具调用立即生效**，不需要重启。也可以继续用 `cordis.patch.yml` 配置，两种方式等价。

> 首次安装后如果设置页里还没看到「视觉安全」，刷新一次 Harness 页面（Ctrl+R）即可加载新的客户端插件。

## 配置

```yaml
- id: visual-safety-control
  name: dsh-visual-safety-control
  config:
    policy:
      enabled: true
      denyLabels: ['支付', '转账', '删除', 'delete', 'pay']
      sensitiveWindows: ['银行', 'Password', 'Bank']
      refuseSecrets: true
      denyKeys: ['alt+f4']
      irreversibleLabels: ['发布', '发送', '提交', 'publish', 'send', 'submit']
      irreversibleMode: ask        # ask | deny | allow
      maxSequenceDepth: 5
    verifyType: true
    verifyClick: true
```

策略在 PowerShell 启动前生效，模型无法通过参数关闭。用户配置里的列表会整表替换默认值。

| 选项 | 默认值 | 说明 |
| :-- | :-- | :-- |
| `enabled` | `true` | 关闭后不注册工具 |
| `powershellPath` | `powershell.exe` | PowerShell 路径 |
| `timeoutMs` | `30000` | 单次调用超时 |
| `screenshotDir` | `$DSH_HOME/desktop-control` | 截图保存目录 |
| `screenshotMaxWidth` | `1440` | 长边上限 |
| `screenshotGrid` / `screenshotCursor` | `false` / `true` | 坐标网格 / 光标标记 |
| `keepShots` | `40` | 保留的截图数量 |
| `elementsMaxRows` | `140` | `elements` 行数上限 |
| `verifyType` / `verifyClick` | `true` | 默认开启校验 |

## 校验结果

| 状态 | 含义 |
| :-- | :-- |
| `verified` | 输入回读包含目标文字，或 `verifyText` 在动作后找到了要求的内容 |
| `unverified` | 回读成功但内容不符，或动作后没有找到 `verifyText` |
| `unknown` | 动作已送达，但结果无法机器校验 |
| `refused` | 拒绝执行：焦点不对、切不到前台、hit-test 不匹配、`expect` 失配或策略拦截 |

## 限制

- 只支持 Windows，并且需要交互式桌面会话；锁屏、UAC 安全桌面、RDP 断开会失败
- 纯坐标点击不受内容策略判断，建议配合 `expect` / `verifyText`
- 短标签或形近字 OCR 可能识别错误，用 `exact` 和 `index` 提高精度
- 不可逆动作默认 `ask`，宿主不支持审批时会直接拒绝

## 文档

- [TESTING.md](TESTING.md)：测试用例和验收清单
- [OPERATING-RULES.md](OPERATING-RULES.md)：操作规范
- [CHANGELOG.md](CHANGELOG.md)：版本变化
- [CONTRIBUTING.md](CONTRIBUTING.md)：提交问题和补丁
- [PUBLISH.md](PUBLISH.md)：发布流程

## 致谢

上游实现来自 [qingying012/dsh-desktop-control](https://github.com/qingying012/dsh-desktop-control)（MIT），原始版权声明保留在 [LICENSE](LICENSE)，改动记录在 [NOTICE](NOTICE) 和 [CHANGELOG.md](CHANGELOG.md)。
