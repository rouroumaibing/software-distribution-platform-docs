# Harbor 镜像仓库对接现状（2026-10-08 全切已落地）

> 状态判断以 [STATUS §2 #22](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准。本文件只记录 harbor 对接的结论与剩余 open 项，**不再保留 2026-09-28 审计快照**（原「当时 0 环节对接 harbor」结论已整体反转，此处以现状为准）。

## 结论（全切已落地，2026-10-08）

Harbor 已作为平台**唯一镜像仓库**全切落地：

- **推送侧**：三仓 `build/<comp>/build.sh` 由 `push_to_local_registry()` 改为 `push_to_harbor()`，推 `harbor.sdpworkflow.com/sdp/<comp>:<tag>`（hub `build/hub/build.sh:179`、runner `:119`、console `:110`）。
- **拉取侧**：三 chart `imageAddr` + 依赖镜像（postgres / envoy-gateway / keycloak）均指向 `harbor.sdpworkflow.com/sdp/*`；`env/local-kind-dev/deploy-local.sh:238` `node_push_to_harbor()` 经节点 containerd 预推。
- **任务默认镜像（第 3 类）**：`job_builder.go` 五镜像 + `agentops` busybox 默认值已改 `harbor.sdpworkflow.com/sdp/*` 扁平命名，本体经节点 containerd 入库，全栈 5 pod 自 harbor 拉取 Running（STATUS #22①③ 收口）。
- **访问**：宿主 443 直转 + 节点 containerd mirror / CoreDNS rewrite（`deploy-local.sh:18`、`deploy/kind.yaml:11-37`），标准 443 直访（原 port-forward 8444 弃用）。

## 剩余 open 项

- **第 4 类：平台级 Build→Harbor 对接**（STATUS #22②）：registry 配置入口 + `REGISTRY_*` 注入 + docker login 凭据 + image 制品命名约定 —— 等首个真实构建推送需求出现再拍板 scope，当前未实现。

## 决策记录（2026-09-28 拍板，2026-10-08 落地）

1. **对接范围：全切** —— 四类镜像全部以 `harbor.sdpworkflow.com` 为唯一仓库；`localhost:5000` 不再作为 SDF 镜像流转目标。
2. **访问稳定化**：宿主 443 直转 + 节点 containerd mirror / CA 信任（已随部署落地，非单独集群重建步骤）。
3. **凭据模型**：admin + `Admin@123`，暂不建 robot 账号。

## 权威位置指针

- 当前状态与待办：[STATUS §2 #22](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md)
- 镜像地址权威：共享仓库 [DATA-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md) §9.3 / §9.10
