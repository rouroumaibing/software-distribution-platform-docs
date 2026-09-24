# console 域文档索引

> 前端控制台（Vue3 + Pinia + Vue Router + OIDC/Keycloak）。代码仓：<https://github.com/rouroumaibing/software-distribution-platform-console>
> 状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准；本目录文档只维护行为规格与设计事实。

## 事实源（唯一）

| 文件 | 说明 |
| --- | --- |
| [CONSOLE-UI-DESIGN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) | **前端设计唯一事实源**（索引 stub）：§0 修订史索引 + §0.4 章节→文件映射表。1686 行原文已于 2026-09-24 按章节拆入 `features/`，章节号不变、只追加铁律随文件下放 |
| [CONSOLE-UI-原型.html](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-原型.html) | IA v3 可交互原型（单文件） |

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

## plans/（活跃计划，只收带实质设计内容的进行中项）

| 文件 | 说明 |
| --- | --- |
| [PIPELINE-LIFECYCLE-PLAN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/plans/PIPELINE-LIFECYCLE-PLAN.md) | 流水线全生命周期 UI 迭代（A 节待实施：下线前端聚合 stopgap 接 `GET /pipelines`；B 节 hold；C/D 已实施）——登记 STATUS §2 #18 |

> 裸待办条目不进本目录，只登记在 [STATUS §2](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md)；本目录文件必须是「有实施路径与验收 Gate 的活跃计划」。

## 跨域引用（权威在他域）

- 权限与审批 UX 的后端权威：[hub/ACCOUNT-PERMISSION-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/ACCOUNT-PERMISSION-MODEL.md)（**权威在 hub**）
- 删除入口契约：[hub/DELETE-CONTRACT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DELETE-CONTRACT.md)（`409 + {reasons}`，**权威在 hub**）
- 端点契约：[hub/API-REFERENCE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/API-REFERENCE.md)
