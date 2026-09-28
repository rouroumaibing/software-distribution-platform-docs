# 平台 TLS 证书（统一生成与引用契约）

> 单一真源：本文档（`docs/shared/CERTIFICATES.md`）是平台**自身 TLS** 证书的生成源与引用契约的权威说明。
> 任何关于“证书在哪生成、被谁引用、如何替换”的疑问，以本文为准。

## 1. 定位

- `env/cert-build/cert-create.sh` 生成的证书是**商用 CA 证书申请之前的替代证书**（dev / staging / 本地联调占位）。
  真实 PKI 证书到位后，运维**手工创建同名 secret 替换**即可（secret 名与 key 名不变，组件无感）。
- **严格范围**：只管**平台自身 TLS**，绝不签发 / 触碰租户 `kubeconfig` 内嵌的 CA / client-cert
  （那些由用户自带，平台只做结构校验 + AES-GCM 信封加密存储，见 hub `internal/credentials`）。
- 与参考工程 `old/go-devops` 一致：**组件镜像与交付包不携带任何证书或私钥**；
  生产由运维手工建 secret，chart 只按 `secretName` 引用。`cert-create.sh` 是“没有 PKI 时的统一兜底”。

## 2. 生成器

- 源（单一真源）：`software-distribution-platform-env/cert-build/cert-create.sh`
- 行为：自签 CA（3650d）+ 由 CA 签发 server 证书（825d，SAN 覆盖 `console.<ns>.svc` 链 +
  `www.sdpworkflow.com` + `localhost` + `127.0.0.1`）。
- 部署期调用（本地）：`deploy-local.sh` 在 TLS 前置阶段直接运行源脚本 `cert-create.sh`（脚本按自身位置定位 `self-signed-ca-cert.sh` 与产物目录）；
  也可随 env 归档分发到目标环境后运行。
- 产物目录 `CERTS_DIR`（默认脚本同级 `output/`）。`--local-only` 只生成文件、不碰集群。
- 幂等：CA 文件已存在则复用；secret 已存在则 `kubectl apply` 更新。

## 3. 消费契约（secret 名 / key / 用途 / 状态）

| Secret | 类型 / key | 生成方 | 消费方（引用点） | 状态 |
| --- | --- | --- | --- | --- |
| `console-tls` | generic: `ca.crt` / `server.crt` / `server.key` | cert-create.sh | ① console nginx 443 挂载 `/etc/nginx/ssl`（console chart `deployment.yaml` + `cert.secretName`）<br>② console `BackendTLSPolicy` 校验后端证书（`gatewayRoute.caSecretName`）<br>③ **hub `auth.trustedCASecret` 出站信任 issuer**（复用同一 `ca.crt`，`deployment-hub.yaml` 挂 `/etc/sdp-ca` + `SSL_CERT_FILE`）<br>④ console nginx 现已只服务前端 SPA，不再反代 `/api`（`/api` 由网关 hub 独立 HTTPRoute 承接，见 hub chart `templates/httproute.yaml`） | 复用同一 CA，统一核心；本地部署已由 `deploy-local.sh --set auth.trustedCASecret=console-tls` 接上 |
| `console-ingress-tls` | tls: `tls.crt` / `tls.key`（= 同一 server 证书） | cert-create.sh | Gateway **https listener** 终结外部 HTTPS（`local-kind-dev/deploy/gateway-sdp.yaml` 的 `certificateRefs`） | 仍被消费，**非废弃** |

> 历史说明：`console-ingress-tls` 命名源自早期 ingress-nginx 时代；网关切到 Envoy Gateway 后，
> 该 secret 改由 `local-kind-dev/deploy/gateway-sdp.yaml` 的 Gateway **https listener** 引用（console chart 已无 ingress 模板）。
> 改名易让人误判其无用 —— **勿删**。

> **hub 独立路由（2026-09-28 网关拆分）**：hub 对外 API 经 hub chart 的 `templates/httproute.yaml`
> （PathPrefix `/api` → hub svc:8080，ClusterIP 明文后端），与 console 的 `PathPrefix /` 拆为**两条独立路由**；
> 浏览器 `https://www.sdpworkflow.com:8443/api/v1/...` 由网关直连 hub，不再经 console nginx 反代。
> hub service 由 `NodePort` 改为 `ClusterIP`（不再对外直连）；`local-kind-dev/deploy/kind.yaml` 中 hub 直连的 `30080` 映射已移除。

## 4. 分发与创建 secret

**方式 A — 本地部署（deploy-local.sh 自动）**：脚本在 TLS 前置阶段**直接运行源脚本** `cert-create.sh`
（脚本按自身位置定位 `self-signed-ca-cert.sh` 与产物目录），末尾自动 `kubectl apply` 两个 secret
（`console-tls` / `console-ingress-tls`，幂等；CA 文件已存在则复用，保证证书链一致）。

**方式 B — 目标环境无 env 仓时手工执行**：

1. 把 `software-distribution-platform-env/cert-build/cert-create.sh` 拷到目标环境某目录（如 `/opt/sdp/cert/`）。
2. 生成证书目录：
   ```bash
   bash cert-create.sh --local-only [namespace]   # 默认命名空间 sdp-workflow
   # 产出 <dir>/output/{ca.crt, server.crt, server.key}（私钥权限 600）
   ```
3. 用 kubectl 引用该目录创建 secret（与生成器末尾 `apply` 等价）：
   ```bash
   kubectl -n sdp-workflow create secret generic console-tls \
       --from-file=ca.crt=output/ca.crt \
       --from-file=server.crt=output/server.crt \
       --from-file=server.key=output/server.key
   kubectl -n sdp-workflow create secret tls console-ingress-tls \
       --cert output/server.crt --key output/server.key
   ```
4. （本地部署）hub 出站信任：确保 hub chart `auth.trustedCASecret=console-tls`
   （复用 `console-tls` 的 `ca.crt`，**无需单独创建 secret**）。生产用公共 CA 时留空。

## 5. 商用证书替换（从自签切到真实 PKI）

自签证书仅为占位。拿到真实证书后，用真实文件**覆盖同名 secret** 即可，组件无需改动
（secret 名 / key 名契约不变，chart 仍按 `secretName` 引用）。

前置：从 CA 取得
- 服务端证书 `server.crt`（含完整链；如有中间证书请合并进同一文件）
- 服务端私钥 `server.key`
- 信任 CA（根 / 中间）`ca.crt`（用于校验 issuer / 后端 mTLS 校验）

步骤：

1. 重建 `console-tls`（generic，key 名不变 `ca.crt` / `server.crt` / `server.key`）：
   ```bash
   kubectl -n sdp-workflow create secret generic console-tls \
       --from-file=ca.crt=<真实CA路径>/ca.crt \
       --from-file=server.crt=<真实server证书路径>/server.crt \
       --from-file=server.key=<真实server私钥路径>/server.key \
       --dry-run=client -o yaml | kubectl apply -f -
   ```
2. 重建 `console-ingress-tls`（tls 类型，证书 + 私钥）：
   ```bash
   kubectl -n sdp-workflow create secret tls console-ingress-tls \
       --cert <真实server证书路径>/server.crt \
       --key <真实server私钥路径>/server.key \
       --dry-run=client -o yaml | kubectl apply -f -
   ```
3. 让挂载生效（chart 未强制 secret hash 滚动）：
   ```bash
   kubectl -n sdp-workflow rollout restart deploy/console deploy/hub
   ```
4. hub 出站信任：
   - 真实证书由**公共 CA** 签发 → hub chart `auth.trustedCASecret` 留空（Go 用系统信任池即可）；
   - 真实证书由**私有 CA** 签发 → 把其 `ca.crt` 单独建 secret 并设 `auth.trustedCASecret=<该 secret>`（复用 `console-tls` 的 `ca.crt` 亦可，只要同一 CA）。
5. 浏览器 / 客户端：重新信任新 `ca.crt`（若非公共 CA）；旧自签 `ca.crt` 指纹变化，已信任旧证书者需清理。

> ⚠️ 真实 server 证书 **SAN 必须覆盖 `www.sdpworkflow.com`**（及集群内 svc FQDN，若保留集群内访问），
> 否则 Gateway / nginx 报证书名不匹配（TLS handshake / x509 unknown authority）。

## 6. 已修正的历史漂移（本次 consolidat​ion 一并修复）

- `console/scripts/cert-create.sh` 注释称 `console-ingress-tls` 用于 “ingress 终结 TLS”
  → 实际由 `local-kind-dev/deploy/gateway-sdp.yaml` 的 Gateway https listener 引用（console chart 已无 ingress 模板）。
  脚本已**迁移至 `env/cert-build`** 并改正注释。
- console chart `values.yaml` 注释称 `frontGateway.tlsSecretName` 引用
  → 全仓无此 value，实际引用点是 `local-kind-dev/deploy/gateway-sdp.yaml:certificateRefs`。已改正。
- console `README.md` 引用 `templates/ingress.yaml`（已删）与 `ingress.tlsSecretName`（无此 key）→ 已改正。

### 2026-09-28 网关拆分 + 证书命名对齐 + 脚本迁移（本轮 consolidation）
- **网关拆分**：console nginx 不再反代 `/api` 到 hub；hub 拥有独立 `HTTPRoute`（`hub` chart `templates/httproute.yaml`，`PathPrefix /api` → hub svc:8080，ClusterIP 明文后端），与 console 拆为两条独立路由。hub `service.yaml` 由 `NodePort` 改 `ClusterIP`（不再对外直连）；`local-kind-dev/deploy/kind.yaml` 移除 hub 直连 `30080` 映射；`local-kind-dev/deploy/gateway-sdp.yaml` / `local-kind-dev/deploy/kind.yaml` 注释同步。前端 `baseUrl` 维持相对 `/api/v1`（经网关直连 hub，无需重建镜像）。
- **脚本迁移**：根目录 5 个本地联调脚本（`deploy-` / `teardown-` / `undeploy-` / `stop-` / `clean-local.sh`）迁至 `software-distribution-platform-env/local-kind-dev/`；本地测试基础设施 `deploy/`（gateway-sdp.yaml / kind.yaml / envoy tgz）一并迁入 `local-kind-dev/deploy/`（随 env 仓跟踪，envoy `.tgz` 已 gitignore）。脚本 `ROOT` 重定义为上两级、互调用改 `$SCRIPT_DIR`；证书生成器引用由 `gen-certs.sh` 修正为 `cert-create.sh`；`undeploy-local.sh` 命名空间 `sdp-system`→`sdp-workflow` 修正。

## 7. 密钥轮换 / 过期

- CA 3650d、server 825d。轮换时在生成器目录重跑（复用已有 CA 或一并重签），再 `kubectl apply` 更新两个 secret；
  或按 §5 用真实证书覆盖。
- 集群内挂载是否自动滚动取决于 chart 是否用 secret hash 注解触发重启；当前 console / hub 未强制，
  必要时手动 `kubectl -n sdp-workflow rollout restart deploy/console deploy/hub`。
