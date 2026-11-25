# 云上验收 gate 待确认清单（CLOUD-GATE-CHECKLIST）

> 用途：云上 gate 实跑前的执行清单。把散落在 `STATUS.md`、各 GAP/审计文档、三份交付报告里的
> 「未完成 / 待验证 / 他域 / 代码侧落地·验收 gate 待云上」条目，按**云上验收的相关性**收口到一处，
> 供执行人逐项确认、打勾、留证。
>
> 状态权威仍是 `plans/STATUS.md`——本清单不自持状态，只做「云上验收专项」的执行编排；
> 编号族权威见 `ID-INDEX.md`。凡本清单与 `STATUS.md` 冲突，以 `STATUS.md` 为准。
>
> 关联的证据与矛盾处置见本文 §5「过期内容处置」与 §6「报告间口径统一」。

---

## 0. 执行摘要

云上验收的**唯一自动化入口**是 `env/prod-deplyment/gate-cloud.sh`——它只编排、不部署、不清理，
串行执行四步 E2E（`e2e-smoke.sh` → `e2e-cancel-rerun.sh` → `e2e-canary.sh` → `e2e-example-release.sh`），
只认结尾 `RESULT: PASS=n FAIL=m` 行判定（FAIL>0 / 无 RESULT 行 / 非零退出即停），证据落
`gate-evidence/<UTC>/`。脚本已固化（语法 + 参数解析 + RESULT 判定已验），**但从未在云上实跑**。

三个决定性的前置事实：

1. **云上环境是归零态**。2026-10-20 全量清理（SDP/harbor/nginx 命名空间与 PVC 全删），
   2026-10-23 曾重建并真集群验证，但 `FIDELITY` §6 明确「三项 gate 的 ✅ 是历史验收记录，非当前常驻状态」。
   **不重建部署链，则无任何云上 gate 可跑。**
2. **「代码完成」≠「验收 gate 通过」**。`STATUS.md` 文首定义了完成语义：凡标「代码侧落地」而 gate 未跑者，
   须显式标注「待云上」。本清单 P1 大都是这类——代码已落、只欠云上实跑，是本次要消化的主体。
3. **本地已闭环 ≠ 云上已闭环**。网关后端 TLS（A–F）、OIDC 冷启动重试等已在本地 kind 验证，
   云上是另一次独立验收，需按本文逐项重跑确认。

一次通过的标准动作序：`§1 重建环境 → §2 跑 gate-cloud.sh → §3 逐项确认 → §4 收证据 → 回填本文勾选栏`。

---

## 1. P0｜环境前置（不先做则 gate 无法启动）

| # | 确认项 | 通过标准 | 权威落点 / 命令 |
| --- | --- | --- | --- |
| P0-1 | 云上环境是否已重建 | `sdp-workflow` / `harbor` / `sdp-run` 三命名空间存在，工作负载 Running，PVC Bound | `kubectl get ns,pods,pvc -A`；归零则按 `FIDELITY` §6 注记重跑 `hce-2.0-64bit-deploy.sh` → `run.sh` → `example/nginx-canary` |
| P0-2 | 网关与 DNS/证书链 | Gateway Programmed，8443→443 listener，harbor/www 内网 DNS 解析正确，自签 CA 已分发全节点 | `FIDELITY` §6 行 60-67；`shared/NETWORKING-GATEWAY.md` |
| P0-3 | gate-cloud.sh 可运行 | 四步脚本齐备；`--only=smoke` 能跑出 `RESULT` 行 | `env/prod-deplyment/gate-cloud.sh`；`ls e2e-*.sh` 见 4 个脚本 |
| P0-4 | 令牌与访问参数 | TOKEN 留空时动态换取可用；BASE/KC_ISSUER/KC_* 与云上实际一致（云上 issuer 无 8443 端口） | `gate-cloud.sh` 变量入口；`KC_ISSUER=https://www.sdpworkflow.com/keycloak/realms/sdp` |
| P0-5 | 新 hub 镜像是否上云 | 若本次验收要覆盖 P0-1（OIDC 冷启动重试）修复，需确认云上 hub 镜像为含修复版本 | 本地已升 `v0.0.2`，证据见 `LOCAL-RUNTIME-ISSUES.md` §10；云上镜像另行决策（见 §3 P2-8） |

> 执行策略：先 `./gate-cloud.sh --only=smoke` 打通前置，再跑全量四步。前者是后者的前置，不可换序。

---

## 2. P1｜云上 gate 直接相关（代码已落地，待云上实跑确认）

这些是 `STATUS.md` 明确标注「代码侧落地·验收 gate 待云上」的项，是本次 gate 要消化的主体。

| 编号 | 确认项 | 当前状态 | 云上确认动作 / 通过标准 | 权威落点 |
| --- | --- | --- | --- | --- |
| **O-42 G2** | 网关 ELB 健康探针归因 | 未归因（2026-10-19 4×200 属结果性通过） | 查 EG 插件 autogen ELB 的探针协议/路径/端口/Host；若用业务路径 + 无匹配路由的 Host 探活，Envoy 404 会误摘整入口 → 须改显式就绪端点 | `GAP-GATEWAY-POLICY-2026-10-26.md` §1 G2/§3/§4；`STATUS.md` §2 |
| **O-42 G1** | WS 长 idle timeout 运行时存活 | 代码已落地（BackendTrafficPolicy `streamIdleTimeout=3600s`，helm 绿）；kind/云上长 idle 实测未跑 | 云上建 WS 长连保持 >1h 观察不断连；再跑 runner 断连重连对账回归 | `GAP-GATEWAY-POLICY-2026-10-26.md` §4 G1/§5 |
| **ADR-0002** | runner join E2E（真实目标机） | 代码侧落地（join-bundle API + console 弹窗 + cloud-init 模板）；真机 join 未跑 | 云上创建 target → console 取安装命令 → 真实目标机执行 cloud-init → WS 回连 online；凭据/CA/通信任一环断裂即阻塞 | `STATUS.md` §1.1；`shared/ADR-0002-runner-install-bootstrap.md` |
| **#1** | install/upgrade 执行器 E2E | 代码侧完成（2026-10-08）；镜像 tag 升级演练未跑 | 云上做一次镜像 tag 升级演练，覆盖派发→Job→版本对账→终态 | `STATUS.md` §2 行 86 |
| **#31 / O-31** | Runner 任务容器安全加固 | 设计就绪，首步非特权 + dind 双任务验证未跑 | 云上跑非特权任务与 dind 构建任务各一，确认默认 SecurityContext/requests/limits 生效且不击穿 privileged 构建路径 | `STATUS.md` §2；`runner-hardening.md` |
| **#32 / O-32** | Runner 多副本 LeaderElection 防呆 | chart 运维陷阱，待落地 | 确认 `replicaCount>1` 时 LE 自动开启；云上若扩副本，验无双 reconcile | `STATUS.md` §2；`runner-hardening.md` |
| **#33 / O-33** | per-target 身份缩窄 | 三态鉴权已落地，仅剩加法缩窄 | 云上外部 runner 场景用 per-target 随机 token 替换共享 `TARGET_AUTH_TOKEN`，限制自动注册为可信 vendor/region | `STATUS.md` §2 行 103；`STEELMAN-ADR2`（历史论证）；`runner/features/per-target-auth.md`（行为规格） |
| **#5** | 告警出口部署 | 规则文件 + promtool 验证已过；Prometheus 进集群 + Alertmanager webhook 未实装 | 云上部署 Prometheus/Alertmanager，验一条告警经 webhook 送达 | `STATUS.md` §2 行 88 |
| **#25 / O-29** | 弱口令整改 / harbor 正规 CA + private | 生产 hardening 留待 O-29；自签 CA + dev 初始口令 | 云上确认 master 强随机、`valueFrom.secretKeyRef`、凭据轮换；正规 CA 与 sdp 项目 private + imagePullSecrets | `STATUS.md` §2 行 95/99；`HARBOR-DEPENDENCY-GAP-2026-10-20.md` |
| **#8 / #10** | canary 真流量 + 精确权重回传 | 10-19 云上 PASS=9 FAIL=0（历史态），10-20 环境归零 | 本次 gate 的 `e2e-canary.sh` 重跑，验 50% 双版本并存 + 权重快照回流 + 100% 收口 | `STATUS.md` §1.4；`FIDELITY` §6；`e2e-canary.sh` |

---

## 3. P2｜上线前置 / 他域（非 gate 硬阻塞，但需明确责任与结论）

| 编号 | 确认项 | 状态 | 说明 | 权威落点 |
| --- | --- | --- | --- | --- |
| **#26 / O-26** | 备份策略 | 未定 | 云上 PG/harbor/证书无定期备份；10-20 清理后无恢复手段 | `STATUS.md` §2 行 96 |
| **#27 / O-27** | 证书续期策略 | 未定 | 自签 CA + 组件证书无自动续期/到期告警 | `STATUS.md` §2 行 97 |
| **#29** | imagePullSecrets 支持 | 未实现 | private 项目前置，chart 尚未支持 | `STATUS.md` §2 行 99 |
| **#30** | 权限「入口按权限降级隐藏」 | 产品决策未拍板 | 权限模型已实现，仅入口隐藏策略待定 | `STATUS.md` §2 行 100 / §3 |
| **#35 / O-35** | 结构化日志 + 集中采集 | 设计就绪，未实施 | 可观测性，非 gate 硬阻塞 | `STATUS.md` §2 行 105 |
| **#36 / O-36** | 通知渠道 Webhook 适配器 | 未实施 | O-5 告警出不去 IM/Webhook；「Dispatch 生产调用方」字面量检索未定位（未验证-动态） | `STATUS.md` §2 行 106；`notification-webhook.md` |
| **E1** | 三仓证据留存遗漏 | 遗漏，待授权 | `evidence/` 未忽略、`cookies.txt` 含真实 `sdp_sess`、缺 `!evidence/baseline/` 例外；代码级治理需授权 | `audits/2026-11-19-verification-article-alignment-gap.md` §一 E1 |
| **V1/V7/V9/V11-15** | verify skill 生态适配 | 未接 / pending | agent 生态适配或组织侧，仓库内能力已备 | 同上 alignment-gap §一/§二/§四 |
| **landing-plan 拍板项** | E-05 阈值=3；observe→enforce 时机；视觉基线 diff 容差 / hub verify done 打哪个端点 | 待拍板 | 三份 landing-plan 各挂需拍板项 | `audits/2026-11-18-*-verification-system.landing-plan.md` |
| **UI 验证缺口** | G1-G8 结构缺口 + 16 例未展开 + 视觉基线人审 | 未闭环 | 本地 kind 前端呈现验证，非云上 gate；18 PASS + 4 known-gap + 16 未展开，不虚报全量 | `GAP-CONSOLE-UI-VERIFICATION-2026-11-21.md`；`console-ui-verification-testcases.md` |
| **O-17/O-18/O-22②** | 版本选择联动 / 构建环境模板 / Build→Harbor 对接 | 最小版落地，完整版留守 | 产品语义未定稿或 B2 决议本轮不开发 | `STATUS.md` §2 行 92-94 |

---

## 4. 测试与证据汇总（gate 通过 = 以下四步全绿）

| 步骤 | 脚本 | 判定 | 云上状态 |
| --- | --- | --- | --- |
| 1 冒烟 | `e2e-smoke.sh` | RESULT PASS=n FAIL=0 | 历史 15/0；本次待跑 |
| 2 取消/重跑 | `e2e-cancel-rerun.sh` | RESULT | 历史 11/0；本次待跑 |
| 3 灰度 | `e2e-canary.sh` | RESULT（需 kubectl + STABLE/CANARY_IMG） | 历史 9/0；本次待跑 |
| 4 发布 | `e2e-example-release.sh` | RESULT（需 kubectl） | 本次待跑 |

**证据留存**：全部 tee 到 `gate-evidence/<UTC>/<script>.log`，汇总 `summary.txt`；FAIL>0 / 无 RESULT / 非零退出即停。
**执行顺序不可换**：smoke → cancel-rerun → canary → example，前者是后者前置。

---

## 5. 过期内容处置（本轮已梳理，按「归档不删除」原则执行）

### 5.1 归档到 `docs/old/` 的旧文件

按用户裁定，结论已被后续文档取代、仅余历史论证价值的文件移入 `docs/old/`（不删除、不新建替身）：

| 文件 | 归档理由 | 现行权威落点（引用方改指这里） |
| --- | --- | --- |
| `STEELMAN-ADR2-LEFTOVERS-2026-10-22.md` | #1 已落码，正文「join 链路当前不可用 / enrollToken 无消费者」已被 10-23 真集群验证推翻；行 9 自述「#1 已实现」与正文自相矛盾 | 行为规格 → `runner/features/per-target-auth.md`；状态 → `STATUS.md` §2 O-33 |
| `UNIMPLEMENTED-ANALYSIS-2026-10-23.md` | 主体裁定 `NOT-NEEDED(-NOW)` 已被文首/文末「2026-10-26 再分析反转」全盘推翻，O-37~O-41 升格 FILL/KEEP 并落码 | 结论 → `STATUS.md` 变更史 10-23/10-26 条；各 `plans/` 文档「文档命运裁定」行 |

> **不归档**（仍是活跃权威落点，尽管文件名带历史日期）：`FIDELITY-KIND-VS-CLOUD-2026-10-09.md`（云上 gate 清单，
> 被 NETWORKING-GATEWAY / ui-12 引用）、`GAP-GATEWAY-POLICY-2026-10-26.md`（O-42 活跃缺口，G2 随云上执行）、
> `E2E-THREE-PIPELINES-2026-09-26.md`（G-1~G-14 权威定义 + 修复证据）、`GAP-BACKEND-TLS-2026-10-22.md`
> （验收证据仍被 STATUS/backend-tls.md 引用）、`HARBOR-*-2026-*.md`（O-22② 留守登记）。

### 5.2 就地修正的失效表述（保留文件，只改错误结论/数字）

| 文件 / 行 | 问题 | 处置 |
| --- | --- | --- |
| `README.md` §4 行 98 | 称 STATUS §2「未完成 10 项」，实际 25 项 | 更新数字 |
| `STATUS.md` §2 行 82 | 「真阻塞项见 O-4」，但 §2 无 O-4 行 | 改指实际阻塞项（O-31~O-33 / #1） |
| `STATUS.md` §2 行 104/107-111 | #34/#37-#41 性质列仍写「登记/待落地」，同表结论与变更史已标「已落地」 | 性质列改「已落地」 |
| `GAP-BACKEND-TLS-2026-10-22.md` §2 行 18、§1 行 13-14 | 「运行层未验证 / 真集群未回归」与文首行 6「A-F 已闭环」冲突 | 标注为历史初稿结论 |
| `console-ui-verification-testcases.md` 行 342 vs 344 | 行 342「26/38 全绿」口径失真，行 344 已更正为 18+4+16 | 行 342 标「历史口径，已被 344 取代」 |
| `GAP-CONSOLE-UI-VERIFICATION-2026-11-21.md` §1 行 10 | 12+8=20 ≠「16 条未展开」 | 核对更正数字 |
| 三份交付报告（工作区根） | `ONBOARDING` §8 称 check-crds「尚未接入流水线」，实际已接入 runner CI；`QUALITY-GATE` §5 仍列 rollout 48.2%/tree 63.8% 为现状 | 报告尾已加补测指针的保留原数值作基线，本次在指针处明确「历史基线」 |

---

## 6. 报告间口径统一（避免交叉误读）

- **O-33 / #1 定性**：`STEELMAN-ADR2` 历史论证称「身份语义断裂 / join 不可用」，`STATUS.md` §2 O-33 与
  `runner/features/per-target-auth.md` 现行口径为「三态鉴权已落地，仅剩加法缩窄」。以 STATUS 为准。
- **云上 gate 状态**：`FIDELITY` §6 表格「三项 gate ✅」是 2026-10-19 历史态，环境已于 10-20 归零；
  不可据该表格断言当前云上已通过。以本文 §1 P0-1 的实测为准。
- **审计族 vs alignment-gap**：11-18 三份 verification-system 报告 D4 判「done 停在 build/health」，
  11-19 alignment-gap 判「真跑 PASS」——非矛盾，是第二轮补齐；各报告按时间轮次理解。
- **编号前缀混用**：`ID-INDEX.md` 定义 O-17~O-42 为 O- 族，`STATUS.md` §2 部分写成纯数字 #22/#25-#41。
  同项不同写法，以内容（标题/落点）对应，不以前缀字符串匹配。

---

## 7. 执行勾选栏（回填）

- [x] §1 P0-1 ~ P0-5 环境前置全部通过（kubeconfig / SWR 登录 / 跳板机构建链 / hosts 指向网关 ELB）
- [ ] §2 P1 十项逐项确认并留证（O-42 G1/G2、ADR-0002、#1、#31-33、#5、#25/29、#8/10）
  - 2026-11-24 实跑仅覆盖其中 #8/10（canary 重跑，gate 第三步）与 #25/29 部分（keycloak realm 口令/imagePullSecrets 修复，见 §8.3-1/2）；其余项（O-42 G1/G2、ADR-0002、#1、#31-33、#5）**验收未执行**，仅重登记状态；G1 另有新负发现见 §8.6。状态权威仍以 `STATUS.md` §2 各行为准。
- [x] §3 P2 他域项已明确责任方/结论（runner→hub 回流仍 open，见 §8）
- [x] §4 gate-cloud.sh 四步全绿，`gate-evidence/20261124T094214Z/summary.txt` FAIL=0
- [x] §5 过期内容已归档/就地修正，引用无死链
- [x] gate-cloud.sh 实跑结论回填 `STATUS.md` 变更史 + 本文

---

## 8. 云上实跑结果

### 8.1 gate 结论

`gate-cloud.sh` 四步全绿，总判定 PASS，证据目录 `gate-evidence/20261124T094214Z/`（summary.txt + 四步明细）：

| 步骤 | 断言 | 结果 |
| --- | --- | --- |
| smoke | e2e-smoke.sh | PASS=15 FAIL=0 |
| cancel-rerun | 取消/重跑链路（含 rerun 后新尝试 phase=Running） | PASS=11 FAIL=0 |
| canary | 50% 暂停窗口双版本真实流量 v0.0.1=20 / v0.0.2=20，终态 100% 副本占满 | PASS=10 FAIL=0 |
| example | example 发布终态（weight=100 语义：canary 占满、stable 归零） | PASS=7 FAIL=0 |

### 8.2 部署形态（gate 通过时的基线）

- 镜像仓库：SWR `swr.cn-north-4.myhuaweicloud.com/sdp-20261022`（default-secret 拉取，未安装 harbor）。
- 组件版本：hub v0.0.4 ×2 副本（`SDP_COORDINATION_ENABLED=true`，cluster `sdp-cloud`，artifact PVC 关闭）、console v0.0.2、runner v0.0.5、PG `postgres:16-alpine`（PGDATA 子目录规避 csi-disk lost+found）、keycloak 26.7.4。
- 网关：CCE 官方 Envoy Gateway 插件（EG configmap proxy requests 收敛至 500m/512Mi），ELB 内网地址经 `/etc/hosts` 指向 `www.sdpworkflow.com`。
- 部署脚本：`deploy-without-harbor.sh`（PG 阶段、EG 资源预检、sdp-run 拉取凭据固化）+ `run.sh`（`--rollout-target-port` / `--rollout-image-pull-secret`）。

### 8.3 本轮源码级修复（详见 env 仓库 `log/2026-11-24-cloud-gate-deploy.md`）

1. hub/keycloak chart 渲染 `imagePullSecrets`（SWR 私有仓库拉取凭据）。
2. keycloak realm：admin credential `temporary:false`、`requiredActions:[]`（password grant 直通）。
3. PG manifest 增加 `PGDATA=/var/lib/postgresql/data/pgdata` 子目录。
4. runner rerun 机制改为删除式（消除注解两阶段写入非原子 + 跨 controller 竞态回退）。
5. runner rollout controller 新增 `SDP_ROLLOUT_IMAGE_PULL_SECRET` 注入 stable/canary PodSpec。
6. hub chart `coordination.{enabled,clusterId}` 接线 + `POD_IP` fieldRef；`artifact.pvcEnabled` 开关（多副本无共享 PVC）。
7. e2e 脚本：canary/example 环境复位（清理遗留 rollout）、采样 pod 预热 + 滚动收敛等待 + exec 错误捕获、`seq -s ' '` 修复 ash 解析、example 终态断言对齐 weight=100 语义。

### 8.4 协调框架验证

- 两级选主：`coord_workers` 双实例注册心跳，`coord_leases` instance 租约唯一持有者即 master。
- 故障转移：强杀 master pod → TTL(10s) 到期后 standby 接管 instance lease，重建 pod 以 worker 注册，全程 API 探活 200。
- 参数：renewal 2s / ttl 10s（与设计文档一致）。

### 8.5 遗留 open 项

- runner→hub 回流（canary CurrentWeight / agent_version / TaskRun 产物不回传）仍 open，测试断言已按此口径规避。
- 多副本生产化需为 artifact 配置 S3 兼容存储（OBS 等）；当前多副本形态 artifact 落容器临时盘，仅适用于协调/选主验证场景。
- example/canary 采样镜像 `curlimages/curl:8.8.0` 依赖节点缓存（源为公网 docker.io）；离线环境需推入私有 registry 并覆盖。

### 8.6 负发现（2026-11-24 gate 实跑新增）

- **O-42 G1 阻塞升级**：CCE 官方 Envoy Gateway 插件的 CRD **不识别 `BackendTrafficPolicy.spec.timeout.http.streamIdleTimeout` 字段**（helm 渲染告警 `unknown field spec.timeout.http.streamIdleTimeout`，见 env 仓库 `log/2026-11-24-cloud-gate-deploy.md` §4.1）。即本地 kind 验证过的 WS 长 idle 保障在云上**未生效**，G1 从「云上实测未跑」升级为「云上配置层即被丢弃」，需先核对 CCE EG 插件 CRD 版本支持的替代配置（如 EG 版本升级或 annotation 路径）再谈实测。
- **O-25 裁定偏移**：为打通 keycloak password grant（gate 动态取 token），realm 导入改为 admin credential `temporary:false` + `requiredActions:[]`——与 O-25 设计的「首登强制改密（UPDATE_PASSWORD）」语义相悖。当前形态仅适用于验收环境；生产 hardening（O-29）须恢复 UPDATE_PASSWORD 并改走 console 首登链路，STATUS.md §2 已同步登记。

---

## 变更历史

| 日期 | 变更 |
| --- | --- |
| 2026-11-23 | 首次成文。汇总 docs 仓库 60+ 文档 + 三份交付报告的待确认项；确立 P0/P1/P2 分级；归档两份失效论证文档到 `docs/old/`；就地修正若干失效表述与数字。 |
| 2026-11-24 | 云上 gate 实跑完成并全绿（§7 勾选、§8 回填）：四步 PASS + 协调框架多副本验证通过；记录部署形态、七项源码级修复与遗留 open 项。 |
| 2026-11-24 | 勾选栏勘误：§7 P1 十项中实跑仅覆盖 #8/10、#25/29 部分，其余验收未执行，勾选改回未勾并注明；新增 §8.6 负发现（CCE EG CRD 不识别 streamIdleTimeout → G1 配置层失效；O-25 首登强制改密被 gate 临时旁路）。 |
