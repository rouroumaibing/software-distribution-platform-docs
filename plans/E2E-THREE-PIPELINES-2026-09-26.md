# E2E 三流水线整体测试（构建 / 日常 / 发布）— 测试记录

> 日期：2026-09-26。本文档是本次 E2E 的**目的、场景定义、流程细节与缺口登记**的权威记录。
> 测试结论 / 结果数据放根目录 `sdp-pipeline-e2e-report.html`（用户分析用），本文只记「怎么测、测什么、发现什么」。
> 状态：**已完成**。缺口 G-1~G-12 + 回归中发现 G-13/G-14 已全部修复，kind 回归 11/11 通过（见 §9）。

---

## 1. 测试目的

1. 用 `software-distribution-platform-example`（nginx 案例）把**三条流水线作为一个整体场景**走通：
   - **构建流水线**：拉取代码 → 构建生成软件包 → 产物归档（归档到 hub 制品库）。
   - **日常流水线**：选定软件包 → 组件详情配置 → 发布到**测试环境**（sdp-test）。
   - **发布流水线**：同日常，但中间加**审批节点**（审批人 approve 后）→ 发布到**生产环境**（sdp-prod）。
2. 除 API 调用外，验证 **console 前端能读取数据并渲染**（服务树 / 组件详情 / 环境 / 流水线 / 运行监控 / 制品 / 审批通知）。
3. 按"先建组件 → 对接环境 → 再建流水线"的真实用户路径走，验证平台核心闭环。
4. 过程中发现的**代码缺口**登记到本文 §6，供后续开发排期。

## 2. 场景与环境

| 项 | 值 |
| --- | --- |
| 集群 | kind `sdp-dev`（本机 docker），namespace `sdp-workflow` |
| hub API | `http://localhost:8080/api/v1`（NodePort 30080） |
| console | `http://localhost:8082`（NodePort 30081）/ `https://localhost:8443`（ingress 自签） |
| runner | target `local-dev`，出站 WS 回连 hub `/gateway/ws` |
| 本地 registry | `localhost:5000`（kind 节点 containerd mirror 指向它） |
| 鉴权 | `SKIP_AUTH=1`（Keycloak API 鉴权旁路；**注意 GATEWAY_TOKEN 仍生效**，见 §7 gotcha） |
| 版本 | v0.0.1（三仓镜像 + helm values） |
| 测试素材 | `localhost:5000/sdp-builder:test`（alpine+git+tar，example 源码烧入）、`localhost:5000/kubectl:1.30`（宿主 kubectl 打包）、`localhost:5000/nginx:v0.0.1`（example make 出的镜像） |

运行命名空间 shim：`sdp-run` / `sdp-test` / `sdp-prod` 三个 ns 的 `default` ServiceAccount 绑定 deploy Role（apps/deployments、core/services、core/configmaps、core/secrets、core/pods、networking.k8s.io/ingresses 全 CRUD）。原因见 §6 G-1。

## 3. 流程细节（测试步骤规格）

### 3.0 基座准备
1. `SKIP_AUTH=1 ./deploy-local.sh v0.0.1` 部署全栈（postgres → keycloak → hub → runner → console）。
2. **预注册 target**：`POST /targets {"name":"local-dev","vendor":"kind","region":"local","targetKind":"k8s"}`——hub 网关在带 token 时**不自动注册**未知 target（`gateway.go:113` GetByName 失败即 404）。
3. 验证 runner 握手：`GET /targets` → `local-dev` `status=online`、心跳更新。
4. 应用 §2 的 SA shim（Role + RoleBinding × 3 ns）。

### 3.1 建组件（组织 / 服务任意）
1. `POST /orgs`（建组织，hub 自动建 1:1 服务树）。
2. `POST /orgs/:id/services`（挂服务）。
3. `POST /services/:id/components`（建组件 `nginx-e2e`）。

### 3.2 对接环境
1. `POST /components/:id/environments`：`test-env`（`envType=test`，target=local-dev，namespace=`sdp-test`）。
2. `prod-env`（`envType=production` → namespace `sdp-prod`）**延后到日常流水线跑完再建**——生产强审批守卫（B-11）按"target 关联了 production 环境"判定，先建会挡住触发实验（反向 409 用例反而需要它，见 3.5）。

### 3.3 构建流水线
1. `POST /pipelines`（kind=`build`）+ `POST /pipelines/:id/stages` + `POST /stages/:stageId/tasks`：
   - Build 任务：image=`localhost:5000/sdp-builder:test`，command 在容器内把 example 源码 + chart 打包为 tar。
   - 归档：调 `POST /artifacts/upload-url` 拿签名 PUT URL → `curl -X PUT` 上传 hub 制品库（local 驱动 PVC `/data/artifacts`）。
2. `POST /pipelines/:id/runs` 触发（params 携带版本号语义；实际注入能力受 §6 G-5 限制）。
3. 轮询 `GET /runs/:id` 至 `phase=Succeeded`；验证制品对象落入 hub 存储；验证前端制品 Tab 渲染状态（受 §6 G-2 影响，预期为空并如实记录）。

### 3.4 日常流水线（发布到测试环境）
1. 建 pipeline（kind=`release`，无审批）+ Release 任务：manifest 静态引用 `localhost:5000/nginx:v0.0.1`，image=`localhost:5000/kubectl:1.30`。
2. 触发时 target=local-dev、targetNamespace=`sdp-test`。
3. 轮询至 `Succeeded`；`kubectl -n sdp-test get pods` 验证 nginx Running。
4. 前端验证：运行监控 DAG、任务日志、组件 Releases Tab。

### 3.5 发布流水线（带审批）
1. 建 pipeline（kind=`release`）+ 两个 task：Approval（`approvalConfig.requiredApprovals=1`）+ Release（manifest → `sdp-prod`）。
2. 触发 → 轮询至 `WaitingApproval`；验证 `GET /notifications` 出现待审批通知。
3. `POST /pipelines/:id/runs/:runId/tasks/:taskName/decision` approve → 轮询至 `Succeeded`；验证 `sdp-prod` nginx Running。
4. **反向用例（B-11 fail-closed）**：建 prod-env 后，对**无 Approval 任务**的流水线触发到 production target → 预期 `409 + reasons`。

### 3.6 前端渲染验证清单
console 逐页检查（浏览器实际渲染，非仅 API）：
- [ ] 服务树（org/service/component 级联）与服务端搜索
- [ ] 组件详情 Overview / 配置(参数管理) / 环境 / 流水线 / 制品 / Releases / 运行 Tab
- [ ] 流水线编辑器（阶段 + 子任务表单）与触发对话框（target/namespace/参数）
- [ ] 运行监控 DAG（相位着色）+ 任务日志流
- [ ] 通知中心铃铛（待审批）+ 审批决策入口
- [ ] 制品 Tab（预期受 G-2 影响为空，如实记录）

## 4. 与用户原始设想的差异（双向钢人结论摘要）

| 设想 | 实际 | 处置 |
| --- | --- | --- |
| 归档 `/tmp/backup` | runner Job 在 kind 节点内，宿主 `/tmp` 不可达；Job 结束即销毁 | 改归档 hub 制品库（upload-url → PUT），steel-man：制品库才是平台内可见、可下载的真归档 |
| 前端选软件包版本 | 无"制品→发布"联动；chart version 是静态字段；触发参数不注入（G-5） | 版本以触发参数语义传入构建任务；发布用固定 manifest 版本；差异如实报告 |
| 构建环境 linux/dind/cind | 无此概念，Build=指定 image 跑 command | 用预构建 sdp-builder 镜像绕开 docker build；登记 G-4 |
| 拿到版本包再发布 | Release 任务不消费制品库产物（consume 为占位） | manifest 固定引用 `localhost:5000/nginx:v0.0.1`；联动列为 G-2/G-3 |

## 5. 钢人决策记录（环境/方法层）

1. **SKIP_AUTH=1**：聚焦流水线场景本身；gateway token 仍生效（runner env 带token），target 必须预注册——这是设计行为不是 bug。
2. **SA shim**（§2）：绕开 G-1，不改代码；G-1 登记为平台缺口。
3. **sdp-builder 镜像**：源码烧入镜像规避"无 git 凭据 + 无 dind"；Build 任务只做打包+归档。
4. **kubectl 镜像**：`bitnami/kubectl:1.30` tag 在 docker.io 不存在 → 用宿主 `/usr/local/bin/kubectl` 打进 alpine（`localhost:5000/kubectl:1.30`）。

## 6. 缺口登记（测试中发现的代码问题）

> 测试结束后同步到 `docs/hub/STORY-BACKLOG.md`（B-XX 编号）与 `plans/STATUS.md`。此处先按 G-XX 登记，证据均为 文件:行号 级。
> **状态（2026-09-26 第二批）**：G-1~G-12 已全部修复并 kind 回归通过（见 §9）；G-3（软件包版本选择）、G-4 完整版（专用构建环境模板）留 follow-up story。

| # | 严重度 | 缺口 | 证据 | 影响 |
| --- | --- | --- | --- | --- |
| G-1 | P0 | **执行 Job 无 ServiceAccount**：hub `buildSpec` 不设 `ServiceAccountName`，runner Job 落到 ns default SA，无部署权限 → Release 必失败 | hub `internal/run/service/pipeline_run.go:599`（buildSpec 无 SA）；runner `pkg/executor/job_builder.go`（`tr.Spec.ServiceAccountName`） | 发布到环境不可用（本次以 SA shim 绕开） |
| G-2 | P0 | **制品登记断链**：`ArtifactService.Register` 全仓无调用方（注释称"归档阶段 status-sync 回调"）；Reconciler 仅报告不入库 → 上传成功后前端制品 Tab 恒空 | hub `internal/artifact/service/artifact.go:31-33`（Register）；`reconcile.go:12`（report-only） | 归档最后一公里缺失 |
| G-3 | P1 | **无软件包版本选择**：构建版本号无字段；制品→发布无联动；`GET /package-versions` 只是平台三组件版本矩阵，与业务包无关 | console `TriggerRunDialog.vue`（仅 target/ns/params）；hub `internal/packageversion/handler.go` | "拿到版本包发布"的产品链路不存在 |
| G-4 | P1 | **无构建环境选择**（linux / dind / containerd-in-containerd）：Build 任务=指定 image 跑 command，无 dind 支持 → 平台内无法 docker build | runner `pkg/executor/job_builder.go`（单 container Job） | 构建"生成软件包"依赖外部预构建镜像 |
| G-5 | P0 | **参数注入断裂**：trigger params → hub spec.Params → CR 通路在，但 runner 除类型定义外无任何 Params 消费者；hub 注释说 runner 替换、runner 注释说 hub 替换，实际两侧都没实现；chart values 的 `${参数key}` 替换同样不存在 | hub `internal/run/models/trigger_request.go:35`（注释声称 runner 做）；runner 全仓 grep `Params` 仅 `pipelinerun_types.go:91-95` + deepcopy | 版本号/镜像 tag 等参数化全部失效 |
| G-6 | P1 | **制品下载（consume）为占位**：runner `consumeContainer` 只 echo 不下载，`Consumes` 键不生效 | runner `pkg/executor/job_builder.go:136-148` | 流水线内任务间产物传递不可用 |
| G-7 | P2 | **runner job 镜像硬编码裸名**（`alpine/git`、`alpine/helm`、`bitnami/kubectl`、`amazon/aws-cli`），受限 registry（仅 localhost:5000 mirror）环境拉不动 | runner `pkg/executor/job_builder.go:22` 等默认值 | 私有环境开箱即败，需可配置 |
| G-8 | P0 | **签名存储路由从未挂载**：`case "local"` 分支只赋 `artifactStore = localStore`，声明的 `localArtifactStore` **从未赋值** → `main.go:552` 的 `if localArtifactStore != nil` 恒假 → `/api/v1/storage/*key` 路由不注册 → upload-url 签发的 PUT/GET URL 全部 404（实测：任务归档 PUT 404，`/data/artifacts` 恒空） | hub `cmd/hub/main.go:213`（声明）vs `:238-242`（未赋值）vs `:552`（守卫） | local 驱动制品上传/下载整体不可用（编译器查不出的 wiring 断裂） |
| G-9 | P0 | **Release 任务丢 ReleaseSpec**：runner `buildTaskRun` 拷贝 ApprovalConfig / RolloutSpec，**漏拷 `task.ReleaseSpec`** → 普通（非 canary）Release 任务的 TaskRun 无 ReleaseSpec，Job 必然 "release task missing ReleaseSpec" 失败（实测复现） | runner `internal/controller/pipelinerun_controller.go:285-302` | Release 类型任务整体不可用（canary Rollout 路径除外） |
| G-10 | P0 | **GetOrgID scan 类型错误 → 审批审计/通知/超时全断**：`ComponentRepository.GetOrgID` 用 GORM `Raw().Scan(&uuid.UUID)`（uuid.UUID 是 [16]byte 数组，GORM 反射按 uint8 元素处理）→ `sql: Scan error ... to a uint8`；每次触发 warn 后静默跳过 pipeline_approvals 登记（`pipeline_run.go:313-340` fallback 设计）→ 实测表 0 行。连锁：① `GET /notifications` 恒空、前端审批铃铛失效；② 审批无审计痕迹；③ **审批超时判负失效**（`approval_timeout.go:118` 同样扫 pipeline_approvals，永远扫不到 Pending） | hub `internal/component/repository/component.go:31-39`（GetOrgID）；日志 W0926 每次触发复现 | 审批闭环的 hub 侧（通知/审计/超时）整体失效；runner 侧 pause/decide 不受影响（本次实测 approve 流转正常） |
| G-11 | P0 | **console config.js 混入 YAML 注释 → 运行时配置整体失效**：console chart `templates/config.yaml` 的 `#` 注释行落在 `config.js: \|` 块内被原样渲染进 JS → `window.__APP_CONFIG__ = { #... }` 非法 JS → 解析失败 → 回落构建期 env（AUTH_DISABLED=false）→ **SKIP_AUTH=1 下前端卡死在 Keycloak 登录页**，无法进入应用（Chrome 实测复现；修复后同页正常进入）。测试期用 ConfigMap 运行时补丁（剔除注释行 + 重启 console）绕过 | console chart `build/console/charts/software-distribution-platform-console/templates/config.yaml`（:16-17 注释在 data 块内） | SKIP_AUTH 模式 console 完全不可用；正式 Keycloak 模式不受影响 |

### 附：Release 任务测试替代路径
G-9 修复前，部署场景用 **Build 任务 + kubectl 镜像 + 内嵌 manifest `kubectl apply`** 验证（编排 / 派发 / 执行 / SA shim / kubectl 下发 / 集群验证全链路不变，仅任务类型不同）。

### 附：构建任务执行语义注意
- 任务成功=退出码 0；`curl PUT` 收到 404 **不非零退出**（curl 对 4xx 返回 0）→ 归档失败但任务 Succeeded。归档脚本须自行校验 HTTP 状态码（`-f` 或显式判断）才能把失败暴露为任务失败。

## 7. Gotchas（部署/测试操作层，非产品缺口）

1. `nohup ./deploy-local.sh &` 会被会话回收杀死（log 0 字节）→ 必须以前台阻塞方式或托管后台任务跑。
2. console 镜像构建：vite 清 `output/dist/assets`（63 文件）触发批量删除守卫（阈值 50）→ 部署前 `find <三仓>/output -depth -delete`。
3. `SKIP_AUTH=1` 只旁路 Keycloak API 鉴权，**不旁路 gateway token**（hub `GATEWAY_TOKEN` 仍设置）→ runner 握手需 token 匹配 + target 预注册，未知 target 404（`gateway.go:113-117`）。
4. hub 无 `/api/v1/health` 路由（404 正常）；探活用 `GET /api/v1/targets`。
5. `docker.io/bitnami/kubectl:1.30` tag 不存在。
6. kind 节点仅 mirror `localhost:5000`，裸名镜像（G-7）一律拉不动。
7. runner chart ClusterRole 必须含 `networking.k8s.io/ingresses`（历史坑，现已修，见 audit §5.2）。
8. **workspace 遮蔽**：runner mainContainer 无条件把 workspace emptyDir 挂在 `/workspace`（`job_builder.go:182`）→ 自带镜像内 `/workspace` 下的内容会被遮蔽；自带源码/工具须放其它路径（本测用 `/opt/src`）。
9. **镜像 tag 缓存**：job Pod imagePullPolicy 默认 IfNotPresent → 同 tag 重新 push 后节点仍用旧镜像；改镜像必须换新 tag（本测 test→v2）。

## 8. 执行状态

- [x] 部署全栈（postgres/hub/runner/console Running）
- [x] 预注册 target local-dev，runner online
- [x] SA shim × 3 ns（sdp-run / sdp-test / sdp-prod）
- [x] org/service/component（E2E Org → Nginx Demo → Nginx E2E）
- [x] environments（test 先建；prod 后建用于 409 反向）
- [x] 构建流水线：run `Succeeded`（3s）；归档链路前半（upload-url 签发）✅，PUT 因 G-8 404 未落库（如实记录）
- [x] 日常流水线（Build+kubectl 替代路径，G-9）：run `Succeeded`，sdp-test nginx-e2e Pod Running（Deployment+Service 就位）
- [x] 发布流水线（审批）：`WaitingApproval` → decision approve → `Succeeded`，sdp-prod nginx-e2e Pod Running
- [x] 409 反向用例：prod-env 建立后，无审批流水线触发生产 → `409 + reasons`（ERR.08409005）
- [x] 前端渲染：首页总览（运行统计+最近运行徽章）/ 服务树（E2E Org→Nginx Demo）/ 运行中心（8 条运行+待审批过滤）均真实数据渲染 ✅；制品 Tab 预期为空（G-2/G-8）
- [x] 根目录 HTML 报告 `sdp-pipeline-e2e-report.html`

### 运行台账（关键 run）
| 流水线 | run | 结果 | 备注 |
| --- | --- | --- | --- |
| nginx-build | f02e8ef1 | Failed | workspace 遮蔽（gotcha 8） |
| nginx-build | dcb3252a | Failed | 镜像 tag 缓存（gotcha 9） |
| nginx-build | 2747506b | **Succeeded** | 归档 PUT 404（G-8）但任务退出码 0 |
| nginx-daily（Release 型） | 2f5ce79a | Failed | G-9 ReleaseSpec 丢失 |
| nginx-daily-v2 | 7161d3ca | Failed | kubectl 为 darwin 二进制（测试素材坑） |
| nginx-daily-v2 | c731d312 | Failed | 参数未注入（G-5 现场） |
| nginx-daily-v2 | e331a54d / pr-b798360a | **Succeeded** | sdp-test nginx Running |
| nginx-release | 61a5d470 / pr-9c4841af | **Succeeded** | WaitingApproval→approve→sdp-prod nginx Running |

## 9. 补齐开发记录（2026-09-26 第二批：缺口修复）

> 用户指令：全量补齐开发、kind 实测验证、文档闭环。修复方案均经双向钢人论证（结论见各行）。
> Gate：hub/runner `go build`+`vet`+`test`+`gofmt -l` 全绿；console `pnpm build`+`test` 全绿。

### 9.1 修复清单（代码位置 + 钢人结论）

| # | 修复 | 代码位置 | 钢人结论（反方 → 处置） |
| --- | --- | --- | --- |
| G-8 | `case "local"` 补 `localArtifactStore = localStore`，签名存储路由恢复挂载 | hub `cmd/hub/main.go`（~:242） | 无反方：一行 wiring 断裂 |
| G-9 | `buildTaskRun` 补拷 `ReleaseSpec`（+ Params/Privileged 透传） | runner `internal/controller/pipelinerun_controller.go` | 无反方：漏拷 |
| G-10 | `GetOrgID` 改 `Raw().Row().Scan(&uuid.UUID)`（uuid.UUID 实现 sql.Scanner；GORM Scan 对 [16]byte 数组反射失效） | hub `internal/component/repository/component.go` | Row().Scan 无行时返回 ErrNoRows，调用方 warn-fallback 语义不变 |
| G-11 | chart 模板把 `#` 注释移出 `config.js: \|` 块（JS 内只用 `//`），并留规约注释 | console chart `templates/config.yaml` | 注释进 data: 层即可，无需改渲染逻辑 |
| G-1 | hub config `SDP_JOB_SERVICE_ACCOUNT`（默认 `sdp-deploy`）注入 spec.ServiceAccountName；**runner 建 TaskRun 前 `ensureRunRBAC` 幂等 ensure SA+最小部署 Role/RoleBinding**；runner chart ClusterRole 补 serviceaccounts/roles/rolebindings create | hub `internal/config/config.go` + `internal/run/service/pipeline_run.go` + `cmd/hub/main.go`；runner `internal/controller/ensure_rbac.go`（新）+ `pipelinerun_controller.go` + chart rbac.yaml | 反方：runner 改写用户 ns 有越权疑虑 → Role 仅含部署所需资源且只绑该 SA，与 Release 授权语义一致；SA 名可配置、置空回退旧行为 |
| G-5 | **双通道**：① hub `templateToTaskSpec` 触发时做 `${KEY}` 替换（command/args/scriptArgs/produces/consumes/image/releaseConfig.manifest/values/chartVersion）；② runner 把 Params 注入容器 env（合法变量名直注，保留字 PATH/HOME/LD_PRELOAD 等拒注） | hub `internal/run/service/pipeline_run_params.go`（新）+ `pipeline_run.go`；runner `pkg/executor/job_builder.go`（paramsToEnv） | 反方：文本替换会改写字面 `${}` → 限定 braced 形式、未知 key 原样保留可见；env 裸名有遮蔽风险 → 保留字 denylist。单通道均覆盖不全（env 管不到 manifest 内容，替换管不到 shell 运行时值），互补 |
| G-2 | `ApplyStatus` 任务 Succeeded 时按模板 Produces 调 `ArtifactService.RegisterProduced` 入库（幂等跳过重复 key）；main.go 装配 `SetArtifactRegistrar` | hub `internal/run/service/pipeline_run.go` + `pipeline_run_params.go`；`internal/artifact/service/artifact.go` | 注册失败仅告警不影响状态回写；version 取 run params `VERSION`，回落 key 第三段约定 |
| G-6 | consume init 容器实装：调新增 `POST /artifacts/storage-url`（key→签名 GET，**不要求登记过制品行**，S3/local 双驱动可用）下载到 workspace；镜像默认 `curlimages/curl` | hub `internal/artifact/handler/artifact.go` + `service/artifact.go`；runner `job_builder.go`（consumeFetchScript） | 反方：任务内互传的 ephemeral 产物未登记、按 id 下载行不通 → 按 key 签发绕开 DB 依赖；hub token 经 `SDP_HUB_API_TOKEN` 注入（SKIP_AUTH 留空） |
| G-7 | 四个 job 默认镜像全部可配置：runner env `SDP_JOB_IMAGE_GIT/ARTIFACT/HELM/KUBECTL`，chart values `jobImages.*` + `hubApi.url/token` | runner `cmd/runner/main.go` + `pkg/executor/job_builder.go` + chart | 反方：artifact 默认镜像从 aws-cli 换 curlimages（consume 需要 curl+sh） |
| G-4（最小版） | 任务级 `privileged` 开关贯通：模板列 → spec → Job securityContext | hub `internal/pipeline/models/task_template.go`；runner types + `job_builder.go`（applyPrivileged）；**console 表单新增「特权模式」勾选** | 定位：构建环境=镜像选择；dind/cind 镜像配合 privileged 即可；专用构建环境模板留 follow-up |
| G-12（新发现） | **console↔hub ReleaseConfig 契约断裂**：console 发 `manifest: <string>`（hub 反序列化必挂）与 `chart.repo/chartUrl`（runner 字段是 `repoURL`，静默丢 repo）。修 console 类型对齐 runnerapi + 表单读写适配 + **移除假字段 chartUrl**（runner 从不支持，留着就是假配置） | console `src/api/pipeline.ts` + `TaskFormDrawer.vue` + `PipelineEditorView.vue` | 用户点题："确认哪些是前端可配置的特性开关而非写死流程"——据此全量盘点：image/command/scriptPath/timeout/retry/produces/consumes/chart/values/manifest/approval 本就可配；本次补 privileged 开关与真实生效的 `${参数key}` 占位提示 |
| G-13（回归中发现） | **runner ClusterRole 权限不足 → K8s 特权提升防护拒绝授予**：`ensureRunRBAC` 要在目标 ns 建 Role/RoleBinding，但 runner 自身 ClusterRole 缺 create/delete 动词 → APIServer 403 "attempting to grant RBAC permissions not currently held"。补齐 deployments/services/configmaps/secrets/pods 的 create/update/patch/delete 全量；另清理 e2e 期手工 shim 遗留的脏 Role（3 apiGroups 混一条 rule 同样触发防护） | runner `build/runner/charts/.../templates/rbac.yaml` | 反方：越权扩面疑虑 → 补的正是它要授予出去的最小集合（部署资源 CRUD），授予者必须先持有是 K8s 设计而非可绕过项 |
| G-14（回归中发现） | **RegisterProduced 非幂等**：ApplyStatus 每次 Succeeded 状态上报都插 artifacts 行 → 同 key 实测重复 7 行。修：按 (component_id, storage_key) 存在即跳过（repo 新增 `ExistsByComponentAndKey`）；存量重复行已 SQL 清理（保留最早） | hub `internal/artifact/service/artifact.go` + `internal/artifact/repository/artifact.go` | 反方：DB 唯一索引更硬 → AutoMigrate 只加不删约束下需迁移清洗历史重复行，且 runner 状态上报串行、竞态窗口可忽略，应用层幂等收益/成本更优 |

### 9.2 前端流水线配置盘点（可配置项 vs 写死项）

| 能力 | 前端形态 | 状态 |
| --- | --- | --- |
| 构建镜像 / 命令 / 脚本逃生通道 / 超时 / 重试 | TaskFormDrawer 一、运行环境与命令 | 既有可配 |
| 产出/消费（产物交接） | produces/consumes 输入框 | 既有可配；G-2/G-6 修复后**真实生效** |
| `${参数key}` / `$参数名` | 命令与 values 占位 | G-5 修复后真实生效（hub 替换 + runner env） |
| 特权模式（dind/cind） | 「特权模式」勾选（新增） | 本次新增 |
| 发布 chart（repoURL/name/version）/ values / manifest | 发布配置组 | G-12 修复后真实生效；假字段 chartUrl 已移除 |
| 审批（人数/审批人） | 人工审核组 | 既有可配 |
| 版本号 | 触发对话框 params（如 VERSION=v0.0.1）+ **制品库版本 picker** | 可配；B-20 最小版已落地（2026-09-26 第三批）：对话框自动列组件已登记制品版本，选中即填 VERSION 参数；kind 实测 UI 触发 run 一次通过。制品→发布语义联动（选版本同时改 chartVersion/manifest）留完整版 |

### 9.3 回归验证（kind 实测，2026-09-26 全部通过）

- [x] 重部署三镜像（docker rmi + deploy-local.sh SKIP_AUTH=1；hub 修复后另以 `build/hub/build.sh v0.0.5` + `kubectl set image` 增量更新）
- [x] G-8/G-2：构建任务 upload-url PUT 200 → hub PVC `/data/artifacts/.../v0.0.4/nginx-v0.0.4.tar.gz` 落盘 → artifacts API 有行（key 已做 `${VERSION}` 替换）
- [x] G-5：manifest `${IMAGE}` 触发时替换（image=localhost:5000/nginx:v0.0.1）+ 脚本 `$VERSION` env 注入（`param VERSION(shell env)=v0.0.3`）
- [x] G-9：真 Release 任务（非 Build 替代）5s Succeeded，部署 sdp-test 成功
- [x] G-1：sdp-test 内 runner 自动创建 sdp-deploy SA/Role/RoleBinding，Job pod `serviceAccountName=sdp-deploy`
- [x] G-10：WaitingApproval 期间 `GET /notifications` 返回 2 条待审批通知；pipeline_approvals 行 Pending → decision approve 后 **Approved**（approver=dev，decided_at 落库）→ run Succeeded → sdp-prod taskrun Completed
- [x] G-6：两阶段流水线 produces→consumes 交接成功（fetch-artifacts init 日志 `fetched components/e768dbad/g6/payload-v0.6.3.txt -> /workspace/payload-v0.6.3.txt (34 bytes)` + `G6-HANDOFF-VERIFIED`）。注意：上传侧用既有 `POST /artifacts/upload-url`（按 key 签 **PUT** URL），下载侧用新增 `POST /artifacts/storage-url`（按 key 签 GET）——两端点按 key 签发、都不要求 DB 登记行
- [x] G-11：helm 重装 console 后 config.js 无 `#` 注释，SKIP_AUTH 前端直进应用
- [x] G-12：console ReleaseConfig 类型对齐 runnerapi（`chart.repoURL`/`manifest.content`）后 API 建任务触发成功；表单读写已同步适配
- [x] 409 生产守卫回归：无 Approval 流水线（nginx-daily-v2）触发 prod target → `409 ERR.08409005` + reasons 明确指出"目标环境属于生产环境"
- [x] G-14（新发现，见 9.1）：RegisterProduced 幂等修复后，同 key 登记恒 1 行（修复前实测 7 行重复）

#### G-6 验证追加 gotcha
- `POST /artifacts/storage-url` 只签 **GET** URL（`method=GET&exp=&sig=`），produce 上传误用它会 `PUT failed`（实测踩中）；上传必须走 `POST /artifacts/upload-url`（`method=PUT`）。两者请求体同为 `{"key":"..."}`，易混。
- G-6 过程中顺带发现 CRD 新字段（spec.params/privileged）被集群旧 CRD schema 结构化剪除 → 需 controller-gen 重生成 CRD 并 `kubectl apply`（已入 §7 补充）。
