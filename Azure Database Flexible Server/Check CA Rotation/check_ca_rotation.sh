#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# check_ca_rotation.sh
# Batch-check Azure China PostgreSQL/MySQL Flexible Server CA certificate
# rotation status.
# =============================================================================

# ---------------------------------------------------------------------------
# Color / emoji helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    C_GREEN='\033[0;32m'
    C_RED='\033[0;31m'
    C_YELLOW='\033[0;33m'
    C_CYAN='\033[0;36m'
    C_BOLD='\033[1m'
    C_RESET='\033[0m'
else
    C_GREEN=''
    C_RED=''
    C_YELLOW=''
    C_CYAN=''
    C_BOLD=''
    C_RESET=''
fi

# ---------------------------------------------------------------------------
# Global defaults
# ---------------------------------------------------------------------------
FILE_INPUT=""
SERVER_TYPE="all"
SUBSCRIPTION=""
ALL_SUBSCRIPTIONS=false
PARALLEL=20
OUTPUT_CSV=""
TMPDIR_BASE=""
RESULT_FILE=""
TIMEOUT_BIN=""

# ---------------------------------------------------------------------------
# Cleanup on exit
# ---------------------------------------------------------------------------
cleanup() {
    if [[ -n "${TMPDIR_BASE}" && -d "${TMPDIR_BASE}" ]]; then
        rm -rf "${TMPDIR_BASE}"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# usage / help
# ---------------------------------------------------------------------------
usage() {
    local exit_code="${1:-0}"
    cat <<'EOF'
用法: check_ca_rotation.sh [选项]

选项:
  --file <path>              CSV 文件输入 (跳过 az CLI 检查)
                             CSV 格式: server_name,type (含表头)
  --type <mysql|postgres|all> 服务器类型过滤 (默认: all)
  --subscription <sub-id>    Azure 订阅 ID
  --all-subscriptions        扫描所有已启用的订阅
  --parallel <N>             并发数 (默认: 20)
  --output <path>            CSV 报告输出路径
  --help                     显示此帮助信息

示例:
  # 使用 az CLI 扫描当前订阅
  ./check_ca_rotation.sh

  # 扫描所有订阅的 MySQL 服务器
  ./check_ca_rotation.sh --all-subscriptions --type mysql

  # 从 CSV 文件读取并输出报告
  ./check_ca_rotation.sh --file servers.csv --output report.csv
EOF
    exit "$exit_code"
}

# ---------------------------------------------------------------------------
# parse_args
# ---------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)
                FILE_INPUT="${2:?'--file 需要一个路径参数'}"
                shift 2
                ;;
            --type)
                SERVER_TYPE="${2:?'--type 需要 mysql|postgres|all'}"
                if [[ "$SERVER_TYPE" != "mysql" && "$SERVER_TYPE" != "postgres" && "$SERVER_TYPE" != "all" ]]; then
                    echo -e "${C_RED}错误: --type 只接受 mysql、postgres 或 all${C_RESET}" >&2
                    exit 1
                fi
                shift 2
                ;;
            --subscription)
                SUBSCRIPTION="${2:?'--subscription 需要订阅 ID'}"
                shift 2
                ;;
            --all-subscriptions)
                ALL_SUBSCRIPTIONS=true
                shift
                ;;
            --parallel)
                PARALLEL="${2:?'--parallel 需要一个数字'}"
                if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]] || [[ "$PARALLEL" -lt 1 ]]; then
                    echo -e "${C_RED}错误: --parallel 必须为正整数${C_RESET}" >&2
                    exit 1
                fi
                shift 2
                ;;
            --output)
                OUTPUT_CSV="${2:?'--output 需要一个路径参数'}"
                shift 2
                ;;
            --help|-h)
                usage
                ;;
            *)
                echo -e "${C_RED}未知参数: $1${C_RESET}" >&2
                usage 1
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# check_prerequisites  — openssl >= 1.1.0, nslookup
# ---------------------------------------------------------------------------
check_prerequisites() {
    # --- openssl ---
    if ! command -v openssl &>/dev/null; then
        echo -e "${C_RED}❌ 未找到 openssl，请先安装:${C_RESET}" >&2
        echo "   sudo apt install openssl  /  sudo yum install openssl  /  brew install openssl" >&2
        exit 1
    fi

    local openssl_ver_str
    openssl_ver_str="$(openssl version 2>&1)"

    # Extract version number — handles "OpenSSL 1.1.1k ..." and "OpenSSL 3.0.2 ..."
    local ver_num
    ver_num="$(echo "$openssl_ver_str" | sed -n 's/.*OpenSSL \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')"
    if [[ -z "$ver_num" ]]; then
        # Try LibreSSL format
        ver_num="$(echo "$openssl_ver_str" | sed -n 's/.*LibreSSL \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')"
    fi
    if [[ -z "$ver_num" ]]; then
        echo -e "${C_YELLOW}⚠️  无法解析 openssl 版本: ${openssl_ver_str}${C_RESET}" >&2
        echo "   脚本需要 openssl >= 1.1.0 (支持 -starttls mysql/postgres)" >&2
        echo "   安装: sudo apt install openssl / sudo yum install openssl / brew install openssl" >&2
        exit 1
    fi

    local major minor
    major="$(echo "$ver_num" | cut -d. -f1)"
    minor="$(echo "$ver_num" | cut -d. -f2)"

    # Need >= 1.1.0
    if [[ "$major" -lt 1 ]] || { [[ "$major" -eq 1 ]] && [[ "$minor" -lt 1 ]]; }; then
        echo -e "${C_RED}❌ openssl 版本过低: ${ver_num} (需要 >= 1.1.0)${C_RESET}" >&2
        echo "   -starttls mysql/postgres 需要 openssl 1.1.0+。" >&2
        echo "   安装: sudo apt install openssl / sudo yum install openssl / brew install openssl" >&2
        exit 1
    fi

    # --- nslookup ---
    if ! command -v nslookup &>/dev/null; then
        echo -e "${C_RED}❌ 未找到 nslookup，请先安装 (通常属于 dnsutils / bind-utils)。${C_RESET}" >&2
        exit 1
    fi

    if command -v timeout &>/dev/null; then
        TIMEOUT_BIN="$(command -v timeout)"
    elif command -v gtimeout &>/dev/null; then
        TIMEOUT_BIN="$(command -v gtimeout)"
    else
        echo -e "${C_RED}❌ 未找到 timeout/gtimeout，请先安装 coreutils。${C_RESET}" >&2
        echo "   Linux: sudo apt install coreutils / sudo yum install coreutils" >&2
        echo "   macOS: brew install coreutils" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# check_az_prerequisites  — az CLI install / login / cloud env / subscription
# ---------------------------------------------------------------------------
check_az_prerequisites() {
    # 1. Check az installed
    if ! command -v az &>/dev/null; then
        echo -e "${C_RED}❌ 未找到 az CLI，请先安装:${C_RESET}" >&2
        echo "   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash" >&2
        exit 1
    fi

    # 2. Check login
    local account_json
    account_json="$(az account show 2>&1)" || true
    if echo "$account_json" | grep -qi "please run.*az login\|not logged in\|AADSTS\|ERROR\|error"; then
        echo -e "${C_RED}❌ 未登录 Azure CLI，请先执行:${C_RESET}" >&2
        echo "   az cloud set --name AzureChinaCloud" >&2
        echo "   az login" >&2
        exit 1
    fi

    # 3. Check cloud environment (use az query instead of python3)
    local env_name
    env_name="$(az account show --query "environmentName" -o tsv 2>/dev/null || true)"
    if [[ -z "$env_name" ]]; then
        env_name="$(echo "$account_json" | grep -o '"environmentName"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"environmentName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
    fi
    if [[ "$env_name" != "AzureChinaCloud" ]]; then
        echo -e "${C_YELLOW}⚠️  当前 az CLI 环境为 ${env_name}，非 AzureChinaCloud${C_RESET}" >&2
        echo "   请执行: az cloud set --name AzureChinaCloud && az login" >&2
    fi

    # 4. Subscription handling
    if [[ -n "$SUBSCRIPTION" ]]; then
        echo -e "${C_CYAN}📌 切换订阅: ${SUBSCRIPTION}${C_RESET}"
        az account set -s "$SUBSCRIPTION"
    elif [[ "$ALL_SUBSCRIPTIONS" != true ]]; then
        local sub_name sub_id
        sub_name="$(az account show --query "name" -o tsv 2>/dev/null || true)"
        sub_id="$(az account show --query "id" -o tsv 2>/dev/null || true)"
        echo -e "${C_CYAN}📌 当前订阅: ${sub_name} (${sub_id})${C_RESET}"
    fi
}

# ---------------------------------------------------------------------------
# get_servers_from_az  — list MySQL / PostgreSQL flexible servers
#   Writes tab-delimited lines: server_name\ttype\tsubscription_name
# ---------------------------------------------------------------------------
get_servers_from_az() {
    local server_list_file="$1"
    local sub_ids=()
    local sub_names=()

    if [[ "$ALL_SUBSCRIPTIONS" == true ]]; then
        # Get all enabled subscriptions
        local subs_tsv
        subs_tsv="$(az account list --query "[?state=='Enabled'].{id:id, name:name}" -o tsv 2>/dev/null)"
        if [[ -z "$subs_tsv" ]]; then
            echo -e "${C_RED}❌ 未找到已启用的订阅${C_RESET}" >&2
            exit 1
        fi
        while IFS=$'\t' read -r sid sname; do
            sub_ids+=("$sid")
            sub_names+=("$sname")
        done <<< "$subs_tsv"
    else
        local sid sname
        sid="$(az account show --query "id" -o tsv 2>/dev/null || true)"
        sname="$(az account show --query "name" -o tsv 2>/dev/null || true)"
        sub_ids+=("$sid")
        sub_names+=("$sname")
    fi

    for i in "${!sub_ids[@]}"; do
        local sid="${sub_ids[$i]}"
        local sname="${sub_names[$i]}"

        if [[ "$ALL_SUBSCRIPTIONS" == true ]]; then
            echo -e "${C_CYAN}📌 扫描订阅: ${sname} (${sid})${C_RESET}"
            az account set -s "$sid" 2>/dev/null
        fi

        # MySQL
        if [[ "$SERVER_TYPE" == "all" || "$SERVER_TYPE" == "mysql" ]]; then
            local mysql_servers
            mysql_servers="$(az mysql flexible-server list --query "[].name" -o tsv 2>/dev/null || true)"
            if [[ -n "$mysql_servers" ]]; then
                while IFS= read -r name; do
                    [[ -z "$name" ]] && continue
                    printf '%s\t%s\t%s\n' "$name" "mysql" "$sname" >> "$server_list_file"
                done <<< "$mysql_servers"
            fi
        fi

        # PostgreSQL
        if [[ "$SERVER_TYPE" == "all" || "$SERVER_TYPE" == "postgres" ]]; then
            local pg_servers
            pg_servers="$(az postgres flexible-server list --query "[].name" -o tsv 2>/dev/null || true)"
            if [[ -n "$pg_servers" ]]; then
                while IFS= read -r name; do
                    [[ -z "$name" ]] && continue
                    printf '%s\t%s\t%s\n' "$name" "postgres" "$sname" >> "$server_list_file"
                done <<< "$pg_servers"
            fi
        fi
    done
}

# ---------------------------------------------------------------------------
# get_servers_from_file  — read CSV (BOM-safe, CRLF-safe)
#   Writes tab-delimited lines: server_name\ttype\t(empty subscription)
# ---------------------------------------------------------------------------
get_servers_from_file() {
    local csv_path="$1"
    local server_list_file="$2"

    if [[ ! -f "$csv_path" ]]; then
        echo -e "${C_RED}❌ 文件不存在: ${csv_path}${C_RESET}" >&2
        exit 1
    fi

    # Read file, strip BOM, strip CR, skip header
    local line_num=0
    while IFS=',' read -r sname stype rest; do
        line_num=$((line_num + 1))
        [[ $line_num -eq 1 ]] && continue          # skip header
        sname="$(echo "$sname" | tr -d '\r' | xargs)"
        stype="$(echo "$stype" | tr -d '\r' | xargs)"
        [[ -z "$sname" ]] && continue

        # Normalise type
        stype="$(echo "$stype" | tr '[:upper:]' '[:lower:]')"
        case "$stype" in
            mysql|postgres) ;;
            postgresql) stype="postgres" ;;
            *)
                echo -e "${C_YELLOW}⚠️  跳过未知类型 (行 ${line_num}): ${sname},${stype}${C_RESET}" >&2
                continue
                ;;
        esac

        # Filter by --type
        if [[ "$SERVER_TYPE" != "all" && "$stype" != "$SERVER_TYPE" ]]; then
            continue
        fi

        printf '%s\t%s\t-\n' "$sname" "$stype" >> "$server_list_file"
    done < <(sed '1s/^\xEF\xBB\xBF//' "$csv_path" | tr -d '\r')
}

# ---------------------------------------------------------------------------
# check_single_server  (exported for xargs)
#   Args: receives a single tab-delimited line: server_name\ttype\tsubscription
#   Outputs one tab-delimited result line to RESULT_FILE
# ---------------------------------------------------------------------------
check_single_server() {
    # Input is a tab-delimited line
    local line="$*"
    local server_name server_type subscription_name
    IFS=$'\t' read -r server_name server_type subscription_name <<< "$line"

    local fqdn port starttls_proto type_label

    case "$server_type" in
        mysql)
            fqdn="${server_name}.mysql.database.chinacloudapi.cn"
            port=3306
            starttls_proto="mysql"
            type_label="MySQL"
            ;;
        postgres)
            fqdn="${server_name}.postgres.database.chinacloudapi.cn"
            port=5432
            starttls_proto="postgres"
            type_label="PostgreSQL"
            ;;
        *)
            echo -e "${C_YELLOW}⚠️  未知类型: ${server_type}${C_RESET}" >&2
            return
            ;;
    esac

    # ----- DNS check -----
    local dns_out
    dns_out="$(nslookup "$fqdn" 2>&1 || true)"

    # Check NXDOMAIN / can't find
    if echo "$dns_out" | grep -qi "NXDOMAIN\|server can't find\|Non-existent domain\|name or service not known"; then
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$subscription_name" "$server_name" "$type_label" "$fqdn:$port" \
            "DNS失败" "" "" "" >> "$RESULT_FILE"
        echo -e "${C_YELLOW}❓ [DNS失败]  ${server_name} (${type_label})$(printf '%*s' $((30 - ${#server_name})) '')→ DNS 解析失败${C_RESET}"
        return
    fi

    # Check privatelink with no public A record
    if echo "$dns_out" | grep -qi "privatelink"; then
        # Check whether there's an actual A record (IP address in answer)
        local has_ip
        has_ip="$(echo "$dns_out" | grep -E 'Address:[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -v '#53' || true)"
        if [[ -z "$has_ip" ]]; then
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$subscription_name" "$server_name" "$type_label" "$fqdn:$port" \
                "仅内网" "" "" "" >> "$RESULT_FILE"
            echo -e "${C_CYAN}🔒 [仅内网]  ${server_name} (${type_label})$(printf '%*s' $((30 - ${#server_name})) '')→ Private Link / DNS 不可达${C_RESET}"
            return
        fi
    fi

    # ----- SSL connect -----
    local ssl_out
    ssl_out="$(echo | "$TIMEOUT_BIN" 5 openssl s_client -starttls "$starttls_proto" -showcerts -connect "${fqdn}:${port}" 2>/dev/null || true)"

    if [[ -z "$ssl_out" ]] || ! echo "$ssl_out" | grep -q "BEGIN CERTIFICATE"; then
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$subscription_name" "$server_name" "$type_label" "$fqdn:$port" \
            "超时" "" "" "" >> "$RESULT_FILE"
        echo -e "${C_YELLOW}⏱️  [超时]    ${server_name} (${type_label})$(printf '%*s' $((30 - ${#server_name})) '')→ 连接超时${C_RESET}"
        return
    fi

    # ----- Parse certificates from chain -----
    local cert_pem_list=()
    local in_cert=false
    local current_cert=""

    while IFS= read -r line; do
        if [[ "$line" == "-----BEGIN CERTIFICATE-----" ]]; then
            in_cert=true
            current_cert="$line"$'\n'
        elif [[ "$line" == "-----END CERTIFICATE-----" ]]; then
            current_cert+="$line"$'\n'
            cert_pem_list+=("$current_cert")
            current_cert=""
            in_cert=false
        elif [[ "$in_cert" == true ]]; then
            current_cert+="$line"$'\n'
        fi
    done <<< "$ssl_out"

    local cert_count=${#cert_pem_list[@]}
    local root_ca_cn=""
    local intermediate_ca_cn=""
    local cert_not_after=""

    # Extract not_after from leaf cert (first cert)
    if [[ $cert_count -ge 1 ]]; then
        cert_not_after="$(echo "${cert_pem_list[0]}" | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//' || true)"
    fi

    if [[ $cert_count -ge 3 ]]; then
        # Full chain: last cert is self-signed root CA
        local last_cert="${cert_pem_list[$((cert_count - 1))]}"
        root_ca_cn="$(echo "$last_cert" | openssl x509 -noout -subject 2>/dev/null | sed 's/.*CN[[:space:]]*=[[:space:]]*//' | sed 's/\/.*//' || true)"

        # Intermediate is second-to-last
        if [[ $cert_count -ge 2 ]]; then
            local inter_cert="${cert_pem_list[$((cert_count - 2))]}"
            intermediate_ca_cn="$(echo "$inter_cert" | openssl x509 -noout -subject 2>/dev/null | sed 's/.*CN[[:space:]]*=[[:space:]]*//' | sed 's/\/.*//' || true)"
        fi
    elif [[ $cert_count -eq 2 ]]; then
        # Incomplete chain: last cert is intermediate → get its Issuer CN to infer root
        local last_cert="${cert_pem_list[$((cert_count - 1))]}"
        intermediate_ca_cn="$(echo "$last_cert" | openssl x509 -noout -subject 2>/dev/null | sed 's/.*CN[[:space:]]*=[[:space:]]*//' | sed 's/\/.*//' || true)"
        root_ca_cn="$(echo "$last_cert" | openssl x509 -noout -issuer 2>/dev/null | sed 's/.*CN[[:space:]]*=[[:space:]]*//' | sed 's/\/.*//' || true)"
    elif [[ $cert_count -eq 1 ]]; then
        # Only leaf cert — try to infer from issuer chain
        local leaf_cert="${cert_pem_list[0]}"
        root_ca_cn="$(echo "$leaf_cert" | openssl x509 -noout -issuer 2>/dev/null | sed 's/.*CN[[:space:]]*=[[:space:]]*//' | sed 's/\/.*//' || true)"
    fi

    # ----- Judgment -----
    local status display_ca
    display_ca="$root_ca_cn"

    if echo "$root_ca_cn" | grep -qi "DigiCert Global Root G2"; then
        status="已轮换"
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$subscription_name" "$server_name" "$type_label" "$fqdn:$port" \
            "$status" "$root_ca_cn" "$intermediate_ca_cn" "$cert_not_after" >> "$RESULT_FILE"
        echo -e "${C_GREEN}✅ [已轮换]  ${server_name} (${type_label})$(printf '%*s' $((30 - ${#server_name})) '')→ ${display_ca}${C_RESET}"
    elif echo "$root_ca_cn" | grep -qi "DigiCert Global Root CA"; then
        status="未轮换"
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$subscription_name" "$server_name" "$type_label" "$fqdn:$port" \
            "$status" "$root_ca_cn" "$intermediate_ca_cn" "$cert_not_after" >> "$RESULT_FILE"
        echo -e "${C_RED}❌ [未轮换]  ${server_name} (${type_label})$(printf '%*s' $((30 - ${#server_name})) '')→ ${display_ca}${C_RESET}"
    else
        status="未知"
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$subscription_name" "$server_name" "$type_label" "$fqdn:$port" \
            "$status" "$root_ca_cn" "$intermediate_ca_cn" "$cert_not_after" >> "$RESULT_FILE"
        echo -e "${C_YELLOW}❓ [未知]    ${server_name} (${type_label})$(printf '%*s' $((30 - ${#server_name})) '')→ ${display_ca:-N/A}${C_RESET}"
    fi
}

# Export for xargs sub-shells
export -f check_single_server

# ---------------------------------------------------------------------------
# print_summary
# ---------------------------------------------------------------------------
print_summary() {
    local total=0 rotated=0 not_rotated=0 private=0 timeout_count=0 dns_fail=0 unknown=0

    while IFS=$'\t' read -r _sub _name _type _fqdn status _root _inter _expire; do
        total=$((total + 1))
        case "$status" in
            已轮换)      rotated=$((rotated + 1)) ;;
            未轮换)      not_rotated=$((not_rotated + 1)) ;;
            仅内网)      private=$((private + 1)) ;;
            超时)        timeout_count=$((timeout_count + 1)) ;;
            DNS失败)     dns_fail=$((dns_fail + 1)) ;;
            *)           unknown=$((unknown + 1)) ;;
        esac
    done < "$RESULT_FILE"

    echo ""
    echo -e "${C_BOLD}===== 检测汇总 =====${C_RESET}"
    printf "总计: %d 台\n" "$total"
    echo -e "${C_GREEN}✅ 已轮换:  ${rotated}${C_RESET}"
    echo -e "${C_RED}❌ 未轮换:  ${not_rotated}${C_RESET}"
    echo -e "${C_CYAN}🔒 仅内网:  ${private}${C_RESET}"
    echo -e "${C_YELLOW}⏱️  超时:    ${timeout_count}${C_RESET}"
    if [[ $dns_fail -gt 0 ]]; then
        echo -e "${C_YELLOW}❓ DNS失败: ${dns_fail}${C_RESET}"
    fi
    if [[ $unknown -gt 0 ]]; then
        echo -e "${C_YELLOW}❓ 未知:    ${unknown}${C_RESET}"
    fi
}

# ---------------------------------------------------------------------------
# export_csv
# ---------------------------------------------------------------------------
export_csv() {
    local out_path="$1"

    {
        echo "subscription,server_name,type,fqdn,status,root_ca,intermediate_ca,cert_not_after"
        while IFS=$'\t' read -r sub name stype fqdn status root inter expire; do
            # In file mode, subscription placeholder '-' → empty
            [[ "$sub" == "-" ]] && sub=""
            # Escape fields that might contain commas
            printf '"%s","%s","%s","%s","%s","%s","%s","%s"\n' \
                "$sub" "$name" "$stype" "$fqdn" "$status" "$root" "$inter" "$expire"
        done < "$RESULT_FILE"
    } > "$out_path"

    echo ""
    echo -e "${C_GREEN}📄 CSV 报告已保存: ${out_path}${C_RESET}"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"

    # Prerequisites
    check_prerequisites

    # Temp directory
    TMPDIR_BASE="$(mktemp -d -t check_ca_XXXXXX)"
    RESULT_FILE="${TMPDIR_BASE}/results.tsv"
    touch "$RESULT_FILE"

    # Export variables needed by check_single_server in xargs sub-shells
    export RESULT_FILE
    export C_GREEN C_RED C_YELLOW C_CYAN C_BOLD C_RESET
    export TIMEOUT_BIN

    local server_list_file="${TMPDIR_BASE}/servers.txt"
    touch "$server_list_file"

    if [[ -n "$FILE_INPUT" ]]; then
        # ---------- FILE MODE ----------
        echo -e "${C_BOLD}📂 从文件读取服务器列表: ${FILE_INPUT}${C_RESET}"
        get_servers_from_file "$FILE_INPUT" "$server_list_file"
    else
        # ---------- AZ CLI MODE ----------
        check_az_prerequisites
        echo ""
        echo -e "${C_BOLD}🔍 正在获取服务器列表...${C_RESET}"
        get_servers_from_az "$server_list_file"
    fi

    local total_servers
    total_servers="$(wc -l < "$server_list_file" | tr -d ' ')"

    if [[ "$total_servers" -eq 0 ]]; then
        echo -e "${C_YELLOW}⚠️  未找到任何服务器${C_RESET}"
        exit 0
    fi

    echo -e "${C_BOLD}🚀 开始检测 ${total_servers} 台服务器 (并发: ${PARALLEL})...${C_RESET}"
    echo ""

    # Run checks in parallel via xargs
    # Each line in server_list_file is tab-delimited: "server_name\ttype\tsubscription_name"
    # Use -d '\n' so each line is one argument (preserves tabs/spaces inside)
    cat "$server_list_file" | xargs -P "$PARALLEL" -d $'\n' -I{} bash -c '
        check_single_server "{}"
    '

    # Summary
    print_summary

    # CSV output
    if [[ -n "$OUTPUT_CSV" ]]; then
        export_csv "$OUTPUT_CSV"
    fi
}

main "$@"
