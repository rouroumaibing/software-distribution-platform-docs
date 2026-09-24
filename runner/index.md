# runner 域文档索引

> 执行器：接收 hub 下发 → k8s CRD → 任务执行 → 状态回写（Go + controller-runtime）。代码仓：<https://github.com/rouroumaibing/software-distribution-platform-runner>
> 状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准。

## 文档清单

| 文件 | 说明 |
| --- | --- |
| [STORY-runner-implementation.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md) | runner 实现 Story：§4.2.3 kubebuilder 安装、§4.3 任务处理与 DAG 推进、§4.4 授权边界 |
| [kubebuilder-install.txt](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/kubebuilder-install.txt) | Kubebuilder / controller-gen 命令记录（CRD / RBAC / deepcopy 生成） |

## features/ 与 plans/（按需建立）

git 不跟踪空目录，且按「无内容不建壳」原则：首份内容落档时创建（如灰度发布、agent_ops 执行器各自成篇落 `features/`；活跃实施计划落 `plans/`）。

## 跨域引用（权威在他域）

- 跨组件对齐总览（北极星 / 授权 / 执行模型 / 术语）：[shared/CROSS-COMPONENT-ALIGNMENT.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/CROSS-COMPONENT-ALIGNMENT.md)

- 执行模型与协议权威：[hub/DATA-MODEL.md §6](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)（**权威在 hub**）
- 授权边界：runner 只消费 hub 已鉴权下发的 spec，自身无授权逻辑（见 Story §4.4；权威模型在 [hub/ACCOUNT-PERMISSION-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/ACCOUNT-PERMISSION-MODEL.md)）
- console 消费的 4 类流水线模式定义：[console/features/ui-01-goals-users-competitors.md §1.1](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/features/ui-01-goals-users-competitors.md)
