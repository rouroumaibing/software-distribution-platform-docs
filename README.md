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
| [plans/ACCOUNT-PERMISSION-DECISIONS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/ACCOUNT-PERMISSION-DECISIONS.md) | hub | 账号权限 **D1–D6 决策材料 · 双向钢人版**（组织载体 / 角色权威 / 不存用户表连锁 / Casbin / token 存法 / `aud`） | §0 一页总览（**钢人后的推荐 + 与 v1 的差异 + 判定规则**）+ **§0.1 决策分级（钢人 ≠ 拍板；最终 0 项阻塞）** / §1–§6 逐项**五段**（事实 → 钢人 → 假钢人 → 分歧+关键变量 → 判定 + 文档核对）/ §7 第一轮 **14 处文档修正清单** + §7.5 第二轮 6 项 / §8 开工第一步（含 gate）/ §9 不可逆性分级（修订）/ §10 上游事实置信度表（含「需实测」标记） |

## 5. 跨组件对齐（重点：跨组件概念必须保持一致）

以下概念横跨多个组件，**任何一处的修改都要同步另外两处**，避免漂移：

### 5.1 整体目标（北极星）

- **写在**：[console 设计文档 §1 + §1.1 + §1.2](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md)、[hub 数据模型 顶部「项目目标」](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)、[runner 实现 Story 顶部「项目目标」](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md)。
- **内容**：通过纯界面交互，把软件「构建 → 测试 → 发布到多套环境」跑通；4 类标准流水线（日常 / 版本归档 / 转测 / 生产）；权限管控（G7）作为核心能力之一落地（§7 多 org 两层 RBAC + 审批子系统 + Enforcement）。

### 5.2 授权模型（G7）

- 两层 RBAC（`platform_roles`/`platform_role_bindings` + `component_roles`/`component_role_bindings`）+ 审批子系统 `pipeline_approvals` + Enforcement 中间件 + DDL（已实现，与 AutoMigrate 同步；共 26 张表）。两张绑定表均带 **`expires_at`**（2026-09-22，`migrations/0011`），且鉴权解析路径**排除已过期授权**。
- ✅ **平台级 HTTP 端点已暴露（2026-09-22，C-10）**：`/platform-roles`（GET/POST + GET/PUT/DELETE `:id`）与 `/platform-role-bindings`（GET/POST + DELETE `:id`）已注册；内置角色不可改删，角色被引用时删除返回 `409 + {reasons}`。**console 侧权限管理 UI 仍未落地**，平台级路由的权限守卫随 `ACCOUNT-PERMISSION-MODEL.md` §11 步骤 4 收口。
- [console 设计文档 §7.9](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) —— 平台级权限页（各页面增删改查颗粒度全分析）+ 组件级「权限 (permissions)」Tab。
- [runner 实现 Story §4.4](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md) —— runner 只消费 hub 已鉴权下发的 spec，自身无授权逻辑；集群侧权限由 k8s RBAC（hub 签发 RoleBinding）约束。
- **设计结论**：Keycloak 只管身份+组；k8s RBAC 只管 runner 集群部署边界；业务授权与审批全部落 hub（app 内 RBAC + 审批表）。

### 5.3 执行模型 / 进展回收

- [console 设计文档 §6](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) —— 阶段串行 + 阶段内 `ExecutionMode`（Serial/Parallel，Stage 级）+ 子任务完成=阶段完成 + 异常分支表。
- [hub 数据模型 §6](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md) —— 推送模型（hub 经 WS 推 spec 给 runner，状态流回写 `task_runs`）；**`stage_runs` 表经双向钢人论证确认不建**，进展由 `task_runs` 读时聚合（`stage-progress` 端点后端一次算好下发）。
- [runner 实现 Story §4.3](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md) —— 任务处理与 DAG 推进（阶段间/内统一 `DependsOn`、单节点执行、状态回流）。

### 5.4 平台自身定位与部署形态（分层边界，2026-09-21 裁定）

> **起因**：console §7.12 补环境对接（kubeconfig / SSH）时暴露出更上游的歧义——「集群 / 目标 / 环境 / 组件」这些词在多种语境下被混用。本节钉死三层的边界与归属。

| 层 | 内容 | 归属 | 权威落点 |
| --- | --- | --- | --- |
| ① 能力 | 平台对目标做：构建 / 测试 / 发布 | 产品语义 | console §7 · hub API-REFERENCE · runner STORY |
| ② 接入 | 平台怎么够到目标：`agent` 回连 / `kubeconfig` / `ssh` | 产品语义 | **§5.6（本层展开）** · console §7.12 · hub `DATA-MODEL.md` §9.5 / §9.7 |
| ③ 自身 | 平台自己（**hub / console**；**不含 runner**，见 §5.6）装在哪、谁装、怎么升级 | **运维实践，不进产品模型** | 本库 [plans/E2E-VERIFY-PLAN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/E2E-VERIFY-PLAN.md) |

**已裁定事实**

- **③ 的起点是手工 helm**：postgres + hub + console + runner **由同一份 helm 一次装齐**进集群；这条 Gen0 基线**长期保留**，不是一次性过渡。
  **runner 不在 ③ 之内**（2026-09-21 二次裁定）：它是**接入侧代理组件**，其安装 / 升级由 **hub 编排、console 只调 API**（见 §5.6）；装在哪、是否与平台同集群，都**不改变它的组件身份**。
  ⚠️ **勿与"安装批次"混淆**：Gen0 安装时 runner 与 hub / console **同批装齐**（部署便利），但组件身份仍是接入代理——**同批安装不使 runner 变成"平台自身"**。
- **② 的主路径是 Agent 回连**：runner 的设计初衷 = 单独部署到**需要对接的各个集群**（可不同厂商 / 不同 region / 不同集群），出站回连 hub，以统一纳管多套环境。因此 `targets` 故意不存 kubeconfig（`internal/target/models/target.go`），`environments` 只引用 `target_id` + `namespace`。
- **直连通道（`kubeconfig` / `ssh`）已裁定立项，且由 hub 侧发起连接**：hub 出站直连目标 apiserver / sshd，**凭据归 hub**；覆盖**非容器目标**（物理机 / VM / 归档机）的连接 / 测试 / 发布 / 执行命令。完整规格、能力矩阵与通道对比见 **§5.6**。⚠️ 本节此前写的"agentless 尚未裁决、凭据挂 runner 侧"**已作废**。
- **单机版 = 目标恰好是平台自身所在集群**（2026-09-21 二次裁定修正）：平台**允许与环境部署在同一个集群**（console / hub / runner 同集群，如 [E2E P0 拓扑](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/E2E-VERIFY-PLAN.md) 的 kind `sdp-dev` + ns `sdp-workflow`），此时 `targets` 里那一行目标指向的集群**恰好也是平台自身所在集群**——这只是**部署位置**上的巧合。
  **事实不变**：那个集群客观上**既是被发布目标、又是平台底座所在**——双重身份在**事实**层面成立。
  **⛔ 作废的是由此推出的结论**：早前把 runner 也算进"平台自身"——**runner 是独立的接入代理组件，其组件身份与部署形态无关**，装在异集群还是与 hub 同集群都不改变这一点。
  仍然成立且必须坚持的是：**不要**为"平台自身"另建集群行 / 另建组件 / 另建环境。故凡提"集群"，仍须说明是哪个角色（**被发布目标** / **平台底座**）。
- **平台自身不进服务树 / 组件 / 环境模型**：③ 不是产品领域对象——避免"删除平台自己的组件"这类自指契约漏洞。**范围收窄为 hub / console（+ 其数据库）**（2026-09-21 二次裁定）；**runner 不在此列**。
- **平台自身的部署与升级留在平台之外**（撤销 2026-09-06 的"自升级默认走平台流水线"）：
  - 官方通道 = 各仓 `make package` / `pnpm image` 产出的镜像 + chart 交付包 → **外部 helm / CI** 发布。
  - **允许的一半**：平台组件的**构建**可走平台流水线（吃狗粮验证 Build 链路，失败可重跑、无自指风险），产物归档进制品库备外部取用。
  - **不允许的一半**：`Release` 不发布平台自身组件。
- **发布动作 = 推三组件镜像 + 维护版本矩阵**（2026-09-21 二次裁定）：部署平台时把**指定版本**的 console / hub / runner 镜像**一并推入镜像仓库**，并以一份**版本对应 ConfigMap**（`console` / `hub` / `runner` 三者版本号）作为**唯一版本事实源**，**集成在 hub 的 chart 内**随 hub 分发。接入管理的 runner 安装 / 升级**按该 CM 取值**（`hub/DATA-MODEL.md` §9.10）。Gen0 安装即**一体化**（console / hub / runner + 数据库一次装齐），故**平台自身集群在接入管理里天然呈"已装 runner"**、动作是**升级**（`hub/DATA-MODEL.md` §9.3 / §9.9）。**发布落点**：三组件配套版本**由人工填写并维护**在 hub 仓 `build/hub/versions.yaml`（三仓 tag 互不知情，**配套关系无法由仓库推导**），`build/hub/build.sh` 做**完整性 + SemVer 校验**后渲染进 chart（CM `package-versions`），由**已存在**的 release workflow 触发；版本号遵循 SemVer 2.0.0（详见 `hub/DATA-MODEL.md` §9.10）。

**不采纳「自升级」的六条理由**（详见 [plans/E2E-VERIFY-PLAN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/E2E-VERIFY-PLAN.md) P6）

1. **hub 是四重自指**：控制面 + 编排存储 + 制品来源 + 制品消费。升级 hub 的编排存在 hub DB 里、chart 由 hub 的制品库供、签名 URL 指向 hub Service——hub 起不来则**升级通道与回滚通道同时消失**，无法自救。
2. **必须放宽安全边界**：runner 的集群侧权限被刻意限定为"只碰某组件命名空间"（见 §5.2 / DATA-MODEL「4 部署边界」）；让它 helm-upgrade `sdp-workflow` 是**实质扩权**，且 `pipeline.sdp.io` 的 CRD 是 **cluster-scoped**，schema 变更绕不过集群级权限。
3. **不可灰度、不可回滚**：CRD 是集群级原子生效；helm rollback **不还原 CRD**（helm 不追踪 CRD 版本）；hub 建表靠启动时 AutoMigrate（只加不删）。新版本一旦把控制面锁死，唯一救生索是手工 `kubectl`。
4. **观测真空恰好覆盖最关键的那次运行**：hub 重启期间，这次升级的记录 / 日志 / DAG 全在重启中的 hub 里——**最需要看清的运行恰好看不见**。
5. ~~**权限主体在 API 层不存在**~~ ✅ **已补（2026-09-22，C-10）**：平台级 RBAC 已有 HTTP 端点（`/platform-roles` / `/platform-role-bindings`），"谁有权批准平台自升级"现在可在平台内表达。**但**「自升级」本身的审批流（`permission_request`）与到期回收作业仍未落地。
6. **收益错配**：平台组件数量固定（**hub / console 两个**；runner 不计入，见 §5.4）、升级者就是平台运维本人；通用流水的价值（版本历史 / 参数管理 / 一键回滚 / 审批）在自升级上边际收益低，而这些恰是外部 CI + helm 的强项。

**「独立升级页面上传组件包」方案**：本期不做。它**不能挂在 console 下**——console 本身是被升级对象，console 挂了正是最需要这个页面的时候。唯一可行形态是**平台之外常驻的 upgrade-controller**（Gen0 手工安装、**永不自升级**，自己服务静态页 + 执行其余三者的 helm 升级），本质是把「平台之外」这条通道产品化，而不是把自升级做进平台。

### 5.5 术语消歧（同一词的不同含义，引用前先确认）

| 词 | 含义 A | 含义 B | 消歧做法 |
| --- | --- | --- | --- |
| **自举** | ⛔ **已停用**：曾指"平台发布平台自己"（旧 P6 方案，2026-09-21 撤销，见 §5.4） | ✅ **读时播种默认数据**（seed-on-read：服务树 / 组件的默认值由**读路径**惰性生成，无 seed 脚本 / 无测试 SQL） | 含义 A 一律写「平台发布平台自己（已撤销）」；含义 B 写「读时播种默认数据（seed-on-read）」。**不再单用「自举」二字** |
| **集群** | ⛔ **已改称「目标（Target）」（2026-09-21）**：`clusters` / `Cluster` 作为领域对象名已废弃 | ③ **平台底座所在**：hub / console 自己装的那个 K8s 集群；K8s 技术词（`kind` 集群 / `ClusterRole` / `ClusterIP`）仍用「集群」 | 指"被纳管的对象"一律写「**目标（Target）**」；「集群」只保留 K8s 技术词与平台底座义 |
| **环境** | ✅ 领域对象：`environments`（挂在组件下，绑 `target_id` + `namespace`） | ⛔ 平台的运行环境（平台的 dev / staging / prod）——**不是领域对象** | 后者一律写「平台的运行环境（运维概念）」 |
| **组件** | ✅ 领域对象：`components`（叶子 = 服务组件，绑一个 git 仓库） | 平台自身的组件（**hub / console**） | 后者一律写「**平台组件**（hub / console）」，并注明其**不进服务模型**（§5.4）。**runner 例外**：接入侧代理组件，**不属平台自身**（2026-09-21 二次裁定） |
| **目标** | ✅ 被纳管的对象 / `targets` 注册表一行：`targetKind` = `k8s` 集群 **或** `host` 非容器主机（物理机 / VM / 归档机）——**不预设类型**；承载 `access` = `agent`/`kubeconfig`/`ssh`。console 菜单名 =「**接入管理**」 | ⛔ 平台的运行环境 | 必带 `targetKind`；非 K8s 目标一律写「**非容器目标**（`host`）」 |
| **通道（接入方式）** | ✅ `access`：平台**怎么够到**目标 —— `agent` / `kubeconfig` / `ssh` | ⛔「网络通道」「CI 通道」等泛称 | 一律写 `access=<值>`；**凭据归属必须同时说明**（`agent` → 目标侧；`kubeconfig`/`ssh` → **hub 侧**） |

> 这张表只做**消歧**，不引入新概念；每个词的权威定义仍在其所属文档（目标 / 环境 → `hub/DATA-MODEL.md` §9；组件 → §1）。

### 5.6 目标接入与执行后端（② 接入层展开；2026-09-21 裁定）

> **起因**：§5.4 钉死了三层的**归属**，但没展开 ② 接入层的**内部结构**。用户澄清：`kubeconfig` / `ssh` 都**由 hub 侧发起连接**（不是给 runner 用）；且**发布目标与归档机器都可能是非 K8s 的**——平台必须覆盖非容器环境的「连接 / 测试 / 发布 / 执行命令」全链路。本节落定这件事。

**（1）现状：两点实测事实，决定了改动量**

| 事实 | 依据 |
| --- | --- |
| hub **零出站能力**：无 `client-go`、无 SSH、无任何"连目标"的代码 | `hub/go.mod`（依赖仅 gin / gorm / minio / oidc / websocket） |
| runner **自己也不执行**：它把任务翻译成**目标集群里的一个 K8s Job**，由 Job 的 main 容器跑 `sh {ScriptPath}` / `helm upgrade --install` / `kubectl apply`；工作区是 **EmptyDir 卷** | `runner/pkg/executor/job_builder.go`（`mainContainer` / `releaseContainer` / `Build`） |
| 任务类型枚举只有 `Build;Release;Approval`（kubebuilder 校验） | `runner/api/v1alpha1/pipelinerun_types.go` |

→ **平台今天的执行底座 = "在目标集群里跑一个容器"。** Job / 命名空间 / ServiceAccount / RoleBinding / 卷，在物理机与虚拟机上**一个都不存在**。所以"兼容非容器环境"**不是加字段，而是执行后端的抽象化**。

**（2）两个正交维度**

| 维度 | 取值 | 说明 |
| --- | --- | --- |
| **目标类型** `targetKind` | `k8s` | Kubernetes 集群（含单机版的本地集群） |
| | `host` | **非容器目标**：物理机 / VM / 裸金属 / 归档存储机 |
| **接入通道** `access` | `agent` | 目标集群内 Runner **出站回连**；**hub 零凭据**；仅 `k8s` |
| | `kubeconfig` | **hub 持 kubeconfig 直连目标 apiserver**；仅 `k8s` |
| | `ssh` | **hub 持 SSH 凭据直连目标主机**；是 `host` 的**唯一**通道 |

**（3）能力矩阵："谁执行"由通道决定**

| 用户能力 | `agent`（现状） | `kubeconfig`（新增） | `ssh`（新增） |
| --- | --- | --- | --- |
| 连接 | Runner 回连，hub 不入站 | hub → 目标 apiserver | hub → 目标 sshd |
| 测试 | 建 Job 跑 test 脚本 | hub 建 Job 跑 test 脚本 | hub 远程跑 test 脚本 |
| 发布 | Job：`helm` / `kubectl` | hub 建 Job：`helm` / `kubectl` | **制品分发到主机 + 启停服务**（脚本） |
| 执行命令 | Job 容器内 | hub 建 Job 容器内 | **远程命令 / 脚本** |
| 工作区 | EmptyDir 卷 | EmptyDir 卷 | **目标主机上的临时目录** |
| 隔离边界 | ns + SA + RoleBinding | ns + SA + RoleBinding | **无**（SSH 用户身份即边界） |
| 凭据方向 | 目标 → 平台（`GATEWAY_TOKEN`） | **平台 → 目标** | **平台 → 目标** |

**（4）三个通道互补，不互相替代**

| 通道 | 需要 hub 主动网络可达目标吗 | 凭据风险 |
| --- | --- | --- |
| `agent` | **不要求**（目标可在 NAT / 内网后，或禁止入站） | **低**：hub 无目标凭据，hub 失守不波及该目标 |
| `kubeconfig` / `ssh` | **必须**可达 | **中**：凭据与条目**一一对应**（一条记录一份凭据，**不存在共享的万能凭据**），故单条失守的**影响面限于该条对应的目标，不横向扩散**；暴露量随直连条目数**线性叠加**。⚠️ 该结论以"只存 ref、明文不落 DB"且 ref 指向 hub 信任域**之外**为前提（`hub/DATA-MODEL.md` §9.5-2 / §9.7） |

→ 因此 **`agent` 通道的安全价值必须保留**：最敏感的目标继续走 `agent`，hub 永远不需要它的凭据。

> **措辞更正（2026-09-21 二次裁定）**：`kubeconfig` / `ssh` 的风险由"爆炸半径**反转**"更正为"**按条线性叠加**"——凭据**逐条对应、互不共享**（同一环境、不同条目即两份独立凭据），**不会因一条失守而全盘失守**。本 §5.6（4）与 `hub/DATA-MODEL.md` §9.5 此前的"反转"措辞**作废**。

**（5）本节改写了三处既有结论**

1. 既有的安全边界表述（hub `DATA-MODEL.md` §6.2 / §8.4、`DELETE-CONTRACT.md` §6 的「平台与目标环境隔离」）**须限定为"`agent` 通道隔离"**——直连通道下 hub **持有**目标凭据。这是本轮的关键更正：早前把 `kubeconfig` / `ssh` 的凭据错挂在 **runner 侧 Secret**。
2. **`targets` 表当前只描述 `agent` 通道**：`targets` 一行 = `k8s` + `agent` 的目标；`kubeconfig` / `ssh` 目标需要扩表承载（`hub/DATA-MODEL.md` §9.7）。
3. **`environments.target_id` NOT NULL 不变式受挑战**：非容器目标没有目标行（同上）。

**（6）待补（本节未裁决）**

- 凭据在 hub 侧的**物理存放**（hub 自身 K8s Secret / 加密落库 / 外部 Vault）——**未定**。注意本库 P0 拓扑**没有**独立 secret manager。
- 直连执行的**权限主体**与**审计落点**（平台级 RBAC 尚无 HTTP 端点，见 §5.2）。
- 是否引入 `executor backend` 抽象进 `TaskRunSpec`（现仅 K8s Job 一种实现）。

## 6. 文档组织

- 设计文档已从三个组件仓库的 `docs/design/` 统一收口到本仓库，作为**单一真源**；本库只放设计文档，不放代码。
- 文档内部互引统一使用 GitHub blob 链接（代码库级别），不使用相对路径或绝对文件路径。
- `hub/assets/` 下的架构图源（png / pptx）为独立图源，当前未被任何 md 引用。
