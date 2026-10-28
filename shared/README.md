# shared/ — 跨组件文档（横跨 ≥2 组件的整体性内容）

> **入住判据（第二次修订，范围优先）**：内容横跨 ≥2 个组件（hub / console / runner / 身份基础设施）即入住，**整体迁入、不拆分、不设主从**——不以"变更权威在谁"为由留在某组件目录下。
> 旧判据「无单一变更权威才入住」已废止（hub 为变更源的横切文档同样入住）；但各概念的**行为权威仍在实现它的代码**，文档内保留的「权威实现在 hub」等标注是事实陈述，不是归属主张。

## 判据裁定记录

| 日期 | 裁定 | 内容 |
| --- | --- | --- |
| 2026-09-24（第一次） | 权威优先 | shared/ 只收「无单一变更权威」的真全局文档；hub 为变更源的横切文档留 hub/，靠域 index 交叉引用。 |
| 2026-09-24（第二次，**终局**） | **范围优先** | 横跨 ≥2 组件的文档**整体迁入、不拆分、不设主从**；六份横切文档自 hub/ 迁入（git mv，历史保留）。 |
| 2026-09-24（代价确认） | **跨目录耦合接受** | 「改 hub 权限代码 → 去 shared/ 改文档」的跨目录耦合被明确接受——**全局视角优先于变更耦合**。此判据终局，不再回退到权威优先。 |

> 裁定语义：目录位置表达的是**文档的治理范围主张**（这份内容属于整个平台），不是变更流程的镜像。防腐不靠位置，靠本 README 的维护纪律 + STATUS 指针协议 + 各域 index 交叉引用。

## 当前住户（16）

| 文件 | 横跨范围 |
| --- | --- |
| [CROSS-COMPONENT-ALIGNMENT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/CROSS-COMPONENT-ALIGNMENT.md) | 北极星 / 授权 / 执行模型 / 三层边界 / 术语 / 接入层，三端对齐视图 |
| [ACCOUNT-PERMISSION-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ACCOUNT-PERMISSION-MODEL.md) | 权限与审批：三条不动式（KC 身份 / hub 强制 / console 展示）+ runner 消费边界，治理三端 |
| [DELETE-CONTRACT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DELETE-CONTRACT.md) | 删除契约：console 入口 + hub 级联校验执行（`409 + {reasons}`） |
| [DATA-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md) | 领域/数据模型：hub 写、runner 写、console 读；含下发/授权/接入拓扑 |
| [API-REFERENCE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/API-REFERENCE.md) | REST 端点契约：hub 实现、console 消费 |
| [KEYCLOAK.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/KEYCLOAK.md) | 认证子系统：keycloakx 部署（hub chart）+ console/hub 交互 + 账号改密 |
| [CERTIFICATES.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/CERTIFICATES.md) | 平台 TLS 证书：env 仓生成器 + 各组件 secret 引用契约（hub/console/网关） |
| [BUILD-TOOLCHAIN.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/BUILD-TOOLCHAIN.md) | 三组件镜像构建工具链版本要求（containerd 路线：nerdctl >= 2.x / buildkit >= v0.34，禁装 docker），build.sh 行为要点 + mirrors 配置（跨三组件 + env 仓） |
| [ADR-dispatch-durable-queue.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ADR-dispatch-durable-queue.md) | hub↔runner WS 线协议决策（耐久队列 + 混合交付）+ §10 线协议类型一致性约定（SSOT=runner api/v1alpha1、hub internal/runnerproto 派生副本、变更同步、兼容规则、三仓独立构建）：变更需两端同步 |
| [runner-reflux-spec.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/runner-reflux-spec.md) | runner→hub 执行态回流协议（灰度权重/产物/agent_version/通知已读）：runner 发、hub 落、console 消费（跨三端永久设计文档） |
| [install-upgrade-executor-design.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/install-upgrade-executor-design.md) | agent_ops install/upgrade 执行器：runner 自升级 Job + hub enroll 对账，台账终态闭环（跨三端永久设计文档） |
| [alerting-rules-design.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/alerting-rules-design.md) | 离线告警规则：hub/runner 指标 → Prometheus rules（env 仓部署）→ 通知流（跨三端永久设计文档） |
| [ADR-0001-runner-first-connect-enrollment.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ADR-0001-runner-first-connect-enrollment.md) | Runner 首连自注册 ADR（跨 hub+runner 线协议）；自根 plans/ 迁入 shared/ |
| [E2E-THREE-PIPELINES-2026-09-26.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/E2E-THREE-PIPELINES-2026-09-26.md) | 三流水线整体 E2E 权威记录（跨组件）；自根 plans/ 迁入 shared/ |
| [ADR-0002-runner-install-bootstrap.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ADR-0002-runner-install-bootstrap.md) | Runner 安装引导 ADR（join-bundle API：网关 URL + CA 信任根 + enroll token 一次性下发，安装数据收编为 hub 能力） |
| [NETWORKING-GATEWAY.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/NETWORKING-GATEWAY.md) | 平台入口网关（Envoy Gateway / Gateway API）：控制面/数据面、Gateway 级资源边界（env 仓脚手架 / CCE 插件持有）、三仓路由清单、Policy 现状、部署顺序与运维（跨三端 + env 仓） |

## 维护纪律

- 住户文件**整体维护**：修改时直接改 shared/ 下的文件，禁止为"某组件视角"另拆副本（单组件视角的内容写进该组件自己的 STORY/feature 文档并互链）。
- 各域 `index.md` 必须交叉引用被本域消费的住户文件。
- 状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准；住户文件不自持状态标记。
- 若某住户日后收敛为单组件内容（横跨不再成立），迁回该域并在本 README 记录一笔。

## 不入住（单组件内容）

- `hub/STORY-*` / `user-stories.md`：hub 实现叙事。
- `console/features/*`：前端既成设计事实。
- `runner/STORY-*`：runner 实现叙事。
