# 同步并执行 playbook（在控制节点上运行 ansible-playbook）
# 用法： .\scripts\run.ps1                                   # 全量
#        .\scripts\run.ps1 playbooks/site.yml --tags docker   # 只跑 docker
#        .\scripts\run.ps1 playbooks/verify.yml               # 校验
param(
    [string]$Playbook = 'playbooks/site.yml',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Extra
)
$ErrorActionPreference = 'Stop'
$Target = 'iotdb-admin@iotdb-node1'
$sshOpts = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=10')

& (Join-Path $PSScriptRoot 'sync.ps1') -Target $Target

$remoteCmd = 'cd ~/ansible && ansible-playbook ' + $Playbook
if ($Extra) { $remoteCmd += ' ' + ($Extra -join ' ') }

Write-Host ("[run] " + $remoteCmd)
ssh @sshOpts $Target $remoteCmd
exit $LASTEXITCODE
