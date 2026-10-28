# console 域文档索引

> 前端控制台（Vue3 + Pinia + Vue Router + OIDC/Keycloak）。代码仓：<https://github.com/rouroumaibing/software-distribution-platform-console>
> 状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准；本目录文档只维护行为规格与设计事实。

## 事实源（唯一）

| 文件 | 说明 |
| --- | --- |
| [CONSOLE-UI-DESIGN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) | **前端设计唯一事实源**（索引 stub）：§0 文档边界与章节约定 + §0.4 章节→文件映射表；修订史见文末「变更历史」。1686 行原文按章节拆入 `features/`，章节号不变、只追加铁律随文件下放 |
| [CONSOLE-UI-prototype.html](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-prototype.html) | IA v3 可交互原型（单文件；**缺口补齐**：单次运行详情 / 审批 / 终止重跑 / 灰度控制台 / 带参触发 / 分页与时间筛选 / 通知中心 / 平台管理弹窗 / 版本矩阵，见 [ui-11 附 K](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-11-implementation-records.md) 与 [ui-05 §7.13](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-05-page-layouts.md)；**补全集成**：四期 14 工作项分布嵌入原有页面（运行中心审批视图 / 接入管理 Runner Tab / 组件「变量与密钥」Tab / 配置版本历史 / 触发器 / 高危原因 / 状态枚举扩展 / 审计筛选 / 通知中心 / PAT / 全局制品库 / 服务树治理 / 实时日志徽章），落点对账见 [ui-12 附 A](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-12-console-completion-design.md)） |

## features/（已完成 / 既成设计事实，一主题一文件，各自只追加）

| 文件 | 原文章节 | 内容 |
| --- | --- | --- |
| [ui-01-goals-users-competitors.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-01-goals-users-competitors.md) | §1–§3 | 问题与目标、4 类标准流水线模式、用户与场景、竞品参考 |
| [ui-02-scope.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-02-scope.md) | §4 | 范围与功能清单（Must-have / Later / 历史模块对账） |
| [ui-03-information-architecture.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-03-information-architecture.md) | §5 | 信息架构：左栏恒 5 项、服务树页、⌘K 全局搜索、组件 7 主 Tab、路由 |
| [ui-04-task-flows.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-04-task-flows.md) | §6 | 核心任务流程：执行模型、流水线 CRUD、异常分支、用户旅程 |
| [ui-05-page-layouts.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-05-page-layouts.md) | §7 | 页面布局：全局骨架、总览、组件详情、运行中心两视图、权限审批 UX（§7.9）、环境对接（§7.12） |
| [ui-06-interactions.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-06-interactions.md) | §8 | 交互细节：状态色 6 态、四态、反馈规则、去冗余原则 |
| [ui-07-visual-system.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-07-visual-system.md) | §9 | 视觉设计系统（双主题、令牌、字体、间距、组件形态） |
| [ui-08-testing-acceptance.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-08-testing-acceptance.md) | §10 + 附 F | 测试与迭代计划、验证门禁、用户侧验收、通用验收标准 |
| [ui-09-backend-deps-api-contract.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-09-backend-deps-api-contract.md) | 附 A + 附 D | 后端依赖与待确认（N 系列编号）、API 契约与三层数据模型 |
| [ui-10-decision-records.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-10-decision-records.md) | 附 B + 附 C | 决策记录：运行中心 URL 形态（`?view=`）、服务树节点删除前后端分工 |
| [ui-11-implementation-records.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-11-implementation-records.md) | 附 E + 附 G/H/I | 实现落地记录：C-01/02（搜索+主题）、C-12（流水线全生命周期）、R-8（服务树规模化）及显式差异记账 |
| [ui-12-console-completion-design.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-12-console-completion-design.md) | 计划 §4.1–§4.5 | 前端设计补全计划（四期 15 工作项）逐项落实：入口/关键交互/权限矩阵（基于 hub `role.go` §7 词表）/五态引用/后端契约引用/决策挂钩；配套契约/spec 文档已并入本文（修订 R3）后删除 |
| [CONSOLE-FRONTEND-FIVES-STATES-2026-10-11.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/CONSOLE-FRONTEND-FIVES-STATES-2026-10-11.md) | 计划 §1.1 / §4.1 | 共享五态规范（空/加载/错误/成功/无权限）+ 403 按钮三策略；被 ui-12 各工作项引用（自根 plans/ 迁入） |

## plans/（活跃计划，只收带实质设计内容的进行中项）

当前无活跃计划。已完成计划（A/B/C/D 节全部落地者）按指针协议迁 `features/`，裸待办条目只登记在 [STATUS §2](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md)，不进本目录。

## 跨域引用（住户在 shared/，完整清单见 [shared/README.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/README.md)）

- 跨组件对齐总览（北极星 / 授权 / 执行模型 / 术语）：[shared/CROSS-COMPONENT-ALIGNMENT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/CROSS-COMPONENT-ALIGNMENT.md)

- 平台入口网关（console HTTPRoute 的挂载点、资产边界与双环境形态）：[shared/NETWORKING-GATEWAY.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/NETWORKING-GATEWAY.md)

- 权限与审批 UX 的后端权威：[shared/ACCOUNT-PERMISSION-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ACCOUNT-PERMISSION-MODEL.md)（**权威在 hub**）
- 删除入口契约：[shared/DELETE-CONTRACT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DELETE-CONTRACT.md)（`409 + {reasons}`，**权威在 hub**）
- 端点契约：[shared/API-REFERENCE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/API-REFERENCE.md)
- runner→hub 回流协议消费端（灰度快照/服务端已读游标/agent_version）：[shared/runner-reflux-spec.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/runner-reflux-spec.md)
