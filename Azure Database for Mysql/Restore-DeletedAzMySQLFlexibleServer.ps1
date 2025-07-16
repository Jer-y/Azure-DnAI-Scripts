<#
.SYNOPSIS
    An interactive PowerShell script to restore a recently deleted Azure Database for MySQL Flexible Server.
.DESCRIPTION
    This script provides a step-by-step interactive guide to restore an Azure Database for MySQL Flexible Server that was deleted within the last 5 days.
.NOTES
    Author: Jer-y
    Team: Azure Mooncake Data & AI Team
    Creation Date: 2025-07-16
#>

#region Main Execution
function Start-MySQLRestoreWizard {
    # --- Step 1: Language Selection ---
    $global:LocalizedStrings = Select-Language
    if (-not $global:LocalizedStrings) { return }

    Clear-Host
    Write-Host $LocalizedStrings.Welcome -ForegroundColor Cyan

    # --- Step 2 & 3: Prerequisites Check ---
    if (-not (Check-Prerequisites)) {
        Write-Error $LocalizedStrings.PrereqCheckFailed
        return
    }

    # --- Step 4: Select Azure Cloud ---
    $selectedCloud = Select-AzureCloud
    if (-not $selectedCloud) { return }

    # --- Step 5: Azure Login ---
    if (-not (Confirm-AzureLogin)) { return }

    # --- Step 6: Select Subscription ---
    $subscriptionId = Select-AzureSubscription
    if (-not $subscriptionId) { return }

    # --- Step 7 & 8: Get Deleted Server ---
    $deletedServer = Get-DeletedMySQLServer
    if (-not $deletedServer) { return }

    # --- Step 9: User confirms the selection (implicit in Get-DeletedMySQLServer) ---

    # --- Step 10: Select Location ---
    $rgName = $deletedServer.ResourceId.Split('/')[4]
    $location = Select-RestoreLocation -ResourceGroupName $rgName
    if (-not $location) { return }

    # --- Step 11: Perform Restore ---
    Invoke-MySQLRestore -DeletedServer $deletedServer -Location $location -ArmEndpointUrl $selectedCloud.endpoints.resourceManager

    # --- Step 13: Final Message ---
    Write-Host $LocalizedStrings.ScriptFinished -ForegroundColor Green
}
#endregion

#region Helper Functions

# Function for Step 1: Language Selection
function Select-Language {
    $strings = @{
        en = @{
            SelectLanguage        = "Please select a language (请输入语言)`n1. English`n2. 中文`nSelection (or 'q' to quit)"
            Welcome               = "--- Azure Database for MySQL flexible server Restore Script ---"
            PSVersionCheck        = "Checking PowerShell version..."
            PSVersionGood         = "PowerShell version is sufficient."
            PSVersionBad          = "PowerShell 5.1 or higher is required. Your version is {0}. Please upgrade."
            AzCliCheck            = "Checking for Azure CLI..."
            AzCliGood             = "Azure CLI is installed."
            AzCliBad              = "Azure CLI is not found. Please install it from: https://aka.ms/azure-cli"
            PrereqCheckFailed     = "Prerequisite check failed. Please resolve the issues above and rerun the script."
            SelectCloud           = "Select an Azure Cloud environment"
            FetchingClouds        = "Fetching Azure Cloud environments..."
            CloudFetchError       = "Failed to fetch Azure Cloud environments."
            CurrentCloudPrompt    = "Select an Azure Cloud environment (Press ENTER for '{0}')"
            AzLoginCheck          = "Checking Azure login status..."
            AzLoginGood           = "You are already logged into Azure CLI."
            AzLoginPrompt         = "You are not logged in. A browser window will open for you to log in."
            AzLoginSuccess        = "Login successful."
            AzLoginFailed         = "Login failed. Please try again."
            FetchingSubs          = "Fetching your subscriptions..."
            SubFetchError         = "Failed to fetch subscriptions."
            SelectSub             = "Please select a subscription"
            DefaultSubPrompt      = "Please select a subscription (Press ENTER for default)"
            SubSetTo              = "Subscription set to: {0} ({1})"
            EnterRGName           = "Please enter the name of the Resource Group"
            ValidatingRG          = "Validating Resource Group '{0}'..."
            RGNotFound            = "Resource Group '{0}' not found or you don't have permission to access it."
            RGValidated           = "Resource Group '{0}' found."
            SearchingActivityLog  = "Searching activity log for deleted MySQL servers in the last 5 days (checking up to 1000 events)..."
            NoDeletedServers      = "No deleted Azure Database for MySQL Flexible Servers found in Resource Group '{0}' in the last 5 days."
            SelectDeletedServer   = "Select a deleted server to restore"
            FetchingLocations     = "Fetching available locations for restore..."
            LocationFetchError    = "Failed to fetch available locations."
            SelectLocation        = "Select a location to restore the server to"
            EnterNewServerName    = "Enter a new, unique name for the restored server"
            RestoringServer       = "Attempting to restore server '{0}' as '{1}' in location '{2}'..."
            RestoreRequestSent    = "Restore request sent successfully. The operation is in progress."
            RestoreDetail         = "Details:"
            RestoreFailed         = "Failed to start the restore operation."
            ErrorDetails          = "Error Details:"
            ScriptFinished        = "Script has finished. Check the Azure portal for the status of the restore."
            InvalidSelection      = "Invalid selection. Please try again."
            RestoreSummary        = "`n=== RESTORE SUMMARY ==="
            SourceServer          = "Source Server: {0}"
            NewServerName         = "New Server Name: {0}"
            TargetLocation        = "Target Location: {0}"
            RestorePoint          = "Restore Point: {0} (15 minutes before deletion)"
            ConfirmRestore        = "`nDo you want to proceed with the restore? (Y/N)"
            OperationCancelled    = "Restore operation cancelled by user."
            RestoreOperationTitle = "Performing Server Restore"
            DefaultLocationSuffix = " (default)"
            RestoreStatus         = "Restore operation status: {0}"
            RestoreSuccess        = "Restore operation initiated successfully."
            RestoreResponse       = "API Response:"
            RestoreLocationHint   = "IMPORTANT: You MUST select the same location as the deleted server because the backups are stored in that location."
            RestoreMonitoringHint = "NOTE: The restore operation may take significant time. Monitor progress in the Activity Log under 'Resource Group: {0}' for operation type 'Microsoft.DBforMySQL/flexibleServers/write'"
        }
        zh = @{
            SelectLanguage        = "请选择语言 (Please select a language)`n1. English`n2. 中文`n选择 (或输入 'q' 退出)"
            Welcome               = "--- Azure Database for MySQL flexible server 恢复脚本 ---"
            PSVersionCheck        = "正在检查 PowerShell 版本..."
            PSVersionGood         = "PowerShell 版本满足要求。"
            PSVersionBad          = "脚本需要 PowerShell 5.1 或更高版本。您的版本是 {0}。请升级。"
            AzCliCheck            = "正在检查 Azure CLI..."
            AzCliGood             = "Azure CLI 已安装。"
            AzCliBad              = "未找到 Azure CLI。请从以下地址安装: https://aka.ms/azure-cli"
            PrereqCheckFailed     = "先决条件检查失败。请解决上述问题后重新运行脚本。"
            SelectCloud           = "请选择一个 Azure 云环境"
            FetchingClouds        = "正在获取 Azure 云环境列表..."
            CloudFetchError       = "获取 Azure 云环境失败。"
            CurrentCloudPrompt    = "请选择一个 Azure 云环境 (直接按 ENTER 键选择 '{0}')"
            AzLoginCheck          = "正在检查 Azure登录状态..."
            AzLoginGood           = "您已登录到 Azure CLI。"
            AzLoginPrompt         = "您尚未登录。将打开浏览器窗口提示您登录。"
            AzLoginSuccess        = "登录成功。"
            AzLoginFailed         = "登录失败，请重试。"
            FetchingSubs          = "正在获取您的订阅列表..."
            SubFetchError         = "获取订阅列表失败。"
            SelectSub             = "请选择一个订阅"
            DefaultSubPrompt      = "请选择一个订阅 (直接按 ENTER 键选择默认订阅)"
            SubSetTo              = "订阅已设置为: {0} ({1})"
            EnterRGName           = "请输入资源组 (Resource Group) 的名称"
            ValidatingRG          = "正在验证资源组 '{0}'..."
            RGNotFound            = "资源组 '{0}' 不存在或您没有权限访问。"
            RGValidated           = "资源组 '{0}' 已找到。"
            SearchingActivityLog  = "正在搜索过去5天内已删除的 MySQL 服务器活动日志 (最多检查1000条事件)..."
            NoDeletedServers      = "在资源组 '{0}' 中未找到过去5天内删除的 Azure Database for MySQL 灵活服务器。"
            SelectDeletedServer   = "请选择一个要恢复的已删除服务器"
            FetchingLocations     = "正在获取可用于恢复的区域..."
            LocationFetchError    = "获取可用区域失败。"
            SelectLocation        = "请选择要将服务器恢复到的区域"
            EnterNewServerName    = "请输入恢复后服务器的新名称 (需保证唯一)"
            RestoringServer       = "正在尝试将服务器 '{0}' 恢复为 '{1}'，目标区域 '{2}'..."
            RestoreRequestSent    = "恢复请求已成功发送。操作正在进行中。"
            RestoreDetail         = "详细信息:"
            RestoreFailed         = "启动恢复操作失败。"
            ErrorDetails          = "错误详情:"
            ScriptFinished        = "脚本执行完毕。请前往 Azure Portal查看恢复状态。"
            InvalidSelection      = "无效选择，请重试。"
            RestoreSummary        = "`n=== 恢复摘要 ==="
            SourceServer          = "源服务器: {0}"
            NewServerName         = "新服务器名称: {0}"
            TargetLocation        = "目标区域: {0}"
            RestorePoint          = "恢复时间点: {0} (删除前15分钟)"
            ConfirmRestore        = "`n是否要继续执行恢复操作? (Y/N)"
            OperationCancelled    = "用户已取消恢复操作。"
            RestoreOperationTitle = "正在执行服务器恢复"
            DefaultLocationSuffix = " (默认)"
            RestoreStatus         = "恢复操作状态: {0}"
            RestoreSuccess        = "恢复操作已成功提交。"
            RestoreResponse       = "API 响应:"
            RestoreLocationHint   = "重要提示：您必须选择与被删除服务器相同的区域，因为备份存储在该区域。"
            RestoreMonitoringHint = "注意：恢复操作可能需要较长时间。请在资源组 '{0}' 的活动日志中监控进度，筛选操作类型 'Microsoft.DBforMySQL/flexibleServers/write'"
        }
    }

    do {
        $selection = Read-Host -Prompt $strings.en.SelectLanguage
        if ($selection -eq 'q') { 
            Write-Host "Operation cancelled by user." -ForegroundColor Yellow
            exit 
        }
        if ($selection -eq '1') { return $strings.en }
        if ($selection -eq '2') { return $strings.zh }
        
        Write-Warning $strings.en.InvalidSelection
    } while ($true)
}

# Function for Step 2 & 3: Prerequisites Check
function Check-Prerequisites {
    $allGood = $true

    # PowerShell Version Check
    Write-Host $LocalizedStrings.PSVersionCheck
    if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
        Write-Error ($LocalizedStrings.PSVersionBad -f $PSVersionTable.PSVersion.ToString())
        $allGood = $false
    } else {
        Write-Host $LocalizedStrings.PSVersionGood -ForegroundColor Green
    }

    # Azure CLI Check
    Write-Host $LocalizedStrings.AzCliCheck
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Error $LocalizedStrings.AzCliBad
        $allGood = $false
    } else {
        Write-Host $LocalizedStrings.AzCliGood -ForegroundColor Green
    }

    return $allGood
}

# Function for Step 4: Select Azure Cloud
function Select-AzureCloud {
    Write-Host "`n--- $($LocalizedStrings.SelectCloud) ---" -ForegroundColor Cyan
    Write-Host $LocalizedStrings.FetchingClouds
    try {
        $activeCloud = az cloud show --output json | ConvertFrom-Json
        $clouds = az cloud list --output json | ConvertFrom-Json
        if (-not $clouds) {
            Write-Error $LocalizedStrings.CloudFetchError
            return $null
        }

        $defaultIndex = -1
        for ($i = 0; $i -lt $clouds.Count; $i++) {
            $cloud = $clouds[$i]
            $isCurrent = ""
            if ($cloud.name -eq $activeCloud.name) {
                $isCurrent = "(current)"
                $defaultIndex = $i + 1
            }
            Write-Host ("{0}. {1} {2}" -f ($i + 1), $cloud.name, $isCurrent)
        }

        $prompt = $LocalizedStrings.CurrentCloudPrompt -f $activeCloud.name
        do {
            $choice = Read-Host -Prompt $prompt
            if ([string]::IsNullOrWhiteSpace($choice)) {
                $choice = $defaultIndex
            }

            if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $clouds.Count) {
                $selectedCloud = $clouds[[int]$choice - 1]
                if ($selectedCloud.name -ne $activeCloud.name) {
                    az cloud set --name $selectedCloud.name | Out-Null
                    Write-Host ("Cloud set to '{0}'" -f $selectedCloud.name) -ForegroundColor Green
                }
                return $selectedCloud
            }
            else {
                Write-Warning $LocalizedStrings.InvalidSelection
            }
        } while ($true)
    }
    catch {
        Write-Error $LocalizedStrings.CloudFetchError
        Write-Error $_.Exception.Message
        return $null
    }
}

# Function for Step 5: Azure Login
function Confirm-AzureLogin {
    Write-Host "`n--- $($LocalizedStrings.AzLoginCheck) ---" -ForegroundColor Cyan
    az account show --output none 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host $LocalizedStrings.AzLoginGood -ForegroundColor Green
        return $true
    }

    Write-Host $LocalizedStrings.AzLoginPrompt
    try {
        az login --use-device-code
        if ($LASTEXITCODE -eq 0) {
            Write-Host $LocalizedStrings.AzLoginSuccess -ForegroundColor Green
            return $true
        } else {
            Write-Error $LocalizedStrings.AzLoginFailed
            return $false
        }
    }
    catch {
        Write-Error $LocalizedStrings.AzLoginFailed
        Write-Error $_.Exception.Message
        return $false
    }
}

# Function for Step 6: Select Subscription
function Select-AzureSubscription {
    Write-Host "`n--- $($LocalizedStrings.SelectSub) ---" -ForegroundColor Cyan
    Write-Host $LocalizedStrings.FetchingSubs
    try {
        $defaultSub = az account show --output json | ConvertFrom-Json
        $allSubs = az account list --output json | ConvertFrom-Json

        $subMap = @{}
        
        # 高亮显示默认订阅
        Write-Host ("1. {0} ({1}) (default)" -f $defaultSub.name, $defaultSub.id) -ForegroundColor Green
        $subMap["1"] = $defaultSub

        $otherSubs = $allSubs | Where-Object { $_.id -ne $defaultSub.id }
        $i = 2
        foreach ($sub in $otherSubs) {
            Write-Host ("{0}. {1} ({2})" -f $i, $sub.name, $sub.id)
            $subMap[$i.ToString()] = $sub
            $i++
        }

        do {
            $choice = Read-Host -Prompt $LocalizedStrings.DefaultSubPrompt
            if ([string]::IsNullOrWhiteSpace($choice)) {
                $choice = "1"
            }

            if ($subMap.ContainsKey($choice)) {
                $selectedSub = $subMap[$choice]
                az account set --subscription $selectedSub.id | Out-Null
                Write-Host ($LocalizedStrings.SubSetTo -f $selectedSub.name, $selectedSub.id) -ForegroundColor Green
                return $selectedSub.id
            }
            else {
                Write-Warning $LocalizedStrings.InvalidSelection
            }
        } while ($true)
    }
    catch {
        Write-Error $LocalizedStrings.SubFetchError
        Write-Error $_.Exception.Message
        return $null
    }
}

# Function for Step 7 & 8: Get Deleted Server
function Get-DeletedMySQLServer {
    Write-Host "`n--- $($LocalizedStrings.SelectDeletedServer) ---" -ForegroundColor Yellow
    $attempts = 0
    $maxAttempts = 3
    
    do {
        $rgName = Read-Host -Prompt $LocalizedStrings.EnterRGName
        
        Write-Host ($LocalizedStrings.ValidatingRG -f $rgName)
        az group show --name $rgName --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host ($LocalizedStrings.RGValidated -f $rgName) -ForegroundColor Green
            break
        }
        
        $attempts++
        if ($attempts -ge $maxAttempts) {
            Write-Error ($LocalizedStrings.RGNotFound -f $rgName)
            return $null
        }
        Write-Warning ($LocalizedStrings.RGNotFound -f $rgName)
        Write-Host "Please try again. Attempts left: $($maxAttempts - $attempts)"
    } while ($true)

    Write-Host $LocalizedStrings.SearchingActivityLog
    try {
        $query = "[?operationName.value=='Microsoft.DBforMySQL/flexibleServers/delete' && status.value=='Succeeded'].{resourceId:resourceId, eventTimestamp:eventTimestamp}"
        
        # Show progress indicator
        $progressMsg = "Searching activity logs..."
        Write-Progress -Activity $progressMsg -Status "Please wait"
        
        $deletedServersLog = az monitor activity-log list --resource-group $rgName --offset 5d --namespace "Microsoft.DBforMySQL" --max-events 1000 --query "$query" --output json | ConvertFrom-Json
        
        Write-Progress -Activity $progressMsg -Completed
        
        if (-not $deletedServersLog) {
            Write-Warning ($LocalizedStrings.NoDeletedServers -f $rgName)
            return $null
        }

        $serverChoices = @()
        foreach ($entry in $deletedServersLog) {
            $serverName = $entry.resourceId.Split('/')[-1]
            $serverChoices += [pscustomobject]@{
                Name             = $serverName
                DeletedTime      = $entry.eventTimestamp
                ResourceId       = $entry.resourceId
            }
        }

        Write-Host $LocalizedStrings.SelectDeletedServer
        for ($i = 0; $i -lt $serverChoices.Count; $i++) {
            Write-Host ("{0}. {1} (Deleted at: {2})" -f ($i + 1), $serverChoices[$i].Name, $serverChoices[$i].DeletedTime)
        }

        do {
            $choice = Read-Host -Prompt $LocalizedStrings.SelectDeletedServer
            if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $serverChoices.Count) {
                return $serverChoices[[int]$choice - 1]
            }
            else {
                Write-Warning $LocalizedStrings.InvalidSelection
            }
        } while ($true)
    }
    catch {
        Write-Error $_.Exception.Message
        return $null
    }
}

# Function for Step 10: Select Location
function Select-RestoreLocation {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroupName
    )
    
    Write-Host "`n--- $($LocalizedStrings.SelectLocation) ---" -ForegroundColor Yellow
    
    # 添加关键位置提示
    Write-Host $LocalizedStrings.RestoreLocationHint -ForegroundColor Yellow
    
    Write-Host $LocalizedStrings.FetchingLocations
    
    try {
        # Get resource group location as default
        $rgLocation = az group show --name $ResourceGroupName --query location --output tsv 2>$null
        if (-not $rgLocation) {
            Write-Warning "Failed to get resource group location. Proceeding without default location."
        }
        
        # Show progress indicator
        $progressMsg = "Fetching available locations..."
        Write-Progress -Activity $progressMsg -Status "Please wait"
        
        # Get all available locations with display names
        $locations = az account list-locations --query "[].{Name:name, DisplayName:displayName}" --output json | ConvertFrom-Json
        
        Write-Progress -Activity $progressMsg -Completed
        
        if (-not $locations) {
            Write-Error $LocalizedStrings.LocationFetchError
            return $null
        }
        
        # Create formatted location list with region codes
        $formattedList = @()
        $defaultIndex = -1
        for ($i = 0; $i -lt $locations.Count; $i++) {
            $loc = $locations[$i]
            $formatted = "{0} ({1})" -f $loc.DisplayName, $loc.Name
            
            # Check if this is the resource group location
            if ($loc.Name -eq $rgLocation) {
                $formatted += $LocalizedStrings.DefaultLocationSuffix
                $defaultIndex = $i
            }
            
            $formattedList += $formatted
        }

        # Display locations
        for ($i = 0; $i -lt $formattedList.Count; $i++) {
            if ($i -eq $defaultIndex) {
                Write-Host ("{0}. {1}" -f ($i + 1), $formattedList[$i]) -ForegroundColor Green
            } else {
                Write-Host ("{0}. {1}" -f ($i + 1), $formattedList[$i])
            }
        }

        do {
            $prompt = if ($defaultIndex -ge 0) {
                $LocalizedStrings.SelectLocation + " (Press ENTER for default)"
            } else {
                $LocalizedStrings.SelectLocation
            }
            
            $choice = Read-Host -Prompt $prompt
            
            # Handle default selection
            if ([string]::IsNullOrWhiteSpace($choice) -and $defaultIndex -ge 0) {
                $selectedLocation = $locations[$defaultIndex].Name
                Write-Host ("Using default location: {0}" -f $formattedList[$defaultIndex]) -ForegroundColor Cyan
                break
            }
            
            if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $locations.Count) {
                $selectedLocation = $locations[[int]$choice - 1].Name
                break
            }
            
            Write-Warning $LocalizedStrings.InvalidSelection
        } while ($true)
        
        return $selectedLocation
    }
    catch {
        Write-Error $LocalizedStrings.LocationFetchError
        Write-Error $_.Exception.Message
        return $null
    }
}

# Function for Step 11 & 13: Perform Restore
function Invoke-MySQLRestore {
    param(
        [Parameter(Mandatory=$true)]
        [psobject]$DeletedServer,
        [Parameter(Mandatory=$true)]
        [string]$Location,
        [Parameter(Mandatory=$true)]
        [string]$ArmEndpointUrl
    )

    Write-Host "`n--- $($LocalizedStrings.RestoreOperationTitle) ---" -ForegroundColor Magenta
    $newServerName = Read-Host -Prompt $LocalizedStrings.EnterNewServerName
    
    $currentSub = az account show --output json | ConvertFrom-Json
    $rgName = $DeletedServer.ResourceId.Split('/')[4]
    
    $apiVersion = "2024-06-01-preview"

    # Calculate restore point (15 minutes before deletion)
    $deletionTimestamp = [datetime]$DeletedServer.DeletedTime
    $validRestorePoint = $deletionTimestamp.AddMinutes(-15)
    $restorePointForApi = $validRestorePoint.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    
    # Display restore summary
    Write-Host $LocalizedStrings.RestoreSummary -ForegroundColor Cyan
    Write-Host ($LocalizedStrings.SourceServer -f $DeletedServer.Name) -ForegroundColor Cyan
    Write-Host ($LocalizedStrings.NewServerName -f $newServerName) -ForegroundColor Cyan
    Write-Host ($LocalizedStrings.TargetLocation -f $Location) -ForegroundColor Cyan
    Write-Host ($LocalizedStrings.RestorePoint -f $restorePointForApi) -ForegroundColor Cyan
    
    # Confirmation step
    $confirmation = Read-Host -Prompt $LocalizedStrings.ConfirmRestore
    if ($confirmation -notin @('Y', 'y')) {
        Write-Host $LocalizedStrings.OperationCancelled -ForegroundColor Yellow
        return
    }

    # Show actual restore message with formatted values
    Write-Host ($LocalizedStrings.RestoringServer -f $DeletedServer.Name, $newServerName, $Location)

    $requestUri = "$($ArmEndpointUrl.TrimEnd('/'))/subscriptions/$($currentSub.id)/resourceGroups/$($rgName)/providers/Microsoft.DBforMySQL/flexibleServers/$($newServerName)?api-version=$apiVersion"

    $requestBody = @{
        location = $Location
        properties = @{
            createMode             = "PointInTimeRestore"
            sourceServerResourceId = $DeletedServer.ResourceId
            restorePointInTime     = $restorePointForApi
        }
    } | ConvertTo-Json -Depth 5 -Compress

    $tempFile = $null
    try {
        $tempFile = New-TemporaryFile
        Set-Content -Path $tempFile.FullName -Value $requestBody -NoNewline

        $azRestArgs = @(
            'rest',
            '--method', 'put',
            '--uri', $requestUri,
            '--body', "@$($tempFile.FullName)",
            '--headers', 'Content-Type=application/json'
        )
        
        # Execute the restore command and capture output
        $output = az @azRestArgs 2>&1 | Out-String
        
        if ($LASTEXITCODE -eq 0) {
            # Success case
            Write-Host $LocalizedStrings.RestoreSuccess -ForegroundColor Green
            Write-Host ($LocalizedStrings.RestoreStatus -f "Request Accepted") -ForegroundColor Green
            Write-Host ($LocalizedStrings.RestoreMonitoringHint -f $rgName) -ForegroundColor Yellow
            
            # Parse and display JSON response
            try {
                $response = $output | ConvertFrom-Json
                Write-Host $LocalizedStrings.RestoreResponse -ForegroundColor Cyan
                $response | Format-List | Out-String | Write-Host
            }
            catch {
                Write-Warning "Failed to parse API response as object. Showing raw response:"
                Write-Host $output
            }
        }
        else {
            # Error case
            Write-Error $LocalizedStrings.RestoreFailed
            Write-Error $LocalizedStrings.ErrorDetails
            Write-Error $output
        }
    }
    catch {
        Write-Error $LocalizedStrings.RestoreFailed
        Write-Error $LocalizedStrings.ErrorDetails
        Write-Error $_.Exception.Message
    }
    finally {
        if ($null -ne $tempFile -and (Test-Path $tempFile.FullName)) {
            Remove-Item $tempFile.FullName -Force
        }
    }
}

#endregion

# --- Script Entry Point ---
Start-MySQLRestoreWizard