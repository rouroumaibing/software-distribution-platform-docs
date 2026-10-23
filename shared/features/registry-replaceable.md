> **来源**：[plans/HARBOR-REGISTRY-INTEGRATION-2026-09-28.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/HARBOR-REGISTRY-INTEGRATION-2026-09-28.md)（harbor 默认对接现状）、[plans/HARBOR-DEPENDENCY-GAP-2026-10-20.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/HARBOR-DEPENDENCY-GAP-2026-10-20.md)（镜像仓库可替换 Gap 跟踪）；状态权威为 [plans/STATUS.md O-22](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md)。
> **拆分说明**：两份 GAP 文档是**对接现状/缺口跟踪**（结论 + 剩余 open 项 + 解耦改点清单），本文件是**行为规格**（镜像仓库如何被配置为可替换后端、默认与边界）。② Build→Harbor 对接为开放留守项，不进本规格。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 1. 问题与目标

历史实现把 harbor 当**必装/必用**的钉死点（镜像地址硬编码 `harbor.sdpworkflow.com/sdp/*`）。目标：镜像仓库作为**可替换后端**，平台默认用 harbor 但不强制；运维可经配置切到任意兼容 OCI Distribution 的仓库（私有 harbor、云厂商镜像仓库、公网 harbor、纯 docker registry）。

## 2. 范围

### 2.1 In-scope
- runner 任务默认镜像五件（`git`/`artifact`/`helm`/`kubectl` + agent exec）支持经环境变量覆盖。
- hub/runner 镜像地址经 `imageAddr` 覆盖。
- 证书信任（ca-trust）与镜像拉取凭据经 chart `imagePullSecrets` 注入。

### 2.2 Out-of-scope
- **② Build→Harbor 对接**：registry 配置入口 + `REGISTRY_*` 注入 + docker login 凭据 + image 制品命名约定——首个真实构建推送需求出现再拍板 scope（STATUS O-22② 维持登记，B2 决议 2026-10-12 不开发）。
- harbor 正规 CA 根治 + sdp 项目转 private（STATUS O-29，chart `imagePullSecrets` 支持未实现）。

## 3. 可配置入口（替换点）

| 维度 | 变量 / 字段 | 默认 | 说明 |
|------|------------|------|------|
| registry 地址 | `HARBOR_REGISTRY` / `HARBOR_PROJECT` | `harbor.sdpworkflow.com` / `sdp` | 仓库域名与项目名 |
| 任务镜像（4 件） | `SDP_JOB_IMAGE_GIT` / `_ARTIFACT` / `_HELM` / `_KUBECTL` | `alpine/git` 等 | 受限 registry 换成私有 mirror |
| agent exec 镜像 | `SDP_AGENT_EXEC_IMAGE` | — | 覆盖 agent 执行镜像 |
| 组件镜像 | chart `image.imageAddr`（`--set image.imageAddr=...`） | `harbor.sdpworkflow.com/sdp/*` | hub/runner/console 部署镜像 |
| 拉取凭据 | chart `image.imagePullSecrets` | `default-secret` | 无鉴权场景留空不渲染 |

> 五组件镜像（postgres/keycloak/hub/runner/console）已改扁平命名 `harbor.sdpworkflow.com/sdp/*`，覆盖位不变（STATUS O-22① 收口）。

## 4. 默认与可替换边界

- **默认 = harbor**：新部署开箱即用，无需配置。
- **可替换 ≠ 强制 harbor API**：平台不依赖 harbor 专属 API；只依赖 OCI Distribution 拉/推语义。
- **bootstrap 中转**：`localhost:5000` 仅本地 kind 引导用，非生产路径。
- **ca-trust 解耦**：自签 CA 经 ca-trust DaemonSet 分发（已随 2026-10-20 清理删除），正规 CA 引入后该机制消失（STATUS O-27/O-29）。

## 5. 代码证据（实测）

| 行为 | 位置 |
|------|------|
| 任务镜像四件覆盖位 | `runner/build/runner/charts/.../values.yaml:46-51`（`jobImages`）+ `deployment-runner.yaml` 注入 `SDP_JOB_IMAGE_*` |
| 组件镜像 `imageAddr` 覆盖 | `runner/build/runner/charts/.../values.yaml:9-15` |
| 拉取凭据 `imagePullSecrets` | 同上 `image.imagePullSecrets` |
| 五镜像入库（harbor） | STATUS O-22①（postgres/keycloak/hub/runner/console 经 node containerd 推入 harbor，全栈 5 pod 自 harbor 拉取 Running，2026-10-08 部署验证） |

## 6. 留守项（开放）

- **O-22② Build→Harbor 对接**：registry 配置入口 + `REGISTRY_*` 注入 + docker login 凭据 + image 制品命名约定。触发 = 首个真实"构建产物推送到可配置 registry"需求。B2 决议 2026-10-12：维持登记，本轮不开发。
- **O-29 harbor 正规 CA + sdp 转 private**：chart `imagePullSecrets` 支持未实现，阻塞 private registry 拉取。

## 7. 测试与验收

- **静态**：values 覆盖位与 chart 注入点齐全；`helm template` 全绿。
- **部署**：全栈 5 pod 自 harbor 拉取 Running（2026-10-08 已验）。
- **可替换验证**：换 `imageAddr` 指向其他 OCI 仓库 + 配 `imagePullSecrets` 拉取成功（属运维验收，待首个非 harbor 仓库需求时补）。

## 8. 决策记录（指针）

harbor 默认对接结论、可替换判定、解耦改点清单见 [HARBOR-REGISTRY-INTEGRATION-2026-09-28.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/HARBOR-REGISTRY-INTEGRATION-2026-09-28.md) 与 [HARBOR-DEPENDENCY-GAP-2026-10-20.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/HARBOR-DEPENDENCY-GAP-2026-10-20.md)。

## 9. 实现记录

- **runner chart**：`build/runner/charts/software-distribution-platform-runner/{values.yaml, templates/deployment-runner.yaml}`
- **权威状态**：`plans/STATUS.md O-22`（①③ 收口；② 留守）
