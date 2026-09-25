# software-distribution-platform-docs

软件发布平台 · **统一设计文档库**（设计文档的单一真相源）

## 1. 本仓库与三个代码仓库的关系

平台由三个**相互独立的 git 仓库**组成，各自只管自己的**代码**；设计文档从历史各自仓库的 `docs/design/` 迁出、统一收口到本仓库。

| 仓库                                        | 仓库地址（代码库级别）                                                               | 角色                                               | 设计文档现归属       |
| ----------------------------------------- | ------------------------------------------------------------------------- | ------------------------------------------------ | ------------- |
| `software-distribution-platform-console`  | <https://github.com/rouroumaibing/software-distribution-platform-console> | 前端控制台（Vue3 + Pinia + Vue Router + OIDC/Keycloak） | 本库 `console/` |
| `software-distribution-platform-hub`      | <https://github.com/rouroumaibing/software-distribution-platform-hub>     | 控制面 / 领域模型 / 数据模型 / API（Go）                      | 本库 `hub/`     |
| `software-distribution-platform-runner`   | <https://github.com/rouroumaibing/software-distribution-platform-runner>  | 执行器（接收 hub 下发 → k8s CRD → 任务执行 → 状态回写）           | 本库 `runner/`  |
| `software-distribution-platform-docs`（本库） | <https://github.com/rouroumaibing/software-distribution-platform-docs>    | 设计文档单一真相源                                        | ——            |
| `software-distribution-platform-example`   | <https://github.com/rouroumaibing/software-distribution-platform-example> | 案例库（示例软件构建与部署样例；可经平台发布，也可直接 k8s 部署）          | 独立仓库，本库不纳入    |

- **本库只放设计文档**，不放代码。
- hub 仓库 `docs/` 根下的 `docs.go` / `swagger.json` / `swagger.yaml` 是 swaggo **自动生成的 API 文档，非设计文档**，仍留在 hub 仓库，不纳入本库。
- 设计文档的修改只在本库进行；不要再回写到三个组件仓库的旧 `docs/design/`（旧处仅保留指针指回本仓库）。

## 2. 代码库级别关联（Directory ↔ Repository）

跨文档引用一律使用各仓库的 GitHub 链接（blob 路径），**不使用相对路径（`../`）或绝对文件路径**。

| 本库目录             | 对应代码仓库                                                                    | 说明           |
| ---------------- | ------------------------------------------------------------------------- | ------------ |
| `console/`       | <https://github.com/rouroumaibing/software-distribution-platform-console> | 前端代码仓库       |
| `hub/`           | <https://github.com/rouroumaibing/software-distribution-platform-hub>     | 控制面代码仓库      |
| `runner/`        | <https://github.com/rouroumaibing/software-distribution-platform-runner>  | 执行器代码仓库      |
| （本库根 / `plans/`） | <https://github.com/rouroumaibing/software-distribution-platform-docs>    | 统一设计文档仓库（本库） |

常用文档的 GitHub 链接：

- console 设计文档：<https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md>
- hub 数据模型：<https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md>
- runner 实现 Story：<https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md>
- hub 控制面 Story：<https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-hub-implementation.md>
- hub Backlog：<https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-BACKLOG.md>
- hub 下发队列 ADR：<https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ADR-dispatch-durable-queue.md>
- 平台状态总览（唯一状态权威）：<https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md>

## 3. 目录结构

```
software-distribution-platform-docs/
├── README.md                      # 本索引 + 文档体系规则（§6）
├── console/
│   ├── index.md                   # console 域文档索引（入口）
│   ├── CONSOLE-UI-DESIGN.md       # 前端设计**唯一事实源索引 stub**（§0 修订史 + §0.4 章节→文件映射；1686 行原文已拆入 features/）
│   ├── CONSOLE-UI-原型.html        # IA v3 可交互原型
│   ├── features/                  # 前端设计事实（一主题一文件，各自只追加，章节号与原文一致）
│   │   ├── ui-01-goals-users-competitors.md   # §1–§3 目标/场景/竞品
│   │   ├── ui-02-scope.md                     # §4 范围与功能清单
│   │   ├── ui-03-information-architecture.md  # §5 信息架构
│   │   ├── ui-04-task-flows.md                # §6 核心任务流程
│   │   ├── ui-05-page-layouts.md              # §7 页面布局（含 §7.9 权限 UX / §7.12 环境对接）
│   │   ├── ui-06-interactions.md              # §8 交互细节与状态
│   │   ├── ui-07-visual-system.md             # §9 视觉设计系统
│   │   ├── ui-08-testing-acceptance.md        # §10 + 附 F 测试与验收
│   │   ├── ui-09-backend-deps-api-contract.md # 附 A + 附 D 后端依赖与 API 契约
│   │   ├── ui-10-decision-records.md          # 附 B + 附 C 决策记录
│   │   └── ui-11-implementation-records.md    # 附 E + 附 G/H/I 实现落地记录
│   └── plans/                     # 活跃计划（只收带实施路径与 Gate 的进行中项）
│       └── PIPELINE-LIFECYCLE-PLAN.md         # 流水线全生命周期 UI 迭代（STATUS §2 #18）
├── hub/
│   ├── index.md                   # hub 域文档索引（入口；横切文档已迁 shared/）
│   ├── STORY-hub-implementation.md
│   ├── STORY-BACKLOG.md
│   ├── STORY-TEMPLATE.md
│   ├── user-stories.md
│   └── assets/                    # 架构图源（png + 流水线.pptx，当前未被 md 引用，属独立图源）
├── runner/
│   ├── index.md                   # runner 域文档索引（入口）
│   ├── STORY-runner-implementation.md  # §4.2.3 kubebuilder 安装、§4.3 任务处理与 DAG 推进 + §4.4 授权边界
│   └── kubebuilder-install.txt         # Kubebuilder / controller-gen 命令记录（CRD / RBAC / deepcopy 生成）
├── shared/
│   ├── README.md                  # **跨组件文档目录**（入住判据：横跨 ≥2 组件整体迁入，不拆分、不设主从）
│   ├── CROSS-COMPONENT-ALIGNMENT.md  # 跨组件对齐总览（北极星/授权/执行模型/三层边界/术语/接入）
│   ├── DATA-MODEL.md              # 领域模型 + §6 下发与进展回收 + §7 授权模型（两层 RBAC + 审批表）
│   ├── API-REFERENCE.md           # REST API 权威端点清单 + old→new 映射 + 设计钢人论证
│   ├── DELETE-CONTRACT.md         # 删除契约：级联校验 + 409 verdict（hub 删除端点行为规格）
│   ├── ACCOUNT-PERMISSION-MODEL.md # 账号与权限规范：三条不动式（KC 只做身份 / hub 唯一权限权威 / 前端只展示）+ 鉴权两段式 + 审计 + 权限申请审批 + 现状对账
│   ├── KEYCLOAK.md                # 认证子系统：keycloakx 子 chart + realm 预置 + 与 console/hub 交互
│   └── ADR-dispatch-durable-queue.md # 下发持久队列 ADR（hub↔runner 线协议）
└── plans/
    ├── STATUS.md                   # **平台状态总览（唯一状态权威 + 全局总索引）**：已完成清单（§1）/ 未完成清单（§2，18 项）/ 刻意不做（§3）
    ├── e2e-smoke.sh                # 按页面真实操作顺序的 API 冒烟脚本（走 console ingress）
    └── e2e-cancel-rerun.sh         # 取消运行 / 单任务重跑的 API 冒烟脚本
```

> **已删档的历史计划文档**（设计信息已迁入各域文档，git 历史可查）：`UNIMPLEMENTED-MODULES-PLAN.md`（批次记录 → 钢人裁定迁 APM §12.1 / DATA-MODEL §6.6·§9.11 / DELETE-CONTRACT §6.6-5）、`PENDING-TASKS-AUDIT-2026-09-23.md`（净结论 → STATUS）、`E2E-VERIFY-PLAN.md`（P6 → DATA-MODEL §9.11）、`ACCOUNT-PERMISSION-DECISIONS.md`（D1–D6 结论 → APM §12）。旧引用中的 §x.y 编号均指删档文档章节。

## 4. 文档索引

| 文件（GitHub 链接）                                                                                                                                                 | 组件      | 核心内容                | 关键章节                                                             |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | ------------------- | ---------------------------------------------------------------- |
| [console/index.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/index.md) | console | **console 域入口索引**（事实源 stub / features 11 篇 / plans / 跨域引用） | —— |
| [console/CONSOLE-UI-DESIGN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) | console | **前端设计唯一事实源（索引 stub）**：§0 修订史索引 + §0.4 章节→文件映射 | §1 目标/4 类流水线模式 → `features/ui-01`、§5 IA → `ui-03`、§6 执行模型 → `ui-04`、§7.9 权限 UX → `ui-05`、§8.2 四态 → `ui-06`、§10.2/§10.3 验收 → `ui-08` |
| [console/CONSOLE-UI-原型.html](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-原型.html)                           | console | IA v3 可交互原型         | ——                                                               |
| [console/plans/PIPELINE-LIFECYCLE-PLAN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/plans/PIPELINE-LIFECYCLE-PLAN.md) | console | 流水线全生命周期 UI 迭代计划（**活跃**：A 节待实施、B 节 hold；登记 STATUS §2 #18） | §1 目标与验收 Gate / §2 现状事实基线 / §4 逐文件改动清单 / §5 Gate 与验证 |
| [hub/index.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/index.md) | hub | **hub 域入口索引**（自有 Story + 消费的 shared 住户清单 + 按需建立 features/plans 的约定） | —— |
| [shared/DATA-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)                                         | 跨组件 | 领域关系链 + 执行/授权模型（hub 写 / runner 写 / console 读）     | §6 下发与进展回收（含 §6.6 取消/重跑裁定）、§7 授权模型、§9 接入拓扑（§9.11 平台自身升级裁决） |
| [shared/API-REFERENCE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/API-REFERENCE.md) | 跨组件 | **REST API 权威端点清单** + old→new 映射 + 设计钢人论证 | 全部 hub 端点（按资源分组）、old 接口组成、合理性论证 |
| [shared/DELETE-CONTRACT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DELETE-CONTRACT.md) | 跨组件 | **删除端点行为契约：级联校验 + `409 + {reasons}` verdict** | §0 总则 / §1 服务树节点删除（N-15）/ §2 流水线删除（N-5）/ §3 验证 gate / §4 后端实现计划 / §6 双向钢人 + 拍板决策（含 §6.6-5 GC 裁定） |
| [shared/ACCOUNT-PERMISSION-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ACCOUNT-PERMISSION-MODEL.md) | 跨组件 | **账号与权限规范（治理三端）** | §0 三条不动式 / §2 token 读什么 / §3 资源归属单表 / §5 RBAC 引擎与 Casbin 边界 / §7 审批与到期回收 / §10 现状对账 / §12 决策状态 + §12.1 实施裁定归档 |
| [shared/KEYCLOAK.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/KEYCLOAK.md) | 跨组件 | **认证子系统：keycloakx 子 chart + realm 预置** | §1 来源 / §2 本地共存 / §3 参数透传 / §4 安装步骤 / §5 realm 预置 / §6 与 console·hub 交互 / §7 账号改密 |
| [shared/ADR-dispatch-durable-queue.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ADR-dispatch-durable-queue.md)         | 跨组件 | 下发持久队列 ADR（hub↔runner 线协议）          | ——                                                               |
| [shared/CROSS-COMPONENT-ALIGNMENT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/CROSS-COMPONENT-ALIGNMENT.md) | 跨组件 | **跨组件对齐总览**（北极星 / 授权 G7 / 执行模型 / 三层边界 / 术语 / 接入） | 六块对齐内容 + 逐条权威落点 + 同步纪律 |
| [hub/STORY-hub-implementation.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-hub-implementation.md)             | hub     | hub 控制面实现 Story     | ——                                                               |
| [hub/STORY-BACKLOG.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-BACKLOG.md)                                   | hub     | 实现 Backlog（B-01~B-19 + 补充 C-01~C-13） | ——                                                               |
| [hub/STORY-TEMPLATE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-TEMPLATE.md)                                 | hub     | Story 模板            | ——                                                               |
| [hub/user-stories.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/user-stories.md)                                     | hub     | 用户故事                | ——                                                               |
| [runner/index.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/index.md) | runner  | **runner 域入口索引** | —— |
| [runner/STORY-runner-implementation.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md) | runner  | runner 实现 Story     | §4.2.3 kubebuilder 安装、§4.3 任务处理/DAG 推进、§4.4 授权边界                 |
| [shared/README.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/README.md) | 跨组件 | **跨组件文档目录**（判据：横跨 ≥2 组件整体迁入，不拆分、不设主从；住户 7） | 住户清单 / 维护纪律 / 不入住说明 |
| [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) | 跨组件 | **平台状态总览（唯一状态权威）**：已完成清单 / 未完成清单 / 刻意不做 | §1 已完成（hub/runner/console/跨组件验证）、§2 未完成（18 项，含性质与前置）、§3 刻意不做 |

## 5. 跨组件对齐（重点：跨组件概念必须保持一致）

整体目标（北极星）/ 授权模型（G7）/ 执行模型与进展回收 / 三层边界与部署形态 / 术语消歧 / 目标接入六块对齐内容的**完整视图 → [shared/CROSS-COMPONENT-ALIGNMENT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/CROSS-COMPONENT-ALIGNMENT.md)**（2026-09-24 自本节迁入——横跨三组件、无单一变更权威，是 shared/ 首位住户）。

同步纪律：修改任一对齐概念时，**先改各域权威文档，再同步 shared 对齐视图**；两边不一致时以各域权威文档为准。

## 6. 文档组织与体系规则

- 设计文档已从三个组件仓库的 `docs/design/` 统一收口到本仓库，作为**单一真源**；本库只放设计文档，不放代码。
- 文档内部互引统一使用 GitHub blob 链接（代码库级别），不使用相对路径或绝对文件路径。
- `hub/assets/` 下的架构图源（png / pptx）为独立图源，当前未被任何 md 引用。

### 6.1 文档形态论（2026-09-24 定稿）

> 计划文档天然腐烂（描述"应该是什么"，会过时）；设计文档描述既成事实，不腐烂。目录结构按此分拣，**放错目录一眼可见**。

| 层 | 位置 | 收什么 | 追加/维护纪律 |
| --- | --- | --- | --- |
| 全局状态权威 | `plans/STATUS.md` | 完成清单 + 未完成登记（#1–#18）+ 刻意不做；**唯一状态权威 + 全局总索引** | 先改 STATUS 再动域文档；域文档不自持状态标记 |
| feature | `<域>/features/` | 已完成/既成事实的设计文档，**一主题一文件** | 各自**只追加**，禁止改写历史段落 |
| 活跃计划 | `<域>/plans/` | 只收**带实质设计内容的进行中计划**（有实施路径与验收 Gate） | 收口后归档/删除，结论迁 feature 文件 |
| 裸待办 | 仅 STATUS §2 | 无设计内容的待办条目 | **禁止**为待办建文档；开工且产生设计内容后才建 plans/ 文件 |
| 真全局文档 | `shared/` | 横跨 ≥2 组件的跨组件文档（整体迁入，不拆分、不设主从） | 判据与住户清单见 `shared/README.md`；当前住户 7 |

### 6.2 归属原则：范围优先（2026-09-24 第二次修订）

- **判据 = 治理范围**：内容横跨 ≥2 个组件（hub / console / runner / 身份基础设施）的文档，**整体迁入 `shared/`**，不以"变更权威在谁"为由留在某组件目录下，也**不做契约/实现拆分、不设主从**。
- 旧判据「无单一变更权威才入住」已废止：权限 / 删除 / 数据模型等虽由 hub 代码先行变更，但治理的是三端行为，按范围判据归 shared/。裁定全程与代价确认（跨目录耦合被明确接受、判据终局）见 [shared/README.md §判据裁定记录](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/README.md)。
- 各概念的**行为权威仍在实现它的代码**（权限强制点在 hub、schema SSOT=AutoMigrate 等）——文档内的「权威实现在 hub」标注是事实陈述，不是归属主张。
- 每域 `index.md` 是该域唯一入口页：收录本域自有文档 + 本域消费的 shared 住户交叉引用。域内文档增删必须同步 index。

### 6.3 大文件拆分先例（CONSOLE-UI-DESIGN，2026-09-24）

1686 行单文件超出可解析上限 → 按章节拆入 `console/features/`（`ui-01`~`ui-11`），原文件保留为**索引 stub**（§0 修订史 + §0.4 章节→文件映射）。拆分三原则：**章节号全局唯一且不变**（外部文本引用 `§N.x` 仍有效）、**外部引用落点不变**（stub 文件名保留）、**只追加铁律随文件下放**。后续大文件（>1000 行）达阈值时照此办理。
