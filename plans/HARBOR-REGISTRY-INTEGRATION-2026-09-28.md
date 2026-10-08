# Harbor 镜像仓库对接盘点（AUDIT）— 2026-09-28

> ## 【2026-10-08 状态更新】核心结论已整体反转，以本框为准
> - **harbor 全切已落地**，原「当前 0 个环节对接 harbor」不再成立（下文正文保留 2026-09-28 原貌，仅受影响处加注）：
>   - **推送侧（第 1 类）**：三仓 `build/<comp>/build.sh` 已由 `push_to_local_registry()` 改为 `push_to_harbor()`，推 `harbor.sdpworkflow.com/sdp/<comp>:<tag>`（hub `build/hub/build.sh:179`、runner `build/runner/build.sh:119`、console `build/console/build.sh:110`）；
>   - **拉取侧（第 1 类）**：三 chart `imageAddr` 均已指向 `harbor.sdpworkflow.com/sdp/*`（hub chart `values.yaml:19`、runner `:10`、console `:16`）；
>   - **依赖镜像（第 2 类）**：`env/local-kind-dev/deploy-local.sh` 新增 `node_push_to_harbor()`（`:238` 起），postgres / envoy-gateway / keycloak 经节点 containerd 预推入 harbor；hub chart keycloak `image.repository` 已切 `harbor.sdpworkflow.com/sdp/keycloak`；
>   - **集群侧**：节点 containerd mirror + CoreDNS rewrite 已配置（`env/local-kind-dev/deploy/kind.yaml:11-37`、`deploy-local.sh` `ensure_node_dns_harbor`），节点经集群 DNS 直达 harbor 网关拉镜像。
> - **第 3 类（任务默认镜像仍 docker.io 裸名，`job_builder.go:37-43`）与第 4 类（平台级 `REGISTRY_*` 注入缺失）仍准确未做**，§4 对应待办保持未勾选。
> - 原「短期 port-forward 8444」访问决策已被**宿主 443 直转 + containerd mirror** 取代（`deploy-local.sh:18` 注释、`deploy/kind.yaml` mirror），见 §3 / §5 注记。
> - **§6 证据快照的行号为 2026-09-28 时点**，不逐行重写历史；现行实现以上述位置为准。

> 背景：Harbor 已部署到 `kind-sdp-dev` 集群（namespace `harbor`），服务域名
> `harbor.sdpworkflow.com`（注：用户口述写成 `sdfworkflow.com`，实际为 `sdpworkflow.com`，
> 即 software-distribution-platform）。本盘点回答一个问题：**当前 SDP 代码库里，哪些环节已经把镜像
> 推到 / 拉自 harbor？**
>
> 结论先行（2026-09-28 时点）：**当时 0 个环节对接 harbor。** Harbor 此刻只完成了"独立部署 + 可达"，
> 但所有 SDF 相关镜像的构建 / 推送 / 拉取路径，仍然指向 `localhost:5000`（kind 本地
> registry）或公网 `docker.io / quay.io`。"SDF 镜像保存到 harbor" 目前是**设计意图，尚未落地**。
> **【2026-10-08 更新：全切已落地，第 1/2 类已对接 harbor，见文首状态更新框。】**

---

## 1. SDF 相关镜像的四大类（及当前真实流转目标）

| # | 镜像类别 | 当前推/拉目标 | 证据（文件:行 / 命令） | 是否对接 harbor |
| --- | --- | --- | --- | --- |
| 1 | **平台组件镜像** hub / runner / console | ~~`localhost:5000/<comp>:vX`~~ → `harbor.sdpworkflow.com/sdp/<comp>:vX`【2026-10-08 已切】 | `build/hub/build.sh:179` `push_to_harbor()`；<br>`build/runner/build.sh:119`；<br>`console/build/console/build.sh:110` | ✅ |
| 2 | **平台依赖镜像** postgres / envoy-gateway / keycloak | ~~`localhost:5000/...`~~ → `harbor.sdpworkflow.com/sdp/...`【2026-10-08 已切】 | `env/local-kind-dev/deploy-local.sh:238-259` `node_push_to_harbor()`（经节点 containerd 预推）；<br>hub chart `keycloak.image.repository: harbor.sdpworkflow.com/sdp/keycloak`（values.yaml:114） | ✅ |
| 3 | **流水线任务默认镜像** git / artifact(curl) / helm / kubectl | `docker.io` 公网（裸名） | `runner/pkg/executor/job_builder.go:37-43`（`alpine/git`、`curlimages/curl`、`alpine/helm`、`bitnami/kubectl`）；<br>runner chart `jobImages.*`（`build/runner/charts/.../values.yaml:32-36`） | ❌ |
| 4 | **用户在流水线 Build 任务产出的业务镜像** | 完全由用户脚本自理 | 见 §2 详述 | ❌ |

### 拉取侧（集群从哪拉镜像）

| 镜像类别 | chart / 部署的 imageAddr | 证据 |
| --- | --- | --- |
| hub | ~~`localhost:5000/...`~~ → `harbor.sdpworkflow.com/sdp/software-distribution-platform-hub:v0.0.1`【2026-10-08 已切】 | `hub/build/hub/charts/.../values.yaml:19` |
| runner | ~~`localhost:5000/...`~~ → `harbor.sdpworkflow.com/sdp/software-distribution-platform-runner:v0.0.1`【2026-10-08 已切】 | `runner/build/runner/charts/.../values.yaml:10` |
| console | ~~`localhost:5000/...`~~ → `harbor.sdpworkflow.com/sdp/software-distribution-platform-console:v0.0.1`【2026-10-08 已切】 | `console/build/console/charts/.../values.yaml:16` |
| keycloak（hub 子 chart） | ~~`localhost:5000/keycloak/keycloak:26.7.4`~~ → `harbor.sdpworkflow.com/sdp/keycloak:26.7.4`【2026-10-08 已切】 | `hub chart values.yaml:114` |

**结论**（2026-09-28 时点）：拉取侧与推送侧当时**全部钉死 `localhost:5000`**。**【2026-10-08 更新：拉取侧（chart `imageAddr`）与推送侧（build.sh / deploy-local.sh）均已切至 `harbor.sdpworkflow.com/sdp/*`，见文首状态更新框。】**

---

## 2. 第 4 类（业务产物镜像）为何"天然没接 harbor"

这是用户所说的「SDF 相关镜像」核心，但它目前**没有任何平台级 harbor 对接**：

- 一个 `Build` 任务（`TaskTypeBuild`）在主容器跑用户的脚本（`runner/pkg/executor/job_builder.go`
  `mainContainer`，`Image` 由用户在任务里指定）。
- 平台**不注入** registry 地址、**不注入** registry 凭据；`docker build` / `docker push` 的
  目标完全由用户脚本硬编码决定。
- hub 侧 `ArtifactRegistry` 接口（G-2，`internal/run/service/pipeline_run_params.go:18-28`）
  **只登记 Produces 的元数据字符串**（如 `location` / `version`），并不会把镜像真实推到某个仓库。
- 种子数据 `cmd/hub/conf/08_runs_artifacts.sql:77,80` 里 `image` 类制品用的是占位
  `registry.local:5000/platform-eng/...` —— **不是 harbor，且只是元数据示例**。
- 制品存储驱动是 `local`（`hub chart values.yaml:65-69` `localRoot: /data/artifacts`），
  存的是文件制品，与镜像仓库无关。

也就是说：哪怕用户现在在 Build 脚本里写 `docker push harbor.sdpworkflow.com/...`，也是**用户自己
硬编码 + 自己配 docker login**，平台既不知道、也不管理这件事。这不是"对接"，是"绕道"。

---

## 3. Harbor 自身引用 `harbor.sdpworkflow.com` 的地方（与"SDF 镜像对接"是两件事）

这些引用只是让 **Harbor 服务本身能对外提供**，并不表示任何 SDF 镜像在用它：

- `software-distribution-platform-env/harbor/values.yaml:4` `externalURL: https://harbor.sdpworkflow.com`
- `software-distribution-platform-env/harbor/harbor-gateway.yaml:12,19` `hostname: harbor.sdpworkflow.com`
- `software-distribution-platform-env/harbor/harbor-command-guide.txt`
- 集群内 TLS Secret `harbor-tls` 用 `cert-build/certs/harbor.crt`（SAN `*.sdpworkflow.com`）。

当前访问链路：Harbor Envoy 经 `kubectl port-forward ... 8444:443`（会话级后台进程）可达，
`curl --noproxy '*' --cacert cert-build/certs/ca.crt https://harbor.sdpworkflow.com:8444/api/v2.0/health`
返回全组件 healthy。
**【2026-10-08 注：该 port-forward 8444 方式已被「宿主 443 直转（`deploy-local.sh:18`，sudo port-forward 宿主 443 -> svc 443）+ 节点 containerd mirror / CoreDNS rewrite（`deploy/kind.yaml:11-37`）」取代，标准 443 直访，8444 弃用。】**

---

## 4. "对接 harbor" 待办清单（已拍板：全切，见 §5）

> 下列为 2026-09-28 拍板时点的清单。**【2026-10-08 更新：第 1/2 类三项已完成（勾选）；第 3/4 类与文档同步项仍未实现，状态不变。】**按 2026-09-28 拍板结论收敛为"全切"方案。

- [x] **组件 build 推送切换（第 1 类）**：三仓 `build/<comp>/build.sh` 的 `push_to_local_registry()`
      切换为推 `harbor.sdpworkflow.com/<project>/<comp>:<tag>`（login 凭据 = admin / `Admin@123`，
      CA 信任 / insecure-registries 随决策 2 的集群重建一并配置）。
      ✅ 2026-10-08：已落地为 `push_to_harbor()`（hub `build/hub/build.sh:179`、runner `:119`、console `build/console/build.sh:110`）。
- [x] **拉取侧切换（第 1 类）**：三 chart `imageAddr` + `deploy-local.sh` 的 `--set image.imageAddr` 改为 harbor 地址。
      ✅ 2026-10-08：三 chart `imageAddr` 均已指向 `harbor.sdpworkflow.com/sdp/*`（hub `values.yaml:19`、runner `:10`、console `:16`）。
- [x] **依赖镜像入 harbor（第 2 类）**：postgres / envoy-gateway / keycloak 全部入 harbor；
      `deploy-local.sh` 预推目标与 hub chart keycloak `image.repository` 同步切换
      （kind 节点拉 harbor 需 containerd mirror / hosts + CA 信任，随集群重建一并做）。
      ✅ 2026-10-08：`deploy-local.sh` `node_push_to_harbor()`（`:238-259`）经节点 containerd 预推；keycloak `image.repository` 已切 harbor（`values.yaml:114`）；节点 containerd mirror + CoreDNS rewrite 已配置（`deploy/kind.yaml:11-37`）。
- [ ] **runner 任务默认镜像入 harbor（第 3 类）**：`job_builder.go` 的 4 个默认镜像
      （G-7 已有 `SDP_JOB_IMAGE_*` 覆盖位）推 harbor 并改默认值；`busybox`（agentops `DefaultImage`）同理。
- [ ] **平台级 Build→Harbor 对接（第 4 类核心）**：
      - 新增 registry 配置入口（地址 / 项目 / 凭据 secret），Build 任务注入 `REGISTRY_*` 与 `docker login` 凭据；
      - 约定 Build 产物镜像命名 `harbor.sdpworkflow.com/<project>/<svc>:<version>`；
      - `Produces` 中 `image` 类制品的 `location` 直接写 harbor URL（替代 `08_runs_artifacts.sql` 的占位）。
- [ ] **文档同步**：`docs/shared/DATA-MODEL.md:689`「镜像与默认参数固化…推入镜像仓库」补 harbor 地址与版本矩阵 ConfigMap 的对应。

---

## 5. 决策记录（2026-09-28 用户拍板）

1. **对接范围：全切。** 四类镜像（平台组件 / 平台依赖 / 任务默认镜像 / 业务产物镜像）全部以
   `harbor.sdpworkflow.com` 为唯一镜像仓库；`localhost:5000`（kind 本地 registry）不再作为
   SDF 镜像流转目标。
2. **访问稳定化：下次重建集群时一并做。** 下次 plan 重建 kind 集群时加 `extraPortMappings`
   （在已发布的 8080/8082/8443 之外固定映射 harbor 443），并同步节点 containerd 的
   harbor mirror / CA 信任。**本次不重建集群**，短期继续用 port-forward 8444 访问。
   **【2026-10-08 注：该决策已提前落地并被取代——宿主 443 直转 + 节点 containerd mirror / CoreDNS rewrite 已配置（`deploy-local.sh:18`、`deploy/kind.yaml:11-37`、`ensure_node_dns_harbor`），port-forward 8444 弃用。】**
3. **凭据模型：admin + `Admin@123`。** 暂不建 robot 账号；凭据落点（docker login /
   registry secret 注入）在落地各清单项时具体化。

---

## 6. 证据快照（本次审计直接读取）

- 推送侧全部 `localhost:5000`：`build/{hub,runner}/build.sh` `push_to_local_registry()`；
  `console/build/console/build.sh` 同名函数；`env/local-kind-dev/deploy-local.sh:132-168`。
- 拉取侧全部 `localhost:5000`：`*chart*/values.yaml` 的 `imageAddr`；`deploy-local.sh:287/321/337`。
- 任务默认镜像公网裸名：`runner/pkg/executor/job_builder.go:37-43`。
- 无平台级 registry 注入：`runner/pkg/executor/job_builder.go`（`mainContainer` 仅注入 `SDP_*` 与用户 `Params`，无 registry 相关 env）。
- harbor 仅自身引用 `harbor.sdpworkflow.com`：`env/harbor/{values.yaml,harbor-gateway.yaml,harbor-command-guide.txt}`。
