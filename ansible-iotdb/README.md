**English** | [简体中文](README-zh.md)

# Apache IoTDB Ansible Playbooks

Ansible automation for **Apache IoTDB 2.x**: `1C1D` (one ConfigNode + one DataNode) and `3C3D`
(three-replica cluster) — installation, post-deploy self-check, version upgrade (with automatic
rollback), and complete uninstall. Optional Semaphore web UI on top.

## 1. Support Matrix

| Scenario | Role | Entry playbook |
| --- | --- | --- |
| Host baseline (timezone / DNS / limits / sysctl) | `roles/common` | `playbooks/site.yml` |
| Docker + Compose v2 | `roles/docker` | same (`--tags docker`) |
| JDK 17 + JAVA_HOME | `roles/java` | same (`--tags java`) |
| 1C1D install / verify / upgrade / uninstall | `roles/iotdb` | `playbooks/iotdb.yml` etc. |
| 3C3D install / verify / upgrade / uninstall | `roles/iotdb_cluster` | `playbooks/iotdb-cluster.yml` etc. |

The IoTDB version is controlled by the single variable `iotdb_version` (default `2.0.11`).
Only **2.x** is supported (configuration layout is `iotdb-system.properties`).

## 2. Requirements

| Item | Requirement |
| --- | --- |
| Control node | Linux / macOS, `ansible-core >= 2.15` (tested with 2.16, 2.19 and 2.20); on Windows use WSL or log in to a Linux host |
| Managed node | Debian/Ubuntu family (`apt`) with systemd, at least 5 GB free on the root filesystem |
| Dependencies | `python3`, JDK 17+, usable `sudo` (passwordless recommended, otherwise pass `-K`) |
| Network | Reachable Apache mirror; Tsinghua mirror is used by default, with fallback to `archive.apache.org` |

## 3. Layout

```
ansible.cfg                       # inventory / become / ssh pipelining
inventory/hosts.yml               # managed hosts
playbooks/group_vars/all.yml      # baseline vars (packages, DNS, docker mirrors, JDK)
playbooks/                        # 12 entry points
roles/common|docker|java/         # host baseline
roles/iotdb/                      # 1C1D
roles/iotdb_cluster/              # 3C3D
deploy/semaphore/                 # optional: Semaphore UI (compose + idempotent seeding)
scripts/                          # bootstrap.sh / sync.ps1 / run.ps1
```

## 4. Quick Start

### 4.1 Inventory

```yaml
all:
  children:
    ubuntu:                # keep this group name: playbooks use "hosts: ubuntu"
      hosts:
        node1:
          ansible_host: 10.0.0.11
          ansible_user: iotdb-admin
          ansible_ssh_private_key_file: ~/.ssh/id_rsa
          ansible_python_interpreter: /usr/bin/python3
```

### 4.2 Run

```bash
ansible-playbook playbooks/site.yml             # host baseline (optional)
ansible-playbook playbooks/iotdb.yml            # 1C1D install + self-check
ansible-playbook playbooks/iotdb-cluster.yml    # 3C3D install + self-check
ansible-playbook playbooks/iotdb-verify.yml     # 1C1D read-only verification
ansible-playbook playbooks/iotdb-cluster-verify.yml
```

Pick a version with `-e iotdb_version=2.0.10`.

### 4.3 Command Reference

| Goal | Command |
| --- | --- |
| 1C1D install | `playbooks/iotdb.yml` |
| 1C1D verify | `playbooks/iotdb-verify.yml` |
| 1C1D upgrade | `playbooks/iotdb-upgrade.yml -e iotdb_version=<x.y.z>` |
| 1C1D uninstall | `playbooks/iotdb-remove.yml` (read-only: `iotdb-remove-verify.yml`) |
| 3C3D install | `playbooks/iotdb-cluster.yml` |
| 3C3D verify | `playbooks/iotdb-cluster-verify.yml` |
| 3C3D upgrade | `playbooks/iotdb-cluster-upgrade.yml -e iotdb_version=<x.y.z>` |
| 3C3D uninstall | `playbooks/iotdb-cluster-remove.yml` (read-only: `iotdb-cluster-remove-verify.yml`) |

## 5. 1C1D (roles/iotdb)

### 5.1 On-disk layout

| Path | Content |
| --- | --- |
| `/opt/iotdb/apache-iotdb-<ver>-all-bin` | one directory per version |
| `/opt/iotdb/current` | symlink to the active version (switched on upgrade) |
| `/var/lib/iotdb` | data (`data` inside the version dir links here) |
| `/var/log/iotdb` | logs (`logs` symlink) |
| `/usr/local/bin/iotdb-start.sh` | start wrapper: waits for the ConfigNode port before starting the DataNode |
| Unit | `iotdb.service` (`Type=simple`) |

### 5.2 Key variables

| Variable | Default | Description |
| --- | --- | --- |
| `iotdb_version` | `2.0.11` | target version |
| `iotdb_install_dir` | `/opt/iotdb` | install root |
| `iotdb_data_dir` / `iotdb_log_dir` | `/var/lib/iotdb` / `/var/log/iotdb` | persistent data / logs |
| `iotdb_rpc_address` | host IPv4 | written to `dn_rpc_address`; RPC binds this address only |
| `iotdb_rpc_port` | `6667` | DataNode RPC |
| `iotdb_cn_internal_port` | `10710` | ConfigNode internal port (consensus 10720) |
| `iotdb_memory_cn` / `iotdb_memory_dn` | `1G` / `2G` | `MEMORY_SIZE` |
| `iotdb_enable_rest` / `iotdb_rest_port` | `true` / `18080` | REST switch / port |
| `iotdb_remove_*` | all true | what to delete during uninstall (install / data / logs / user) |

### 5.3 Configuration management

Keys in `iotdb_system_properties` **match `conf/iotdb-system.properties` exactly** and default to
the values shipped in the distribution. Each entry is applied with `lineinfile` (missing keys are
appended) and only triggers a restart when something changes. Temporary override:

```bash
ansible-playbook playbooks/iotdb.yml -e '{"iotdb_system_properties_extra": {"dn_rpc_port": 6668}}'
```

## 6. 3C3D (roles/iotdb_cluster)

By default all six instances run on **one host** with distinct ports (handy for single-machine
validation). For a real multi-host cluster, split `iotdb_nodes` across hosts — every instance
already has its own directory and port set.

| Instance | Ports |
| --- | --- |
| cn1 / cn2 / cn3 | 10710 / 10711 / 10712 (consensus 10720+, metrics 9091-9093) |
| dn1 / dn2 / dn3 | RPC 6667 / 6668 / 6669 (internal 10730+, MPP 10740+, consensus 10750+/10760+) |

Layout: `/opt/iotdb-cluster/{apache-iotdb-<ver>-all-bin, nodes/<instance>, packages}`,
data `/var/lib/iotdb-cluster/<instance>`, logs `/var/log/iotdb-cluster/<instance>`,
units `iotdb-cn1` … `iotdb-dn3`.

Configuration uses the same `iotdb_system_properties` (shared) plus per-node `ports` / `extra`;
addresses are filled in by the role according to the node type.

> 1C1D and 3C3D use the same default ports and cannot run together. The cluster role checks this
> up front and tells you to stop 1C1D or shift the ports.

## 7. Upgrades

| Scenario | Mechanism | Variables |
| --- | --- | --- |
| 1C1D | unpack the new version → switch the `current` symlink → re-apply config → restart; on failure the symlink is switched back | `iotdb_upgrade_keep_old`, `iotdb_allow_downgrade` |
| 3C3D | each instance is moved to a `.prev` snapshot → rebuilt from the new distribution → restarted; on failure the snapshot is restored in seconds | same |

Both enforce: version direction (downgrades blocked by default), free-disk check, a snapshot of the
database list taken before the upgrade and compared afterwards, an assertion that the running
version equals the target, and the full verification suite (topology + read/write + REST).

## 8. Uninstall

`playbooks/iotdb-remove.yml` / `playbooks/iotdb-cluster-remove.yml`:
stop services and remove units → kill leftover JVMs → delete directories → remove the user/group →
assert everything is gone (unit, state, processes, ports, directories, account).

Keep data for a reinstall: `-e iotdb_remove_data=false -e iotdb_remove_logs=false`.
If another deployment is still present (e.g. the 1C1D install directory exists), the `iotdb`
user is kept automatically.

## 9. Semaphore UI (optional)

`deploy/semaphore/` ships a compose file (SQLite persistence), a `gitconfig` (for git
`safe.directory` inside the container) and an idempotent `seed.sh` that creates the project,
inventory, repository and templates. Notes:

- the container runs as non-root (uid 1001); cloning a repository owned by the host user requires
  `/etc/gitconfig` to allow `safe.directory`
- the playbook repository is mounted read-only as `file:///opt/ansible`, so changes must be committed first
- the admin account is initialised from `SEMAPHORE_ADMIN*` in `.env`

## 10. Verification Design

Every playbook asserts instead of trusting the exit code:

- service: unit active / all instances Running
- topology: row count and node types from `show cluster` (2 rows for 1C1D, 6 for 3C3D)
- configuration: every `key=value` really written to `iotdb-system.properties`
- data: write/read round-trip (`root.ansible_smoke.d1` → 42.0), plus database-list comparison on upgrade
- channels: REST `/ping` returns 200 and `/rest/v1/query` answers
- idempotency: a second run must report `changed=0`

## 11. Known Pitfalls (all handled in code)

1. **`start-standalone.sh` ships a fixed `sleep 3`** — on a busy machine the DataNode starts before
   the ConfigNode is ready and exits with `Fail to connect to any config node`. The role ships
   `iotdb-start.sh`, which polls the ConfigNode port first.
2. **`pkill -f` also matches the shell running it** (kills itself, rc=-15) — use the
   `iotdb[-]cluster` trick to avoid self-matching.
3. **`systemctl is-active` returning `inactive` breaks `'active' not in stdout`** (substring match) —
   assert with `regex_findall('=active')` instead.
4. **Ansible 2.19 lazy containers do not support indexing** (`stderr.splitlines()[0]` raises
   `_AnsibleLazyTemplateList`) — keep assertion messages static and print values separately.
5. **Cluster `iotdb_system_properties` has no `dn_rpc_address`** (filled per node) — use
   `iotdb_rpc_address` in scripts.
6. **1C1D and 3C3D share default ports** — the cluster role checks whether `iotdb.service` is active.
7. **Docker Hub is unreachable from some networks** — `roles/docker` writes a configurable
   `registry-mirrors` list (`docker_registry_mirrors`) into `daemon.json`.

## 12. Versioning & License

- Versioning: single `iotdb_version` variable; old version directories are kept
  (`iotdb_upgrade_keep_old`) for rollback and comparison.
- License: Apache License 2.0, see `LICENSE` at the repository root.
