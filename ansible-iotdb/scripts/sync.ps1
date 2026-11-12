# 将本项目同步到控制节点的 ~/ansible（按需修改 $Target）
param(
    [string]$Target = 'iotdb-admin@iotdb-node1',
    [string]$RemoteDir = 'ansible'
)
$ErrorActionPreference = 'Stop'
$sshOpts = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=10')
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

Push-Location $root
try {
    ssh @sshOpts $Target "mkdir -p ~/$RemoteDir"
    if ($LASTEXITCODE -ne 0) { throw "ssh mkdir failed ($LASTEXITCODE)" }

    $items = @('ansible.cfg', 'inventory', 'roles', 'playbooks', 'scripts', 'deploy', 'README.md', 'README-zh.md') |
        Where-Object { Test-Path $_ }
    scp @sshOpts -r -q $items ($Target + ':~/' + $RemoteDir + '/')
    if ($LASTEXITCODE -ne 0) { throw "scp failed ($LASTEXITCODE)" }

    Write-Host ("[sync] " + $root + " -> " + $Target + ":~/" + $RemoteDir + "  OK")

    # Semaphore 从 VM 上的 git 仓库克隆 playbook，所以同步后要提交一次
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $commit = "cd ~/" + $RemoteDir + " && git add -A && git -c user.name='Ansible Sync' -c user.email='sync@example.com' commit -q -m 'sync " + $stamp + "'"
    ssh @sshOpts $Target $commit 2>&1 | Out-Null
    Write-Host "[sync] committed to git on VM"
}
finally {
    Pop-Location
}