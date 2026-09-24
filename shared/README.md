# shared/ — 跨组件文档（横跨 ≥2 组件的整体性内容）

> **入住判据（2026-09-24 第二次修订，范围优先）**：内容横跨 ≥2 个组件（hub / console / runner / 身份基础设施）即入住，**整体迁入、不拆分、不设主从**——不以"变更权威在谁"为由留在某组件目录下。
> 旧判据「无单一变更权威才入住」已废止（hub 为变更源的横切文档同样入住）；但各概念的**行为权威仍在实现它的代码**，文档内保留的「权威实现在 hub」等标注是事实陈述，不是归属主张。

## 判据裁定记录

| 日期 | 裁定 | 内容 |
| --- | --- | --- |
| 2026-09-24（第一次） | 权威优先 | shared/ 只收「无单一变更权威」的真全局文档；hub 为变更源的横切文档留 hub/，靠域 index 交叉引用。 |
| 2026-09-24（第二次，**终局**） | **范围优先** | 横跨 ≥2 组件的文档**整体迁入、不拆分、不设主从**；六份横切文档自 hub/ 迁入（git mv，历史保留）。 |
| 2026-09-24（代价确认） | **跨目录耦合接受** | 「改 hub 权限代码 → 去 shared/ 改文档」的跨目录耦合被明确接受——**全局视角优先于变更耦合**。此判据终局，不再回退到权威优先。 |

> 裁定语义：目录位置表达的是**文档的治理范围主张**（这份内容属于整个平台），不是变更流程的镜像。防腐不靠位置，靠本 README 的维护纪律 + STATUS 指针协议 + 各域 index 交叉引用。

## 当前住户（7）

| 文件 | 横跨范围 |
| --- | --- |
| [CROSS-COMPONENT-ALIGNMENT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/CROSS-COMPONENT-ALIGNMENT.md) | 北极星 / 授权 / 执行模型 / 三层边界 / 术语 / 接入层，三端对齐视图 |
| [ACCOUNT-PERMISSION-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ACCOUNT-PERMISSION-MODEL.md) | 权限与审批：三条不动式（KC 身份 / hub 强制 / console 展示）+ runner 消费边界，治理三端 |
| [DELETE-CONTRACT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DELETE-CONTRACT.md) | 删除契约：console 入口 + hub 级联校验执行（`409 + {reasons}`） |
| [DATA-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md) | 领域/数据模型：hub 写、runner 写、console 读；含下发/授权/接入拓扑 |
| [API-REFERENCE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/API-REFERENCE.md) | REST 端点契约：hub 实现、console 消费 |
| [KEYCLOAK.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/KEYCLOAK.md) | 认证子系统：keycloakx 部署（hub chart）+ console/hub 交互 + 账号改密 |
| [ADR-dispatch-durable-queue.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ADR-dispatch-durable-queue.md) | hub↔runner WS 线协议决策：变更需两端同步 |

## 维护纪律

- 住户文件**整体维护**：修改时直接改 shared/ 下的文件，禁止为"某组件视角"另拆副本（单组件视角的内容写进该组件自己的 STORY/feature 文档并互链）。
- 各域 `index.md` 必须交叉引用被本域消费的住户文件。
- 状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准；住户文件不自持状态标记。
- 若某住户日后收敛为单组件内容（横跨不再成立），迁回该域并在本 README 记录一笔。

## 不入住（单组件内容）

- `hub/STORY-*` / `user-stories.md`：hub 实现叙事。
- `console/features/*`：前端既成设计事实。
- `runner/STORY-*`：runner 实现叙事。
