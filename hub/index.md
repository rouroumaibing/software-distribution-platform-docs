# hub 域文档索引

> 控制面 / 领域模型 / 数据模型 / REST API（Go + Gin + GORM + PG）。代码仓：<https://github.com/rouroumaibing/software-distribution-platform-hub>
> 状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准。
> **归属原则**：本目录多份文档虽然被 console / runner 消费，但变更源（代码权威）全部在 hub（权限唯一权威、删除判定在后端、schema SSOT=AutoMigrate），故留 hub/ 原位；真正"无单一权威"的全局文档才进 `../shared/`（见其 README 入住门槛）。

## 域级权威参考（横切消费、hub 为变更权威）

| 文件 | 说明 | 被谁消费 |
| --- | --- | --- |
| [DATA-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md) | 领域模型 + §6 下发与进展回收（§6.6 取消/重跑裁定）+ §7 授权模型 + §9 接入拓扑（§9.0 三层边界 / §9.11 自升级裁决） | hub / console / runner |
| [API-REFERENCE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/API-REFERENCE.md) | REST API 权威端点清单 + old→new 映射 + 设计钢人论证 | hub / console |
| [DELETE-CONTRACT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DELETE-CONTRACT.md) | 删除契约：级联校验 + `409 + {reasons}` verdict（hub 删除端点行为规格） | hub / console |
| [ACCOUNT-PERMISSION-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/ACCOUNT-PERMISSION-MODEL.md) | 账号与权限规范（唯一权威边界）：三条不动式 + 两层 RBAC + 审计 + 申请审批 + §12.1 实施裁定归档 | hub / console / Keycloak 运维 |
| [KEYCLOAK.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/KEYCLOAK.md) | 认证子系统：keycloakx 子 chart + realm 预置 + 与 console/hub 交互 + 账号改密 | hub / console |
| [ADR-dispatch-durable-queue.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/ADR-dispatch-durable-queue.md) | 下发持久队列 ADR | hub / runner |

## Story / 过程文档

| 文件 | 说明 |
| --- | --- |
| [STORY-hub-implementation.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-hub-implementation.md) | hub 控制面实现 Story |
| [STORY-BACKLOG.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-BACKLOG.md) | 实现 Backlog（B-01~B-19 + C-01~C-13）；**状态以 STATUS 为准，本表只记叙事** |
| [STORY-TEMPLATE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-TEMPLATE.md) | Story 模板 |
| [user-stories.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/user-stories.md) | 用户故事（裁定已折进正文标记） |
| [assets/](https://github.com/rouroumaibing/software-distribution-platform-docs/tree/main/hub/assets) | 架构图源（png + 流水线.pptx，独立图源，未被 md 引用） |

## features/ 与 plans/（按需建立）

git 不跟踪空目录，且按「无内容不建壳」原则：本域 features/ 与 plans/ 在**首份内容落档时创建**，不预建空壳。已有 Story 若未来按 feature 拆分（如审批子系统、agent_ops 各自成篇），落 `features/`；活跃实施计划落 `plans/`。

## 跨域引用

- 跨组件对齐总览（北极星 / 授权 / 执行模型 / 术语）：[shared/CROSS-COMPONENT-ALIGNMENT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/CROSS-COMPONENT-ALIGNMENT.md)

- 前端消费侧：[console/index.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/index.md)
- runner 消费侧：[runner/index.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/index.md)
- 全局状态：[plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md)
