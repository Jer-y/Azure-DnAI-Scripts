#!/bin/bash
#
# SYNOPSIS
#   An interactive shell script to restore a recently deleted Azure Database for MySQL Flexible Server.
#
# DESCRIPTION
#   This script provides a step-by-step interactive guide to restore an Azure Database for MySQL Flexible Server that was deleted within the last 5 days. It is a Bash equivalent of the original PowerShell script.
#
# NOTES
#   Author: Jer-y
#   Team: Azure Mooncake Data & AI Team
#   Creation Date: 2025-07-16
#

# --- Color Definitions ---
C_GREEN='\033[0;32m'
C_CYAN='\033[0;36m'
C_YELLOW='\033[0;33m'
C_RED='\033[0;31m'
C_MAGENTA='\033[0;35m'
C_NC='\033[0m' # No Color (reset)

#region Helper Functions

# --- Step 1: Language Selection ---
function select_language() {
    # Associative arrays for localized strings
    declare -gA en=(
        [SelectLanguage]="Please select a language (请输入语言)\n1. English\n2. 中文"
        [Welcome]="--- Azure Database for MySQL flexible server Restore Script ---"
        [PrereqCheck]="Checking for required tools (Azure CLI & jq)..."
        [JqNotFound]="'jq' is not installed. Please install it to proceed (e.g., 'sudo apt-get install jq')."
        [AzCliNotFound]="Azure CLI ('az') is not found. Please install it from: https://aka.ms/azure-cli"
        [PrereqCheckFailed]="Prerequisite check failed. Please resolve the issues above and rerun the script."
        [SelectCloud]="Select an Azure Cloud environment"
        [FetchingClouds]="Fetching Azure Cloud environments..."
        [CloudFetchError]="Failed to fetch Azure Cloud environments."
        [CurrentCloudPrompt]="Select an Azure Cloud environment (Press ENTER for '%s')"
        [AzLoginCheck]="Checking Azure login status..."
        [AzLoginGood]="You are already logged into Azure CLI."
        [AzLoginPrompt]="You are not logged in. Please log in to Azure."
        [AzLoginSuccess]="Login successful."
        [AzLoginFailed]="Login failed. Please try again."
        [FetchingSubs]="Fetching your subscriptions..."
        [SubFetchError]="Failed to fetch subscriptions."
        [SelectSub]="Please select a subscription"
        [DefaultSubPrompt]="Please select a subscription (Press ENTER for '%s')"
        [SubSetTo]="Subscription set to: %s (%s)\n"
        [EnterRGName]="Please enter the name of the Resource Group"
        [ValidatingRG]="Validating Resource Group '%s'..."
        [RGNotFound]="Resource Group '%s' not found or you don't have permission to access it."
        [RGValidated]="Resource Group '%s' found."
        [SearchingActivityLog]="Searching activity log for deleted MySQL servers in the last 5 days (checking up to 1000 events)..."
        [NoDeletedServers]="No deleted Azure Database for MySQL Flexible Servers found in Resource Group '%s' in the last 5 days."
        [SelectDeletedServer]="Select a deleted server to restore"
        [FetchingLocations]="Fetching available locations for restore..."
        [LocationFetchError]="Failed to fetch available locations."
        [SelectLocation]="Select a location to restore the server to"
        [EnterNewServerName]="Enter a new, unique name for the restored server"
        [RestoringServer]="Attempting to restore server '%s' as '%s' in location '%s'..."
        [RestoreRequestSent]="Restore request sent successfully. The operation is in progress."
        [RestoreFailed]="Failed to start the restore operation."
        [ErrorDetails]="Error Details:"
        [ScriptFinished]="Script has finished. Check the Azure portal for the status of the restore."
        [InvalidSelection]="Invalid selection. Please try again."
        [RestoreSummary]="\n=== RESTORE SUMMARY ==="
        [SourceServer]="Source Server : %s"
        [NewServerName]="New Server Name: %s"
        [TargetLocation]="Target Location: %s"
        [RestorePoint]="Restore Point  : %s (approx. 15 minutes before deletion)"
        [ConfirmRestore]="Do you want to proceed with the restore? (y/N)"
        [OperationCancelled]="Restore operation cancelled by user."
        [RestoreOperationTitle]="Performing Server Restore"
        [DefaultSuffix]="(default)"
        [RestoreSuccess]="Restore operation initiated successfully."
        [RestoreResponse]="API Response:"
        [RestoreLocationHint]="IMPORTANT: You MUST select the same location as the deleted server because the backups are stored in that location."
        [RestoreMonitoringHint]="NOTE: The restore operation may take significant time. Monitor progress in the Activity Log under 'Resource Group: %s' for operation type 'Microsoft.DBforMySQL/flexibleServers/write'"
        [QuitPrompt]="Selection (or 'q' to quit): "
    )

    declare -gA zh=(
        [SelectLanguage]="请选择语言 (Please select a language)\n1. English\n2. 中文"
        [Welcome]="--- Azure Database for MySQL flexible server 恢复脚本 ---"
        [PrereqCheck]="正在检查所需工具 (Azure CLI & jq)..."
        [JqNotFound]="未找到 'jq'。请安装后再继续 (例如: 'sudo apt-get install jq')。"
        [AzCliNotFound]="未找到 Azure CLI ('az')。请从以下地址安装: https://aka.ms/azure-cli"
        [PrereqCheckFailed]="先决条件检查失败。请解决上述问题后重新运行脚本。"
        [SelectCloud]="请选择一个 Azure 云环境"
        [FetchingClouds]="正在获取 Azure 云环境列表..."
        [CloudFetchError]="获取 Azure 云环境失败。"
        [CurrentCloudPrompt]="请选择一个 Azure 云环境 (直接按 ENTER 键选择 '%s')"
        [AzLoginCheck]="正在检查 Azure 登录状态..."
        [AzLoginGood]="您已登录到 Azure CLI。"
        [AzLoginPrompt]="您尚未登录，请登录 Azure。"
        [AzLoginSuccess]="登录成功。"
        [AzLoginFailed]="登录失败，请重试。"
        [FetchingSubs]="正在获取您的订阅列表..."
        [SubFetchError]="获取订阅列表失败。"
        [SelectSub]="请选择一个订阅"
        [DefaultSubPrompt]="请选择一个订阅 (直接按 ENTER 键选择 '%s')"
        [SubSetTo]="订阅已设置为: %s (%s)\n"
        [EnterRGName]="请输入资源组 (Resource Group) 的名称"
        [ValidatingRG]="正在验证资源组 '%s'..."
        [RGNotFound]="资源组 '%s' 不存在或您没有权限访问。"
        [RGValidated]="资源组 '%s' 已找到。"
        [SearchingActivityLog]="正在搜索过去5天内已删除的 MySQL 服务器活动日志 (最多检查1000条事件)..."
        [NoDeletedServers]="在资源组 '%s' 中未找到过去5天内删除的 Azure Database for MySQL 灵活服务器。"
        [SelectDeletedServer]="请选择一个要恢复的已删除服务器"
        [FetchingLocations]="正在获取可用于恢复的区域..."
        [LocationFetchError]="获取可用区域失败。"
        [SelectLocation]="请选择要将服务器恢复到的区域"
        [EnterNewServerName]="请输入恢复后服务器的新名称 (需保证唯一)"
        [RestoringServer]="正在尝试将服务器 '%s' 恢复为 '%s'，目标区域 '%s'..."
        [RestoreRequestSent]="恢复请求已成功发送。操作正在进行中。"
        [RestoreFailed]="启动恢复操作失败。"
        [ErrorDetails]="错误详情:"
        [ScriptFinished]="脚本执行完毕。请前往 Azure Portal 查看恢复状态。"
        [InvalidSelection]="无效选择，请重试。"
        [RestoreSummary]="\n=== 恢复摘要 ==="
        [SourceServer]="源服务器 : %s"
        [NewServerName]="新服务器名称: %s"
        [TargetLocation]="目标区域 : %s"
        [RestorePoint]="恢复时间点 : %s (大约在删除前15分钟)"
        [ConfirmRestore]="是否要继续执行恢复操作? (y/N)"
        [OperationCancelled]="用户已取消恢复操作。"
        [RestoreOperationTitle]="正在执行服务器恢复"
        [DefaultSuffix]="(默认)"
        [RestoreSuccess]="恢复操作已成功提交。"
        [RestoreResponse]="API 响应:"
        [RestoreLocationHint]="重要提示：您必须选择与被删除服务器相同的区域，因为备份存储在该区域。"
        [RestoreMonitoringHint]="注意：恢复操作可能需要较长时间。请在资源组 '%s' 的活动日志中监控进度，筛选操作类型 'Microsoft.DBforMySQL/flexibleServers/write'"
        [QuitPrompt]="选择 (或输入 'q' 退出): "
    )

    while true; do
        echo -e "${en[SelectLanguage]}"
        read -p "${en[QuitPrompt]}" selection
        case "$selection" in
            1) LANG_CODE="en"; return 0 ;;
            2) LANG_CODE="zh"; return 0 ;;
            [qQ]) echo "Operation cancelled by user."; exit 0 ;;
            *) echo "Invalid selection, please try again.";;
        esac
    done
}

function t() {
    local key="$1"
    if [ "$LANG_CODE" == "zh" ]; then
        echo -e "${zh[$key]}"
    else
        echo -e "${en[$key]}"
    fi
}

function check_prerequisites() {
    echo "$(t PrereqCheck)"
    local all_good=true

    if ! command -v jq &> /dev/null; then
        echo -e "${C_RED}$(t JqNotFound)${C_NC}" >&2
        all_good=false
    fi

    if ! command -v az &> /dev/null; then
        echo -e "${C_RED}$(t AzCliNotFound)${C_NC}" >&2
        all_good=false
    fi

    if [ "$all_good" = false ]; then
        return 1
    else
        echo -e "${C_GREEN}Tools are installed.${C_NC}"
        return 0
    fi
}

function select_azure_cloud() {
    echo -e "\n${C_CYAN}--- $(t SelectCloud) ---${C_NC}"
    echo "$(t FetchingClouds)"
    
    CLOUDS_JSON=$(az cloud list 2> /dev/null)
    if [ $? -ne 0 ]; then
        echo -e "${C_RED}$(t CloudFetchError)${C_NC}" >&2
        return 1
    fi
    ACTIVE_CLOUD_JSON=$(az cloud show 2> /dev/null)
    if [ $? -ne 0 ]; then
        echo -e "${C_RED}$(t CloudFetchError)${C_NC}" >&2
        return 1
    fi

    local active_cloud_name=$(echo "$ACTIVE_CLOUD_JSON" | jq -r '.name')
    mapfile -t cloud_names < <(echo "$CLOUDS_JSON" | jq -r '.[].name')
    local default_index=-1

    echo "Available clouds:"
    for i in "${!cloud_names[@]}"; do
        if [[ "${cloud_names[$i]}" == "$active_cloud_name" ]]; then
            default_index=$((i + 1))
            echo -e "${C_GREEN}$((i + 1)). ${cloud_names[$i]} (current)${C_NC}"
        else
            echo "$((i + 1)). ${cloud_names[$i]}"
        fi
    done

    while true; do
        local prompt_str
        printf -v prompt_str "$(t CurrentCloudPrompt)" "$active_cloud_name"
        read -p "$prompt_str: " choice
        choice=${choice:-$default_index}

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#cloud_names[@]}" ]; then
            selected_cloud_name="${cloud_names[$((choice - 1))]}"
            if [[ "$selected_cloud_name" != "$active_cloud_name" ]]; then
                echo "Setting active cloud to '$selected_cloud_name'..."
                az cloud set --name "$selected_cloud_name" > /dev/null
            fi
            ARM_ENDPOINT=$(echo "$CLOUDS_JSON" | jq -r --arg name "$selected_cloud_name" '.[] | select(.name == $name) | .endpoints.resourceManager')
            return 0
        else
            echo -e "${C_YELLOW}$(t InvalidSelection)${C_NC}"
        fi
    done
}

function confirm_azure_login() {
    echo -e "\n${C_CYAN}--- $(t AzLoginCheck) ---${C_NC}"
    az account show &> /dev/null
    if [ $? -eq 0 ]; then
        echo -e "${C_GREEN}$(t AzLoginGood)${C_NC}"
        return 0
    fi

    echo "$(t AzLoginPrompt)"
    az login --use-device-code
    if [ $? -eq 0 ]; then
        echo -e "${C_GREEN}$(t AzLoginSuccess)${C_NC}"
        return 0
    else
        echo -e "${C_RED}$(t AzLoginFailed)${C_NC}" >&2
        return 1
    fi
}

function select_azure_subscription() {
    echo -e "\n${C_CYAN}--- $(t SelectSub) ---${C_NC}"
    echo "$(t FetchingSubs)"

    SUBS_JSON=$(az account list --output json 2> /dev/null)
    if [ $? -ne 0 ]; then
        echo -e "${C_RED}$(t SubFetchError)${C_NC}" >&2
        return 1
    fi

    local default_index=-1
    local default_sub_name=""
    local i=0
    
    declare -a sub_ids
    declare -a sub_names

    echo "Available subscriptions:"
    while IFS=$'\t' read -r id name is_default; do
        i=$((i + 1))
        sub_ids[$i]=$id
        sub_names[$i]=$name

        if [[ "$is_default" == "true" ]]; then
            default_index=$i
            default_sub_name=$name
            printf "${C_GREEN}%d. %s (%s) %s${C_NC}\n" "$i" "$name" "$id" "$(t DefaultSuffix)"
        else
            printf "%d. %s (%s)\n" "$i" "$name" "$id"
        fi
    done < <(echo "$SUBS_JSON" | jq -r '.[] | [.id, .name, .isDefault] | @tsv')
    
    local sub_count=$i
    while true; do
        local prompt_str
        if [[ -n "$default_sub_name" ]]; then
            printf -v prompt_str "$(t DefaultSubPrompt)" "$default_sub_name"
        else
            prompt_str="$(t SelectSub)"
        fi
        
        read -p "$prompt_str: " choice
        choice=${choice:-$default_index}

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$sub_count" ]; then
            SELECTED_SUB_ID="${sub_ids[$choice]}"
            az account set --subscription "$SELECTED_SUB_ID" > /dev/null
            printf "${C_GREEN}"
            printf "$(t SubSetTo)" "${sub_names[$choice]}" "$SELECTED_SUB_ID"
            printf "${C_NC}"
            return 0
        else
            echo -e "${C_YELLOW}$(t InvalidSelection)${C_NC}"
        fi
    done
}

function get_deleted_mysql_server() {
    echo -e "\n${C_YELLOW}--- $(t SelectDeletedServer) ---${C_NC}"
    local attempts=0
    local max_attempts=3
    
    while [ $attempts -lt $max_attempts ]; do
        read -p "$(t EnterRGName): " RG_NAME
        
        printf "$(t ValidatingRG)\n" "$RG_NAME"
        if az group show --name "$RG_NAME" &> /dev/null; then
            printf "${C_GREEN}$(t RGValidated)${C_NC}\n" "$RG_NAME"
            break
        else
            attempts=$((attempts + 1))
            if [ $attempts -ge $max_attempts ]; then
                printf "${C_RED}$(t RGNotFound)${C_NC}\n" "$RG_NAME" >&2
                return 1
            fi
            printf "${C_YELLOW}$(t RGNotFound)\n Please try again. Attempts left: %d${C_NC}\n" "$RG_NAME" "$((max_attempts - attempts))"
        fi
    done
    
    echo "$(t SearchingActivityLog)"
    local spin='-\|/'
    (
      az monitor activity-log list --resource-group "$RG_NAME" --offset 5d --namespace "Microsoft.DBforMySQL" --max-events 1000 \
        --query "[?operationName.value=='Microsoft.DBforMySQL/flexibleServers/delete' && status.value=='Succeeded'].{resourceId:resourceId, eventTimestamp:eventTimestamp}" --output json > /tmp/deleted_servers.json
    ) &
    local pid=$!
    while kill -0 $pid 2>/dev/null; do
      i=$(( (i+1) %4 )); printf "\r[%c] Searching..." "${spin:$i:1}"; sleep .1;
    done
    printf "\rSearch complete.  \n"

    DELETED_SERVERS_JSON=$(cat /tmp/deleted_servers.json)
    rm /tmp/deleted_servers.json
    
    if [[ -z "$DELETED_SERVERS_JSON" || "$(echo "$DELETED_SERVERS_JSON" | jq 'length')" -eq 0 ]]; then
        printf "${C_YELLOW}$(t NoDeletedServers)${C_NC}\n" "$RG_NAME"
        return 1
    fi
    
    mapfile -t server_resource_ids < <(echo "$DELETED_SERVERS_JSON" | jq -r '.[].resourceId')
    mapfile -t server_deleted_times < <(echo "$DELETED_SERVERS_JSON" | jq -r '.[].eventTimestamp')

    echo "$(t SelectDeletedServer):"
    for i in "${!server_resource_ids[@]}"; do
        local server_name=$(basename "${server_resource_ids[$i]}")
        printf "%d. %s (Deleted at: %s)\n" "$((i + 1))" "$server_name" "${server_deleted_times[$i]}"
    done

    while true; do
        read -p "$(t SelectDeletedServer): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#server_resource_ids[@]}" ]; then
            SELECTED_DELETED_SERVER_ID="${server_resource_ids[$((choice - 1))]}"
            SELECTED_DELETED_SERVER_NAME=$(basename "$SELECTED_DELETED_SERVER_ID")
            SELECTED_DELETED_SERVER_TIME="${server_deleted_times[$((choice - 1))]}"
            return 0
        else
            echo -e "${C_YELLOW}$(t InvalidSelection)${C_NC}"
        fi
    done
}

# --- [REVISED FUNCTION] ---
function select_restore_location() {
    echo -e "\n${C_YELLOW}--- $(t SelectLocation) ---${C_NC}"
    echo -e "${C_YELLOW}$(t RestoreLocationHint)${C_NC}"
    echo "$(t FetchingLocations)"
    
    local rg_location
    rg_location=$(az group show --name "$RG_NAME" --query location -o tsv 2>/dev/null | tr -d '[:space:]')
    
    # CORRECTED LINE: Use lowercase 'name' and 'displayName' in the query to match the jq filter later.
    LOCATIONS_JSON=$(az account list-locations --query "[?metadata.regionType=='Physical'].{name:name, displayName:displayName}" -o json)
    if [ -z "$LOCATIONS_JSON" ]; then
        echo -e "${C_RED}$(t LocationFetchError)${C_NC}" >&2
        return 1
    fi

    local default_index=-1
    local default_loc_display_name=""
    local i=0

    declare -a loc_names
    declare -a loc_display_names

    echo "Available locations:"
    while IFS=$'\t' read -r name displayName; do
        i=$((i + 1))
        loc_names[$i]=$name
        loc_display_names[$i]=$displayName
        
        local name_trimmed
        name_trimmed=$(echo "$name" | tr -d '[:space:]')

        if [[ -n "$rg_location" && "$name_trimmed" == "$rg_location" ]]; then
            default_index=$i
            default_loc_display_name=$displayName
            printf "${C_GREEN}%d. %s (%s) %s${C_NC}\n" "$i" "$displayName" "$name" "$(t DefaultSuffix)"
        else
            printf "%d. %s (%s)\n" "$i" "$displayName" "$name"
        fi
    done < <(echo "$LOCATIONS_JSON" | jq -r '.[] | [.name, .displayName] | @tsv')

    local loc_count=$i
    while true; do
        local prompt_str
        if [[ -n "$default_loc_display_name" ]]; then
            printf -v prompt_str "$(t DefaultSubPrompt)" "$default_loc_display_name"
        else
            prompt_str="$(t SelectLocation)"
        fi
        
        read -p "$prompt_str: " choice
        if [[ -z "$choice" && $default_index -ne -1 ]]; then
            choice=$default_index
        fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$loc_count" ]; then
            SELECTED_LOCATION="${loc_names[$choice]}"
            printf "Location set to: ${C_CYAN}%s${C_NC}\n" "$SELECTED_LOCATION"
            return 0
        else
            echo -e "${C_YELLOW}$(t InvalidSelection)${C_NC}"
        fi
    done
}

function invoke_mysql_restore() {
    echo -e "\n${C_MAGENTA}--- $(t RestoreOperationTitle) ---${C_NC}"
    read -p "$(t EnterNewServerName): " NEW_SERVER_NAME
    
    local deletion_timestamp_unix=$(date -d"$SELECTED_DELETED_SERVER_TIME" +%s)
    local restore_point_unix=$((deletion_timestamp_unix - 15 * 60))
    local restore_point_for_api=$(date -u -d"@$restore_point_unix" +"%Y-%m-%dT%H:%M:%SZ")

    echo -e "${C_CYAN}$(t RestoreSummary)${C_NC}"
    printf "${C_CYAN}$(t SourceServer)${C_NC}\n" "$SELECTED_DELETED_SERVER_NAME"
    printf "${C_CYAN}$(t NewServerName)${C_NC}\n" "$NEW_SERVER_NAME"
    printf "${C_CYAN}$(t TargetLocation)${C_NC}\n" "$SELECTED_LOCATION"
    printf "${C_CYAN}$(t RestorePoint)${C_NC}\n" "$restore_point_for_api"
    
    read -p "$(t ConfirmRestore) " confirmation
    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        echo -e "${C_YELLOW}$(t OperationCancelled)${C_NC}"
        return
    fi
    
    printf "$(t RestoringServer)\n" "$SELECTED_DELETED_SERVER_NAME" "$NEW_SERVER_NAME" "$SELECTED_LOCATION"
    
    local api_version="2024-06-01-preview"
    local request_uri="${ARM_ENDPOINT}/subscriptions/${SELECTED_SUB_ID}/resourceGroups/${RG_NAME}/providers/Microsoft.DBforMySQL/flexibleServers/${NEW_SERVER_NAME}?api-version=${api_version}"
    
    local request_body
    request_body=$(jq -n \
                  --arg loc "$SELECTED_LOCATION" \
                  --arg sourceId "$SELECTED_DELETED_SERVER_ID" \
                  --arg restoreTime "$restore_point_for_api" \
                  '{location: $loc, properties: {createMode: "PointInTimeRestore", sourceServerResourceId: $sourceId, restorePointInTime: $restoreTime}}')

    output=$(az rest --method put --uri "$request_uri" --body "$request_body" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${C_GREEN}$(t RestoreSuccess)${C_NC}"
        printf "${C_YELLOW}$(t RestoreMonitoringHint)${C_NC}\n" "$RG_NAME"
        echo -e "${C_CYAN}$(t RestoreResponse)${C_NC}"
        echo "$output" | jq .
    else
        echo -e "${C_RED}$(t RestoreFailed)${C_NC}" >&2
        echo -e "${C_RED}$(t ErrorDetails)${C_NC}" >&2
        echo "$output" >&2
    fi
}
#endregion

# --- Script Entry Point ---
function main() {
    trap 'echo -e "\n\nScript interrupted."; exit 130' INT

    select_language
    clear
    echo -e "${C_CYAN}$(t Welcome)${C_NC}"

    if ! check_prerequisites; then
        echo -e "${C_RED}$(t PrereqCheckFailed)${C_NC}" >&2; exit 1;
    fi
    if ! select_azure_cloud; then exit 1; fi
    if ! confirm_azure_login; then exit 1; fi
    if ! select_azure_subscription; then exit 1; fi
    if ! get_deleted_mysql_server; then exit 1; fi
    if ! select_restore_location; then exit 1; fi

    invoke_mysql_restore

    echo -e "${C_GREEN}\n$(t ScriptFinished)${C_NC}"
}

main "$@"
