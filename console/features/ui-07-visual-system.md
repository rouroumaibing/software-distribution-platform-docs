> **来源**：[CONSOLE-UI-DESIGN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) · §9 视觉设计系统（双主题）
> **拆分说明**（2026-09-24）：原文 1686 行按章节拆分归档至 `console/features/`，**章节号与原文一致**，外部引用「CONSOLE-UI-DESIGN §N.x」仍有效（章节→文件映射见原文档 §0.4）。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 9. 视觉设计系统（双主题）

### 9.1 设计原则

| 原则 | 说明 |
| --- | --- |
| 单一调性 | 内容与导航**同一套令牌**；light 全浅、dark 全深，消除海军蓝割裂（P4） |
| 状态非纯色 | 状态 = 图标 + 文字 + 色，灰阶可辨（§8.1） |
| 结构先行 | 左栏 268 / 折叠 64 + 顶栏 56 + 全宽内容（三段式贯穿全站） |
| 密度可调 | 表格 13~14px；标题 24~28px；大数字 32px；脚注 12px |
| 克制动效 | 仅 hover / 选中 / 主题切换有 0.15s 过渡；不做装饰动画 |
| Apple 风格克制 | 仅必要处用阴影；列表/卡片用 1px hairline；背景留白克制 |

### 9.2 令牌（CSS 变量，`:root[data-theme]` 切换）

| Token | Light | Dark | 用途 |
| --- | --- | --- | --- |
| `--bg` | `#F5F5F7` | `#101216` | 画布底 |
| `--surface` | `#FFFFFF` | `#171A20` | 卡片/左栏 |
| `--surface-2` | `#FAFAFC` | `#1D2129` | 表头/hover |
| `--text` | `#1D1D1F` | `#E6E8EC` | 一级文字 |
| `--text-sub` | `#5F6368` | `#98A0AD` | 次级文字 |
| `--hairline` | `#E0E0E0` | `#262B34` | 描边 |
| `--accent` | `#0066CC` | `#4DA3FF` | 主操作/选中 |
| `--accent-soft` | `#E8F0FE` | `#12304D` | 选中底 |
| `--rail-bg` | `#FFFFFF` | `#141720` | 左栏底（**light 不再用海军蓝**） |

**色板命名（v2 沿用的语义名，保留以免引用断裂）**：Action Blue `#0066CC`（主操作/链接/选中/Running）、Ink `#1D1D1F`（一级文字/深色按钮）、Near-Black `#272729`（备选深色填充）、Parchment `#F5F5F7`（画布底色 → 即 `--bg`）、Hairline `#E0E0E0`、Sub Hairline `#F0F0F2`（表格行间分隔）。

### 9.3 字体

- 字体：Inter（数字/拉丁）+ Noto Sans SC（中文）。
- 字号阶（px）：12 caption / 13 small / 14 body / 17 subtitle / 24 / 28 title / 32 display。
- 标题字重 600（徽章 Inter Bold，标题 Noto Sans SC SemiBold）。

### 9.4 间距与圆角

- 间距：4 / 8 / 12 / 16 / 24 / 32。
- 圆角：药丸 9999 / 卡片 12 / 徽章 9999 / 图标按钮 8 / Tag chip 6。

### 9.5 组件形态

- 按钮：`Primary`（药丸/Action Blue/白字）/ `Dark`（药丸/Ink/白字）/ `Pearl`（矩形/白底 hairline/深字）；危险操作用 `Danger`（红底，仅用于"确认删除"）。
- 徽章：药丸 + 状态图标 + 文字（§8.1）。
- 顶部导航：56px 高 + 底部 hairline + 面包屑 + 右侧 搜索(⌘K) / 主题 / 灰阶 / 设计备注 / 头像。
- 左栏：268px（折叠 64px）+ `--rail-bg` 底 + 条目 36px 行高 + 选中项 `--accent-soft` 底 + `--accent` 字（**不用 3px 竖条**）。
- 分段控件（`seg`）：视图切换、状态筛选、四态演示共用同一形态。
- 树行（`tnode`）：服务/组件共用一套样式；展开箭头 + 状态点 + 标签 + 行内操作（hover 出现）；服务树与环境树共用。

### 9.6 主题机制

- `document.documentElement.dataset.theme = 'light' | 'dark'`；CSS 用 `:root` 与 `:root[data-theme='dark']` 覆盖。
- 默认：读 `localStorage` → 无则 `prefers-color-scheme`。
- 灰阶自检：原型内置"灰阶模式"开关（`filter: grayscale(1)`），一键验证 S4。

---
