<#
.SYNOPSIS
    批量检测 Azure China PostgreSQL/MySQL Flexible Server CA 证书轮换状态。

.DESCRIPTION
    通过 openssl 连接每台服务器，解析证书链中的根 CA，判断是否已完成
    DigiCert Global Root G2 轮换。支持 az CLI 列表和 CSV 文件两种输入模式，
    支持并行检测、CSV 报告导出。

.EXAMPLE
    .\Check-CaRotation.ps1 -Type mysql
    .\Check-CaRotation.ps1 -File servers.csv -Output report.csv
    .\Check-CaRotation.ps1 -AllSubscriptions -Parallel 20 -Output report.csv
#>

param(
    [string]$File,
    [ValidateSet('mysql','postgres','all')]
    [string]$Type = 'all',
    [string]$Subscription,
    [switch]$AllSubscriptions,
    [ValidateRange(1, 2147483647)]
    [int]$Parallel = 10,
    [string]$Output,
    [switch]$Help
)

$ErrorActionPreference = 'Continue'

# ─── Help ────────────────────────────────────────────────────────────────────
if ($Help) {
    Write-Host @"

用法: .\Check-CaRotation.ps1 [参数]

参数:
  -File <path>          从 CSV 文件读取服务器列表 (列: server_name,type)
  -Type <mysql|postgres|all>  服务器类型筛选 (默认 all)
  -Subscription <id>    指定 Azure 订阅
  -AllSubscriptions     遍历所有已启用订阅
  -Parallel <n>         并行数 (默认 10)
  -Output <path>        导出 CSV 报告路径
  -Help                 显示此帮助

示例:
  .\Check-CaRotation.ps1 -Type mysql
  .\Check-CaRotation.ps1 -File servers.csv -Output report.csv
  .\Check-CaRotation.ps1 -AllSubscriptions -Parallel 20

"@ -ForegroundColor Cyan
    return
}

# ─── Test-Prerequisites ──────────────────────────────────────────────────────
function Test-Prerequisites {
    # Check openssl
    $opensslCmd = Get-Command openssl -ErrorAction SilentlyContinue
    if (-not $opensslCmd) {
        Write-Host "❌ 未找到 openssl，请先安装:" -ForegroundColor Red
        Write-Host "   Windows: winget install ShiningLight.OpenSSL 或 choco install openssl" -ForegroundColor Yellow
        Write-Host "   Linux:   sudo apt install openssl / sudo yum install openssl" -ForegroundColor Yellow
        return $false
    }

    # Parse openssl version
    $versionOutput = & openssl version 2>&1
    $versionString = "$versionOutput"
    # Match patterns like "OpenSSL 1.1.1" or "OpenSSL 3.0.2" or "LibreSSL 3.3.6"
    if ($versionString -match '(\d+)\.(\d+)\.(\d+)') {
        $major = [int]$Matches[1]
        $minor = [int]$Matches[2]
        if ($versionString -match 'LibreSSL') {
            # LibreSSL 2.x+ generally supports starttls
            Write-Host "ℹ️  检测到 $versionString (LibreSSL，starttls 支持可能有限)" -ForegroundColor Yellow
        }
        elseif ($major -lt 1 -or ($major -eq 1 -and $minor -lt 1)) {
            Write-Host "❌ openssl 版本过低: $versionString (需要 >= 1.1.0)" -ForegroundColor Red
            Write-Host "   需要 openssl >= 1.1.0 以支持 -starttls mysql 和 -starttls postgres" -ForegroundColor Yellow
            Write-Host "   Windows: winget install ShiningLight.OpenSSL 或 choco install openssl" -ForegroundColor Yellow
            return $false
        }
        else {
            Write-Host "✅ openssl: $versionString" -ForegroundColor Green
        }
    }
    else {
        Write-Host "⚠️ 无法解析 openssl 版本: $versionString，继续执行..." -ForegroundColor Yellow
    }

    $hasResolveDns = Get-Command Resolve-DnsName -ErrorAction SilentlyContinue
    $hasNslookup = Get-Command nslookup -ErrorAction SilentlyContinue
    if (-not $hasResolveDns -and -not $hasNslookup) {
        Write-Host "❌ 未找到 DNS 解析命令，请安装 nslookup 或在支持 Resolve-DnsName 的环境中运行。" -ForegroundColor Red
        return $false
    }

    return $true
}

# ─── Test-AzPrerequisites ────────────────────────────────────────────────────
function Test-AzPrerequisites {
    param(
        [string]$TargetSubscription,
        [switch]$CheckAllSubs
    )

    # Check az CLI installed
    $azCmd = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azCmd) {
        Write-Host "❌ 未找到 az CLI，请先安装:" -ForegroundColor Red
        Write-Host "   winget install Microsoft.AzureCLI" -ForegroundColor Yellow
        return $false
    }

    # Check login status
    $accountJson = az account show 2>&1
    $accountStr = "$accountJson"
    if ($accountStr -match 'ERROR' -or $accountStr -match 'Please run' -or $LASTEXITCODE -ne 0) {
        Write-Host "❌ 未登录 Azure CLI，请先执行:" -ForegroundColor Red
        Write-Host "   az cloud set --name AzureChinaCloud" -ForegroundColor Yellow
        Write-Host "   az login" -ForegroundColor Yellow
        return $false
    }

    # Parse account info
    try {
        $account = $accountJson | ConvertFrom-Json
    }
    catch {
        Write-Host "❌ 无法解析 az account show 输出" -ForegroundColor Red
        return $false
    }

    # Check environment
    $envName = $account.environmentName
    if ($envName -ne 'AzureChinaCloud') {
        Write-Host "⚠️ 当前 az CLI 环境为 $envName，非 AzureChinaCloud" -ForegroundColor Yellow
        Write-Host "   请执行: az cloud set --name AzureChinaCloud && az login" -ForegroundColor Yellow
    }

    # Set subscription if specified
    if ($TargetSubscription) {
        Write-Host "📌 切换订阅: $TargetSubscription" -ForegroundColor Cyan
        az account set -s $TargetSubscription 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ 无法切换到订阅: $TargetSubscription" -ForegroundColor Red
            return $false
        }
        # Re-read account info
        $accountJson = az account show 2>&1
        $account = $accountJson | ConvertFrom-Json
    }

    if (-not $CheckAllSubs) {
        Write-Host "📌 当前订阅: $($account.name) ($($account.id))" -ForegroundColor Cyan
    }

    return $true
}

# ─── Get-ServersFromAz ───────────────────────────────────────────────────────
function Get-ServersFromAz {
    param(
        [string]$ServerType,
        [string]$SubscriptionName = ''
    )

    $servers = @()

    if ($ServerType -eq 'all' -or $ServerType -eq 'mysql') {
        Write-Host "  🔍 查询 MySQL Flexible Server..." -ForegroundColor Gray
        $mysqlRaw = az mysql flexible-server list --query "[].name" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and $mysqlRaw) {
            $mysqlNames = ($mysqlRaw -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            foreach ($name in $mysqlNames) {
                $servers += [PSCustomObject]@{
                    server_name  = $name
                    type         = 'mysql'
                    subscription = $SubscriptionName
                }
            }
            Write-Host "    找到 $($mysqlNames.Count) 台 MySQL 服务器" -ForegroundColor Gray
        }
        else {
            Write-Host "    未找到 MySQL Flexible Server 或查询出错" -ForegroundColor Gray
        }
    }

    if ($ServerType -eq 'all' -or $ServerType -eq 'postgres') {
        Write-Host "  🔍 查询 PostgreSQL Flexible Server..." -ForegroundColor Gray
        $pgRaw = az postgres flexible-server list --query "[].name" -o tsv 2>&1
        if ($LASTEXITCODE -eq 0 -and $pgRaw) {
            $pgNames = ($pgRaw -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            foreach ($name in $pgNames) {
                $servers += [PSCustomObject]@{
                    server_name  = $name
                    type         = 'postgres'
                    subscription = $SubscriptionName
                }
            }
            Write-Host "    找到 $($pgNames.Count) 台 PostgreSQL 服务器" -ForegroundColor Gray
        }
        else {
            Write-Host "    未找到 PostgreSQL Flexible Server 或查询出错" -ForegroundColor Gray
        }
    }

    return $servers
}

# ─── Get-ServersFromFile ─────────────────────────────────────────────────────
function Get-ServersFromFile {
    param(
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        Write-Host "❌ 文件不存在: $FilePath" -ForegroundColor Red
        return @()
    }

    $csv = Import-Csv -Path $FilePath
    if (@($csv).Count -eq 0) {
        Write-Host "❌ CSV 文件为空或仅包含表头: $FilePath" -ForegroundColor Red
        return @()
    }

    # Validate columns
    $columns = @($csv)[0].PSObject.Properties.Name
    if ('server_name' -notin $columns -or 'type' -notin $columns) {
        Write-Host "❌ CSV 文件格式错误，需要包含列: server_name, type" -ForegroundColor Red
        Write-Host "   当前列: $($columns -join ', ')" -ForegroundColor Yellow
        return @()
    }

    $servers = @()
    foreach ($row in $csv) {
        $sType = $row.type.Trim().ToLower()
        if ($sType -notin @('mysql', 'postgres')) {
            Write-Host "⚠️ 跳过无效类型: $($row.server_name) ($sType)" -ForegroundColor Yellow
            continue
        }
        $servers += [PSCustomObject]@{
            server_name  = $row.server_name.Trim()
            type         = $sType
            subscription = ''
        }
    }

    return $servers
}

# ─── Test-SingleServer ───────────────────────────────────────────────────────
function Test-SingleServer {
    param(
        [string]$ServerName,
        [string]$ServerType,
        [string]$SubscriptionName = ''
    )

    # Build FQDN and port
    if ($ServerType -eq 'mysql') {
        $fqdn = "$ServerName.mysql.database.chinacloudapi.cn"
        $port = 3306
        $starttls = 'mysql'
        $typeLabel = 'MySQL'
    }
    else {
        $fqdn = "$ServerName.postgres.database.chinacloudapi.cn"
        $port = 5432
        $starttls = 'postgres'
        $typeLabel = 'PostgreSQL'
    }

    $result = [PSCustomObject]@{
        subscription    = $SubscriptionName
        server_name     = $ServerName
        type            = $typeLabel
        fqdn            = "${fqdn}:${port}"
        status          = ''
        root_ca         = ''
        intermediate_ca = ''
        cert_not_after  = ''
    }

    # ── DNS Resolution ──
    $dnsResolved = $false
    $isPrivateLink = $false

    # Try Resolve-DnsName first (Windows)
    $hasResolveDns = Get-Command Resolve-DnsName -ErrorAction SilentlyContinue
    if ($hasResolveDns) {
        try {
            $dnsResult = Resolve-DnsName -Name $fqdn -ErrorAction Stop
            if ($dnsResult) {
                # Check for privatelink CNAME with no A record
                $cnameRecords = $dnsResult | Where-Object { $_.QueryType -eq 'CNAME' -or $_.Type -eq 'CNAME' -or $_.PSObject.Properties['NameHost'] }
                $aRecords = $dnsResult | Where-Object { $_.QueryType -eq 'A' -or $_.Type -eq 'A' -or ($_.PSObject.Properties['IPAddress'] -and $_.IPAddress -match '^\d') }

                $privateLinkCname = $cnameRecords | Where-Object {
                    ($_.NameHost -and $_.NameHost -match 'privatelink')
                }

                if ($privateLinkCname -and -not $aRecords) {
                    $isPrivateLink = $true
                }
                elseif ($aRecords) {
                    $dnsResolved = $true
                }
                else {
                    # Has some DNS records but no A record and no privatelink
                    # Might still be resolvable — treat as resolved if we got any result
                    $dnsResolved = $true
                }
            }
        }
        catch {
            # Resolve-DnsName failed, fall through to nslookup
        }
    }

    # Fallback: nslookup (Linux/macOS or if Resolve-DnsName failed)
    if (-not $dnsResolved -and -not $isPrivateLink) {
        try {
            $nslookupOutput = & nslookup $fqdn 2>&1
            $nslookupStr = $nslookupOutput -join "`n"

            if ($nslookupStr -match 'NXDOMAIN' -or $nslookupStr -match "can't find" -or $nslookupStr -match 'server can' ) {
                # DNS failed
            }
            elseif ($nslookupStr -match 'privatelink' -and $nslookupStr -notmatch 'Address:\s*\d+\.\d+\.\d+\.\d+') {
                $isPrivateLink = $true
            }
            elseif ($nslookupStr -match 'Address:\s*\d+\.\d+\.\d+\.\d+') {
                # Filter out the DNS server address line (first Address line after "Server:")
                $lines = $nslookupStr -split "`n"
                $passedServer = $false
                foreach ($line in $lines) {
                    if ($line -match '^\s*Name:') { $passedServer = $true }
                    if ($passedServer -and $line -match 'Address:\s*(\d+\.\d+\.\d+\.\d+)') {
                        $dnsResolved = $true
                        break
                    }
                }
                # If we didn't find Address after Name, but there were addresses, still consider it resolved
                if (-not $dnsResolved -and $nslookupStr -match 'Name:') {
                    $dnsResolved = $true
                }
            }
        }
        catch {
            # nslookup also failed
        }
    }

    if ($isPrivateLink) {
        $result.status = '仅内网'
        $result.root_ca = 'Private Link / DNS 不可达'
        return $result
    }

    if (-not $dnsResolved) {
        $result.status = 'DNS失败'
        $result.root_ca = 'DNS 解析失败'
        return $result
    }

    # ── OpenSSL Connect ──
    $opensslOutput = ''
    try {
        # Use Process directly with timeout for best cross-platform/cross-version compatibility
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = 'openssl'
        $pinfo.Arguments = "s_client -starttls $starttls -showcerts -connect ${fqdn}:${port}"
        $pinfo.RedirectStandardInput = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $pinfo
        $proc.Start() | Out-Null

        # Send empty input to close stdin (triggers TLS handshake completion)
        $proc.StandardInput.Close()

        # Read output with timeout
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        if ($proc.WaitForExit(10000)) {
            # Process exited within timeout
            $stdoutTask.Wait(2000) | Out-Null
            $stderrTask.Wait(2000) | Out-Null
            $opensslOutput = $stdoutTask.Result + "`n" + $stderrTask.Result
        }
        else {
            # Timeout — kill process
            try { $proc.Kill() } catch {}
        }
    }
    catch {
        # openssl invocation failed
    }

    if (-not $opensslOutput -or $opensslOutput.Trim() -eq '') {
        $result.status = '超时'
        $result.root_ca = '连接超时'
        return $result
    }

    # ── Parse Certificate Chain ──
    $certs = @()
    $certBlock = ''
    $inCert = $false
    foreach ($line in ($opensslOutput -split "`n")) {
        if ($line -match '-----BEGIN CERTIFICATE-----') {
            $inCert = $true
            $certBlock = $line + "`n"
        }
        elseif ($line -match '-----END CERTIFICATE-----') {
            $certBlock += $line + "`n"
            $certs += $certBlock
            $certBlock = ''
            $inCert = $false
        }
        elseif ($inCert) {
            $certBlock += $line + "`n"
        }
    }

    if ($certs.Count -eq 0) {
        # No certificates found — might be connection issue
        if ($opensslOutput -match 'connect:errno|Connection refused|Connection timed out|no peer certificate') {
            $result.status = '超时'
            $result.root_ca = '连接超时'
        }
        else {
            $result.status = '超时'
            $result.root_ca = '无法获取证书'
        }
        return $result
    }

    # Decode each certificate to get Subject and Issuer
    $certInfos = @()
    foreach ($certPem in $certs) {
        $subject = ''
        $issuer = ''
        $notAfter = ''
        try {
            # Use Process to pipe PEM to openssl x509 (more reliable than PowerShell pipe)
            $pi = New-Object System.Diagnostics.ProcessStartInfo
            $pi.FileName = 'openssl'
            $pi.Arguments = 'x509 -noout -subject -issuer -enddate'
            $pi.RedirectStandardInput = $true
            $pi.RedirectStandardOutput = $true
            $pi.RedirectStandardError = $true
            $pi.UseShellExecute = $false
            $pi.CreateNoWindow = $true
            $p = New-Object System.Diagnostics.Process
            $p.StartInfo = $pi
            $p.Start() | Out-Null
            $p.StandardInput.Write($certPem)
            $p.StandardInput.Close()
            $decodedStr = $p.StandardOutput.ReadToEnd()
            $p.WaitForExit(5000) | Out-Null
            if (-not $p.HasExited) { try { $p.Kill() } catch {} }

            foreach ($dLine in ($decodedStr -split "`n")) {
                if ($dLine -match '^subject\s*=\s*(.+)') {
                    $subject = $Matches[1].Trim()
                }
                elseif ($dLine -match '^issuer\s*=\s*(.+)') {
                    $issuer = $Matches[1].Trim()
                }
                elseif ($dLine -match '^notAfter\s*=\s*(.+)') {
                    $notAfter = $Matches[1].Trim()
                }
            }
        }
        catch {}
        $certInfos += [PSCustomObject]@{
            Subject  = $subject
            Issuer   = $issuer
            NotAfter = $notAfter
        }
    }

    if ($certInfos.Count -eq 0) {
        $result.status = '超时'
        $result.root_ca = '证书解析失败'
        return $result
    }

    # Extract CN from a subject/issuer string
    # Handles both "CN = Something" and "CN=Something" and "/CN=Something"
    function Get-CN {
        param([string]$str)
        if ($str -match 'CN\s*=\s*([^,/]+)') {
            return $Matches[1].Trim()
        }
        return $str
    }

    # Determine root CA
    $rootCaName = ''
    $intermediateCaName = ''
    $certNotAfter = ''

    # Leaf cert not_after (first cert in chain)
    if ($certInfos[0].NotAfter) {
        $certNotAfter = $certInfos[0].NotAfter
    }

    if ($certs.Count -ge 3) {
        # Full chain: last cert is self-signed root CA
        $lastCert = $certInfos[$certInfos.Count - 1]
        $rootCaName = Get-CN $lastCert.Subject
        if ($certInfos.Count -ge 2) {
            $intermediateCaName = Get-CN $certInfos[$certInfos.Count - 2].Subject
        }
    }
    elseif ($certs.Count -eq 2) {
        # Incomplete chain: last cert is intermediate, infer root from its Issuer
        $lastCert = $certInfos[$certInfos.Count - 1]
        $rootCaName = Get-CN $lastCert.Issuer
        $intermediateCaName = Get-CN $lastCert.Subject
    }
    elseif ($certs.Count -eq 1) {
        # Only leaf cert: infer from its Issuer
        $lastCert = $certInfos[0]
        $rootCaName = Get-CN $lastCert.Issuer
    }

    $result.root_ca = $rootCaName
    $result.intermediate_ca = $intermediateCaName
    $result.cert_not_after = $certNotAfter

    # Judgment
    if ($rootCaName -match 'DigiCert Global Root G2') {
        $result.status = '已轮换'
    }
    elseif ($rootCaName -match 'DigiCert Global Root CA' -and $rootCaName -notmatch 'G2') {
        $result.status = '未轮换'
    }
    else {
        $result.status = '未知'
    }

    return $result
}

# ─── Write-ServerResult ──────────────────────────────────────────────────────
function Write-ServerResult {
    param(
        [PSCustomObject]$Result
    )

    $name = $Result.server_name
    $type = $Result.type
    $ca = $Result.root_ca

    # Pad for alignment
    $nameType = "$name ($type)"
    $padded = $nameType.PadRight(40)

    switch ($Result.status) {
        '已轮换' {
            Write-Host "✅ [已轮换]  $padded → $ca" -ForegroundColor Green
        }
        '未轮换' {
            Write-Host "❌ [未轮换]  $padded → $ca" -ForegroundColor Red
        }
        '仅内网' {
            Write-Host "🔒 [仅内网]  $padded → $ca" -ForegroundColor Yellow
        }
        '超时' {
            Write-Host "⏱️  [超时]    $padded → $ca" -ForegroundColor Yellow
        }
        'DNS失败' {
            Write-Host "⏱️  [DNS失败] $padded → $ca" -ForegroundColor Yellow
        }
        '未知' {
            Write-Host "❓ [未知]    $padded → $ca" -ForegroundColor Yellow
        }
        default {
            Write-Host "❓ [未知]    $padded → $ca" -ForegroundColor Yellow
        }
    }
}

# ─── Write-Summary ───────────────────────────────────────────────────────────
function Write-Summary {
    param(
        [array]$Results
    )

    $total = $Results.Count
    $rotated = @($Results | Where-Object { $_.status -eq '已轮换' }).Count
    $notRotated = @($Results | Where-Object { $_.status -eq '未轮换' }).Count
    $privateLink = @($Results | Where-Object { $_.status -eq '仅内网' }).Count
    $timeout = @($Results | Where-Object { $_.status -eq '超时' }).Count
    $dnsFail = @($Results | Where-Object { $_.status -eq 'DNS失败' }).Count
    $unknown = @($Results | Where-Object { $_.status -eq '未知' }).Count

    Write-Host ""
    Write-Host "===== 检测汇总 =====" -ForegroundColor Cyan
    Write-Host "总计: $total 台"
    Write-Host "✅ 已轮换:  $rotated" -ForegroundColor Green
    Write-Host "❌ 未轮换:  $notRotated" -ForegroundColor Red
    Write-Host "🔒 仅内网:  $privateLink" -ForegroundColor Yellow
    Write-Host "⏱️  超时:    $timeout" -ForegroundColor Yellow
    if ($dnsFail -gt 0) {
        Write-Host "⏱️  DNS失败: $dnsFail" -ForegroundColor Yellow
    }
    if ($unknown -gt 0) {
        Write-Host "❓ 未知:    $unknown" -ForegroundColor Yellow
    }
    Write-Host ""
}

# ─── Export-CsvReport ────────────────────────────────────────────────────────
function Export-CsvReport {
    param(
        [array]$Results,
        [string]$Path
    )

    $Results | Select-Object subscription, server_name, type, fqdn, status, root_ca, intermediate_ca, cert_not_after |
        Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8

    Write-Host "📄 报告已导出: $Path" -ForegroundColor Cyan
}

# ─── Invoke-ParallelCheck ────────────────────────────────────────────────────
function Invoke-ParallelCheck {
    param(
        [array]$Servers,
        [ValidateRange(1, 2147483647)]
        [int]$ThrottleLimit
    )

    $total = $Servers.Count
    Write-Host ""
    Write-Host "🚀 开始检测 $total 台服务器 (并行: $ThrottleLimit)..." -ForegroundColor Cyan
    Write-Host ""

    $results = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

    # The Test-SingleServer function definition as a string for use in runspaces / parallel
    $functionDef = ${function:Test-SingleServer}.ToString()

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # ── pwsh 7+: ForEach-Object -Parallel ──
        $Servers | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            # Re-define the function inside the parallel scope
            ${function:Test-SingleServer} = $using:functionDef

            $server = $_
            $r = Test-SingleServer -ServerName $server.server_name -ServerType $server.type -SubscriptionName $server.subscription
            ($using:results).Add($r)

            # Write output to host (thread-safe Write-Host in pwsh 7)
            $name = $r.server_name
            $type = $r.type
            $ca = $r.root_ca
            $nameType = "$name ($type)"
            $padded = $nameType.PadRight(40)
            switch ($r.status) {
                '已轮换'  { Write-Host "✅ [已轮换]  $padded → $ca" -ForegroundColor Green }
                '未轮换'  { Write-Host "❌ [未轮换]  $padded → $ca" -ForegroundColor Red }
                '仅内网'  { Write-Host "🔒 [仅内网]  $padded → $ca" -ForegroundColor Yellow }
                '超时'    { Write-Host "⏱️  [超时]    $padded → $ca" -ForegroundColor Yellow }
                'DNS失败' { Write-Host "⏱️  [DNS失败] $padded → $ca" -ForegroundColor Yellow }
                '未知'    { Write-Host "❓ [未知]    $padded → $ca" -ForegroundColor Yellow }
                default   { Write-Host "❓ [未知]    $padded → $ca" -ForegroundColor Yellow }
            }
        }
    }
    else {
        # ── PS 5.1: RunspacePool ──
        $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $runspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit, $sessionState, $Host)
        $runspacePool.Open()

        $scriptBlock = [ScriptBlock]::Create(@"
param(`$ServerName, `$ServerType, `$SubscriptionName)
${function:Test-SingleServer}
Test-SingleServer -ServerName `$ServerName -ServerType `$ServerType -SubscriptionName `$SubscriptionName
"@)

        $runspaces = [System.Collections.ArrayList]::new()

        foreach ($server in $Servers) {
            $ps = [System.Management.Automation.PowerShell]::Create()
            $ps.RunspacePool = $runspacePool
            [void]$ps.AddScript($scriptBlock.ToString())
            [void]$ps.AddParameter('ServerName', $server.server_name)
            [void]$ps.AddParameter('ServerType', $server.type)
            [void]$ps.AddParameter('SubscriptionName', $server.subscription)

            $handle = $ps.BeginInvoke()
            [void]$runspaces.Add([PSCustomObject]@{
                PowerShell = $ps
                Handle     = $handle
            })
        }

        # Collect results
        foreach ($rs in $runspaces) {
            try {
                $r = $rs.PowerShell.EndInvoke($rs.Handle)
                if ($r) {
                    foreach ($item in $r) {
                        $results.Add($item)
                        Write-ServerResult -Result $item
                    }
                }
            }
            catch {
                Write-Host "⚠️ 并行任务异常: $_" -ForegroundColor Yellow
            }
            finally {
                $rs.PowerShell.Dispose()
            }
        }

        $runspacePool.Close()
        $runspacePool.Dispose()
    }

    return @($results.ToArray())
}

# ─── Main ────────────────────────────────────────────────────────────────────
function Main {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║   Azure China Flexible Server CA 证书轮换检测工具           ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # 1. Prerequisites
    if (-not (Test-Prerequisites)) {
        return
    }

    # 2. Collect servers
    $allServers = @()

    if ($File) {
        # ── File mode ──
        Write-Host "📂 从文件加载: $File" -ForegroundColor Cyan
        $allServers = Get-ServersFromFile -FilePath $File
        if ($allServers.Count -eq 0) {
            Write-Host "❌ 未从文件中读取到有效服务器" -ForegroundColor Red
            return
        }
        Write-Host "   共 $($allServers.Count) 台服务器" -ForegroundColor Gray
    }
    else {
        # ── az CLI mode ──
        if (-not (Test-AzPrerequisites -TargetSubscription $Subscription -CheckAllSubs:$AllSubscriptions)) {
            return
        }

        if ($AllSubscriptions) {
            Write-Host ""
            Write-Host "🔄 遍历所有已启用订阅..." -ForegroundColor Cyan

            $subsRaw = az account list --query "[?state=='Enabled'].{id:id, name:name}" -o json 2>&1
            try {
                $subs = $subsRaw | ConvertFrom-Json
            }
            catch {
                Write-Host "❌ 无法获取订阅列表" -ForegroundColor Red
                return
            }

            foreach ($sub in $subs) {
                Write-Host ""
                Write-Host "📌 订阅: $($sub.name) ($($sub.id))" -ForegroundColor Cyan
                az account set -s $sub.id 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  ⚠️ 无法切换到此订阅，跳过" -ForegroundColor Yellow
                    continue
                }
                $subServers = Get-ServersFromAz -ServerType $Type -SubscriptionName $sub.name
                $allServers += $subServers
            }
        }
        else {
            Write-Host ""
            $currentSub = (az account show --query "name" -o tsv 2>&1).Trim()
            $allServers = Get-ServersFromAz -ServerType $Type -SubscriptionName $currentSub
        }

        if ($allServers.Count -eq 0) {
            Write-Host "❌ 未找到任何 Flexible Server" -ForegroundColor Red
            return
        }
    }

    # Filter by type if from file and -Type specified
    if ($File -and $Type -ne 'all') {
        $allServers = $allServers | Where-Object { $_.type -eq $Type }
        if ($allServers.Count -eq 0) {
            Write-Host "❌ 过滤后无匹配服务器 (类型: $Type)" -ForegroundColor Red
            return
        }
    }

    # 3. Run parallel checks
    $results = Invoke-ParallelCheck -Servers $allServers -ThrottleLimit $Parallel

    # 4. Summary
    Write-Summary -Results $results

    # 5. Export CSV
    if ($Output) {
        Export-CsvReport -Results $results -Path $Output
    }
}

# ─── Entry Point ─────────────────────────────────────────────────────────────
Main
