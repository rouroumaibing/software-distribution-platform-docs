# shared/ — 无单一权威的全局文档

> 本目录收留**描述范围横跨 ≥2 个组件、且不存在单一变更权威**的真全局文档。

## 当前住户

| 文件 | 资格说明 |
| --- | --- |
| [CROSS-COMPONENT-ALIGNMENT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/CROSS-COMPONENT-ALIGNMENT.md) | 跨组件对齐总览（北极星 / 授权模型 / 执行模型 / 三层边界 / 术语消歧 / 接入层）：横跨三组件、变更不由单一组件发起（2026-09-24 自根 README §5 迁入） |

## 入住门槛（三条同时满足，缺一不可）

1. **范围**：文档描述的内容横跨 ≥2 个组件（hub / console / runner / 部署拓扑）。
2. **无单一权威**：变更不由任何一个组件的代码单独发起——即不存在"谁改代码谁改文档"的天然落点。
3. **不可归位**：无法在保持"文档位置镜像代码权威结构"的前提下放进某个域目录。

## 反例（不入住，留在权威域 + 交叉引用）

| 文档 | 为什么不入住 |
| --- | --- |
| `hub/ACCOUNT-PERMISSION-MODEL.md` | 被三端消费，但权限唯一权威是 hub → 留 hub/ |
| `hub/DELETE-CONTRACT.md` | console 有入口，但删除判定权威在后端 → 留 hub/ |
| `hub/DATA-MODEL.md` | console/runner 读，但 schema SSOT=AutoMigrate 在 hub → 留 hub/ |
| `hub/KEYCLOAK.md` | 身份层贯穿三端，但 KC 由 hub chart 托管 → 留 hub/ |

## 候选住户（未来可能产生）

- 部署拓扑总览（kind / 网关 / 三服务互联，横跨 deploy 与三仓的独立成篇版）

## 维护纪律

- 新文件入住前，先在其**来源域**的 index.md 交叉引用处标注「已迁 shared/」，再删除原位文件（git mv），避免死链。
- 发现某个住户已能被单一权威覆盖时，**迁回该域**并在本 README 记录一笔。
