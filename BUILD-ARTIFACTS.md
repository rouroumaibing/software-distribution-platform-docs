# 生成物链路梳理报告 — hub / runner / console 三项目

> 产出方式：`how-code-chain-work` 协议（Phase 0 边界 → Phase 1 梳理 → Phase 2 待确认关卡）。
> **§0–§9 是 2026-09-15 上午的梳理与取证快照**（当时未改动任何代码）。
> **§10 是同日的两轮落地记录**（10.1–10.6 第一轮收口；10.7 第二轮）。
> **附 C 是 F-1 的双向钢人论证与最终裁决**——F-1 的结论以附 C 为准。
> 凡被 §10 / 附 C 覆盖的条目，正文已就地标注「→ §10」/「→ 附 C」。
> 梳理日期：2026-09-15。基线：hub `f6e89af`、runner / console 各自 main。

---

## 0. Phase 0 任务边界

| 项 | 内容 |
| --- | --- |
| **关心的行为** | 三个项目的**生成物生命周期链**是否四段闭合：**产生 → 落点 → 版本控制忽略 → 清理 → 再生成**。重点是找出「被当成可丢弃产物、实际却是编译/打包必需输入」这类不自洽。 |
| **范围边界** | 展开：三仓内 `Makefile` / `package.json` / `build/**` / `hack/**` / `scripts/**` / `.gitignore` / `.github/workflows/**` / `deploy/**`；工作区根 `deploy-local.sh` `undeploy-local.sh` `stop-dev.sh` `.dockerignore`。**不展开**：Go/TS 第三方库源码、`old/`（参考工程，仅作对照）、`software-distribution-platform-docs/` 自身。 |
| **正确性要求等级** | **高**。生成物链断在「编译必需产物」上，会让 CI、发布、新克隆、`make clean` 后重建同时失效——与权限/支付同级。 |

---

## 1. 入口清单（Phase 1.1）

| # | 入口 | 位置 | 性质 |
| --- | --- | --- | --- |
| E1 | 根部署编排 | `deploy-local.sh:1-218` | 编排（回调三仓 build.sh） |
| E2 | 根卸载 | `undeploy-local.sh:19-23` | 清理（集群侧） |
| E3 | 根开发进程清扫 | `stop-dev.sh:19-26` | 清理（进程侧） |
| E4 | hub Makefile | `software-distribution-platform-hub/Makefile` 9 targets | 仓级入口 |
| E5 | runner Makefile | `software-distribution-platform-runner/Makefile` 9 targets | 仓级入口 |
| E6 | console scripts | `software-distribution-platform-console/package.json:7-21` 12 scripts | 仓级入口 |
| E7 | 三份打包脚本 | `build/{hub,runner,console}/build.sh` | 交付包生成 |
| E8 | 三份开发服务脚本 | `hub/hack/svc.sh`、`runner/hack/svc.sh`、`console/scripts/svc.sh` | 运行期产物 |
| E9 | console 清理脚本 | `console/scripts/clean.sh:13-35` | 清理 |
| E10 | 证书生成 | `console/scripts/gen-certs.sh:17-73` | 工作区根产物 |
| ~~E11~~ | ~~P0 legacy~~ | ~~`hub/deploy/p0-up.sh`、`hub/deploy/p0-down.sh`、`hub/deploy/Dockerfile`、`runner/deploy/Dockerfile`~~ | **→ §10.7 已删除**（无引用者）；同目录 **活文件** `kind.yaml` + `manifests/**` 保留 |

---

## 2. 生成物拓扑总表（先给结论）

### 表 A — 仓内生成物（三仓）

| 项目 | 生成物 | 生产者 | 编译/打包必需？ | 已入库？ | 被忽略？ | 被 clean 删？ |
| --- | --- | --- | --- | --- | --- | --- |
| hub | `docs/docs.go` `swagger.json` `swagger.yaml` | `swag init`（本机需先装 CLI） | ✅ **必需**（`cmd/hub/main.go:18` 空白导入） | ✅ **已入库**（→ 附 C） | ❌ 否（→ 附 C） | ❌ 否（默认；`PURGE_DOCS=1` 才删） |
| hub | `bin/hub` | `make build`(:43-44) | 否（本地便利） | ❌ | ✅ | ✅ |
| hub | `<仓根>/hub`（64MB） | 裸跑 `go build ./cmd/hub` | 否 | ❌ | ⚠️ 本轮才补 `/hub` | ✅ 本轮才补 |
| hub | `output/**`（staging/二进制 tar/镜像 tar/chart tgz/交付包） | `build/hub/build.sh` | 否（交付产物） | ❌ | ✅ | ✅ |
| hub | `.run/dev.log` `.run/dev.pid` | `hack/svc.sh:14-16` | 否 | ❌ | ✅ | ✅ |
| runner | `api/v1alpha1/zz_generated.deepcopy.go`、`config/crd/bases/*.yaml` | controller-gen（无 target） | ✅ **必需** | ✅ **已入库** | ❌ 否 | ❌ 否 → **正确范本** |
| runner | `bin/runner` `output/**` `.run/**` | 同 hub | 否 | ❌ | ✅ | ✅ |
| console | `dist/**` | `pnpm build`（`build.sh:34`） | 否 | ❌ | ✅ | ✅ |
| console | `node_modules/` `.pnpm-store/` | `pnpm install` | 否（依赖） | ❌ | ✅ | 仅 `clean:deep` |
| console | `.vite/` `*.tsbuildinfo` | vite | 否 | ❌ | ✅ | ✅ |
| console | `{{ 无编译必需生成物 }}` | — | — | — | — | — |

> **关键对比**：runner 与 hub 面对**同一类**问题（生成物是编译/打包必需输入），runner 按 kubebuilder 惯例**入库**，hub **忽略+可删** → hub 断链。

> **→ §10 落点变更（2026-09-15）**：`make build` 的二进制已从 `bin/<c>` 迁到 **`output/bin/<c>`**；console 的 vite 产物已从 `dist/**` 迁到 **`output/dist/**`**（+ 缓存 `output/.vite`）。即「构建生成物全部收敛到 `output/`」，上表第 2/3 行（hub）、第 8 行（console `dist/**`）的落点以此为准；三仓 clean 相应变为**先停服务 → 一条 `rm -rf output`**。

### 表 B — 工作区根生成物（**不在任何 git 仓内**）

工作区根 `/Users/rouroumaibing/work/devops` **不是 git 仓**（无 `.git`）→ 无忽略问题，但**也无任何统一 clean 入口**。

| 生成物 | 生产者 | 备注 |
| --- | --- | --- |
| `.bin/helm` | `deploy-local.sh:44-46` | 缺失自动重下，自愈；**→ §10 已可由 `clean-local.sh --all` 清理** |
| `.kubeconfig` | `deploy-local.sh:69`（kind export） | 缺失可由 deploy 重建；**→ §10 已可由 `clean-local.sh --all` 清理** |
| `.dockerconfig/` | 会话级 sandbox 重定向（`deploy-local.sh:18`） | deploy 依赖其存在；**刻意不清理**（空目录，删了没收益） |
| ~~`certs/console/**`（含 `ca.key` `server.key` **私钥**）~~ | `gen-certs.sh`（曾为 `OUTPUT_DIR=$ROOT/certs`） | **→ §10.7 已删除**：证书定位改为「生产由运维手工创建 secret / 本地自签产物落 `console/output/certs`」，工作区根 `certs/` 已 `rm -rf`（旧 CA 指纹留档于 §10.7） |
| `.gocache/` `.gomodcache/`（约 2.2GB） | **来源未见于任何脚本**（疑似会话级 env） | 见 §5 U-1；**→ §10 已可由 `clean-local.sh --all` 清理** |
| ~~`/tmp/sdp-build-{hub,runner,console}.log`~~ | `deploy-local.sh:128` | **→ §10.7 已改**：日志移到工作区根 **`.logs/build-<comp>.log`**（随 `clean-local.sh` 回收），且**失败会打印日志尾部并中止**（F-4 闭合） |

---

## 3. 正向调用链（入口 → 内部调用）

### E1 `deploy-local.sh` — 本层直接子调用总数 **N = 22**

| # | 调用的命令/脚本 | 位置 | 分类 | 置信度 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 1 | `helm version` | :49 | 剪枝 | 确认 | 只读探测 |
| 2 | `curl get.helm.sh` → `.bin/helm` | :44-46 | 展开 | 确认 | 产工作区根生成物（表 B） |
| 3 | `docker network create kind` | :52 | 剪枝 | 确认 | docker 网络，非文件 |
| 4 | `docker run kind-registry` | :53-55 | 剪枝 | 确认 | 外部 docker 状态；undeploy:23 明确保留 |
| 5 | `kind get/create cluster --config hub/deploy/kind.yaml` | :68,:110 | 剪枝 | 确认 | 消费 `deploy/kind.yaml`（活文件） |
| 6 | `kind export kubeconfig` | :69,:111 | 展开 | 确认 | 产 `.kubeconfig` |
| 7 | `kubectl get node`（`wait_node_ready`） | :72-78 | 剪枝 | 确认 | 只读轮询 |
| 8 | `docker network disconnect/connect`（`pin_static_ip`） | :80-86 | 剪枝 | 确认 | 外部网络配置 |
| 9 | `docker exec` 读 kubelet.conf（`repair_node_ip`） | :88-104 | 剪枝 | 确认 | 只读取证 |
| 10 | `docker exec systemctl`（代理清理） | :116 | 剪枝 | 确认 | 集群内环境 |
| 11 | **`build/{comp}/build.sh $VERSION`** | **:128** | **展开** | 确认 | **回调三仓打包脚本**（→ E7）；产 `output/**` + registry 镜像 |
| 12 | `docker image inspect/push`（hub/runner/console） | :124-125 | 展开 | 确认 | registry 内镜像 |
| 13 | `docker pull/tag/push postgres:16-alpine` | :132-136 | 剪枝 | 确认 | 外部镜像搬运，不产仓内文件 |
| 14 | `docker pull/tag/push` ingress-nginx ×2 | :138-144 | 剪枝 | 确认 | 同上 |
| 15 | `kubectl apply -f` manifests ×3 | :148,:149,:156 | 剪枝 | 确认 | 消费 `deploy/manifests/**`（活文件） |
| 16 | `kubectl rollout status` | :150,:158-159,:171,:182,:193 | 剪枝 | 确认 | 等待 |
| 17 | `kubectl delete` legacy 资源 | :163-165 | 剪枝 | 确认 | 集群侧清理 |
| 18 | `helm upgrade --install` ×3 | :169,:180,:188 | 剪枝 | 确认 | 消费 chart 源目录 |
| 19 | `curl POST /api/v1/clusters` | :175-177 | 剪枝 | 确认 | 集群内数据 |
| 20 | **`console/scripts/gen-certs.sh`** | **:187** | **展开** | 确认 | **产 `certs/console/**`（含私钥）** |
| 21 | `kubectl rollout restart/status deploy/console` | :192-193 | 剪枝 | 确认 | 等待 |
| 22 | `kubectl logs`（握手验证） | :199,:206 | 剪枝 | 确认 | 只读 |

**小计：展开 5 + 剪枝 17 + 未验证 0 = 22 ✓**

### E7 `build/{hub,runner,console}/build.sh` — 本层直接子调用总数 **N = 7**（三份同构）

| # | 子调用（stage） | 位置（hub 版） | 分类 | 置信度 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 1 | `prepare_go_mod()` | :28-34 | 剪枝 | 确认 | 仅设 env，不产文件 |
| 2 | `prepare_build_file()` | :36-40 | 展开 | 确认 | `charts/` `images/` → `output/` |
| 3 | `build_<c>()` | :42-57 | 展开 | 确认 | **`go build`（:46-48）** → `output/staging/` → `images/<c>.tar.gz` |
| 4 | `build_<c>_docker_image()` | :59-71 | 展开 | 确认 | `docker build/save` → `images/<c>-<v>.tar` |
| 5 | `push_to_local_registry()` | :74-82 | 展开 | 确认 | registry 镜像（失败不阻断） |
| 6 | `charts_pack()` | :84-94 | 展开 | 确认 | `output/charts/<c>-<v>.tgz` |
| 7 | `pack()` | :96-106 | 展开 | 确认 | `output/<c>-<v>.tar.gz` 交付包 |

**小计：展开 6 + 剪枝 1 + 未验证 0 = 7 ✓**

- console 版差异：stage 3 为 `pnpm install --frozen-lockfile` + `pnpm build`（`build/console/build.sh:33-34`），产物为 `dist/` → `images/console-dist.tar.gz`（:37）；**无 `prepare_go_mod`**（实际仍保留 7 个顶层调用，第 1 个缺省）。
- 三份 `images/Dockerfile` 只 `ADD <tar.gz>`（hub :7 / runner :6 / console :9）→ **镜像不含源码，纯交付物**。

### E4 / E5 Makefile — 9 targets

| target | 命令 | 分类 | 置信度 |
| --- | --- | --- | --- |
| `help` | echo ×9 | 剪枝 | 确认 |
| `clean` | `rm -rf bin .run output coverage` + `find -maxdepth 2 -delete` + hub 额外 `rm docs/{docs.go,swagger.*}`（hub :37） | **展开** | 确认 |
| `clean-deep` | 依赖 `clean` | 展开 | 确认 |
| `build` | `go build -o bin/hub ./cmd/hub` | **展开** | 确认 |
| `package` | `bash build/<c>/build.sh` | 展开 | 确认 |
| `start-dev` / `stop-dev` | `bash hack/svc.sh start\|stop` | 展开 | 确认 |
| `start-deploy` / `stop-deploy` | `bash ../deploy-local.sh` / `../undeploy-local.sh` | 展开 | 确认 |

**小计（E4）：展开 8 + 剪枝 1 + 未验证 0 = 9 ✓**（E5 同，差异：runner 无 docs 删除行、find 多含 `*.err.txt`）

### E6 console `package.json` scripts — 12 条

| script | 命令 | 分类 | 置信度 |
| --- | --- | --- | --- |
| `dev` / `preview` | `vite` / `vite preview` | 展开 | 确认 |
| `build` / `package` | `vue-tsc --noEmit && vite build` / `vite build` | 展开 | 确认 |
| `typecheck` | `vue-tsc --noEmit` | 剪枝 | 确认 |
| `test:runcenter` | `node scripts/runcenter-url-smoke.mjs` | 剪枝（只读断言） | 确认 |
| `clean` / `clean:deep` | `bash scripts/clean.sh [--deep]` | 展开 | 确认 |
| `image` | `bash build/console/build.sh` | 展开 | 确认 |
| `start:dev` / `stop:dev` | `bash scripts/svc.sh` | 展开 | 确认 |
| `start:deploy` / `stop:deploy` | `bash ../deploy-local.sh` / `../undeploy-local.sh` | 展开 | 确认 |

**小计：展开 10 + 剪枝 2 + 未验证 0 = 12 ✓**

### E8 `hack/svc.sh` / `scripts/svc.sh` — 本层直接子调用总数 **N = 8**

`mkdir -p .run`(:17) / `kill -0`(:19) / `kill -TERM -pgid`(:27) / `kill -KILL -pgid`(:32) / `rm -f dev.pid`(:35) / `pkill -f`(:40) / `setsid bash -c <cmd>`(:49) / `pgrep -f`(:63) — 全部 **展开**（产 `.run/dev.{pid,log}`）。

**小计：展开 8 + 剪枝 0 + 未验证 0 = 8 ✓**
> `case "$APP"` 分支为**配置驱动**（附录 A 气味：配置驱动分支）：`console` 分支在 hub 副本里仍是 `npm install`/`npm run dev`（`hub/hack/svc.sh:44`），而 console 已迁 pnpm（`console/scripts/svc.sh:44`）→ 见 F-3。

### E9 `console/scripts/clean.sh` — N = 6

`rm -rf dist .vite coverage .run output`(:22) / `find -maxdepth 2 -delete`(:25-29) / `rm -rf node_modules`(:33) / `rm -rf .pnpm-store`(:34) / `echo`×2 — **展开 4 + 剪枝 2 = 6 ✓**

### E10 `gen-certs.sh` — N = 6

`mkdir -p $OUT`(:12) / `openssl req -x509`（CA，:19-21） / `cat > server-csr.conf`(:25-53) / `openssl req -new`(:56-58) / `openssl x509 -req`(:59-62) / `kubectl create secret`×2(:66-73) — **展开 5 + 剪枝 1（echo/日志）= 6 ✓**
> **→ §10.7 已改**：产物落 `<console>/output/certs`（不再经 `OUTPUT_DIR` 注入）；`deploy-local.sh` 改为「secret 已存在则复用、缺失才自签兜底」；脚本新增 **`--local-only`**（集群未起 / 无 kubectl 时只产文件，不碰集群）。

### E2 / E3 / E11（紧凑枚举）

| 入口 | 直接子调用 | 分类 | 置信度 |
| --- | --- | --- | --- |
| E2 `undeploy-local.sh` | `helm uninstall hub runner console`(:19)、`kubectl delete ns sdp-system`(:20) | 展开 2 | 确认；**不触碰 `output/` `.run/` `certs/` 与镜像**（:22-23 显式声明保留） |
| E3 `stop-dev.sh` | `ps`(:30)、`grep`(:34)、`kill -TERM/-KILL`(:62,:77,:84)、`awk`(:60,:76) | 展开 5 | 确认；**不清理 `.run/*.pid`**（与 E8 职责不重叠） |
| E11 `p0-up.sh` | `docker network/inspect/run/build`(:51-52 用 `deploy/Dockerfile`)、`kind`、`kubectl`、`swag`? | 见 F-7 | 确认（未展开：**已无引用者**，仅在文件自身） |

---

## 4. 反向调用点（谁在调用这些生成物/入口）

| 被调用者 | 调用方（位置） | 是否受「F-1 缺 docs.go」影响 | 置信度 |
| --- | --- | --- | --- |
| `build/*/build.sh` | `deploy-local.sh:128` | **是**（hub：`go build ./cmd/hub` 在 build.sh:46） | 确认（已复现 `go build` 失败） |
| `build/hub/build.sh` | `hub/.github/workflows/release.yml:63` | **是**（release 发不出交付包） | 确认（同一命令） |
| `go build ./cmd/hub` | `hub/Makefile:44`（`make build`） | **是** | **确认（已复现：`make: *** [build] Error 1`；补回 docs.go → exit=0）** |
| `go build ./...` | `hub/.github/workflows/ci.yml:54`（+ `:50` vet、`:58` test） | **是**（三步全红） | **确认（已复现三步输出）** |
| ~~`go build ./cmd/hub`~~ | ~~`hub/deploy/Dockerfile:14`（容器内编译）~~ | **→ §10.7 该文件已删**（§5 U-2 随之关闭：这条编译路径已不存在） | — |
| ~~`go build ./cmd/runner`~~ | ~~`runner/deploy/Dockerfile:9`~~ | **→ §10.7 该文件已删** | — |
| `make clean`（曾 **删** `docs/*`） | 用户 / 文档 README:17 | **→ 附 C 已反转**：`clean` 默认**保留** `docs/`（`PURGE_DOCS=1` 才删）→ 自伤闭环闭合 | **确认（已复现 A/B）** |
| `hack/svc.sh` | `hub/Makefile:51,54`；`runner/Makefile:51,54`；`console/package.json:17-18` | 否（`go run` 不产仓内二进制）；**→ §10.7 三份副本已消除漂移** | 确认 |
| `gen-certs.sh` | `deploy-local.sh:187`（唯一调用点，**→ §10.7 后不变**；仅内部行为改为「secret 存在则复用」+ 支持 `--local-only`） | 否 | 确认 |
| `deploy/kind.yaml` `deploy/manifests/**` | `deploy-local.sh:68,110,148,149,156` | 否 | 确认 |
| ~~`deploy/{p0-up.sh,p0-down.sh,Dockerfile}`~~ | ~~**仅 `p0-up.sh` 自身**（:51-52）~~ | **→ §10.7 已删除**（活文件 `kind.yaml` / `manifests/**` 保留） | — |

---

## 5. 未验证-动态 清单

| # | 位置 | 命中的气味 | 候选范围 | 建议验证方式 |
| --- | --- | --- | --- | --- |
| U-1 | `.gocache/` `.gomodcache/`（工作区根） | 配置驱动 / 环境变量 | 可能是 `GOCACHE`/`GOMODCACHE` 会话级重定向；全仓脚本**无一处**设置（已 grep `*.sh`/`Makefile`/`*.json`） | `go env GOCACHE GOMODCACHE` 对比根目录；或查会话/shell profile。**当前 `go env` 显示为默认 `~/go/pkg/mod`** → 两个根目录疑似历史遗留 |
| ~~U-2~~ | ~~`hub/deploy/Dockerfile:14`~~ | ~~构建上下文 + .dockerignore 语义~~ | **→ §10.7 关闭（N/A）**：`deploy/Dockerfile` 已删除，容器内编译这条路径不存在。正式镜像路径是 `build/hub/images/Dockerfile`，它只 `ADD output/images/*.tar.gz`（不含源码，天然不受 `docs/` 影响） | — |
| U-3 | hub CI 的**实际**结论 | 外部系统 | `gh` 未认证（HTTP 401）→ 取不到 run 列表 | 打开 GitHub Actions 页面确认 `ci` 在 main 上的最近结论（本地复现已证明该状态下三步必失败） |

---

## 6. 梳理中发现的既有问题

### F-1 【致命 · 已复现】hub `docs/`：编译必需产物被当成可丢弃生成物

**断链事实链**（全部有据）：

| 环节 | 证据 |
| --- | --- |
| ① 编译**必需** | `cmd/hub/main.go:18` → `_ "github.com/rouroumaibing/software-distribution-platform-hub/docs"`（空白导入注册 swagger spec；`cfg.SwaggerEnabled` 门控的 `/swagger/*any`（:307-309）依赖它） |
| ② **未入库** | `git ls-files docs/` → 仅 `docs/design/README.md`；`git log --all -- docs/docs.go` → **空（从未入库）** |
| ③ **被忽略** | `hub/.gitignore:19-21` 忽略 `docs/docs.go` `docs/swagger.json` `docs/swagger.yaml` |
| ④ **被 clean 删** | `hub/Makefile:37` `rm -f docs/docs.go docs/swagger.json docs/swagger.yaml` |
| ⑤ **无再生成入口** | 全仓无 `swag init` 调用（唯一出现在 `old/go-devops-gin/README.md:22`）；**`swag` 不在 PATH**；无 `make docs`/`swagger` target；`.gitignore` 引入于 `f6e89af`（2026-09-09）且该提交同时写下 clean 规则 |

**复现证据**（`git archive HEAD` → /tmp 纯入库副本，**只读原仓**）：

```
A. 无 docs.go
   go vet ./...   → cmd/hub/main.go:18:2: no required module provides package .../docs
   go build ./... → 同上
   go test ./...  → FAIL github.com/.../cmd/hub [setup failed]
   make build     → make: *** [build] Error 1
B. 补回 docs.go（仅此一文件）
   go list -deps ./cmd/hub → exit 0
   go build ./cmd/hub      → exit 0（产出 bin/hub 67MB）
   make build              → exit 0
```

**影响面**：CI（每次 push main 必红） · release（Publish 发不出交付包） · 新克隆（不可构建） · `make clean`（**自伤**：README 并列推荐的两条命令互为破坏） · `deploy-local.sh`（镜像缺则自动构建那条路会终止）。

**为什么 hub 单边坏**：runner 面对同一类问题已按 kubebuilder 惯例**入库**（`zz_generated.deepcopy.go` + `config/crd/bases/*.yaml` 均 tracked 且未被 ignore），其 CI（`runner/.github/workflows/ci.yml:33-40`）为绿。**所以这不是策略问题，是 hub 没跟上。**

**根因（超出代码）**：再生成命令只活在**记忆/口口相传**里，没进仓。历史记录显示 `swag init --generalInfo cmd/hub/main.go --parseInternal --output docs` 是既有约定，也曾在 2026-09-14 手工执行过一次让本机构建转绿——**即"靠人记得"维持**。

> ⚠️ **与既有决策冲突，需人工裁决**：2026-09-09 的既定策略是「生成物一律 gitignore + 可 clean」（当时为**用户显式意图**，非误判）。F-1 证明该策略对**编译/打包必需**的生成物不成立。**本报告不擅自反转该决策。**

### F-2 【中】三份 `svc.sh` 复制漂移

`hub/hack/svc.sh`、`runner/hack/svc.sh`、`console/scripts/svc.sh` 近乎逐字重复（约 78 行）。其中 hub 副本的 `console` 分支仍是 `npm install` / `npm run dev`（`hub/hack/svc.sh:44`），而 console 已迁 pnpm（`console/scripts/svc.sh:44` 为 `pnpm`）。该分支在 hub 仓属死代码，但**会误导**（读 hub 的脚本以为 console 用 npm）。

> **→ §10.7 已处理**：三份的 `console` 分支统一为 `pnpm install` / `pnpm dev`，注释同步为「vite / go run / 编译产物子进程」。**保留"每仓一份"**（各仓须自包含，不做跨仓引用），但语义已逐字对齐（hub 与 runner 两份现在完全相同，console 一份仅用法路径注释不同）。

### F-3 【中】工作区根生成物无归属、无清理入口

表 B 全部 6 类产物位于**任何 git 仓之外**：既无忽略问题，也**没有任何统一 clean 入口**。其中 `certs/console/{ca.key,server.key}` 是**私钥**，`gen-certs.sh` 只有生成路径（幂等复用），**无轮换/失效/删除路径**。

> **→ §10 / §10.7 已处理**：新增工作区级 `clean-local.sh`（含 `--all` 清 `.bin`/`.kubeconfig`/`.gocache`/`.gomodcache`、`.logs/`）；证书私钥产物迁出工作区根并纳入 clean 生命周期；工作区根 `certs/` 已删除。

### F-4 【中】构建日志吞进 `/tmp` 且失败静默

`deploy-local.sh:128` 将 `build.sh` 输出重定向到 `/tmp/sdp-build-<comp>.log`。`set -euo pipefail`（:13）会让失败终止脚本，但**屏幕上没有错误上下文**，只能去 `/tmp` 翻。与 F-1 叠加尤其危险：因缺 `docs.go` 导致的构建失败**完全不可见**。

> **→ §10.7 已闭合**：日志改落工作区根 `.logs/build-<comp>.log`（随 `clean-local.sh` 回收）；构建失败时**打印日志尾部（`tail -30`，前缀 `| `）并 `exit 1`**。已用「真实代码段 + 桩 build.sh/docker」实测：屏幕上能看到 FATAL 与编译错误原文。

### F-5 【低】console CI 未纳入已有测试

`pnpm test:runcenter`（运行中心 URL 契约冒烟，14 条断言）未进 `console/.github/workflows/ci.yml`（:36-43 只跑 install/typecheck/build）→ 契约回归无 gate。

> **→ §10.7 已闭合**：`console/.github/workflows/ci.yml` 增加 `pnpm test:runcenter` 一步。

### F-6 【低】hub `clean` 的 find 漏了 `*.err.txt`

`hub/.gitignore:7-8` 忽略 `*.err.txt`/`*_err.txt`，但 `hub/Makefile:36` 的 `find` 未含该 pattern（runner `Makefile:38` 含）→ 清理面比忽略面窄。

> **→ §10 已闭合**：`hub/Makefile` 的 find 已补 `*.err.txt` / `*_err.txt`（同时补 `*.prof` / `*.coverprofile`），与忽略面齐平。

### F-7 【低 · 需人工定性】`deploy/` 目录新旧混杂

`hub/deploy/{p0-up.sh,p0-down.sh,Dockerfile}`（+ runner 对应件）是 P0 legacy：`p0-up.sh` **无任何引用者**（唯一调用关系在它自己 :51-52）。但同目录的 `deploy/kind.yaml` 与 `deploy/manifests/**` 是**活文件**（`deploy-local.sh:68,110,148,149,156` 在用）→ **不可整目录删除**。

> **→ §10.7 已处理（删除）**：`hub/deploy/{p0-up.sh,p0-down.sh,Dockerfile}` + `runner/deploy/Dockerfile` 已 `git rm`；**活文件保留**（`hub/deploy/{.gitkeep,kind.yaml,manifests/**}`、`runner/deploy/helm/.gitkeep`）。同时同步了 `plans/E2E-VERIFY-PLAN.md` 里指向 `p0-up.sh` 的引用（改为指向工作区根 `deploy-local.sh`），避免死链。

---

## 7. 剪枝日志（汇总）

| 被剪枝项 | 位置 | 剪枝理由 |
| --- | --- | --- |
| helm 下载/探测、kind 集群操作、network/IP 修复、rollout 等待、`kubectl logs`、`curl POST /clusters` | E1 #1,#3,#5,#7-10,#16,#19,#21,#22 | 只读或集群/docker 外部状态，不产生「需版本控制治理的仓内文件生成物」 |
| postgres / ingress-nginx 镜像搬运 | E1 #13,#14 | 外部镜像在本地 registry 的副本，非项目产物 |
| `manifests` apply、`helm upgrade`、legacy delete | E1 #15,#17,#18 | 集群侧资源与部署动作，消费者而非生成者 |
| `prepare_go_mod()` | E7 #1 | 仅导出 env（GOOS/GOARCH/GOPROXY），不落文件 |
| `typecheck` / `test:runcenter` | E6 | 只读断言，无产物 |
| `help` / `echo` | E4,E5,E9 | 纯输出 |

---

## 8. 结论与建议（⚠️ Phase 2 待确认，未动代码）

### 可以安全修改的范围
- 文档级陈述与索引同步（本报告 + README 索引）。

### 需要人工裁决后才能动

**裁决 1 — F-1 走哪条路？**（三选一，直接影响既有「生成物不入库」策略）

| 方案 | 做法 | 优点 | 代价 |
| --- | --- | --- | --- |
| **A 入库**（对齐 runner / kubebuilder 惯例） | `git add docs/{docs.go,swagger.json,swagger.yaml}`；从 `.gitignore` 与 `Makefile:37` 移除 | 最小改动；新克隆/CI/release/`make build` 立刻全绿；与 runner 策略一致 | 改 swagger 注解须重生成并提交；仓库多 ~55KB |
| **B 补可复现生成**（保留"不入库"） | `go.mod` 加 tool 依赖 + `Makefile` 加 `docs:` target（`go tool swag init -g cmd/hub/main.go -o docs`），并让 `build`/`package` 依赖它；CI 先跑 `make docs` | 保留原策略；生成物仍不入库 | 构建链路多一步；`swag init` 有已知告警（`models.TriggerRequest` 递归） |
| **C A+B** | 入库 + 同时提供 `make docs` 再生成入口 | 最稳（可复现 + 可校验漂移） | 改动最多 |

> ❌ **不建议**："从 clean 里删掉、但仍 gitignore"——那只是把「CI 必红」降级为「看本机有没有跑过 `swag init`」，属把断链藏得更深。

> **→ 附 C 已裁决（2026-09-15）**：走 **A（入库）**，并**反转 clean 语义**（默认保留，`PURGE_DOCS=1` 才删）。
> B 未被采纳为**唯一**方案，原因是本机 `go run github.com/swaggo/swag/cmd/swag` 因 go.sum 缺 `github.com/urfave/cli/v2` 跑不通（实测），
> 「不入库 + 靠再生成」等价于「构建能力依赖本机装没装 swag」；但**再生成命令已写入 `hub/README.md`**（补上 B 的可复现价值，不引入 CI 依赖）。
> 落地细节见 §10.7，论证过程见 **附 C**。

**裁决 2 — F-2 三份 `svc.sh`**：归并成一份（如仓间引用）还是明确「每仓一份是刻意的」？若归并，顺带修掉 hub 副本的 `npm` 死分支。

> **→ §10.7 已裁决**：**保留"每仓一份"**（各仓须自包含；跨仓引用会让"单仓可独立使用"失效），但把三份的 `console` 分支与注释**统一为 pnpm** —— 拿到了"归并"想要的消除漂移，去掉了"归并"的代价。

**裁决 3 — F-3 `certs/` 私钥**：是否需要轮换/清理入口（或至少在 README 定义其生命周期）？

> **→ §10 已落地（2026-09-15，按用户指示）**：证书的定位被明确为「**本地测试临时产物**；生产由运维手工创建 secret，组件容器内引用（同 `old/go-devops`）」。私钥产物迁到 `console/output/certs` 并纳入 clean 生命周期；`deploy-local.sh` 改为「secret 已存在则复用，缺失才自签兜底」；TLS 交付契约（secret 名 / key / 挂载点 / 权限）写入 `console/README.md`。

> **→ §10.7 追加**：工作区根 `certs/`（含 `ca.key`/`server.key` 旧自签私钥）已按用户指示**删除**；`gen-certs.sh` 新增 `--local-only`（无集群时只产文件）；新 CA/server 证书已在 `console/output/certs` **重新生成并校验**（链 `openssl verify` OK、SAN 覆盖 `console.sdp-system.svc*` + `console.local` + `localhost`、私钥 `600`）。

**裁决 4 — F-7 `deploy/` legacy**：`p0-up.sh`/`p0-down.sh`/`deploy/Dockerfile` 是否删除？（**注意保留 `kind.yaml` 与 `manifests/`**）

> **→ §10.7 已裁决：删除**（4 个文件 `git rm`，含 `runner/deploy/Dockerfile`）；`kind.yaml` / `manifests/**` / `.gitkeep` 保留；`plans/E2E-VERIFY-PLAN.md` 里指向 `p0-up.sh` 的引用已同步改指 `deploy-local.sh`。

### 低风险可直接做（如你同意）
- F-4：`deploy-local.sh:128` 改为 `tee` 或失败时 `tail` 日志再退出（错误可见）。**→ §10.7 已做并实测**（日志落 `.logs/`、失败打印尾部 + `exit 1`）。
- F-5：console CI 加一步 `pnpm test:runcenter`。**→ §10.7 已做**。
- F-6：hub `Makefile:36` 的 find 补 `*.err.txt`。**→ §10 已做**（并补 `*.prof`/`*.coverprofile`）。
- F-1 落地后：README 补一行「docs 的再生成/入库策略」，把只活在记忆里的命令写进仓。**→ §10.7 已做**（`hub/README.md` 新增「swaggo API 文档」一节，含 `swag init` 命令与 go.sum 前置说明）。

### 建议的回归验证方式
1. `git archive HEAD | tar -x` → 在纯入库副本跑 `go vet ./... && go build ./... && go test ./...`（**当前必失败；这是 F-1 的 gate**）。
2. `make clean && make build` 在 hub 仓连跑（**当前必失败**）→ 修后必通过。
3. 三仓 `make clean`/`pnpm clean` 后 `git status --porcelain` 应无生成物残留（上轮已建立该 gate 的做法）。

---

## 9. 机械完整性核对

| 入口 | 机械枚举 N | 展开 | 剪枝 | 未验证 | 核对 |
| --- | --- | --- | --- | --- | --- |
| E1 `deploy-local.sh` | 22 | 5 | 17 | 0 | 22 = 5+17+0 ✓ |
| E4 hub Makefile | 9 | 8 | 1 | 0 | 9 = 8+1+0 ✓ |
| E5 runner Makefile | 9 | 8 | 1 | 0 | 9 = 8+1+0 ✓ |
| E6 console scripts | 12 | 10 | 2 | 0 | 12 = 10+2+0 ✓ |
| E7 `build.sh`（单份） | 7 | 6 | 1 | 0 | 7 = 6+1+0 ✓ |
| E8 `svc.sh` | 8 | 8 | 0 | 0 | 8 = 8+0+0 ✓ |
| E9 `clean.sh` | 6 | 4 | 2 | 0 | 6 = 4+2+0 ✓ |
| E10 `gen-certs.sh` | 6 | 5 | 1 | 0 | 6 = 5+1+0 ✓ |
| E2 / E3 / E11 | 2 / 5 / n | 2 / 5 | 0 | 0 | ✓（E11 未展开，见 F-7） |

**未闭合项**：E11 未逐层展开（`p0-up.sh` 已无引用者）；`.` 「未验证-动态」U-1/U-2/U-3 待环境验证。

---

## 10. 落地记录（2026-09-15 收口）

按用户三条指示收口：**① 构建生成物全部放 `output/`，方便清理；② 清理前先停服务；③ certs 是临时测试的，生产改为手工创建 secret、容器内引用（同 old）**。

### 10.1 指示 ① 生成物收敛到 `output/`

对齐参考工程 `old/go-devops`（其 `console/vite.config.ts` 本来就是 `outDir: './output/dist'`，Go 二进制打包后即删）——**新 console 反而退回了仓根 `dist/`，本次改回**。

| 项目 | 改前落点 | 改后落点 | 改动位置 |
| --- | --- | --- | --- |
| hub | `bin/hub` | **`output/bin/hub`** | `hub/Makefile`（`BIN := output/bin/$(APP)` + `mkdir -p`） |
| runner | `bin/runner` | **`output/bin/runner`** | `runner/Makefile`（同上） |
| console | `dist/**` | **`output/dist/**`** | `console/vite.config.ts`（`build.outDir`） |
| console | `node_modules/.vite` | **`output/.vite`** | `console/vite.config.ts`（`cacheDir`） |
| console | `build.sh` 读 `${PROJECT_ROOT}/dist` | 读 `${OUTPUTDIR}/dist` | `console/build/console/build.sh` |

- 结果：三仓**清理主体退化为一条 `rm -rf output`**；`clean` 仍保留历史位置（`bin/` `dist/` `.vite/`）以防旧检出残留。
- **刻意未动**：hub `docs/{docs.go,swagger.json,swagger.yaml}` —— 它按 **Go import 路径**被 `cmd/hub/main.go:18` 引用，**物理上不能**挪进 `output/`。它不是"可丢弃的构建生成物"，而是**缺失的编译输入**（F-1，独立待裁决，见 10.4）。

### 10.2 指示 ② 清理前先停服务

| 入口 | 改动 |
| --- | --- |
| `hub/Makefile` clean | 首行先 `bash hack/svc.sh stop`；`NO_STOP=1 make clean` 跳过 |
| `runner/Makefile` clean | 同上 |
| `console/scripts/clean.sh` | 先 `scripts/svc.sh stop`；`--no-stop` / `NO_STOP=1` 跳过 |
| **`clean-local.sh`（新增，工作区根）** | 编排：先 `stop-dev.sh kill`（工作区级兜底清扫）→ 再逐仓 clean；`--deep` 删依赖、`--all` 清工作区级可再生资源、`--purge-docs` 放行 hub docs 删除 |

- 顺序理由：服务运行时会持有产物与 pid，先停再删才不留孤儿进程 / 半删状态。
- `clean-local.sh` **刻意不碰** `.dockerconfig/`、kind 集群、`kind-registry` 容器（属部署形态，由 `deploy-local.sh` / `undeploy-local.sh` 管理）。

### 10.3 指示 ③ certs = 本地临时；生产手工 secret（对齐 old）

事实核对：本仓 chart **本来就已经**是「容器内引用 secret」模式（`deployment.yaml` 的 `secret.secretName` + `items`→`/etc/nginx/ssl`，`ingress.yaml` 的 `tlsSecretName`），与 `old/go-devops`（`server-secret`→`/source/certs`、`nginx-ingress-tls`）同构。**真正的偏差在"谁生成 secret"**：old 由运维手工跑 `certs/k8s-secret-create.sh`，我们则由部署脚本自动生成并 apply。

| 改动 | 内容 |
| --- | --- |
| `console/scripts/gen-certs.sh` | 重定位为 **【本地联调专用】自签兜底**；产物默认落 `console/output/certs`（随 clean 回收）；文件头写明生产契约与消费方 |
| `deploy-local.sh:185-200` | 由"无条件自签"改为 **`console-tls` / `console-ingress-tls` 已存在则复用**；缺失才自签兜底；`SKIP_GEN_CERTS=1` 强制要求已存在（纯生产语义） |
| `console/.../values.yaml` | 注释改为「chart 只引用 secret 名；生产由运维手工创建，部署流程不生成私钥」 |
| `console/README.md` | 新增 **§TLS 证书（交付契约）**：两个 secret 的类型/必需 key/消费方/挂载路径 + 生产 `kubectl create secret` 示例 + `values` 改名入口 |

**交付契约（不改则已，改需同步 chart）**：

| Secret | 类型 | 必需 key | 消费方 |
| --- | --- | --- | --- |
| `console-tls` | `Opaque` | `ca.crt` `server.crt` `server.key` | nginx 443（挂 `/etc/nginx/ssl`，`defaultMode 384`） |
| `console-ingress-tls` | `kubernetes.io/tls` | `tls.crt` `tls.key` | ingress 终结 TLS |

### 10.4 F-1 现状变化：从"待裁决"变成"已加护栏，但仍待裁决"

`make clean` 删 `docs/*` 后 `make build` 必挂的问题**依然存在**（10.1 说明它不能挪进 `output/`）。本次不反转 2026-09-09 策略，只加护栏：

1. `hub/Makefile` clean 增 **`KEEP_DOCS=1`** 开关（默认仍删，保持既有语义）；
2. **`clean-local.sh` 默认传 `KEEP_DOCS=1`** —— 工作区级"一键清理"不该把本仓清成不可恢复（实测：传与不传的 dry-run 已核对）；
3. `hub/README.md` 与本节写明后果与恢复路径（`swag` 未装、`go run .../cmd/swag` 因 go.sum 缺 `github.com/urfave/cli/v2` 跑不通 —— 即**当前确实没有可复现再生成入口**）。

**仍待用户裁决**：§8 裁决 1 的 A（入库）/ B（补 `make docs` target，需先补 tool 依赖）/ C。

### 10.5 验证记录（本次全部实跑，非推断）

| # | 验证 | 结果 |
| --- | --- | --- |
| V1 | hub `make build` | exit 0，产物 `output/bin/hub`（67MB）；**仓根不再产生 `hub`** |
| V2 | runner `make build` | exit 0，产物 `output/bin/runner`（46MB）；仓根无 `runner` |
| V3 | console `pnpm build` | exit 0，产物 `output/dist/**`；**仓根不再产生 `dist/`** |
| V4 | `vite optimize`（等价 dev 首次启动） | 缓存落 `output/.vite/deps`；`node_modules/.vite` 不再被使用 |
| V5 | hub `make clean` | 先 `[svc:hub] 已停止本地开发服务。` → 删 `output/` 与仓根裸二进制 ✓；**并现场复现 F-1 自伤**（docs/* 被删，随后 `make build` 报 `cmd/hub/main.go:18:2: no required module provides package .../docs`） |
| V6 | hub `make clean` 后 `make build`（docs 已恢复） | exit 0 ✓ |
| V7 | runner `make clean` → `make build` | 往返通过；`api/v1alpha1/zz_generated.deepcopy.go` + `config/crd/bases/*.yaml` **未被删** ✓ |
| V8 | `./clean-local.sh` 端到端 | 先停服务 → 三仓清理 → 残留核对三仓均 ✓；hub docs 被 `KEEP_DOCS=1` 保留；仓根 64MB `hub` 裸二进制被清 ✓ |
| V9 | `bash -n` 语法检查 | `gen-certs.sh` / `clean.sh` / `clean-local.sh` / `deploy-local.sh` / `build/console/build.sh` 全部 OK |

### 10.6 本次未处理（保持原状，避免越界）

| 项 | 说明 |
| --- | --- |
| F-1 根治 | 需用户裁决 A/B/C（10.4） |
| F-4 构建日志失败静默 | `deploy-local.sh` 仍把 build.sh 输出丢 `/tmp`；用户未列入本轮指示 |
| F-5 console CI 未跑 `test:runcenter` | 同上 |
| F-2 三份 `svc.sh` 复制漂移 | 未合并（每仓一份是否刻意，仍待裁决 2） |
| F-7 `deploy/` legacy 三件 | 未删（裁决 4） |
| 工作区根遗留 `certs/`（含私钥） | **未删**（含私钥且可能已被浏览器/钥匙串信任）；`clean-local.sh` 只在结尾提示手工删除命令 |
| ~~U-2~~ 容器内编译 | **→ §10.7 关闭（N/A）**：`deploy/Dockerfile` 已删 |
| U-1 / U-3 | 未验证项不变（`.gocache`/`.gomodcache` 来源、hub CI 面板结论） |

---

## 10.7 第二轮收口（2026-09-15 午后）

用户三条指示：**① F-1 做双向钢人论证**（口径：子项目里 docs **不删**；整体上文档类内容归 `software-distribution-platform-docs` 仓）；**② 清理老证书、按新方式生产新证书、同步涉及到的代码**；**③ F-2 / F-4 / F-7 都要更新**。

### 10.7.1 改动清单

| # | 项 | 改动 | 证据 |
| --- | --- | --- | --- |
| 1 | **F-1 裁决落地**（走 A + clean 语义反转） | `hub/.gitignore` 去掉三行 swagger 忽略（改写成"刻意不忽略、必须入库"的说明）；`git add docs/{docs.go,swagger.json,swagger.yaml}` → **入库**；`hub/Makefile`：`KEEP_DOCS` → **`PURGE_DOCS`（默认保留）**，`build` 增前置检查（缺 `docs.go` 时给可操作提示）；`clean-local.sh` 同步（默认与仓级一致、`--purge-docs` 才删）；`hub/README.md` 新增 **「swaggo API 文档」** 一节（含 `swag init` 再生成命令 + go.sum 前置说明） | `git ls-files docs/` → 4 项（含 3 个生成物）；`git check-ignore --no-index docs/docs.go` **exit=1**（不再被忽略）；`make -n clean` 默认打印"保留…"，`PURGE_DOCS=1` 打印 `rm -f`；见 10.7.2 V1–V4 |
| 2 | **证书收口** | 工作区根 `certs/`（旧自签 CA + server **私钥**）**已 `rm -rf`**；`gen-certs.sh` 新增 **`--local-only`**（无集群/无 kubectl 时只产文件）；新证书在 `console/output/certs` **重新生成**；`clean-local.sh` 去掉 certs 提示、改为清理 `.logs/`；`console/README.md` §TLS 补 `--local-only` 与"换机/重生成会让 CA 指纹变化"提示 | 老 CA 指纹 `C5:F8:E9:…:14:84` → 新 CA `1D:59:AA:…:79:01`（确已换新）；`openssl verify -CAfile ca.crt server.crt` → **OK**；SAN 覆盖 `console` / `console.sdp-system[.svc[.cluster[.local]]]` / `console.local` / `localhost` / `127.0.0.1`；私钥 `600` |
| 3 | **F-2** | hub / runner 副本的 `svc.sh` `console` 分支 `npm` → **`pnpm`**，注释补 `vite`；**保留"每仓一份"**（各仓自包含），只消除漂移 | hub 与 runner 两份现在**逐字相同**；三份的 console 分支与注释一致，console 那份仅"用法路径"注释不同（`bash -n` 全 OK） |
| 4 | **F-4** | `deploy-local.sh`：构建日志 `/tmp/sdp-build-<comp>.log` → **`.logs/build-<comp>.log`**（工作区内、随 `clean-local.sh` 回收）；**失败时打印 `tail -30`（前缀 `\| `）并 `exit 1`**；头部说明同步 | 用**真实代码段**（`awk` 从 `deploy-local.sh` 抽出 step 4）+ 桩 `docker`/桩 `build.sh` 实测：屏幕出现 `FATAL: hub 构建失败，日志尾部如下（完整日志: …/.logs/build-hub.log）:` + 编译错误原文，`exit=1` |
| 5 | **F-7** | `git rm` `hub/deploy/{p0-up.sh,p0-down.sh,Dockerfile}` + `runner/deploy/Dockerfile`；**活文件保留**；同步 `plans/E2E-VERIFY-PLAN.md` 里指向 `p0-up.sh` 的引用（改指工作区根 `deploy-local.sh`），避免死链 | 删除后 `find` 只剩 `hub/deploy/{.gitkeep,kind.yaml,manifests/**}` 与 `runner/deploy/helm/.gitkeep`；全仓按调用形态 grep `p0-up\|p0-down` **无调用点** |
| 6 | **F-5** | `console/.github/workflows/ci.yml` 增加 **`pnpm test:runcenter`** 一步（+ 头部注释同步） | 本地 `pnpm test:runcenter` → `14/14 passed` |
| 7 | **顺带修（1.5 类发现）** | `undeploy-local.sh:14` 的真 bug：`log "未找到 $KUBECONFIG（可能从未部署）…"` —— 全角 `（` 被 bash 吞进变量名，`set -u` 下**这条"友好提示"分支本身就会崩**（`bash: KUBECONFIG�: unbound variable`，exit=1）。改为 `${KUBECONFIG}` | 已复现（exit=1）→ 修复后输出正常、exit=0。**同类陷阱本轮共修 3 处**（另两处在新写的 `gen-certs.sh` / `deploy-local.sh` 里，被测试当场抓到） |

> **⚠️ 本轮踩到并已沉淀的工具坑**：bash 中 `$VAR` **紧跟非 ASCII 字符**（如全角 `（`、`）`）时，该多字节字符会被当成变量名的一部分 → `unbound variable`。凡 `${VAR}` 能写就写 `${VAR}`。已对全部根脚本与三仓脚本做过模式扫描。

### 10.7.2 验证记录（本轮全部实跑）

| # | 验证 | 结果 |
| --- | --- | --- |
| V1 | `git check-ignore --no-index docs/docs.go docs/swagger.json docs/swagger.yaml` | `exit=1`（不再被忽略）✓ |
| V2 | `git ls-files docs/` | `docs/design/README.md` + 三个生成物 → **已入库（A）** ✓ |
| V3 | `make clean`（hub） | 打印「保留 docs/docs.go …（编译必需输入，已入库）」；`output/` 已删；`docs/` 完好 ✓ |
| V4 | `make clean PURGE_DOCS=1` → `make build` → `git checkout -- docs/` → `make build` | ① docs 被删；② build 打印 **可操作 FATAL** 并失败；③ `checkout` 恢复；④ build 重新 `exit 0`（`output/bin/hub` 67MB）—— **恢复路径与提示文案都实测可用** ✓ |
| V5 | `gen-certs.sh --local-only`（含幂等复跑） | 首次产 CA + server；复跑复用 CA、重签 server；产物/权限/链校验见 10.7.1 #2 ✓ |
| V6 | `./clean-local.sh` 端到端 | 先停服务 → 三仓清理 → 残留核对三仓 ✓ → **`.logs/` 被清** → hub `docs/` **保留** ✓ |
| V7 | hub / runner `go vet ./... && go build ./... && go test ./...` | 全 `exit=0`（hub `internal/run/service` ok；runner 全 ok）✓ |
| V8 | console `vue-tsc --noEmit` / `test:runcenter` / `vite build` | `exit=0` / `14/14 passed` / `✓ built`；产物落 `output/dist/**` ✓ |
| V9 | 全部被改脚本 `bash -n` | `deploy-local.sh` / `clean-local.sh` / `undeploy-local.sh` / `gen-certs.sh` / `clean.sh` / 三份 `svc.sh` 全 OK ✓ |
| V10 | **F-1 的 gate：纯入库副本**（`git ls-files -z \| tar` 造新克隆等价副本） | ① **`.../docs` 报错彻底消失**（旧行为是 `go vet/build/test` 三步全红）；② 但副本**仍不绿**，首错变成 `undefined: permbrepo.ComponentRoleRepository` / `undefined: models.PipelineApproval` —— 见 10.7.3 |
| V11 | **对照 B**：入库文件 + 未忽略的未跟踪文件（`git ls-files -co --exclude-standard`） | `go vet` / `go build` / `go test` **全 `exit=0`** ✓ → 证明 V10 的残留**不是** F-1 造成的 |

### 10.7.3 本轮暴露出的**同类新问题**（未擅自处理，需你裁决）

V10 与 V11 的对照说明：**F-1 的机制已被修好，但同一个病根还长在别处 —— hub 仓有一批"编译必需、却尚未入库"的在制品源码**：

| 未入库文件 | 后果 |
| --- | --- |
| `internal/run/models/pipeline_approval.go`、`internal/run/repository/approval.go` | `undefined: models.PipelineApproval`（`internal/run/service/pipeline_run.go:112,114,115,305`） |
| `internal/permission/{models,repository}/component_role.go`、`platform_role*.go`、`handler/component_role.go` | `undefined: permbrepo.ComponentRoleRepository`（`internal/component/service/component.go:21,27`） |
| `cmd/hub/conf/09_rbac_multiorg.sql`、`migrations/0004_rbac_multiorg.sql`、`0005_*` | 不影响编译，但新克隆缺迁移脚本 |

**这与 F-1 是同一条判据**：编译/打包必需的输入没进仓 → 新克隆/CI 必挂。**我没有 `git add` 它们**（属你正在推进的权限/审批在制品，与你的其它改动一起提交更合适）。提交后 `git ls-files` 副本即应转绿 —— 这条建议作为**新的 gate**：`V10 那条命令 + go vet/build/test`。

### 10.7.4 本轮未做 / 存疑

| 项 | 说明 |
| --- | --- |
| **集群侧证书未更新** | 本机 docker daemon 未运行、`kind` 不在 PATH、`.kubeconfig` 指向的 apiserver（`127.0.0.1:65449`）不可达 → 新证书只落本地 `console/output/certs`，**未写入集群 secret**。下次 `deploy-local.sh` 时若 `console-tls`/`console-ingress-tls` 仍在集群里，会按"已存在则复用"**跳过** → 要让新证书生效，先 `kubectl -n sdp-system delete secret console-tls console-ingress-tls`，或集群起来后直接跑一次**不带** `--local-only` 的 `gen-certs.sh` 覆写 |
| 浏览器信任 | 新 CA 指纹已变（旧 `C5:F8:…` → 新 `1D:59:AA:…`）：若此前把旧 `ca.crt` 加进过系统/浏览器信任，需替换 |
| `git add` 未提交 | hub 的 3 个生成物已 `git add`（index 里，状态 `A`），四个仓的其它改动仍在工作区 —— **等你 commit** |
| U-1 / U-3 | 不变（`.gocache`/`.gomodcache` 来源、hub CI 面板结论） |

---

## 附 C：F-1 的双向钢人论证与裁决（2026-09-15）

### C.1 先把用户口径拆开：它并不矛盾

用户口径两句：「**子项目里 docs 不删**」「**整体项目看，文档相关的放到 docs 仓**」。看似冲突，拆开即自洽 —— 关键在于**把"文档"与"生成物"分开**：

| 类别 | 归属 | 理由 |
| --- | --- | --- |
| **手写文档**（设计文档 / Story / ADR / 用户故事 …） | → **`software-distribution-platform-docs` 仓** | 是"知识资产"：跨组件、要单一真源、不随代码二进制变化 |
| **编译必需的生成物**（`docs.go` 等） | → **子仓 + 入库** | 是"构建输入"：被 Go **import 路径**硬引用，挪走或丢失即构建失败；与 runner 的 `zz_generated.deepcopy.go` 同类 |

hub 现状**其实已经在执行第 1 条**（`docs/design/README.md` 只是指向 docs 仓的指针，本仓不留正文）。所以 F-1 要解决的**只是第 2 条**：把"生成物"从"一律忽略 + 可 clean"里**豁免出来**。

### C.2 双向钢人论证

判别标准（避免"各有各的好"式空转）：分**结构性缺陷**（不改就不成立）与**纪律性缺陷**（靠约定能兜住）。

#### 方案 A — 入库（+ clean 默认保留）

**最强支持（steelman）**
- **A1 构建可复现**：新克隆 `go vet/build/test ./...` 直接绿。这是"仓库自洽"的最低门槛，也是 runner 已用实践证明的做法（kubebuilder 惯例：生成物入库）。
- **A2 与 Go 的语义对齐**：`docs.go` 是被 `import` 的**包**，不是"某次构建的副产品"。把它当产物丢弃，等于把源码的一部分当垃圾。
- **A3 零流程成本**：不装 `swag`、不动 `go.sum`、CI 不加前置步骤；改注解后"重生成 + 提交"即可。
- **A4 可 diff**：spec 变化在 PR 里可见（评审价值），而非"各机器各生成各的"。

**最强反对（false-steelman：假设 A 会被怎么攻击）**
- **A5 会漂移**：注解改了忘重生成 → 仓里的 spec 落后于代码，且无人察觉。
- **A6 体积 / diff 污染**：仓库多 ~55KB，`docs.go` 是大段机器生成文本。
- **A7 与既有策略冲突**：2026-09-09 定的"生成物一律忽略 + 可 clean"（当时是用户显式意图）。

#### 方案 B — 不入库，补"可复现再生成"

**最强支持**
- **B1 单一真源在注解**：spec 永远由代码生成，不存"可能过期的副本"（正面回应 A5）。
- **B2 规则无需破例**：`docs/` 就是产物目录，策略保持简单一致。
- **B3 仓干净、diff 干净**（正面回应 A6）。

**最强反对**
- **B4 构建能力被"本机装没装 swag"绑架**：本机实测 `swag` 不在 PATH，`go run github.com/swaggo/swag/cmd/swag` 报 `missing go.sum entry for module providing package github.com/urfave/cli/v2` —— 要让它可复现，必须动 `go.mod`/`go.sum`。**这不是"多一步命令"，是"多一条供应链依赖"**。
- **B5 CI / 新克隆仍要多一步**：`make docs` 必须排在 `build`/`test`/`vet` 之前，否则等价失败只是从"永久红"变成"忘了跑就红"；而 hub CI 现在是三步直跑，引入前置会牵动多个 workflow。
- **B6 它没消掉 A5 关心的问题，只换了个位置**：A5 是"生成物可能过期"，B 是"生成动作可能被遗忘" —— 两者都要纪律，B 还多一个"工具可用性"失败面。
- **B7 报错指不到根因**：缺 `docs.go` 时是 `cmd/hub/main.go:18:2: no required module providing package .../docs`，读起来像"模块路径写错了"，对新人极不友好。

#### 交叉检验（决定性的两条）

| 检验 | A 入库 | B 补再生成 |
| --- | --- | --- |
| **失败模式**：漏做该做的事会怎样？ | 漏重生成 → spec 落后。**可发现**：`swag init` 后 `git diff docs/` 非空即漂移 | 漏跑 `make docs` / 本机没装 swag → **构建直接挂**（hard fail，且报错误导） |
| **能否靠约定兜住？** | **能**：CI 可加一步"重生成后 `git diff --exit-code docs/`"把 A5 变成 gate（可选、非必需） | **不能**：工具可用性在 CI 之外 —— 本地没装 swag 时，"跑一下就行"根本不成立（B4 实测） |

**结论**：A 的缺陷是**纪律性**的（漂移，可用 diff-gate 收口）；B 的缺陷是**结构性**的（构建依赖外部工具可用性 + 需改动多份 workflow），且 B 的"再生成"在**本机当前环境跑不通**（B4）。按「结构性缺陷 ≫ 纪律性缺陷」的排序 → **A 胜**。

### C.3 裁决与不变量

1. **走 A**：`docs/{docs.go,swagger.json,swagger.yaml}` **入库**；`.gitignore` 去掉对应忽略；**`make clean` 默认不删**（`PURGE_DOCS=1` 才删）。
2. **采纳 B 的可用部分**：把 `swag init` 的再生成命令**写进仓**（`hub/README.md`「swaggo API 文档」），并注明"需先装 swag / 补 go.sum 条目"这一前置 —— 从"只活在记忆里"变成"仓里查得到"。**但不把再生成设为 CI 前置**（规避 B4/B5 的代价）。
3. **本次沉淀的通用判据（生成物分岔铁律）**：
   > 生成物是否入库，只看一条 —— **它是不是编译/打包必需输入**。
   > **必需 → 入库**（kubebuilder 惯例：runner 的 `zz_generated.deepcopy.go`、hub 的 `docs.go`）；
   > **纯运行 / 本地便利产物**（`bin/` `output/` `.run/` `dist/`）→ **忽略 + 可 clean**。
4. **文档分工**（用户口径第 2 条）与现状一致，继续执行：**手写文档 → docs 仓**；hub 仓 `docs/` 只留「指针 + 编译必需的生成物」。
5. 由 C.3.3 直接推出 **10.7.3 那条新问题**（在制品源码未入库 = 同类断链），处置权交用户。
