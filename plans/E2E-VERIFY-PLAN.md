# E2E-VERIFY-PLAN — 端到端联调验证计划

> 状态：计划（未执行） · 创建：2026-09-06 · 前置：各组件 Backlog（见 [console 设计文档 附 B](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI设计文档.md)）G1–G6 已关闭
>
> 成功定义（已锚定）：**通过界面流水线（构建、发布、测试）把软件在真实环境中成功运行**。
> 门禁全绿只是工程完成度；本计划负责补上从未验证过的"运行侧"。

---

## 0. 成功标识（L2 验收清单）

| # | 标识 | 验证阶段 |
|---|---|---|
| L2-1 | ✅ runner 连上 hub，gateway 握手 + 心跳正常（2026-09-06，`gateway: cluster local-dev connected`，cluster status=online） | P0 |
| L2-2 | 一条 **Build** 任务真跑通（`go build`/`go test`），Job 退出码正确回传 | P1 |
| L2-3 | 一条 **Release** 任务真发布（chart 拉取 + values 注入生效） | P3 |
| L2-4 | 金丝雀实测：晋升推进、**回滚真的把流量拉回 0%** | P4 |
| L2-5 | **Approval** 任务：暂停 → 界面审批 → 恢复闭环 | P4 |
| L2-6 | 人为制造一次失败，**只靠 console 日志面板**定位根因 | P1 |
| L2-7 | 制品上传/下载真实走通（G5 upload-url） | P2 |
| L2-8 | R1–R3 由"推测缺口"变成"实测结论"，回写各组件设计文档 | P5 |

---

## 1. 环境方案（单机 docker K8s）

**选型：kind（Kubernetes in Docker）**。理由：复用本机 docker、支持把本地镜像 load 进集群、端口映射直观；有现成集群，但首轮优先单机验证。

### 1.1 部署拓扑（hub 也进集群，推荐）

```
宿主机 mac
├─ docker
│  ├─ kind 节点（单节点集群）
│  │  ├─ ns: sdp-system
│  │  │  ├─ hub (Deployment + Service NodePort)
│  │  │  ├─ postgres:16 (hub 的 DB, hub 仅支持 postgres)
│  │  │  ├─ runner (Deployment, CRD 已 apply)
│  │  │  └─ (P2 后) demo-app 的 Deployment/Service/Rollout
│  │  └─ registry:2 (本地镜像仓库, :5000, kind containerd 回环)
│  └─ (可选) postgres 备选：跑宿主侧容器
└─ console: vite dev server (宿主机, proxy → hub NodePort)
```

**hub 进集群的理由**：runner 的 releaseContainer 要拉 chart tgz——G5 的 `ARTIFACT_STORE_DRIVER=local` 签名 URL 指向 hub Service（集群内 DNS 可达），制品/chart 链路天然打通；同时提前验证生产部署形态。

### 1.2 关键配置

| 组件 | 配置要点 |
|---|---|
| hub | `DATABASE_DSN=postgres://...postgres.svc:5432/sdp`；`ARTIFACT_STORE_DRIVER=local`，`ARTIFACT_STORE_LOCAL_ROOT=/data/artifacts`（挂 PVC/hostPath）；`ARTIFACT_STORE_PUBLIC_URL=http://hub.sdp-system.svc:8080`（使签名 URL 集群内可达）；`GATEWAY_TOKEN=<共享密钥>` |
| runner | env 指向 `ws://hub.sdp-system.svc:8080<gateway path>`，同一 `GATEWAY_TOKEN`；RBAC 允许管理 Job / TaskRun / Rollout |
| console | `.env.development` proxy target 改为 `http://localhost:<hub NodePort>`；`VITE_AUTH_DISABLED=true` 保持 |
| kind registry | 本地 `registry:2` + kind 集群 containerd 配置回环（`localhost:5000` 直接可拉），Build 产镜像 push 后集群即用 |

### 1.3 镜像供给（R3 定案）

| 镜像 | 定值 | 说明 |
|---|---|---|
| Build 任务基础镜像 | `golang:1.22-alpine`（或按需 `node:20-alpine`） | 公共源可拉，单机无需私有 registry |
| releaseContainer | `alpine/helm:3.14.4`（现状保持） | 内含 helm，能执行 upgrade --install / kubectl |
| 业务镜像 | `localhost:5000/demo-app:<ver>` | Build 产物镜像 push 本地 registry |

---

## 2. 构建资产（复刻 old/ 模式）

### 2.1 镜像构建脚本（仿 `old/go-devops/go-devops/build/go-devops/build.sh`）

在新平台建 `build/` 目录，复刻 old 五步模式：

1. 交叉编译：`GOOS=linux GOARCH=amd64 go build -ldflags "-X ...version=..."`（ldflags 版本注入照搬 old 的 versions 包模式）
2. 打包：二进制 + conf → `<name>.tar.gz`
3. 镜像：`FROM ubuntu:22.04` + `ADD <name>.tar.gz /source/`（old 用 18.04，升级到 22.04）
4. `docker build` → `docker push localhost:5000/<name>:<ver>`（old 是 `docker save` 离线 tar；单机 registry 场景改为 push；save/load 保留为离线兜底）
5. chart 打包：`tar -zcvf <name>-<ver>.tgz <name>/`

### 2.2 demo chart（仿 old charts 结构）

以 `old/go-devops/go-devops/build/go-devops/charts/go-devops/` 为蓝本做轻量化 `demo-app` chart：

- 保留：`Chart.yaml`（apiVersion v2 / name / version）、`templates/deployment.yaml`（values 驱动 image/replicaCount/resources/probe）、`templates/service.yaml`
- **简化掉**：mysql/redis/oauth secrets、certs hostPath、HTTPS 探针（old 的 go-devops 依赖太重，首轮不用它当被发布物；go-devops 完整版留作二期挑战）
- values 保留 old 的分节风格：`basic(component/replicaCount/update_versions)` / `service(ports)` / `image(imageAddr/pullPolicy)` / `resources`
- values 注入验证点：界面 Trigger 时传 `params: replicaCount=2` → Release 映射为 `--set basic.replicaCount=2` → 集群中副本数真变 2（R2 的 e2e 证据）

### 2.3 被发布软件

- 首选：`demo-app`——一个极简 Go HTTP 服务（`/healthz` 返回版本号），用于验证链路
- 二期：`go-devops`（old 完整版，带真实探针/配置），验证复杂 values + secrets 场景
- **终极目标：平台自己（hub / runner / console）**——见 P6 自举；old 的 go-devops / go-devops-ui 正是它们的前身，构建模式天然同源

---

## 3. 阶段计划

### P0 环境就绪（对应 L2-1）✅ 已完成（2026-09-06）

1. ✅ kind 集群 `sdp-dev`（v1.33.1）+ registry + postgres 起动
2. ✅ runner CRD apply + runner Deployment 部署
3. ✅ hub 容器化部署（AutoMigrate 建表）+ NodePort 30080（主机 8080 直通）
4. ✅ console 无需改动（vite proxy 目标 http://localhost:8080 与 kind 端口映射吻合）
5. ✅ gateway 握手：`gateway: cluster local-dev connected`，集群 status=online

**P0 实测抓到并修复的问题**（全部是 build/test 门禁抓不到的运行期问题）：
- 🔴 **gin 路由 panic（真 bug）**：父级作用域路由用 `:serviceId/:componentId/:pipelineId/:treeId` 与 `RegisterCRUD` 生成的 `:id` 在同位置冲突——hub 从未真正启动过所以一直没暴露。已统一改为 `:id`（10 个文件，含 main.go 的 `wrap` 权限参数名）
- 节点代理污染：kind 节点继承 Docker Desktop `HTTP_PROXY`（节点内不可达）→ 集群创建后清代理环境 + 重启 containerd；`NO_PROXY` 未含 `kind-registry`
- 节点拉不到 docker.io → postgres 镜像也推本地 registry
- hub go.mod `replace ../runner` → hub 镜像用 workspace 根上下文构建（根 `.dockerignore` 收窄）
- dev 镜像同 tag 覆盖 → `imagePullPolicy: Always`
- `POSTGRES_HOST_AUTH_METHOD=trust`（dev-only）修复 pg_hba 拒连
- 集群需先在 hub 注册（`POST /clusters` 种子数据）runner 才能握手

全部固化在 `hub/deploy/p0-up.sh`（幂等可重跑）。

### P1 Build 链路（L2-2 + L2-6）

1. 界面建组件 → 配参数 → 编排流水线：Stage1 `Build`（command=`go build ./...`，image=`golang:1.22-alpine`）+ Stage2 `Build`（command=`go test ./...`）
2. 界面触发 → runner 收 `apply_pipeline_run` → Job 起跑
3. **通过标准**：Job 退出码 0 → TaskRun Succeeded；console 运行监控 DAG 变绿；日志面板看到**真实编译/测试输出**（G2 落库链路真验证）
4. **失败演练**：故意改坏命令（`go buil`）→ 触发 → Job Failed → 只靠日志面板定位到 typo（L2-6 达成）

### P2 制品 + 镜像链路（L2-7）

1. Build 产物（二进制）经 `POST /artifacts/upload-url` 签名 PUT 上传制品库
2. console 制品页下载回来、校验内容一致
3. 构建业务镜像 → push `localhost:5000/demo-app:<ver>` → 集群内 `crictl pull` 验证可拉
4. **通过标准**：制品往返无损；镜像集群可见

### P3 Release 链路（L2-3 + R2 e2e）

1. demo-app chart 打 tgz → 制品上传 → 拿到制品 URL
2. 界面编排 `Release` 任务：ChartURL=制品 URL，values 参数注入 `replicaCount=2`
3. 触发 → runner `releaseContainer` 执行 `helm upgrade --install`（ChartURL 直拉 tgz，无需 chart 仓库——**R1 就此绕过**，真实 chart 仓库出现时再补鉴权）
4. **通过标准**：集群中 demo-app Deployment Ready、副本数=注入值（R2 e2e 证据）；TaskRun Succeeded；console 发布页可见

### P4 控制面（L2-4 + L2-5）

1. Release 任务带 `RolloutSpec`（金丝雀 10/50/100）→ 观察 Rollout CR 步进
2. 界面 **暂停** → 权重停在当前步；**晋升** → 推进到下一步；**回滚** → 流量回 0%、Phase→Degraded
3. 编排 `Approval` 任务 → 运行中暂停 → 界面提交审批 → 恢复推进
4. **通过标准**：三个控制动作在集群侧真实生效（`kubectl get rollout` 权重可见），不只是 UI 状态变化

### P5 全链路验收（L2-8）

1. 一条完整流水线：`Build(go build) → Build(go test) → Approval → Release(chart+金丝雀)` 界面一次触发全自动跑通
2. 把 P0–P4 中暴露的问题回写：R1–R3 结论落各组件设计文档（[hub 数据模型](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)、[runner 实现 Story](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md)）（"实测通过/遗留 X"）
3. 真实集群复跑（现成 K8s）：镜像源从 localhost:5000 换为真实 registry（此时才需要你的 registry 地址），其余不变

---

### P6 自举：平台发布平台自己（二期）

> 背景：old/go-devops 是 hub 前身、old/go-devops-ui 是 console 前身——"我如何发布我自己"。
>
> **运营模式裁决（2026-09-06 钢人论证后）**：升级频率为每周或更频繁（活跃迭代期）→ 自升级**默认走平台流水线**（版本历史/参数管理/一键回滚在高频下收益最大，且三镜像三 chart 本就是 P5 真实集群部署的必需品，P6 边际成本≈0）；**手工 helm 保留为应急通道**（CRD 破坏性变更、平台被锁死时的 break-glass）。机制上无任何新东西——自升级就是一次普通发布。

**代际阶梯**（解决鸡生蛋，手工只允许出现在 Gen0）：

| 代际 | 方式 | 内容 |
|---|---|---|
| Gen0 | 手工（P0，唯一一次） | kubectl/helm 装 postgres + hub + runner |
| Gen1 | 平台发布（P3/P5） | demo-app |
| Gen2 | **平台发布自己（P6）** | hub / runner / console 三个镜像 + 三张 chart |

**P6 交付物**：
1. 三张镜像（复刻 old build.sh 模式）：hub（Go 二进制 + ubuntu 打包）、runner（Go 二进制）、console（静态文件多阶段构建 + nginx 托管）
2. 三张 chart（old 模板蓝本）：hub-chart（values 含 postgres DSN secret、GATEWAY_TOKEN、artifact PVC）、runner-chart（RBAC + CRD 存量不碰）、console-chart（反代指向 hub）
3. 界面编排 self-release 流水线：`Build(编译 hub/console/runner) → Approval → Release(helm upgrade)`

**升级机制（无新东西）**：chart tgz 经制品库进环境 + 镜像进 registry → Release 任务 ChartURL 指向 tgz → `helm upgrade --install` 原地升级。**这就是 P3/P4 已验证的同一条路径**，自举不需要新机制，差别只在被发布物是平台自己。

**排流水线时的四个注意**（是流水线编排约定，不是额外机制）：
1. `Build → Approval → Release`：加一个 Approval 任务当人工卡点——升级自己挂了没人救，人工确认不可省
2. hub / runner 分两个 Release 任务、按阶段顺序先 hub 后 runner：hub 升级时 runner 断连只重连不退出（存量任务照跑）；runner 自升级时，执行升级的 releaseContainer Job 独立于 runner Pod 存活，旧 runner 把 reconcile 跑完
3. 上一版 chart/镜像保持在制品库：helm 原生 rollback / P4 回滚随时可用
4. **CRD schema 分级处理**（不是一刀切禁止）：
   - **兼容变更**（新增可选字段、放宽校验、加枚举值）**可进自升级**——但必须是显式前置步骤（pre-upgrade hook Job 或独立的 kubectl apply 任务）。注意 Helm 3 的 `crds/` 目录是 install-only，`helm upgrade` **不会**更新它——靠 chart 直升 CRD 需要放 `templates/`（helm 会接管其生命周期，uninstall 连删，不推荐）或走 hook
   - **破坏性变更**（加 required、删字段、改类型、引新版本+conversion）走手工：先备份存量对象（`kubectl get -o yaml`）再 apply
   - 破坏性变更手工的三个硬理由：① CRD 变更是**集群级原子生效，无法灰度**——Deployment 能金丝雀，schema 不能；② helm rollback **不还原 CRD**（helm 不追踪 CRD 版本），"回滚是安全网"的前提对 schema 失效；③ runner 既是升级执行者又是被升级者——破坏性变更会让旧 runner 写出的对象过不了新校验，**锁死自升级通道本身**，唯一救生索就是手工 kubectl
   - 判断口诀：**改完后，旧版本 runner 创建的对象还能通过新 schema 校验吗？** 能→兼容可自动；不能→破坏必须手工

**通过标准**：hub/console/runner 的新版本经界面流水线发布并滚动替换 Gen0 手工装的实例，服务无中断；随后故意发布一个坏版本 → 回滚成功。此后**平台自身的所有升级都走平台**。

## 4. R1–R3 处置映射

| 缺口 | 处置 | 落点 |
|---|---|---|
| R3 镜像固化 | §1.3 定案：Build=golang:1.22-alpine、Release=alpine/helm:3.14.4、业务镜像=localhost:5000 | P0 |
| R1 chart 鉴权 | 本地无 chart 仓库 → ChartURL 指向 G5 制品 URL 绕过；鉴权推迟到真实仓库出现时 | P3 |
| R2 values 注入 | `--set` e2e：界面 params → 集群副本数变化 | P3 |

## 5. 已知风险 / 待确认

1. **hub 仅支持 postgres**（`db.go` 写死 `postgres.Open`）——单机环境必须带 postgres 容器；若想省依赖可后续加 sqlite driver（非本轮必须）
2. kind 拉本地 registry 需集群创建时配 containerd 回环 patch（计划内固定步骤）
3. G5 `local` 驱动在集群内需持久卷（hostPath/kind PV）；`ARTIFACT_STORE_PUBLIC_URL` 必须是集群内地址，否则 releaseContainer 拉不到签名 URL
4. runner wss 连 hub NodePort：GATEWAY_TOKEN 两端一致；NodePort 明文 ws 可接受（本机验证），真实集群再上 TLS
5. old go-devops 依赖 mysql/redis/certs——二期发布它之前需先在集群准备这些依赖（或进一步精简 chart）

## 6. 执行约定

- 每阶段结束更新本文件的阶段状态 + 发现的问题记录到各组件设计文档对应章节
- P0–P5 顺序执行，任何阶段失败先修复再前进；**不写平台功能代码，除非联调暴露真实缺陷**
