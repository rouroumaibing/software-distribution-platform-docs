# hub 域文档索引

> 控制面实现（Go + Gin + GORM + PG）。代码仓：<https://github.com/rouroumaibing/software-distribution-platform-hub>
> 状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准。
> **归属原则（2026-09-24 修订，范围优先）**：横跨 ≥2 组件的文档整体归 `../shared/`——本域曾收纳的 DATA-MODEL / API-REFERENCE / DELETE-CONTRACT / ACCOUNT-PERMISSION-MODEL / KEYCLOAK / ADR-dispatch-durable-queue 六份横切文档已迁入 shared/（不拆分、不设主从）。

## hub 消费的跨组件文档（住户在 shared/）

| 文件 | 说明 |
| --- | --- |
| [DATA-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md) | 领域模型 + §6 下发与进展回收（§6.6 取消/重跑裁定）+ §7 授权模型 + §9 接入拓扑（§9.0 三层边界 / §9.11 自升级裁决） |
| [API-REFERENCE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/API-REFERENCE.md) | REST API 权威端点清单 + old→new 映射 + 设计钢人论证 |
| [DELETE-CONTRACT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DELETE-CONTRACT.md) | 删除契约：级联校验 + `409 + {reasons}` verdict |
| [ACCOUNT-PERMISSION-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ACCOUNT-PERMISSION-MODEL.md) | 账号与权限规范：三条不动式 + 两层 RBAC + 审计 + 申请审批 + §12.1 实施裁定归档 |
| [KEYCLOAK.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/KEYCLOAK.md) | 认证子系统：keycloakx 子 chart + realm 预置 + 与 console/hub 交互 + 账号改密 |
| [ADR-dispatch-durable-queue.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ADR-dispatch-durable-queue.md) | 下发持久队列 ADR |
| [CROSS-COMPONENT-ALIGNMENT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/CROSS-COMPONENT-ALIGNMENT.md) | 跨组件对齐总览（北极星 / 授权 / 执行模型 / 术语） |

完整住户清单与维护纪律见 [shared/README.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/README.md)。

## hub 自有文档（单组件叙事）

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

- 前端消费侧：[console/index.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/index.md)
- runner 消费侧：[runner/index.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/index.md)
- 全局状态：[plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md)
