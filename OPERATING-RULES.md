# 操作铁律（Operating rules）

> 适用于任何使用本插件（或任何桌面自动化）的场景。违反这些规则导致的误点/误发，插件无法兜底。

## 0. 一句话

**每次动作之前，先截图；截图是操作的许可证。** 没有新截图，就不要点、不要输入。

## 1. 动作前必须截图

- 每次 `click` / `type` / `key` / `drag` / `scroll` 之前，先对**目标窗口**截图（必要时整屏），确认：
  - 目标窗口在哪、是否在前台、是否被遮挡；
  - 目标控件/文字在屏幕上的**当前**位置；
  - 当前页面处于什么状态（有没有弹窗、加载中、菜单开着）。
- 截图后如果发现状态与预期不符，**先处理状态，不要继续原计划**。
- 上一步的截图不能当作下一步的许可证；**状态变化后必须重新截图**（开菜单、切页、输入、滚动、弹窗）。

## 2. 坐标永远重新算

- 每次操作前重新获取窗口矩形（`windows`），**不要复用上一屏的坐标**。窗口会移动、控件会随内容位移（实测：输入正文后「发布」按钮上移约 40px）。
- 优先用可定位的目标：OCR `find` 文字、UIA `uia` 控件；裸坐标只作为最后手段。
- 点击后如果界面没有按预期变化：**停下、截图、重新定位**，不要连续盲试相邻坐标。

## 3. 不可逆动作要"三截图"

发布 / 发送 / 删除 / 支付 / 提交这类动作：

1. 动作前截图：确认目标文字、分区、输入内容、按钮状态；
2. 动作时：优先用文字/UIA 定位（不要裸坐标），并开启 `verify`；
3. 动作后截图：确认页面跳转/提示/列表出现，必要时用 `find` 搜索成功证据（如帖子正文首句）。
4. 没有拿到可核对的证据之前，**不要宣布成功**，也不要重复点击。

## 4. 失败即停

- 同一个动作失败两次（截图确认状态未变），停止并报告：当前截图、已试过的操作、预期 vs 实际。
- 不要用"换个坐标再试试"掩盖失败；不要连续点击同一区域。

## 5. 浏览/探索类任务

- 每一屏截图后再决定下一步；滚动后必须重新截图。
- 只会读取时，避免点击帖子卡片（会进入详情页）；滚动区域要落在列表内部。
- 遇到登录/验证码/MFA/UAC，立即交还用户，不猜不绕。

## 6. 证据与隐私

- 每个关键动作保存截图路径（本插件默认写入 `$DSH_HOME/desktop-control/`）。
- 不把含个人聊天/账号/银行信息的截图提交到仓库或公开渠道。

---

**English summary.** Before every action, take a fresh screenshot of the target window; the screenshot is the
permission to act. Re-read the window rect every time (windows move and controls shift), prefer OCR/UIA
targets over raw coordinates, re-screenshot after any state change, and for irreversible actions
(publish/send/delete/pay) screenshot before, act by text/UIA with `verify`, and screenshot after to
confirm the result — never claim success without evidence. Stop after two failed attempts instead of
guessing coordinates.
