# CROSS-COMPONENT-ALIGNMENT — 跨组件对齐总览

> **住户资格**（2026-09-24 自 README §5 迁入）：横跨 hub / console / runner 三组件、变更从不由单一组件发起、无法归入任何一个域目录——满足 `shared/README.md` 三条门槛。
> **状态判断**一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准；本文件只做对齐与导航，**每个概念的权威定义仍在其所属域文档**（下文逐条标注）。

## 1. 整体目标（北极星）

- **写在**（三处同步，无单一权威）：[console 设计文档 §1 + §1.1 + §1.2](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-01-goals-users-competitors.md)、[hub 数据模型 顶部「项目目标」](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)、[runner 实现 Story 顶部「项目目标」](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md)。
- **内容**：通过纯界面交互，把软件「构建 → 测试 → 发布到多套环境」跑通；4 类标准流水线（日常 / 版本归档 / 转测 / 生产）；权限管控（G7）作为核心能力之一落地（§7 多 org 两层 RBAC + 审批子系统 + Enforcement）。

## 2. 授权模型（G7）

- **设计结论**：Keycloak 只管身份 + 组；k8s RBAC 只管 runner 集群部署边界；业务授权与审批全部落 hub（app 内两层 RBAC + 审批表 + Enforcement 中间件）。
- 权威落点（**权威在 hub**）：[shared/ACCOUNT-PERMISSION-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ACCOUNT-PERMISSION-MODEL.md)（账号与权限唯一权威边界）、[shared/DATA-MODEL.md §7](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)（分层模型 + 表结构）、[shared/API-REFERENCE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/API-REFERENCE.md)（端点与实现状态）。
- 跨组件：[console 设计文档 §7.9](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-05-page-layouts.md) —— 平台级权限页 + 组件级「权限 (permissions)」Tab；[runner 实现 Story §4.4](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md) —— runner 只消费 hub 已鉴权下发的 spec，自身无授权逻辑。

## 3. 执行模型 / 进展回收

- [console 设计文档 §6](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-04-task-flows.md) —— 阶段串行 + 阶段内 `ExecutionMode`（Serial/Parallel，Stage 级）+ 子任务完成=阶段完成 + 异常分支表。
- [hub 数据模型 §6](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md) —— 推送模型（hub 经 WS 推 spec 给 runner，状态流回写 `task_runs`）；**`stage_runs` 表经双向钢人论证确认不建**，进展由 `task_runs` 读时聚合（`stage-progress` 端点后端一次算好下发）。**权威在 hub**。
- [runner 实现 Story §4.3](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md) —— 任务处理与 DAG 推进（阶段间/内统一 `DependsOn`、单节点执行、状态回流）。

## 4. 平台自身定位与部署形态（分层边界）

三层边界（① 能力 / ② 接入 / ③ 自身）的边界表、八条已裁定事实与完整论证 → **[shared/DATA-MODEL.md §9.0](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)**；不采纳自升级的六条理由与「独立升级页面」裁定 → **[shared/DATA-MODEL.md §9.11](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)**。（**权威在 hub**）

## 5. 术语消歧

「自举 / 集群 / 环境 / 组件 / 目标 / 通道」六词的含义 A/B 与消歧做法 → **[shared/DATA-MODEL.md §9.0](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)**（每个词的权威定义仍在其所属章节：目标 / 环境 → §9；组件 → §1）。

## 6. 目标接入与执行后端（② 接入层展开）

`targetKind` × `access` 两个正交维度、能力矩阵、三通道互补与凭据风险 → **[shared/DATA-MODEL.md §9.5](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)**；直连扩表形状与凭据加密落库 → §9.7；runner 安装 / 升级编排 → §9.9；版本矩阵 CM → §9.10；agent_ops 台账与直连执行全链路（协议裁定 / Job 执行语义 / install·upgrade 留守 queued）→ **DATA-MODEL §9.5 agent_ops 段**（现状登记 → **[plans/STATUS.md §2](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md)** #1）。

---

## 修改同步纪律

以上概念横跨多个组件，**任何一处的修改都要同步另外两处**，避免漂移。本文件是「对齐视图」：先改各域权威文档，再回到这里同步摘要与指针；两边不一致时，以各域权威文档为准。
