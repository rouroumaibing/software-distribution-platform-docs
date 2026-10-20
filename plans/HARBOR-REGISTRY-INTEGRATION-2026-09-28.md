# Harbor 镜像仓库对接现状（Harbor 为默认镜像仓库、registry 可配置、非强制依赖）

> 状态判断以 [STATUS §2 #22](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准。本文件只记录 harbor 对接的结论与剩余 open 项（以现状为准）。
>
> **设计裁定**：镜像仓库为**可替换后端**，Harbor 仅是平台**默认**镜像仓库、**非强制依赖**。下文"全切"指"默认 registry 全切到 harbor"，不代表平台钉死 harbor 产品或 harbor 专属 API；registry 经 `HARBOR_REGISTRY` / `HARBOR_PROJECT` / `SDP_JOB_IMAGE_*` / `SDP_RUNNER_IMAGE` / 部署 `--set image.imageAddr` 可配置为其他兼容 OCI Distribution 的仓库（私有 harbor、云厂商镜像仓库、公网 harbor、纯 docker registry 等）。实现层仍把 harbor 当必装/必用的钉死点，见 [HARBOR-DEPENDENCY-GAP-2026-10-20.md](./HARBOR-DEPENDENCY-GAP-2026-10-20.md)。

## 结论

Harbor 已作为平台**默认镜像仓库**全切落地（registry 可配置，harbor 非强制依赖）：

- **推送侧**：三仓 `build/<comp>/build.sh` 由 `push_to_local_registry()` 改为 `push_to_harbor()`，默认推 `harbor.sdpworkflow.com/sdp/<comp>:<tag>`（hub `build/hub/build.sh:179`、runner `:119`、console `:110`）；推送目标经 `HARBOR_REGISTRY` / `HARBOR_PROJECT` 可改。
- **拉取侧**：三 chart `imageAddr` + 依赖镜像（postgres / envoy-gateway / keycloak）默认指向 `harbor.sdpworkflow.com/sdp/*`；`env/local-kind-dev/deploy-local.sh:238` `node_push_to_harbor()` 经节点 containerd 预推。部署时 `imageAddr` 经 `--set` 由 `HARBOR_REGISTRY` 派生，可覆盖为其他 registry。
- **任务默认镜像（第 3 类）**：`job_builder.go` 五镜像 + `agentops` busybox 默认值默认 `harbor.sdpworkflow.com/sdp/*` 扁平命名，本体经节点 containerd 入库，全栈 5 pod 自 harbor 拉取 Running（STATUS #22①③ 收口）；运行时镜像经 `SDP_JOB_IMAGE_*` 可换私有 mirror。
- **访问**：宿主 443 直转 + 节点 containerd mirror / CoreDNS rewrite（`deploy-local.sh:18`、`deploy/kind.yaml:11-37`），标准 443 直访（原 port-forward 8444 弃用）。
- **凭据**：默认 `admin` / `Admin@123`，暂不建 robot 账号。

## 剩余 open 项

- **第 4 类：平台级 Build→Harbor 对接**（STATUS #22②）：registry 配置入口 + `REGISTRY_*` 注入 + docker login 凭据 + image 制品命名约定 —— 等首个真实构建推送需求出现再拍板 scope，当前未实现；该项的 registry 抽象入口须支持非 harbor 后端。
- **实现层 harbor 强制依赖待解耦**：部署脚本 `stage_harbor()` 必装 harbor 本体、runner 自升级测试断言锁 harbor 前缀、三 chart `imageAddr` 默认值写死 harbor、agentops busybox 默认镜像缺 env 覆盖——均属实现钉死点，不反映设计意图，见 [HARBOR-DEPENDENCY-GAP-2026-10-20.md](./HARBOR-DEPENDENCY-GAP-2026-10-20.md)。

## 权威位置指针

- 当前状态与待办：[STATUS §2 #22](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md)
- 镜像地址权威：共享仓库 [DATA-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md) §9.3 / §9.10（§9.10 已载明 registry 可配置、harbor 默认）
- 实现层解耦改点：[HARBOR-DEPENDENCY-GAP-2026-10-20.md](./HARBOR-DEPENDENCY-GAP-2026-10-20.md)

## 变更历史

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-09-28 | 对接范围拍板：默认 registry 全切，四类镜像默认全部以 `harbor.sdpworkflow.com` 为仓库；`localhost:5000` 不再作为 SDF 镜像流转目标 | 平台镜像流转统一收口到 harbor 默认 |
| 2026-09-28 | 访问稳定化：宿主 443 直转 + 节点 containerd mirror / CA 信任 | 访问路径标准化 |
| 2026-09-28 | 凭据模型：默认 admin / `Admin@123`，暂不建 robot 账号 | 简化首版凭据管理 |
| 2026-10-08 | 默认 registry 全切落地（STATUS #22①③ 收口）；`localhost:5000` 仅保留为 harbor 未起时的 bootstrap 中转 | 部署脚本与 chart 全切到 harbor 默认 |
| 2026-10-20 | registry 可替换裁定：平台不钉死 harbor 产品或 harbor 专属 API；镜像地址经 `imageAddr` / `HARBOR_REGISTRY` / `HARBOR_PROJECT` / `SDP_JOB_IMAGE_*` / `SDP_RUNNER_IMAGE` 参数化支持任意兼容 OCI Distribution 的 registry；原"唯一镜像仓库"措辞修正为"默认镜像仓库" | 用户裁定镜像仓库不应强制绑定 Harbor 产品/API；原"唯一/必须"措辞与可替换架构意图冲突 |
