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
- hub 数据模型：<https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md>
- runner 实现 Story：<https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md>
- hub 控制面 Story：<https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-hub-implementation.md>
- hub Backlog：<https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-BACKLOG.md>
- hub 下发队列 ADR：<https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/ADR-dispatch-durable-queue.md>
- E2E 验证计划：<https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/E2E-VERIFY-PLAN.md>

## 3. 目录结构

```
software-distribution-platform-docs/
├── README.md                      # 本索引
├── console/
│   ├── CONSOLE-UI-DESIGN.md       # 前端设计（**唯一事实源**，IA v3：目标/场景/IA/页面/执行模型+异常分支/状态色+6 态/四态/权限审批 UX/视觉/验收）
│   └── CONSOLE-UI-原型.html        # IA v3 可交互原型
├── hub/
│   ├── DATA-MODEL.md              # 领域模型 + §6 下发与进展回收 + §7 授权模型（两层 RBAC + 审批表）
│   ├── API-REFERENCE.md           # REST API 权威端点清单 + old→new 映射 + 设计钢人论证
│   ├── DELETE-CONTRACT.md         # 删除契约：级联校验 + 409 verdict（hub 删除端点行为规格）
│   ├── STORY-hub-implementation.md
│   ├── STORY-BACKLOG.md
│   ├── STORY-TEMPLATE.md
│   ├── ADR-dispatch-durable-queue.md
│   ├── user-stories.md
│   ├── KEYCLOAK.md                # 认证子系统：keycloakx 子 chart + realm 预置 + 与 console/hub 交互
│   ├── ACCOUNT-PERMISSION-MODEL.md # 账号与权限规范：三条不动式（KC 只做身份 / hub 唯一权限权威 / 前端只展示）+ 鉴权两段式 + 审计 + 权限申请审批 + 现状对账
│   └── assets/                    # 架构图源（png + 流水线.pptx，当前未被 md 引用，属独立图源）
├── runner/
│   ├── STORY-runner-implementation.md  # §4.2.3 kubebuilder 安装、§4.3 任务处理与 DAG 推进 + §4.4 授权边界
│   └── kubebuilder-install.txt         # Kubebuilder / controller-gen 命令记录（CRD / RBAC / deepcopy 生成）
└── plans/
    ├── E2E-VERIFY-PLAN.md          # 端到端联调验证计划（跨组件 P0–P6）
    ├── P0-3-CONSOLE-PIPELINE-LIFECYCLE-PLAN.md  # Console 流水线全生命周期 UI 实施计划（评审稿，待 v3 IA 定稿）
    ├── UNIMPLEMENTED-MODULES-PLAN.md  # 未落地模块总表 + 执行顺序（Epic A–E；含本轮 Epic A 落地清单与验证 gate）
    ├── ACCOUNT-PERMISSION-DECISIONS.md  # 账号权限 D1–D6 决策材料 · 双向钢人版（事实 / 钢人 / 假钢人 / 判定 + 文档修正清单 + 决策分级：0 项阻塞）
    └── e2e-smoke.sh                # 按页面真实操作顺序的 API 冒烟脚本（走 console ingress）
```

## 4. 文档索引

| 文件（GitHub 链接）                                                                                                                                                 | 组件      | 核心内容                | 关键章节                                                             |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | ------------------- | ---------------------------------------------------------------- |
| [console/CONSOLE-UI-DESIGN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) | console | **前端整体设计（唯一事实源，IA v3）** | §1 目标/4 类流水线模式、§5 IA（左栏恒 5 项 / 运行中心两视图 / 组件 7 主 Tab）、§6 执行模型+异常分支、§7.9 权限与审批 UX、§8.2 四态、§10.2/§10.3 验收 |
| [console/CONSOLE-UI-原型.html](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-原型.html)                           | console | IA v3 可交互原型         | ——                                                               |
| [hub/DATA-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)                                         | hub     | 领域关系链 + 执行/授权模型     | §6 下发与进展回收（推送模型、stage 不建表）、§7 授权模型                               |
| [hub/API-REFERENCE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/API-REFERENCE.md) | hub     | **REST API 权威端点清单** + old→new 映射 + 设计钢人论证 | 全部 hub 端点（按资源分组）、old 接口组成、合理性论证 |
| [hub/DELETE-CONTRACT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DELETE-CONTRACT.md) | hub | **删除端点行为契约：级联校验 + `409 + {reasons}` verdict** | §0 总则 / §1 服务树节点删除（N-15）/ §2 流水线删除（N-5）/ §3 验证 gate / §4 后端实现计划 / §6 双向钢人 + 拍板决策 |
| [hub/STORY-hub-implementation.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-hub-implementation.md)             | hub     | hub 控制面实现 Story     | ——                                                               |
| [hub/STORY-BACKLOG.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-BACKLOG.md)                                   | hub     | 实现 Backlog（B-01~B-16 + 补充 C-01~C-13） | ——                                                               |
| [hub/STORY-TEMPLATE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-TEMPLATE.md)                                 | hub     | Story 模板            | ——                                                               |
| [hub/ADR-dispatch-durable-queue.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/ADR-dispatch-durable-queue.md)         | hub     | 下发持久队列 ADR          | ——                                                               |
| [hub/user-stories.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/user-stories.md)                                     | hub     | 用户故事                | ——                                                               |
| [hub/KEYCLOAK.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/KEYCLOAK.md) | hub | **认证子系统：keycloakx 子 chart + realm 预置** | §1 来源 / §2 本地共存 / §3 参数透传 / §4 安装步骤 / §5 realm 预置 / §6 与 console·hub 交互 / §7 账号改密 |
| [hub/ACCOUNT-PERMISSION-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/ACCOUNT-PERMISSION-MODEL.md) | hub | **账号与权限规范（唯一权威边界）** | §0 三条不动式 / §2 token 读什么 / §3 资源归属单表 / §4 请求两件事 / §5 RBAC 引擎与 Casbin 边界 / §6 审计 / §7 权限申请审批与到期回收 / §8 前端只展示 / §10 现状对账 / §12 待拍板 |
| [runner/STORY-runner-implementation.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md) | runner  | runner 实现 Story     | §4.2.3 kubebuilder 安装、§4.3 任务处理/DAG 推进、§4.4 授权边界                 |
| [plans/E2E-VERIFY-PLAN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/E2E-VERIFY-PLAN.md)                           | 跨组件     | 端到端联调验证计划           | P0 环境→P6 平台自身部署裁决（成功标准 / kind 拓扑 / 各阶段验证）                              |
| [plans/P0-3-CONSOLE-PIPELINE-LIFECYCLE-PLAN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/P0-3-CONSOLE-PIPELINE-LIFECYCLE-PLAN.md) | console | Console 流水线全生命周期 UI 实施计划（评审稿） | §1 目标与验收 Gate / §2 现状事实基线 / §4 逐文件改动清单 / §5 Gate 与验证 |
| [plans/UNIMPLEMENTED-MODULES-PLAN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/UNIMPLEMENTED-MODULES-PLAN.md) | 跨组件 | **未落地模块总表 + 执行顺序（Epic A–E）** | §0 已落地 / §1 未落地总表 / §2 执行顺序 / §3 本期 Epic A（交付清单 + gate + 落地结果 + 明确不做） |
| [plans/ACCOUNT-PERMISSION-DECISIONS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/ACCOUNT-PERMISSION-DECISIONS.md) | hub | 账号权限 **D1–D6 决策材料**（组织载体 / 角色权威 / 不存用户表连锁 / Casbin / token 存法 / `aud`；逐项事实→钢人→假钢人→判定五段 + 决策分级 + 文档修正清单） | §0 一页总览 / §1–§6 逐项 / §7 文档修正 / §9 不可逆性分级 / §10 上游事实置信度 |

## 5. 跨组件对齐（重点：跨组件概念必须保持一致）

以下概念横跨多个组件，**任何一处的修改都要同步另外两处**，避免漂移：

### 5.1 整体目标（北极星）

- **写在**：[console 设计文档 §1 + §1.1 + §1.2](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md)、[hub 数据模型 顶部「项目目标」](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)、[runner 实现 Story 顶部「项目目标」](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md)。
- **内容**：通过纯界面交互，把软件「构建 → 测试 → 发布到多套环境」跑通；4 类标准流水线（日常 / 版本归档 / 转测 / 生产）；权限管控（G7）作为核心能力之一落地（§7 多 org 两层 RBAC + 审批子系统 + Enforcement）。

### 5.2 授权模型（G7）

- **设计结论**：Keycloak 只管身份 + 组；k8s RBAC 只管 runner 集群部署边界；业务授权与审批全部落 hub（app 内两层 RBAC + 审批表 + Enforcement 中间件）。
- 权威落点：[hub/ACCOUNT-PERMISSION-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/ACCOUNT-PERMISSION-MODEL.md)（账号与权限唯一权威边界）、[hub/DATA-MODEL.md §7](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)（分层模型 + 表结构）、[hub/API-REFERENCE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/API-REFERENCE.md)（端点与实现状态）。
- 跨组件：[console 设计文档 §7.9](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) —— 平台级权限页 + 组件级「权限 (permissions)」Tab；[runner 实现 Story §4.4](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md) —— runner 只消费 hub 已鉴权下发的 spec，自身无授权逻辑。

### 5.3 执行模型 / 进展回收

- [console 设计文档 §6](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) —— 阶段串行 + 阶段内 `ExecutionMode`（Serial/Parallel，Stage 级）+ 子任务完成=阶段完成 + 异常分支表。
- [hub 数据模型 §6](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md) —— 推送模型（hub 经 WS 推 spec 给 runner，状态流回写 `task_runs`）；**`stage_runs` 表经双向钢人论证确认不建**，进展由 `task_runs` 读时聚合（`stage-progress` 端点后端一次算好下发）。
- [runner 实现 Story §4.3](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md) —— 任务处理与 DAG 推进（阶段间/内统一 `DependsOn`、单节点执行、状态回流）。

### 5.4 平台自身定位与部署形态（分层边界）

三层边界（① 能力 / ② 接入 / ③ 自身）的边界表、八条已裁定事实与完整论证 → **[hub/DATA-MODEL.md §9.0](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)**；不采纳自升级的六条理由与「独立升级页面」裁定 → **[plans/E2E-VERIFY-PLAN.md P6](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/E2E-VERIFY-PLAN.md)**。

### 5.5 术语消歧

「自举 / 集群 / 环境 / 组件 / 目标 / 通道」六词的含义 A/B 与消歧做法 → **[hub/DATA-MODEL.md §9.0](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)**（每个词的权威定义仍在其所属章节：目标 / 环境 → §9；组件 → §1）。

### 5.6 目标接入与执行后端（② 接入层展开）

`targetKind` × `access` 两个正交维度、能力矩阵、三通道互补与凭据风险 → **[hub/DATA-MODEL.md §9.5](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)**；直连扩表形状与凭据加密落库 → §9.7；runner 安装 / 升级编排 → §9.9；版本矩阵 CM → §9.10；直连执行端点的 runner 侧 follow-up → **[plans/UNIMPLEMENTED-MODULES-PLAN.md §16.4](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/UNIMPLEMENTED-MODULES-PLAN.md)**。

## 6. 文档组织

- 设计文档已从三个组件仓库的 `docs/design/` 统一收口到本仓库，作为**单一真源**；本库只放设计文档，不放代码。
- 文档内部互引统一使用 GitHub blob 链接（代码库级别），不使用相对路径或绝对文件路径。
- `hub/assets/` 下的架构图源（png / pptx）为独立图源，当前未被任何 md 引用。
