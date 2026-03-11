# Azure China Flexible Server — CA 证书轮换批量检测工具

Azure China（世纪互联）从 2026 年 3 月 9 日起，将 PostgreSQL 和 MySQL Flexible Server 的 Root CA 从 **DigiCert Global Root CA**（G1）轮换到 **DigiCert Global Root G2**。本工具用于批量检测所有服务器的轮换状态，提供 Bash 和 PowerShell 两个版本。

## 文件说明

| 文件 | 适用平台 | 说明 |
|------|---------|------|
| `check_ca_rotation.sh` | Linux / macOS | Bash 版本，使用 `xargs -P` 并发；macOS 需提供 GNU `xargs` |
| `Check-CaRotation.ps1` | Windows / 跨平台 | PowerShell 版本，兼容 PS 5.1+ 和 pwsh 7+ |

## 前置条件

| 依赖 | 最低版本 | 用途 | 何时必需 |
|------|---------|------|---------|
| openssl | 1.1.0 | TLS 连接并获取证书链 | 始终 |
| nslookup / Resolve-DnsName | — | DNS 解析 | 始终（一般内置） |
| timeout / gtimeout | — | 连接超时控制（Bash 版） | 仅 Bash |
| az CLI | — | 从 Azure 获取服务器列表 | 仅 az CLI 模式 |

> **OpenSSL 版本说明**：`-starttls mysql` 和 `-starttls postgres` 需要 OpenSSL 1.1.0 及以上。macOS 自带的 LibreSSL 可能不支持这两个协议，建议通过 `brew install openssl` 安装。

### 安装依赖

**Linux (Debian/Ubuntu)**

```bash
sudo apt install openssl coreutils dnsutils    # openssl + timeout + nslookup
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash  # az CLI（可选）
```

**macOS**

```bash
brew install openssl coreutils findutils   # openssl + gtimeout + GNU xargs
brew install azure-cli                # az CLI（可选）
```

如果使用 Bash 版，macOS 还需要让 GNU 工具优先进入 `PATH`，否则系统自带的 BSD `xargs` 不支持脚本所用的 `-d` 参数：

```bash
export PATH="$(brew --prefix findutils)/libexec/gnubin:$(brew --prefix openssl)/bin:$PATH"
```

**Windows**

```powershell
winget install ShiningLight.OpenSSL   # 或 choco install openssl
winget install Microsoft.AzureCLI    # az CLI（可选）
```

## 使用方式

### 模式一：az CLI 动态获取（默认）

需要先登录 Azure China 环境：

```bash
az cloud set --name AzureChinaCloud
az login
```

> `--subscription` / `-Subscription` 和 `--all-subscriptions` / `-AllSubscriptions` 会切换当前 Azure CLI profile 的默认订阅，脚本结束后不会自动恢复。若希望隔离影响，建议配合 `AZURE_CONFIG_DIR` 使用独立 profile。

```bash
# 扫描当前订阅下所有 Flexible Server
./check_ca_rotation.sh

# 指定订阅
./check_ca_rotation.sh --subscription <subscription-id>

# 仅检测 MySQL
./check_ca_rotation.sh --type mysql

# 遍历所有已启用的订阅
./check_ca_rotation.sh --all-subscriptions

# 导出 CSV 报告
./check_ca_rotation.sh --all-subscriptions --output report.csv
```

PowerShell 版本参数对应：

```powershell
.\Check-CaRotation.ps1
.\Check-CaRotation.ps1 -Subscription <subscription-id>
.\Check-CaRotation.ps1 -Type mysql
.\Check-CaRotation.ps1 -AllSubscriptions
.\Check-CaRotation.ps1 -AllSubscriptions -Output report.csv
```

### 模式二：CSV 文件输入

当无法登录 az CLI 或需要检测已知服务器列表时，可以通过 CSV 文件输入。此模式不需要 az CLI。

CSV 格式（首行为表头）：

```csv
server_name,type
my-mysql-server,mysql
my-pg-server,postgres
```

```bash
./check_ca_rotation.sh --file servers.csv
./check_ca_rotation.sh --file servers.csv --output report.csv
```

```powershell
.\Check-CaRotation.ps1 -File servers.csv
.\Check-CaRotation.ps1 -File servers.csv -Output report.csv
```

## 参数一览

### Bash 版 (`check_ca_rotation.sh`)

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--file <path>` | CSV 文件输入（跳过 az CLI 检查） | — |
| `--type <mysql\|postgres\|all>` | 服务器类型过滤 | `all` |
| `--subscription <id>` | 指定 Azure 订阅 | 当前默认订阅 |
| `--all-subscriptions` | 遍历所有已启用的订阅 | — |
| `--parallel <N>` | 并发数 | `20` |
| `--output <path>` | CSV 报告输出路径 | — |
| `--help` | 显示帮助 | — |

### PowerShell 版 (`Check-CaRotation.ps1`)

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-File <path>` | CSV 文件输入 | — |
| `-Type <mysql\|postgres\|all>` | 服务器类型过滤 | `all` |
| `-Subscription <id>` | 指定 Azure 订阅 | 当前默认订阅 |
| `-AllSubscriptions` | 遍历所有已启用的订阅 | — |
| `-Parallel <N>` | 并发数 | `10` |
| `-Output <path>` | CSV 报告输出路径 | — |
| `-Help` | 显示帮助 | — |

## 检测逻辑

对每台服务器，脚本依次执行以下步骤：

1. **拼接 FQDN** — 根据服务器类型拼接 China 区域名：
   - MySQL: `<name>.mysql.database.chinacloudapi.cn:3306`
   - PostgreSQL: `<name>.postgres.database.chinacloudapi.cn:5432`

2. **DNS 解析** — 通过 nslookup / Resolve-DnsName 检查域名是否可达：
   - CNAME 指向 `privatelink.*` 且无公网 A 记录 → 标记为「仅内网」
   - NXDOMAIN → 标记为「DNS 失败」

3. **TLS 连接** — 通过 `openssl s_client -starttls <protocol>` 获取证书链（超时 5 秒）

4. **证书链解析** — 从证书链中提取根 CA 信息：
   - 完整链（3 层）：取最后一张自签名证书的 Subject CN
   - 不完整链（2 层）：取最后一张证书的 Issuer CN 推断根 CA

5. **判定结果**：
   - 根 CA 为 `DigiCert Global Root G2` → 已轮换
   - 根 CA 为 `DigiCert Global Root CA`（非 G2） → 未轮换
   - 其他情况 → 未知

## 输出说明

### 终端输出

```
✅ [已轮换]  my-server (PostgreSQL)        → DigiCert Global Root G2
❌ [未轮换]  old-server (MySQL)            → DigiCert Global Root CA
🔒 [仅内网]  private-server (MySQL)        → Private Link / DNS 不可达
⏱️  [超时]    stopped-server (PostgreSQL)   → 连接超时
```

### 汇总统计

```
===== 检测汇总 =====
总计: 100 台
✅ 已轮换:  60
❌ 未轮换:   5
🔒 仅内网:  30
⏱️  超时:     5
```

### CSV 报告

通过 `--output` / `-Output` 参数导出，包含以下字段：

| 字段 | 说明 |
|------|------|
| `subscription` | 所属订阅名称（文件模式下为空） |
| `server_name` | 服务器名称 |
| `type` | MySQL 或 PostgreSQL |
| `fqdn` | 完整域名及端口 |
| `status` | 已轮换 / 未轮换 / 仅内网 / 超时 / DNS失败 / 未知 |
| `root_ca` | 根 CA 名称 |
| `intermediate_ca` | 中间 CA 名称 |
| `cert_not_after` | 叶证书过期时间 |

## 常见问题

### 「仅内网」是什么意思？

服务器启用了 Private Link（私有终结点），DNS 的 CNAME 指向 `privatelink.*` 域名，但从公网无法解析到 IP 地址。这类服务器需要从 VNet 内部检测。

### 「超时」的可能原因？

- 服务器已停止运行
- 防火墙规则阻止了来自检测机器的连接
- 网络不可达

### macOS 上报错 `-starttls` 不支持？

macOS 自带的 LibreSSL 不支持 `-starttls mysql` 和 `-starttls postgres`。请安装 OpenSSL：

```bash
brew install openssl
export PATH="$(brew --prefix openssl)/bin:$PATH"
```

### 如何配合多 Azure 账号使用？

通过 `AZURE_CONFIG_DIR` 环境变量切换 az CLI 配置目录：

```bash
AZURE_CONFIG_DIR=~/.azure-profiles/Lab ./check_ca_rotation.sh --all-subscriptions
```

## 参考文档

- [Azure China PostgreSQL TLS 证书](https://docs.azure.cn/en-us/postgresql/security/security-tls)
- [Azure China MySQL TLS 根证书轮换](https://docs.azure.cn/en-us/mysql/flexible-server/security-tls-root-certificate-rotation)
- [Azure Global PostgreSQL TLS](https://learn.microsoft.com/azure/postgresql/security/security-tls)
- [az CLI 云环境管理](https://learn.microsoft.com/cli/azure/manage-clouds-azure-cli)
