#!/usr/bin/env bash
# 在 Semaphore 里创建项目/清单/仓库/模板（幂等：已存在则跳过）
# 用法：bash seed.sh [base_url] [admin_user] [admin_email] [admin_password]
set -euo pipefail

BASE="${1:-http://127.0.0.1:3000}"
USER="${2:-admin}"
EMAIL="${3:-admin@xiaoxin.local}"
PW="${4:-}"
JAR=$(mktemp)
trap 'rm -f "$JAR"' EXIT

login() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -c "$JAR" -X POST "$BASE/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"auth\":\"$USER\",\"email\":\"$EMAIL\",\"password\":\"$PW\"}")
  [ "$code" = "204" ] || { echo "login failed ($code)"; exit 1; }
}

api() { curl -s -b "$JAR" -H 'Content-Type: application/json' "$@"; }

login

# 1) 项目（type 必须给 ansible，否则子资源接口 404）
PID=$(api "$BASE/api/projects" | jq -r '[.[] | select(.name=="xiaoxin")][0].id // empty')
if [ -z "$PID" ]; then
  PID=$(api -X POST "$BASE/api/projects" -d '{"name":"xiaoxin","alert":true,"max_parallel_tasks":0,"type":"ansible"}' | jq -r '.id')
  echo "project created: $PID"
else
  echo "project exists: $PID"
fi

# 2) key（inventory/repository 的 ssh_key_id 必须指向已存在的 key，0 会 404）
KID=$(api "$BASE/api/project/$PID/keys" | jq -r '[.[] | select(.name=="none")][0].id // empty')
if [ -z "$KID" ]; then
  KID=$(api -X POST "$BASE/api/project/$PID/keys" \
        -d "{\"name\":\"none\",\"project_id\":$PID,\"type\":\"none\",\"secret\":\"\"}" | jq -r '.id')
  echo "key created: $KID"
fi

# 3) 静态清单
INV=$(api "$BASE/api/project/$PID/inventory" | jq -r '[.[] | select(.name=="xiaoxin-static")][0].id // empty')
if [ -z "$INV" ]; then
  cat > /tmp/sem_inv.yml <<'EOF'
all:
  children:
    ubuntu:
      hosts:
        xiaoxin:
          ansible_host: 192.168.100.103
          ansible_user: fzw
          ansible_ssh_private_key_file: /opt/keys/id_ed25519
          ansible_python_interpreter: /usr/bin/python3
EOF
  INV=$(jq -n --rawfile inv /tmp/sem_inv.yml --argjson pid "$PID" --argjson kid "$KID" \
        '{name:"xiaoxin-static",project_id:$pid,type:"static-yaml",inventory:$inv,ssh_key_id:$kid,become_key_id:$kid}' |
        api -X POST "$BASE/api/project/$PID/inventory" -d @- | jq -r '.id')
  echo "inventory created: $INV"
fi

# 4) playbook 仓库（容器内只读挂载的 git 仓库）
RID=$(api "$BASE/api/project/$PID/repositories" | jq -r '[.[] | select(.name=="ansible-project")][0].id // empty')
if [ -z "$RID" ]; then
  RID=$(jq -n --argjson pid "$PID" --argjson kid "$KID" \
        '{name:"ansible-project",project_id:$pid,git_url:"file:///opt/ansible",git_branch:"main",ssh_key_id:$kid}' |
        api -X POST "$BASE/api/project/$PID/repositories" -d @- | jq -r '.id')
  echo "repository created: $RID"
fi

# 5) 环境
EID=$(api "$BASE/api/project/$PID/environment" | jq -r '[.[] | select(.name=="default")][0].id // empty')
if [ -z "$EID" ]; then
  EID=$(api -X POST "$BASE/api/project/$PID/environment" \
        -d "{\"name\":\"default\",\"project_id\":$PID,\"json\":\"{}\",\"env\":\"{}\"}" | jq -r '.id')
  echo "environment created: $EID"
fi

# 6) 模板
mk_tpl() {
  local name="$1" pb="$2" desc="$3"
  local exists
  exists=$(api "$BASE/api/project/$PID/templates" | jq -r "[.[] | select(.name==\"$name\")][0].id // empty")
  [ -n "$exists" ] && { echo "template exists: $name ($exists)"; return; }
  jq -n --argjson pid "$PID" --argjson inv "$INV" --argjson rid "$RID" --argjson eid "$EID" \
     --arg name "$name" --arg pb "$pb" --arg desc "$desc" \
     '{name:$name,project_id:$pid,inventory_id:$inv,repository_id:$rid,environment_id:$eid,
       app:"ansible",playbook:$pb,arguments:"[]",description:$desc,
       allow_override_args_in_task:true,survey_vars:[],autorun:false,type:""}' |
     api -X POST "$BASE/api/project/$PID/templates" -d @- | jq -r '.id' |
     xargs -I{} echo "template created: $name ({})"
}
mk_tpl "site.yml / 基线配置" "playbooks/site.yml" "common + docker + java"
mk_tpl "verify.yml / 环境体检" "playbooks/verify.yml" "打印 OS/docker/java/dns/limits 现状"
mk_tpl "iotdb.yml / IoTDB 1C1D 部署" "playbooks/iotdb.yml" "Apache IoTDB 2.0.11 单机 1C1D，含部署后验证"
mk_tpl "iotdb-verify.yml / IoTDB 校验" "playbooks/iotdb-verify.yml" "只读校验 IoTDB 1C1D 集群与读写"
mk_tpl "iotdb-upgrade.yml / IoTDB 1C1D 升级" "playbooks/iotdb-upgrade.yml" "升级到指定版本，含版本断言、数据校验与失败回滚"
mk_tpl "iotdb-remove.yml / IoTDB 彻底删除" "playbooks/iotdb-remove.yml" "停服删单元、清数据与安装目录、删用户，并断言已删净"
mk_tpl "iotdb-remove-verify.yml / 删除结果校验" "playbooks/iotdb-remove-verify.yml" "只读校验 IoTDB 是否已彻底删除"
mk_tpl "iotdb-cluster.yml / IoTDB 3C3D 部署" "playbooks/iotdb-cluster.yml" "单机多实例 3C3D 集群，含配置变量与部署后验证"
mk_tpl "iotdb-cluster-verify.yml / 3C3D 校验" "playbooks/iotdb-cluster-verify.yml" "只读校验 3C3D 拓扑、跨节点读写、REST"
mk_tpl "iotdb-cluster-upgrade.yml / 3C3D 升级" "playbooks/iotdb-cluster-upgrade.yml" "快照式滚动升级，含版本断言、数据校验与失败回滚"
mk_tpl "iotdb-cluster-remove.yml / 3C3D 彻底删除" "playbooks/iotdb-cluster-remove.yml" "停 6 实例、删单元与目录、删用户，并断言已删净"
mk_tpl "iotdb-cluster-remove-verify.yml / 3C3D 删除校验" "playbooks/iotdb-cluster-remove-verify.yml" "只读校验 3C3D 是否已彻底删除"

echo "done. open $BASE with project id $PID"
