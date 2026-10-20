# 保真度差异清单：本地 kind vs 云上托管 K8s

> 日期：2026-10-09
> 决策背景：用户拍板双环境分工——本地 kind = 开发迭代（快反馈），云上托管 K8s = 验收 gate（真实验证）。
> 实证前提：2026-10-08/09 两日失败分类中，"单机 kind ≠ 生产导致的环境失真 = 0 例"；被证伪的是
> "AI 沙箱执行 + 脚手架缺陷"组合，不是本地环境的验证效力。本清单的作用是把"哪些验证必须上云"
> 从直觉变成逐项判定。

## 1. 判定方法

对每个差异点回答三问：
- **影响**：该差异会改变被测系统的哪些行为？
- **验收用例**：是否需要云上专门验证？(必须 / 顺带 / 不需要)
- **迁移改动**：上云需要改什么（chart 参数 / 新 manifest / 无）

## 2. 差异矩阵

| # | 维度 | 本地 kind 现状 | 云上托管 K8s | 影响 | 验收用例 | 迁移改动 |
|---|------|--------------|-------------|------|---------|---------|
| 1 | 拓扑 | 单节点 control-plane | 多节点 | 调度/反亲和/PV 节点绑定/节点故障行为 | **必须**（pod 分布、PV 跨节点挂载） | 无（K8s 原生调度自动生效） |
| 2 | DNS | /etc/hosts + CoreDNS rewrite | 真域名解析 | 证书校验、浏览器访问、跨环境 URL 一致性 | **必须**（ issuer 域名、harbor 域名全链路） | 移除 hub hostAliases（真 DNS 替代） |
| 3 | 证书 | cert-build 自签 + 手动信任 | cert-manager / Let's Encrypt / 云证书 | TLS 握手链、runner/hub 对 CA 的信任配置 | **必须**（hub trustedCASecret 语义变化） | sdp-ca secret 换真 CA 链 |
| 4 | 入口形态 | Envoy Gateway ClusterIP + 宿主 port-forward | LB / 生产 Ingress | 流量路径、源 IP、健康检查、TLS 卸载位置 | **必须**（Gateway API 在真实 LB 下的 Programmed/Accepted） | Gateway listener 换 LB；端口约定 443 不变 |
| 5 | 镜像源 | 本地 harbor（节点 ctr 直推） | 云 registry / 公网 harbor | ImagePullSecret、拉取限流、跨区带宽 | 顺带 | image.imageAddr 参数化；nodes 加 pull secret |
| 6 | 存储 | local-path（节点本地盘） | 云盘 CSI storageClass | PVC 跨节点挂载、IOPS、快照/备份 | **必须**（postgres/keycloak PVC 用真 CSI） | values 指定 storageClassName |
| 7 | Keycloak issuer | https://www.sdpworkflow.com:8443（非标端口） | 标准 443（或保留 8443 但真 DNS） | issuer URL 一致性、token iss 校验、redirect URI | **必须**（注册认证链在 443 下复验） | ISSUER/helm 参数去掉 :8443 |
| 8 | 网络策略 | 无 NetworkPolicy | 生产可能有 | pod 间访问控制、egress 限制 | 顺带 | 按云厂商基线策略评估 |
| 9 | 资源/配额 | 无 limits、无 quota | quota / LimitRange / 节点规格 | OOMKilled、调度失败、 autoscaler 行为 | 顺带 | 补 resources.requests/limits |
| 10 | harbor TLS | 集群内 plain-http（svc 直连）+ 网关 443 自签 | 真证书全链路 | ctr/docker push 信任路径 | 顺带 | --plain-http/--skip-verify 移除 |

## 3. 分级结论

- **必须上云验证**（本地无证据效力）：#1 多节点调度与 PV、#2 真 DNS 链路、#3 真证书信任链、#4 真实 LB 下的 Gateway 行为、#6 云存储、#7 issuer 443 化复验。
- **本地已足够**：控制面业务逻辑（pipeline 状态机、审批、RBAC、注册认证链的语义部分）、helm 渲染正确性、镜像构建产物。
- **本地负责发现、云上负责确认**：所有 E2E 场景先在本地跑绿，再在云上以同样用例复跑。

## 4. 云上首跑前置（Phase 3 输入）

- [x] 集群 kubeconfig（用户；CCE 托管，HCE 2.0 节点）
- [x] 镜像仓库方案：集群内自建 harbor（bitnami chart + csi-disk，ELB 443 暴露）
- [x] 平台域名 + 证书方案：自签 CA（`*.sdpworkflow.com`）+ 内网 DNS；真证书/公网 DNS 留守未拍板
- [x] storageClass：`csi-disk`（华为 EVS）
- [x] deploy 目标参数化：`env/prod-deplyment/` 独立脚本链（`hce-2.0-64bit-env.sh` 构建 → `run.sh` 推镜像（`--runtime nerdctl|docker`）→ `hce-2.0-64bit-deploy.sh` 一键部署）

## 5. 验收 gate 定位（Phase 4）

云上环境**只跑**，不进日常循环：
1. E2E 三流水线场景（构建/日常/发布+审批）
2. #10 canary 真流量 gate（ingress-nginx + 真实流量切分——唯一纯本地做不真的项）
3. 发布 pipeline 验收（pre-release/production 语义）

触发时机：里程碑 / 发布前 / 底层依赖升级。

## 6. 云上落地进展（2026-10-19）

差异矩阵逐项落定（验证证据：`env log/2026-10-19-cloud-install.md`、`env log/2026-10-19-cloud-deploy.md`）：

| # | 落定结果 |
|---|---------|
| 1 拓扑 | 多节点集群就绪；扩容新节点已实测（Pod 跨节点调度正常） |
| 2 DNS | `harbor/www.sdpworkflow.com` 已注册内网 DNS 并验证解析 |
| 3 证书 | 自签 CA 经 privileged DaemonSet 分发全节点（`harbor-ca-trust`）；正规 CA（消除分发）留守待拍板 |
| 4 入口 | **裁定：CCE 官方 Envoy Gateway 插件**（GatewayClass `envoy-gateway`，按 Gateway listeners 自动建独享 ELB，https=443）；自建 EG 数据面 ClusterIP 无 LB，云上禁用；Gateway Programmed + 端到端 4×200 验证通过 |
| 6 存储 | postgres/harbor PVC 走 `csi-disk`，全 Bound |
| 7 issuer | 443 标准端口下 `/keycloak/realms/sdp` 200，issuer 复验通过 |

- **验收 gate（§5）进展（2026-10-19）**：①E2E 冒烟 ✅（e2e-smoke.sh 云上首跑 PASS=15 FAIL=0 + cancel/rerun 定向 E2E PASS=11 FAIL=0，run 终态 Succeeded，脚本内动态取 token/内置 no_proxy，一条命令跑通）；②**canary 真流量 ✅**（e2e-canary.sh PASS=9 FAIL=0：release 流水线 → Rollout 步进 → 50% 双版本 2/2 并存 + NodePort 合成流量 18/22 → 权重快照回流 → 100% 收口）；③发布 pipeline 语义 ✅（Release 任务 RolloutConfig → Rollout CR → canary 引擎 → 快照回流，与 ② 同链贯通）。三项 gate 全绿。
- 端口裁定修正：本地 kind 8443 为端口映射时代过渡，云上 https listener=443（ELB 下 X-Forwarded-Port=443，issuer 推导不带端口）。
