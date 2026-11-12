[English](README.md) | **简体中文**

# Apache IoTDB Ansible 模板

用 Ansible 管理 **Apache IoTDB 2.x** 的 `1C1D`（单 ConfigNode + 单 DataNode）与 `3C3D`（三副本集群）：
安装、部署后自检、版本升级（含失败回滚）、彻底卸载。可选配套 Semaphore Web UI。

## 1. 支持矩阵

| 场景 | 角色 | 入口 playbook |
| --- | --- | --- |
| 主机基线（时区/DNS/limits/sysctl） | `roles/common` | `playbooks/site.yml` |
| Docker + Compose v2 | `roles/docker` | 同上（`--tags docker`） |
| JDK 17 + JAVA_HOME | `roles/java` | 同上（`--tags java`） |
| 1C1D 安装/校验/升级/卸载 | `roles/iotdb` | `playbooks/iotdb.yml` 等 |
| 3C3D 安装/校验/升级/卸载 | `roles/iotdb_cluster` | `playbooks/iotdb-cluster.yml` 等 |

IoTDB 版本通过变量 `iotdb_version` 指定（默认 `2.0.11`），只支持 **2.x**（配置布局为 `iotdb-system.properties`）。

## 2. 环境要求

| 项 | 要求 |
| --- | --- |
| 控制节点 | Linux / macOS，`ansible-core >= 2.15`（本项目在 2.19、2.20 实测）；Windows 可经 WSL 或登录一台 Linux 执行 |
| 被管节点 | Debian/Ubuntu 系（使用 `apt`）+ systemd，根分区预留 ≥ 5G |
| 依赖 | `python3`、JDK 17+、可用 `sudo`（建议免密，否则 `-K` 输入） |
| 网络 | 可访问 Apache 镜像；默认清华镜像，失败自动回落 `archive.apache.org` |

## 3. 目录结构

```
ansible.cfg                       # inventory / become / ssh pipelining
inventory/hosts.yml               # 被管节点清单
playbooks/group_vars/all.yml      # 主机基线变量（包名、DNS、Docker 镜像加速、JDK 版本）
playbooks/                        # 12 个入口
roles/common|docker|java/         # 主机基线
roles/iotdb/                      # 1C1D
roles/iotdb_cluster/              # 3C3D
deploy/semaphore/                 # 可选：Semaphore Web UI（compose + 幂等 seed 脚本）
scripts/                          # bootstrap.sh / sync.ps1 / run.ps1（Windows 侧同步执行）
```

## 4. 快速开始

### 4.1 编辑清单

```yaml
all:
  children:
    ubuntu:                # 分组名保持 ubuntu，playbook 里 hosts: ubuntu
      hosts:
        node1:
          ansible_host: 10.0.0.11
          ansible_user: iotdb-admin
          ansible_ssh_private_key_file: ~/.ssh/id_rsa
          ansible_python_interpreter: /usr/bin/python3
```

### 4.2 执行

```bash
ansible-playbook playbooks/site.yml             # 主机基线（可选）
ansible-playbook playbooks/iotdb.yml            # 1C1D 安装 + 自检
ansible-playbook playbooks/iotdb-cluster.yml    # 3C3D 安装 + 自检
ansible-playbook playbooks/iotdb-verify.yml     # 1C1D 只读校验
ansible-playbook playbooks/iotdb-cluster-verify.yml
```

指定版本：`-e iotdb_version=2.0.10`。

### 4.3 命令总览

| 目的 | 命令 |
| --- | --- |
| 1C1D 安装 | `playbooks/iotdb.yml` |
| 1C1D 校验 | `playbooks/iotdb-verify.yml` |
| 1C1D 升级 | `playbooks/iotdb-upgrade.yml -e iotdb_version=<x.y.z>` |
| 1C1D 卸载 | `playbooks/iotdb-remove.yml` / 只读校验 `iotdb-remove-verify.yml` |
| 3C3D 安装 | `playbooks/iotdb-cluster.yml` |
| 3C3D 校验 | `playbooks/iotdb-cluster-verify.yml` |
| 3C3D 升级 | `playbooks/iotdb-cluster-upgrade.yml -e iotdb_version=<x.y.z>` |
| 3C3D 卸载 | `playbooks/iotdb-cluster-remove.yml` / 只读校验 `iotdb-cluster-remove-verify.yml` |

## 5. 1C1D（roles/iotdb）

### 5.1 安装布局

| 路径 | 内容 |
| --- | --- |
| `/opt/iotdb/apache-iotdb-<ver>-all-bin` | 每个版本一个目录 |
| `/opt/iotdb/current` | 软链，指向当前版本（升级时切换） |
| `/var/lib/iotdb` | 数据（版本目录下 `data` 软链到这里） |
| `/var/log/iotdb` | 日志（`logs` 软链） |
| `/usr/local/bin/iotdb-start.sh` | 启动包装：等 ConfigNode 端口就绪后再起 DataNode |
| 单元 | `iotdb.service`（`Type=simple`） |

### 5.2 主要变量

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `iotdb_version` | `2.0.11` | 目标版本 |
| `iotdb_install_dir` | `/opt/iotdb` | 安装根目录 |
| `iotdb_data_dir` / `iotdb_log_dir` | `/var/lib/iotdb` / `/var/log/iotdb` | 持久化数据/日志 |
| `iotdb_rpc_address` | 主机 IPv4 | 写入 `dn_rpc_address`，RPC 只绑该地址 |
| `iotdb_rpc_port` | `6667` | DataNode RPC |
| `iotdb_cn_internal_port` | `10710` | ConfigNode 内部端口（共识 10720） |
| `iotdb_memory_cn` / `iotdb_memory_dn` | `1G` / `2G` | `MEMORY_SIZE` |
| `iotdb_enable_rest` / `iotdb_rest_port` | `true` / `18080` | REST 开关/端口 |
| `iotdb_remove_*` | 全部 true | 卸载时是否删安装/数据/日志/用户 |

### 5.3 配置管理

`iotdb_system_properties` 的**键名与 `conf/iotdb-system.properties` 完全一致**，默认值取自发行包；
每项通过 `lineinfile` 落到配置文件（缺键自动追加），有变更才重启。临时覆盖：

```bash
ansible-playbook playbooks/iotdb.yml -e '{"iotdb_system_properties_extra": {"dn_rpc_port": 6668}}'
```

## 6. 3C3D（roles/iotdb_cluster）

默认在**同一台机器**上起 3 个 ConfigNode + 3 个 DataNode（端口错开），适合单机验证；
多机部署时把 `iotdb_nodes` 按主机拆分即可（每个实例独立目录与端口）。

| 实例 | 端口 |
| --- | --- |
| cn1 / cn2 / cn3 | 10710 / 10711 / 10712（共识 10720+，指标 9091-9093） |
| dn1 / dn2 / dn3 | RPC 6667 / 6668 / 6669（内部 10730+，MPP 10740+，共识 10750+/10760+） |

布局：`/opt/iotdb-cluster/{apache-iotdb-<ver>-all-bin, nodes/<实例>, packages}`，
数据 `/var/lib/iotdb-cluster/<实例>`，日志 `/var/log/iotdb-cluster/<实例>`，单元 `iotdb-cn1` … `iotdb-dn3`。

配置同样走 `iotdb_system_properties`（公共）+ 节点级 `ports` / `extra`（地址由角色按节点类型补齐）。

> 1C1D 与 3C3D 默认端口相同，不能同时运行；集群角色有前置检查，会提示先停 1C1D 或偏移端口。

## 7. 升级

| 场景 | 机制 | 变量 |
| --- | --- | --- |
| 1C1D | 解压新版本 → 切换 `current` 软链 → 重放配置 → 重启；失败把 `current` 切回旧版本 | `iotdb_upgrade_keep_old`、`iotdb_allow_downgrade` |
| 3C3D | 每个实例先 `mv` 成 `.prev` 快照 → 用新版本重建目录 → 重启；失败用快照秒级回滚 | 同上 |

两者都会：校验版本方向（默认禁止降级）、检查磁盘余量、记录升级前数据库列表并逐项比对、
断言运行版本等于目标版本、跑通用校验（拓扑 + 写读 + REST）。

## 8. 卸载

`playbooks/iotdb-remove.yml` / `playbooks/iotdb-cluster-remove.yml`：
停服删单元 → 清理残留 JVM → 删目录 → 删用户/组 → 逐项断言（单元、状态、进程、端口、目录、用户）。

保留数据重装：`-e iotdb_remove_data=false -e iotdb_remove_logs=false`。
若检测到另一套实例仍在（1C1D 的安装目录存在），会自动跳过删除 `iotdb` 用户。

## 9. Semaphore Web UI（可选）

`deploy/semaphore/` 提供 compose（SQLite 持久化）、`gitconfig`（容器内 git `safe.directory`）
和幂等 `seed.sh`（建项目/清单/仓库/模板）。要点：

- 容器以非 root（uid 1001）运行，克隆宿主机上的 playbook 仓库需要 `/etc/gitconfig` 放开 `safe.directory`
- playbook 仓库用 `file:///opt/ansible` 只读挂载，改完需先 `git commit`
- 管理员账号由 `.env` 里的 `SEMAPHORE_ADMIN*` 初始化

## 10. 验证设计

每个 playbook 都带断言而不是只看退出码：

- 服务：单元 active / 全部实例 Running
- 拓扑：`show cluster` 行数与类型（1C1D=2 行，3C3D=6 行）
- 配置：逐项断言 `key=value` 已写入 `iotdb-system.properties`
- 数据：写读闭环（`root.ansible_smoke.d1` 写入后查回 42.0），升级时比对升级前数据库列表
- 通道：REST `/ping` 200 + `/rest/v1/query` 可查询
- 幂等：重复执行应为 `changed=0`

## 11. 已知坑（都已在代码里规避）

1. **发行包 `start-standalone.sh` 里固定 `sleep 3`**，机器忙时 DataNode 会抢在 ConfigNode 就绪前启动并报
   `Fail to connect to any config node` 后退出 → 改用自带 `iotdb-start.sh` 轮询端口后再起 DataNode。
2. **`pkill -f` 会匹配到执行它的 shell 自身**（自杀，rc=-15）→ 用 `iotdb[-]cluster` 这种写法规避。
3. **`systemctl is-active` 返回 `inactive` 时不能断言 `'active' not in stdout`**（子串误判）→ 改 `regex_findall('=active')`。
4. **Ansible 2.19 的惰性容器不支持下标**（`stderr.splitlines()[0]` 报 `_AnsibleLazyTemplateList`）→ 断言文案改静态，值单独 debug。
5. **集群 `iotdb_system_properties` 里没有 `dn_rpc_address`**（地址按节点补齐）→ 脚本里直接用 `iotdb_rpc_address`。
6. **1C1D 与 3C3D 端口冲突** → 集群角色启动前检查 `iotdb.service` 是否 active。
7. **Docker Hub 在部分网络不可达** → `roles/docker` 的 `daemon.json` 支持配置镜像加速（`docker_registry_mirrors`）。

## 12. 版本与许可

- 版本策略：`iotdb_version` 单一变量；升级保留旧版本目录（`iotdb_upgrade_keep_old`）便于回滚/对比。
- 许可：Apache License 2.0，见仓库根目录 `LICENSE`。
