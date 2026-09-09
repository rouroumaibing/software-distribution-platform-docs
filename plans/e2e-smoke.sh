#!/usr/bin/env bash
# e2e-smoke.sh — 按页面真实操作顺序冒烟测试全部前端 API（经 console ingress = 浏览器同路径）。
# console 已从 NodePort(8081) 改为 ClusterIP + ingress（kind 8443->443），自签证书用 curl -k。
set -u
BASE="https://localhost:8443/api/v1"
CURL="curl -sk"
PASS=0; FAIL=0
req() { # method path body
  local m="$1" p="$2" b="${3:-}"
  local out code
  if [ -n "$b" ]; then
    out=$($CURL -w "\n%{http_code}" -X "$m" "$BASE$p" -H 'Content-Type: application/json' -d "$b")
  else
    out=$($CURL -w "\n%{http_code}" -X "$m" "$BASE$p")
  fi
  code="${out##*$'\n'}"; body="${out%$'\n'*}"
  if [[ "$code" =~ ^2 ]]; then PASS=$((PASS+1)); echo "PASS $code $m $p" >&2
  else FAIL=$((FAIL+1)); echo "FAIL $code $m $p  << ${body:0:200}" >&2; fi
  echo "$body"
}
jqf() { python3 -c "import sys,json;d=json.load(sys.stdin);print(eval(sys.argv[1]))" "$1" 2>/dev/null; }

TS=$(date +%s)
echo "===== 1) 组织 / 服务树 ====="
R=$(req POST "/orgs" "{\"name\":\"E2E冒烟$TS\",\"slug\":\"e2e-smoke-$TS\"}")
ORG=$(echo "$R" | jqf "d['data']['id']")
R=$(req GET  "/orgs?page=1&pageSize=100");            echo "$R" | jqf "len(d['data']['items'])" >/dev/null
R=$(req GET  "/orgs/$ORG")
R=$(req GET  "/orgs/$ORG/service-tree")
TREE=$(echo "$R" | jqf "d['data']['id']")
R=$(req GET  "/service-trees/$TREE/services?page=1&pageSize=100")

echo "===== 2) 服务 / 组件 ====="
R=$(req POST "/services" "{\"serviceTreeId\":\"$TREE\",\"key\":\"e2e-svc\",\"name\":\"E2E服务\"}")
SVC=$(echo "$R" | jqf "d['data']['id']")
R=$(req GET  "/services/$SVC")
R=$(req GET  "/services/$SVC/components?page=1&pageSize=100")
R=$(req POST "/components" "{\"serviceId\":\"$SVC\",\"key\":\"e2e-comp\",\"name\":\"E2E组件\",\"repoUrl\":\"https://example.com/e2e.git\",\"defaultBranch\":\"main\"}")
COMP=$(echo "$R" | jqf "d['data']['id']")
R=$(req GET  "/components/$COMP")

echo "===== 3) 环境 ====="
R=$(req GET  "/clusters?page=1&pageSize=100")
CLUS=$(echo "$R" | jqf "(d['data']['items'] or [{}])[0].get('id','')")
R=$(req GET  "/components/$COMP/environments?page=1&pageSize=100")
R=$(req POST "/environments" "{\"componentId\":\"$COMP\",\"key\":\"e2e-env\",\"name\":\"E2E环境\",\"envType\":\"dev\",\"clusterId\":\"$CLUS\",\"namespace\":\"e2e\"}")

echo "===== 4) 流水线 / 阶段 / 任务 ====="
R=$(req GET  "/components/$COMP/pipelines?page=1&pageSize=100")
R=$(req POST "/pipelines" "{\"componentId\":\"$COMP\",\"name\":\"E2E流水线$TS\",\"kind\":\"build\"}")
PIPE=$(echo "$R" | jqf "d['data']['id']")
R=$(req GET  "/pipelines/$PIPE")
R=$(req POST "/pipelines/$PIPE/stages" "{\"name\":\"build-stage\",\"sortOrder\":1}")
STAGE=$(echo "$R" | jqf "d['data']['id']")
R=$(req GET  "/pipelines/$PIPE/stages")
R=$(req POST "/stages/$STAGE/tasks" "{\"name\":\"echo-task\",\"type\":\"Build\",\"image\":\"busybox\",\"command\":[\"echo\"],\"args\":[\"e2e\"],\"displayOrder\":1}")
TASK=$(echo "$R" | jqf "d['data']['id']")
R=$(req GET  "/stages/$STAGE/tasks")
R=$(req PUT  "/tasks/$TASK" "{\"name\":\"echo-task\",\"type\":\"Build\",\"image\":\"busybox\",\"command\":[\"echo\"],\"args\":[\"e2e-v2\"],\"displayOrder\":1}")

echo "===== 5) 运行 ====="
R=$(req POST "/pipelines/$PIPE/runs" "{}")
RUN=$(echo "$R" | jqf "d['data']['id']")
[ -n "$RUN" ] && [ "$RUN" != "None" ] && {
  req GET "/runs/$RUN"
  req GET "/runs/$RUN/tasks"
}

echo "===== 6) 权限 ====="
req GET "/users?page=1&pageSize=100"
req GET "/roles"
req GET "/components/$COMP/role-bindings"

echo "===== 7) 清理 ====="
[ -n "${TASK:-}" ] && req DELETE "/tasks/$TASK" >/dev/null
req DELETE "/pipelines/$PIPE"
req DELETE "/environments/$(req GET "/components/$COMP/environments?page=1&pageSize=100" | jqf "d['data']['items'][0]['id']")" >/dev/null
req DELETE "/components/$COMP"
req DELETE "/services/$SVC"
req DELETE "/orgs/$ORG"

echo "=============================="
echo "RESULT: PASS=$PASS FAIL=$FAIL"
