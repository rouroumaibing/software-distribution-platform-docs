> **来源**：[CONSOLE-UI-DESIGN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) · §4 范围与功能清单
> **拆分说明**（2026-09-24）：原文 1686 行按章节拆分归档至 `console/features/`，**章节号与原文一致**，外部引用「CONSOLE-UI-DESIGN §N.x」仍有效（章节→文件映射见原文档 §0.4）。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 4. 范围与功能清单

### 4.1 本次重设计 Must-have

| ID | 项 | 对应页面 |
| --- | --- | --- |
| R-1 | **极简左栏导航（恒 5 项）**：`总览 · 服务树 · 运行中心` + `用户与权限 · 接入管理`（+ 主题切换）——**不含资源树，也不含"最近访问"**；主区不挂分组标签 | 全局骨架 |
| R-2 | 跨组件巡视（运行 / 发布 **两视图**） | 左栏「运行中心」（`/runs?view=runs\|releases`） |
| R-3 | 总览指挥中心（待办 + KPI + 最近运行 + 异常） | `/dashboard` 重做 |
| R-4 | 组件详情 Tab 收敛（9 → **7 主 Tab**，仅「交付」带子 Tab） | `/components/:id` |
| R-5 | 流水线 CRUD（新建 / 编排 / 更新 / 删除） | 组件「交付→流水线」+ `/pipelines/:id` |
| R-6 | 双主题令牌系统（light / dark）+ 状态非纯色化 | 全局 |
| R-7 | **全局搜索（⌘K）**：组件 / 流水线 / Service 跨层级直达，结果带所属路径 | 顶栏 + 浮层 |
| R-8 | **服务树独立页的规模化**：懒加载（展开才请求） + 服务端搜索 + 虚拟滚动 + 独立滚动容器 | `/service-tree`（`/catalog`） |

### 4.2 后续 Later（刻意不做 / 待补）

- ❌ 通知中心（顶栏铃铛真实化）——需后端通知端点。
- ❌ DAG 自由画布（沿用结论，`DependsOn` 需求明确后评估 vue-flow）。
- ✅ ~~流水线版本历史 / 回滚到旧版本~~ **已落地（2026-09-22，C-09）** —— hub `GET /pipelines/:id/versions` + `/:version` + `/:version/diff` + `POST /:version/rollback`；console `PipelineVersionPanel.vue`（对比 + 回滚二次确认）。回滚 = 结构回填 + 追加新版本，绝不重写历史。
- ❌ 左栏内联资源树（**已明确否决**，见 S5）。
- ❌ API 管理模块（新平台无此后端域）。

### 4.3 历史模块清单（MOD-0~MOD-10，v2 时期编号，保留供对账）

> 状态：⬜ 未开始 · 🟨 桩已存在待对齐 · 🟩 已可对接后端 · 🟥 页面已建但无数据通道。
> **当前进度以 [`hub/STORY-BACKLOG.md`](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-BACKLOG.md) 为准**（功能缺口已并入其 B-/C- 清单），本表只作模块边界索引。

| ID | 模块 | 对应页面 |
| --- | --- | --- |
| MOD-0 | 应用骨架 / 导航 / 设计系统组件 | 全局骨架 + tokens |
| MOD-1 | 服务树导航（Org→Service→Component） | 服务树页 master-detail |
| MOD-2 | 组件详情 + 参数管理 | 组件详情 Tab |
| MOD-3 | 流水线编排器 + 三态子任务表单 | 流水线编排 |
| MOD-4 | 运行触发对话框 | F4→F5 入口 |
| MOD-5 | 运行监控（DAG + 进度轮询） | 运行监控 |
| MOD-6 | 审批决策 | 监控页 Approval 节点 |
| MOD-7 | 日志查看 | 监控页日志面板 + 日志页 |
| MOD-8 | 灰度/发布进度 | 灰度发布 |
| MOD-9 | 制品库 | 制品列表/详情 |
| MOD-10 | 权限 / 访问控制 | 组件详情权限 Tab + 平台管理 |

---
