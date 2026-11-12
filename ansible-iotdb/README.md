# Ansible 基线项目 — ubuntu.xiaoxin

把局域网里的 Ubuntu 虚拟机（`fzw-VMware-Virtual-Platform`）作为被管节点 + Ansible 控制节点，
统一管理主机基线、Docker 与 Java 环境。

**Web 界面（Semaphore UI）：http://192.168.100.103:3000** —— 登录 admin，密码见 VM 上 /home/fzw/semaphore/.env 的 SEMAPHORE_ADMIN_PASSWORD。

## 1. 连接信息

| 项 | 值 |
| --- | --- |
| 主机名 | `ubuntu.xiaoxin` |
| 当前 IP | `192.168.100.103`（DHCP，原 hosts 里的 `192.168.100.110` 已失效） |
| 系统 | Ubuntu 26.04 LTS (resolute) / 8C / 7.2G 内存 / 98G 磁盘 |
| 登录用户 | `fzw`（SSH 密钥已配置，免密登录） |
| sudo | 已配置 `NOPASSWD`（`/etc/sudoers.d/90-fzw-nopasswd`） |
| 控制节点 | 就是这台 VM 自己：`ansible-core 2.20.1`（apt 安装） |

> Windows 无法作为 Ansible 控制节点（Ansible 官方不支持 Windows 控制端），
> 因此本机（Windows）只作为**源码编辑器**，通过 `scripts/run.ps1` 同步到 VM 上执行。

## 2. 目录结构

```
ansible.cfg                     # inventory / become / ssh pipelining 等全局配置
inventory/hosts.yml             # 被管节点清单
playbooks/group_vars/all.yml    # 变量：包名、DNS、Docker 镜像加速、Java 版本…
                                # （放 playbook 目录下，本地运行和 Semaphore 运行都能加载）
roles/common/                   # 时区、基础包、DNS、limits、sysctl
roles/docker/                   # docker.io + compose v2、daemon.json、用户组
roles/java/                     # openjdk-17 + JAVA_HOME
playbooks/site.yml              # 全量入口（按 tag 可只跑一部分）
playbooks/verify.yml            # 环境校验，打印现状
scripts/bootstrap.sh            # 一次性引导（sudo 免密 / DNS / ansible-core）
scripts/sync.ps1                # Windows → VM 同步
scripts/run.ps1                 # 同步 + 执行 playbook
```

## 3. 使用方法（在 Windows 本机）

```powershell
# 全量执行
.\scripts\run.ps1

# 只跑某个角色
.\scripts\run.ps1 playbooks/site.yml --tags docker
.\scripts\run.ps1 playbooks/site.yml --tags java

# 校验环境
.\scripts\run.ps1 playbooks/verify.yml

# 语法检查（不落地）
ssh fzw@192.168.100.103 "cd ~/ansible && ansible-playbook playbooks/site.yml --syntax-check"
```

也可以直接登到 VM 上操作：`ssh fzw@192.168.100.103` → `cd ~/ansible` → `ansible-playbook playbooks/site.yml`。

## 4. 已完成的一次性引导（手工，脚本见 `scripts/bootstrap.sh`）

1. **sudo 免密**：写 `/etc/sudoers.d/90-fzw-nopasswd`（`fzw ALL=(ALL) NOPASSWD:ALL`，`visudo -c` 校验通过），
   Ansible `become` 才能无交互提权。
2. **DNS 修正**：网关 `192.168.100.1` 会把 `mirrors.aliyun.com`、`baidu.com` 等 A 记录解析成自己，
   导致 `apt-get update` 连网关 80 端口失败。已用 netplan drop-in（`/etc/netplan/99-dns-override.yaml`）
   关闭 DHCP 下发 DNS，改用 `223.5.5.5 / 119.29.29.29`。
   （ICMP 与出网 TCP 一直是通的，纯粹是 DNS 被劫持。）
3. **ansible-core**：`apt-get install ansible-core python3-apt curl`。

## 5. 已知环境坑

- **Docker Hub 不可达**：`registry-1.docker.io` 连接超时，已在 `group_vars/all.yml` 配置镜像加速
  （`docker.m.daocloud.io` / `docker.1panel.live` / `dockerproxy.net`），写入 `/etc/docker/daemon.json`。
- **docker-ce 不在 Ubuntu 源里**：`resolute` 版本 Docker 官方源尚未覆盖，因此用发行版自带的
  `docker.io 29.1.3` + `docker-compose-v2`（命令为 `docker compose`）。
- **IP 是 DHCP**：如果虚拟机重启后 IP 变化，改 `inventory/hosts.yml` 里的 `ansible_host`，
  或在路由器上做静态绑定 / 在 netplan 里改静态 IP。
- **Windows 的 `C:\Windows\System32\drivers\etc\hosts`** 里 `192.168.100.110 ubuntu.xiaoxin` 已过期，
  建议改成 `192.168.100.103`（需要管理员权限）。

## 6. 后续可扩展

- 把 `common` 里的 limits 用 systemd `LimitNOFILE` 一并覆盖（服务级更可靠）。
- 加 `roles/timecho`（TimechoDB/IoTDB 单机或集群）与 `roles/nginx` 等。
- 增加 `ansible-lint` / `yamllint` 预检（控制节点 `pip install ansible-lint`）。
## 7. Semaphore Web UI（Ansible 图形界面）

| 项 | 值 |
| --- | --- |
| 地址 | http://192.168.100.103:3000 |
| 账号 | admin / 见 VM 上 `/home/fzw/semaphore/.env` |
| 版本 | Semaphore v2.19.17（镜像 `semaphoreui/semaphore:latest`） |
| 数据 | SQLite：`/home/fzw/semaphore/data/database.sqlite`（挂载持久化） |
| 部署文件 | `deploy/semaphore/`：docker-compose.yml、gitconfig、seed.sh |

UI 里已建好项目 **xiaoxin**：

- 清单 `xiaoxin-static`：组 `ubuntu` → 主机 `xiaoxin`，登录用 `/opt/keys/id_ed25519`
- 仓库 `ansible-project`：`file:///opt/ansible`（容器内只读挂载的 `~/ansible` git 仓库）
- 模板：`site.yml / 基线配置`、`verify.yml / 环境体检` —— 点 Run 即可，日志实时可见

注意：

- 容器以 uid 1001 运行，克隆 `~/ansible` 需要 `/etc/gitconfig` 中 `safe.directory = *`（已挂载 `deploy/semaphore/gitconfig`）。
- **改完 playbook 要提交到 VM 的 git 仓库**才会被 Semaphore 看到；`scripts/sync.ps1` 已自动 commit。
- 重置：`cd ~/semaphore && docker compose down && rm -rf data && docker compose up -d`。
- 重建项目/模板：`bash ~/ansible/deploy/semaphore/seed.sh http://127.0.0.1:3000 admin admin@xiaoxin.local <密码>`（幂等）。
## 8. Apache IoTDB 1C1D 模板

`roles/iotdb/` + `playbooks/iotdb.yml`，一条命令装好单机 1C1D（1 ConfigNode + 1 DataNode）并自证可用。

### 8.1 组成

| 文件 | 作用 |
| --- | --- |
| `roles/iotdb/defaults/main.yml` | 版本、镜像、路径、端口、堆内存 |
| `roles/iotdb/tasks/main.yml` | Java 校验 → 建用户/目录 → 下载解压 → 配置 → systemd → 启动 |
| `roles/iotdb/tasks/verify.yml` | 端口等待 → `show cluster` 断言 1C1D Running → 写读闭环 → REST 校验 |
| `roles/iotdb/templates/iotdb.service.j2` | oneshot 单元，`start-standalone.sh` / `stop-standalone.sh` |
| `playbooks/iotdb.yml` | 部署入口 |
| `playbooks/iotdb-verify.yml` | 只读校验入口 |

### 8.2 关键变量（`roles/iotdb/defaults/main.yml`）

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `iotdb_version` | `2.0.11` | 改版本即可升级（数据目录是软链，不随版本丢失） |
| `iotdb_install_dir` | `/opt/iotdb` | 解压到 `apache-iotdb-<ver>-all-bin`，`current` 为软链 |
| `iotdb_data_dir` / `iotdb_log_dir` | `/var/lib/iotdb` / `/var/log/iotdb` | 版本目录下的 `data`、`logs` 软链到这里 |
| `iotdb_rpc_address` | 主机 IPv4 | 影响 `dn_rpc_address` 默认值，**RPC 端口只绑这个地址** |
| `iotdb_rpc_port` | `6667` | DataNode RPC（`dn_rpc_port` 的默认值来源） |
| `iotdb_cn_internal_port` | `10710` | ConfigNode 内部/共识 10720 |
| `iotdb_memory_cn` / `iotdb_memory_dn` | `1G` / `2G` | 写进 `confignode-env.sh` / `datanode-env.sh` 的 `MEMORY_SIZE` |
| `iotdb_enable_rest` / `iotdb_rest_port` | `true` / `18080` | REST 开关/端口（`enable_rest_service`、`rest_service_port` 的默认值来源） |

### 8.2.1 改 `iotdb-system.properties`（键名与配置文件完全一致）

角色用字典 `iotdb_system_properties` 渲染配置文件，**键名 = 配置文件里的原始键名，默认值 = 2.0.11 发行包里的默认值**：

```yaml
iotdb_system_properties:
  cluster_name: defaultCluster
  cn_seed_config_node: "127.0.0.1:{{ iotdb_cn_internal_port }}"
  dn_seed_config_node: "127.0.0.1:{{ iotdb_cn_internal_port }}"
  cn_internal_address: 127.0.0.1
  cn_internal_port: "{{ iotdb_cn_internal_port }}"
  cn_consensus_port: 10720
  dn_rpc_address: "{{ iotdb_rpc_address }}"
  dn_rpc_port: "{{ iotdb_rpc_port }}"
  dn_internal_address: 127.0.0.1
  dn_internal_port: 10730
  dn_mpp_data_exchange_port: 10740
  dn_schema_region_consensus_port: 10750
  dn_data_region_consensus_port: 10760
  schema_replication_factor: 1
  data_replication_factor: 1
  cn_metric_prometheus_reporter_port: 9091
  dn_metric_prometheus_reporter_port: 9092
  enable_rest_service: "{{ iotdb_enable_rest | bool | lower }}"
  rest_service_port: "{{ iotdb_rest_port }}"
# 临时覆盖（不改 defaults 文件）：-e '{"iotdb_system_properties_extra": {"dn_rpc_port": 6668}}'
iotdb_system_properties_extra: {}
```

生效值 = `iotdb_system_properties` + `iotdb_system_properties_extra` 合并；每个键都会用 `lineinfile` 落到
`conf/iotdb-system.properties`（缺键自动追加，多余键保留原样），有变更才触发重启。
`verify.yml` 会**逐项断言变量确实写进了文件**（19 项），并用配置里的实际端口做连通性校验。

示例（把 RPC 改到 6668、REST 改到 18081）：

```powershell
.\scripts\run.ps1 playbooks/iotdb.yml --extra-vars '{"iotdb_system_properties_extra": {"dn_rpc_port": 6668, "rest_service_port": 18081}}'
```

### 8.3 部署与验证

```powershell
.\scripts\run.ps1 playbooks/iotdb.yml          # 部署（幂等）
.\scripts\run.ps1 playbooks/iotdb-verify.yml   # 只读体检
```

Semaphore 里对应模板：`iotdb.yml / IoTDB 1C1D 部署`、`iotdb-verify.yml / IoTDB 校验`。

### 8.4 实测输出

```
IoTDB> show cluster
+------+----------+-------+---------------+------------+-------+---------+
|NodeID|  NodeType| Status|InternalAddress|InternalPort|Version|BuildInfo|
+------+----------+-------+---------------+------------+-------+---------+
|     0|ConfigNode|Running|      127.0.0.1|       10710| 2.0.11|  7c0de06|
|     1|  DataNode|Running|      127.0.0.1|       10730| 2.0.11|  7c0de06|
+------+----------+-------+---------------+------------+-------+---------+
```

角色内断言：服务 active、10710 与 6667 可连、ConfigNode/DataNode 均 Running、
`root.ansible_smoke.d1` 写入 42.0 后可查回、REST `/ping` 200 且 `SHOW DATABASES` 有冒烟库。
重复执行 `changed=0`（幂等）。

### 8.5 运维要点

```bash
systemctl {status,restart,stop} iotdb        # 一条单元管两个 JVM
printf 'show databases\n' | /opt/iotdb/current/sbin/start-cli.sh -h 192.168.100.103 -p 6667 -u root -pw root
curl -s http://192.168.100.103:18080/ping    # {"code":200,"message":"SUCCESS_STATUS"}
```

- 默认账号 `root/root`（Apache 开源版），上生产请改密码并限制 6667 的访问范围。
- REST 返回的字符串值会被掩码成 `********`，做断言时别直接比对完整库名。
- 端口 6667/10710/10720/10730/18080/9091/9092 已随部署开放绑定，防火墙未启用（ufw inactive）。
- 版本升级：改 `iotdb_version` 重跑；旧的 `data`、`logs` 软链会重新指向持久目录。
- **Semaphore 内置 ansible 比控制节点上的旧（容器内 13.5.0 / core 2.19.x，宿主机 core 2.20.1）**：
  模板里不要对注册变量做下标（如 `stderr.splitlines()[0]`），2.19 的惰性容器会报
  `_AnsibleLazyTemplateList object has no element 0`。已改为静态断言文案 + 单独 debug 输出。
### 8.7 彻底卸载（含删除验证）

| 入口 | 作用 |
| --- | --- |
| `playbooks/iotdb-remove.yml` | 卸载 + 立即验证（`roles/iotdb/tasks/remove.yml` → `remove_verify.yml`） |
| `playbooks/iotdb-remove-verify.yml` | 只读校验是否已删净（`remove_verify.yml`） |

执行顺序：停服并禁用自启 → 删除 systemd 单元 + `daemon-reload` → 清理残留 JVM（TERM 15s → KILL） →
等 6667/10710 释放 → 删 `/opt/iotdb`、`/var/lib/iotdb`、`/var/log/iotdb` → 删 `iotdb` 用户/组 → 逐项断言。

开关（默认全部 true，即“彻底删除”）：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `iotdb_remove_install` | `true` | 删 `/opt/iotdb`（含安装包缓存） |
| `iotdb_remove_data` | `true` | 删 `/var/lib/iotdb` |
| `iotdb_remove_logs` | `true` | 删 `/var/log/iotdb` |
| `iotdb_remove_user` | `true` | 删 `iotdb` 用户与组 |

保留数据重装：`-e iotdb_remove_data=false -e iotdb_remove_logs=false`。

验证项：单元文件不存在、服务非 active、无 `org.apache.iotdb` 进程、6667/10710/10720/10730/18080 无监听、
三个目录不存在、用户与组不存在（每项一个 assert，最后打印汇总）。

实测：首次 `ok=28 changed=6 failed=0`；二次 `changed=0`（幂等）；只读校验 `ok=15 failed=0`；
外部 `ss/systemctl/getent/ls` 复核同样干净。Semaphore 模板：`iotdb-remove.yml / IoTDB 彻底删除`、
`iotdb-remove-verify.yml / 删除结果校验`。
## 9. Apache IoTDB 3C3D 集群模板

`roles/iotdb_cluster/` + `playbooks/iotdb-cluster.yml`：一台机器上跑 3 个 ConfigNode + 3 个 DataNode（端口错开），
结构与 1C1D 一致（同样的配置变量机制），只是从单实例变成按清单批量部署。

### 9.1 文件

| 文件 | 作用 |
| --- | --- |
| `roles/iotdb_cluster/defaults/main.yml` | 版本/路径/内存/副本数 + `iotdb_nodes` 节点清单 |
| `roles/iotdb_cluster/tasks/main.yml` | Java 校验 → 用户目录 → 下载解压 → 逐节点部署 → 启动 → 验证 |
| `roles/iotdb_cluster/tasks/node.yml` | 单节点：复制实例目录、软链数据/日志、写配置、断言配置落地、部署 systemd 单元 |
| `roles/iotdb_cluster/tasks/start.yml` / `restart.yml` | 先 CN 后 DN 的顺序启动；配置变更时整体重启 |
| `roles/iotdb_cluster/tasks/verify.yml` | 6 实例 active → 等端口 → `show cluster` 断言 3C3D → 跨节点写读 → REST |
| `roles/iotdb_cluster/templates/iotdb-instance.service.j2` | `Type=simple` 单元（`start-*-node.sh` 默认前台跑 Java） |
| `playbooks/iotdb-cluster.yml` / `iotdb-cluster-verify.yml` | 部署（含验证）/ 只读校验 |

### 9.2 拓扑与端口

| 实例 | 类型 | 内部端口 | 其它 |
| --- | --- | --- | --- |
| cn1 / cn2 / cn3 | ConfigNode | 10710 / 10711 / 10712 | 共识 10720/10721/10722，指标 9091-9093 |
| dn1 / dn2 / dn3 | DataNode | 10730 / 10731 / 10732 | RPC 6667/6668/6669，MPP 10740+，共识 10750+/10760+ |

数据 `/var/lib/iotdb-cluster/<实例>`，日志 `/var/log/iotdb-cluster/<实例>`，实例目录 `/opt/iotdb-cluster/nodes/<实例>`；
单实例单元 `iotdb-cn1` … `iotdb-dn3`（6 个）。

### 9.3 配置变量（与配置文件键名一致）

`iotdb_system_properties` 是**所有节点共用**的配置，默认：

```yaml
iotdb_system_properties:
  cluster_name: cluster_3c3d
  cn_seed_config_node: "{{ iotdb_seed_host }}:{{ iotdb_seed_cn_port }}"
  dn_seed_config_node: "{{ iotdb_seed_host }}:{{ iotdb_seed_cn_port }}"
  schema_replication_factor: 3
  data_replication_factor: 3
  enable_rest_service: "false"      # 仅 dn1 通过 extra 打开
  rest_service_port: 18080
```

每个节点再叠加 `iotdb_nodes[].ports`（自己的端口）和 `iotdb_nodes[].extra`（节点级覆盖），
最终值 = `iotdb_system_properties` + `iotdb_system_properties_extra` + 节点 ports + 节点 extra + 类型对应地址。
`node.yml` 写完配置后会**逐项断言** `key=value` 确实在文件里。

改配置三种方式：

```powershell
# 1) 临时全局覆盖（会触发整体重启）
.\scripts\run.ps1 playbooks/iotdb-cluster.yml --extra-vars '{"iotdb_system_properties_extra": {"schema_replication_factor": 2}}'
# 2) 长期：改 roles/iotdb_cluster/defaults/main.yml 里的 iotdb_system_properties
# 3) 单节点：改 iotdb_nodes 里该节点的 ports / extra
```

### 9.4 实测

```
+------+----------+-------+---------------+------------+-------+---------+
|     0|ConfigNode|Running|192.168.100.103|       10710| 2.0.11|  7c0de06|
|     3|ConfigNode|Running|192.168.100.103|       10711| 2.0.11|  7c0de06|
|     4|ConfigNode|Running|192.168.100.103|       10712| 2.0.11|  7c0de06|
|     1|  DataNode|Running|192.168.100.103|       10730| 2.0.11|  7c0de06|
|     2|  DataNode|Running|192.168.100.103|       10731| 2.0.11|  7c0de06|
|     5|  DataNode|Running|192.168.100.103|       10732| 2.0.11|  7c0de06|
+------+----------+-------+---------------+------------+-------+---------+
Total line number = 6
```

- 首次部署 `ok=83 changed=17 failed=0`；二次 `changed=0`（幂等）。
- 跨节点写读：dn1(6667) 写入 `root.ansible_smoke.d1`，dn2(6668) 读回 42.0。
- 配置变量演示：`schema_replication_factor` 3→2 时 6 个节点配置全部改写并整体重启，集群仍 6 节点 Running；
  再跑默认值恢复为 3，同样验证通过。
- 资源：6 JVM 常驻约 3.5G（CN 堆 512M、DN 堆 768M），7.2G 内存的机器可用余量约 3.7G。

### 9.5 注意事项

- `start-confignode.sh` / `start-datanode.sh` **默认前台 exec java**，所以单元必须用 `Type=simple`；
  用 oneshot 会一直卡住直到 `TimeoutStartSec` 超时（已踩过）。
- 单机多实例时所有节点必须绑定主机网卡地址（`iotdb_rpc_address`），不能用 127.0.0.1，否则节点间无法互访。
- 真·多机 3C3D：把 `iotdb_nodes` 拆成每台机器一份、`hosts` 里加 3 台主机即可；
  当前实现是单机多实例（因为只有一台可用主机），端口/目录隔离方式可直接复用。
### 9.6 彻底卸载（含删除验证）

| 入口 | 作用 |
| --- | --- |
| `playbooks/iotdb-cluster-remove.yml` | 卸载 + 立即验证（`roles/iotdb_cluster/tasks/remove.yml` → `remove_verify.yml`） |
| `playbooks/iotdb-cluster-remove-verify.yml` | 只读校验是否删净（`remove_verify.yml`） |

执行顺序：逆序（dn3→dn1→cn3→cn1）停服并禁用 → `reset-failed` → 删 6 个单元 + `daemon-reload` →
清理残留 JVM（`pkill -f 'iotdb[-]cluster/nodes'`，先 TERM 后 KILL） → 等 7 个端口释放 →
删 `/opt/iotdb-cluster`、`/var/lib/iotdb-cluster`、`/var/log/iotdb-cluster` → 删 `iotdb` 用户/组 → 逐项断言。

开关（默认全 true）：`iotdb_remove_install` / `iotdb_remove_data` / `iotdb_remove_logs` / `iotdb_remove_user`。
**安全保护**：若检测到 1C1D 的 `/opt/iotdb` 仍存在，会自动跳过删除 `iotdb` 用户/组（避免误伤另一套实例）。

验证项：6 个单元文件消失、无实例 active、无残留进程、7 个端口（10710-10712/6667-6669/18080）无监听、
三个目录不存在、用户与组不存在；最后打印汇总。

实测：首次 `ok=31 changed=4 failed=0`；二次 `changed=0`（幂等）；只读校验 `ok=17 failed=0`；
外部 `ls/systemctl/getent/ss` 复核同样干净，内存从 3.5G 回落（free 3.2G / available 5.6G）。
Semaphore 模板：`iotdb-cluster-remove.yml / 3C3D 彻底删除`、`iotdb-cluster-remove-verify.yml / 3C3D 删除校验`。

踩坑记录：`pkill -f '/opt/iotdb-cluster/nodes/'` 会匹配到 ansible 自己的 shell 命令而自杀（rc=-15），
改用 `pkill -f 'iotdb[-]cluster/nodes'` 规避自匹配；`systemctl is-active` 返回 `inactive` 时不能断言
`'active' not in stdout`（子串误判），改用 `regex_findall('=active')` 精确判断。
## 10. 指定版本安装

两个角色都用 `iotdb_version` 这一个变量控制版本（默认 `2.0.11`），下载 URL、解压目录、
systemd 单元、集群实例目录全部随它派生：

```powershell
# 1C1D 装 2.0.10
.\scripts\run.ps1 playbooks/iotdb.yml --extra-vars "iotdb_version=2.0.10"

# 3C3D 装 2.0.10
.\scripts\run.ps1 playbooks/iotdb-cluster.yml --extra-vars "iotdb_version=2.0.10"
```

Semaphore 里在模板 Run 对话框的 Arguments 填 `-e iotdb_version=2.0.10` 即可。

| 关注点 | 行为 |
| --- | --- |
| 可用版本 | 清华镜像现有 `0.13.4 / 1.3.7 / 2.0.10 / 2.0.11`；其它版本自动回落到 `archive.apache.org` |
| 版本限制 | 只支持 **2.x**；指定 1.3/0.13 会被版本守卫直接拦下（配置文件名/布局不同） |
| 1C1D 升级 | 新版本解压到 `apache-iotdb-<ver>-all-bin`，`current` 软链切换；`/var/lib/iotdb` 数据保留 |
| 3C3D 升级 | 实例目录内有 `.iotdb_version` 标记，版本变化时自动重建实例目录并重启，`/var/lib/iotdb-cluster` 数据保留 |
| 磁盘 | 旧版本目录不会自动删除（1C1D 两个版本约 471M），确认无误后手工 `rm -rf /opt/iotdb/apache-iotdb-<旧版本>-all-bin` |

注意：**1C1D 与 3C3D 不能同时跑**（都占 6667/10710）。集群角色已内置前置检查，
检测到 `iotdb.service` active 会直接报错并提示先 `systemctl stop iotdb` 或整体偏移端口。

实测（本次）：

| 场景 | 结果 |
| --- | --- |
| `-e iotdb_version=1.3.7` | 守卫拦截：`本模板基于 2.x 的 iotdb-system.properties 布局` |
| `-e iotdb_version=2.0.10` 1C1D | `ok=45 changed=16 failed=0`，`show version` = 2.0.10 (3c26382) |
| 再装 2.0.11（升级） | `current` 切到 2.0.11，2.0.10 时建的 `root.ansible_smoke` 数据仍在 |
| 集群 `-e iotdb_version=2.0.10` | 6 节点 Running，版本均为 2.0.10，6 个实例标记均为 2.0.10 |
| 集群删除后恢复 1C1D | 清理 `ok=30 failed=0`，`systemctl start iotdb` 后 2.0.11 正常运行 |
## 11. 1C1D 版本升级

| 入口 | 作用 |
| --- | --- |
| `playbooks/iotdb-upgrade.yml` | 升级 + 版本/数据校验 + 失败自动回滚（`roles/iotdb/tasks/upgrade.yml`） |

```powershell
.\scripts\run.ps1 playbooks/iotdb-upgrade.yml --extra-vars "iotdb_version=2.0.11"
# 或 Semaphore 模板「iotdb-upgrade.yml / IoTDB 1C1D 升级」，Run 时 Arguments 填 -e iotdb_version=2.0.11
```

升级流程：读当前版本 → 方向校验（默认禁止降级）→ 前置检查（数据目录、磁盘余量）→ 记录现有数据库列表 →
停服并等端口释放 → 下载/解压新版本 → 对新版本目录重放配置（内存、properties、单元）→ 切 `current` 软链 →
启动 → **断言运行版本 = 目标版本** → 通用验证（集群 Running、写读、REST）→ **断言升级前的库都还在**。
任一步失败 → 自动把 `current` 切回旧版本并重启（回滚），最后抛出失败提示。

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `iotdb_version` | `2.0.11` | 目标版本 |
| `iotdb_allow_downgrade` | `false` | 目标低于当前时需显式置 true |
| `iotdb_upgrade_keep_old` | `true` | 保留旧版本目录；置 false 升级成功后自动删除 |
| `iotdb_upgrade_min_free_gb` | `2` | 升级前磁盘可用空间下限（GB） |

实测（本次）：

| 场景 | 结果 |
| --- | --- |
| 已是目标版本再跑 | `当前已是 2.0.11，无需升级`，`changed=0` |
| 目标低于当前（2.0.11 → 2.0.10） | 直接拦截：`确需降级请加 -e iotdb_allow_downgrade=true` |
| 2.0.10 → 2.0.11 正式升级 | `ok=63 changed=12 failed=0`，`运行版本已切换为 2.0.11`，`数据保留：root.ansible_smoke` |
| 模拟失败回滚 | 升级后 DN 未就绪 → 自动回滚到 2.0.10（日志：`升级失败已回滚`），服务恢复 |

踩坑修复：1C1D 之前用发行包的 `start-standalone.sh`（内部固定 `sleep 3` 再起 DataNode），
机器慢时 DataNode 会抢在 ConfigNode 就绪前启动并报 `Fail to connect to any config node` 后退出。
现改为角色自带的 `/usr/local/bin/iotdb-start.sh`：先起 ConfigNode，**轮询端口就绪**后再起 DataNode，
systemd 单元改 `Type=simple` 托管该包装脚本（旧版本目录升级时也会重新渲染）。
## 12. 3C3D 集群升级

| 入口 | 作用 |
| --- | --- |
| `playbooks/iotdb-cluster-upgrade.yml` | 集群升级 + 版本/数据校验 + 失败自动回滚（`roles/iotdb_cluster/tasks/upgrade.yml`） |

```powershell
# 1C1D 必须先停（占 6667/10710，角色内有前置检查）
ssh fzw@192.168.100.103 "sudo systemctl stop iotdb"   # 若装了 1C1D
.\scripts\run.ps1 playbooks/iotdb-cluster-upgrade.yml --extra-vars "iotdb_version=2.0.11"
# Semaphore：模板 #12「iotdb-cluster-upgrade.yml / 3C3D 升级」
```

流程：读 `cn1/.iotdb_version` → 方向校验（默认禁止降级）→ 前置检查（数据目录、磁盘 ≥2G）→ 记录现有库 →
逆序停 6 实例并等端口释放 → 下载/解压新发行包 → **逐节点快照**（`nodes/<n>` → `nodes/<n>.prev`，mv 瞬时完成）
并用新版本重建实例目录 + 重放该节点配置 → `daemon-reload` → 按序启动（CN→DN）→ 验证：
6 节点 Running 且版本=目标、升级前库都还在、dn1 写 dn3 读、通用集群验证 → 删除 `.prev` 快照。
任一步失败 → 用 `.prev` 快照秒级回滚并重启旧集群，然后抛错。

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `iotdb_version` | `2.0.11` | 目标版本 |
| `iotdb_allow_downgrade` | `false` | 目标低于当前需显式置 true |
| `iotdb_upgrade_keep_old` | `true` | 保留旧版本发行包目录（实例快照成功后必删） |
| `iotdb_upgrade_min_free_gb` | `2` | 升级前磁盘余量下限；6 个实例快照约占 1.4G |

实测（本次）：

| 场景 | 结果 |
| --- | --- |
| 3C3D@2.0.10 → 2.0.11 | `ok=157 changed=36 failed=0 rescued=0`，6 节点全 `2.0.11` |
| 版本断言 | `3C3D 已运行在 2.0.11`（表格 Version 列 6 行均为 2.0.11） |
| 数据保留 | `数据保留：root.ansible_smoke`（schema/data 副本仍 3/3） |
| 跨节点写读 | `dn1 写、dn3 读回 42.0`；通用校验里 `dn1 写、dn2 读回 42.0` |
| 幂等 | 同版本再跑：`集群当前已是 2.0.11，无需升级`，`changed=0` |
| 实例标记 | `cn1..dn3` 的 `.iotdb_version` 全部变为 `2.0.11` |

踩坑：集群 `iotdb_system_properties` 默认字典里**没有** `dn_rpc_address`（地址是每节点在 `node.yml` 里叠加的），
升级脚本里不能写 `iotdb_system_properties.dn_rpc_address`，直接用 `iotdb_rpc_address`。
