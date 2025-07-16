[Read the documentation in English](README.md)

---

# Azure DB for MySQL Flexible Server 恢复脚本

这是一组交互式脚本，旨在简化恢复已删除的 Azure Database for MySQL Flexible Server 的过程。如果您不小心删除了服务器，这些脚本提供了一个引导式的、分步的向导来帮助您恢复它。

此代码库包含两个功能相同但适用于不同操作系统的脚本：
* `Restore-DeletedAzMySQLFlexibleServer.ps1`: 适用于使用 PowerShell 的 **Windows** 用户。
* `restore_azmysql_flexible_server.sh`: 适用于使用 Bash 的 **Linux、macOS 或 WSL** 用户。

## 问题背景

当一个 Azure Database for MySQL 灵活服务器被删除后，其备份数据仍会保留 **5 天**，允许用户进行时间点还原。

这些脚本将整个过程自动化，提供了一个简单易用的交互式界面。如果脚本执行不成功，请参考[手动操作指南](https://docs.azure.cn/zh-cn/mysql/flexible-server/how-to-restore-dropped-server)

## 功能特性

- **交互式向导**: 一步步引导您完成整个恢复过程。
- **跨平台支持**: 同时提供适用于 Windows 的 PowerShell 脚本和适用于 Linux/macOS 的 Bash 脚本。
- **多语言界面**: 支持英文 (English) 和中文 (Chinese)。
- **自动发现**: 在您指定的资源组中，自动搜索 Azure 活动日志以查找最近删除的服务器。
- **云环境选择**: 允许您选择不同的 Azure 云环境（例如，Azure 全球区、Azure 中国区）。
- **简化 API 调用**: 封装了复杂的 REST API 请求构建和发送过程，让恢复操作更简单。

## 环境要求

在运行脚本之前，请确保您已安装以下工具：

#### Windows 用户 (使用 PowerShell)
- **Azure CLI**: [安装指南](https://aka.ms/azure-cli)
- **PowerShell 5.1** 或更高版本 (Windows 10/11 已内置)。

#### Linux, macOS, 或 WSL 用户 (使用 Bash)
- **Azure CLI**: [安装指南](https://aka.ms/azure-cli)
- **jq**: 一个轻量级且灵活的命令行 JSON 处理器。
  - 在 Debian/Ubuntu 上: `sudo apt-get install jq`
  - 在 macOS 上 (使用 Homebrew): `brew install jq`
  - 在 Fedora/CentOS 上: `sudo dnf install jq`

## 使用方法

1.  **下载脚本**: 下载适用于您操作系统的脚本。
    -   Windows 用户: `Restore-DeletedAzMySQLFlexibleServer.ps1`
    -   Linux/macOS 用户: `restore_azmysql_flexible_server.sh`

2.  **打开终端**:
    -   在 Windows 上, 打开 **PowerShell** 终端。
    -   在 Linux/macOS 上, 打开 **Bash** 终端。

3.  **运行脚本**:
    -   **对于 Bash**, 您可能需要先为脚本授予执行权限：
        ```bash
        chmod +x restore_azmysql_flexible_server.sh
        ./restore_azmysql_flexible_server.sh
        ```
    -   **对于 PowerShell**:
        ```powershell
        # 您可能需要为当前会话更改执行策略
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
        .\Restore-DeletedAzMySQLFlexibleServer.ps1
        ```

4.  **跟随提示操作**: 脚本将引导您完成以下步骤：
    -   选择语言。
    -   登录到您的 Azure 帐户。
    -   选择正确的订阅。
    -   指定服务器所在的资源组。
    -   从列表中选择已删除的服务器。
    -   选择要恢复到的位置。
    -   为恢复后的服务器提供一个新的、唯一的名称。
    -   确认恢复操作。

## ⚠️ 重要注意事项

-   **5 天恢复窗口**: 您只能在服务器删除后的 **5 天内**进行恢复。超过此期限，备份将被永久删除。
-   **恢复位置**: **您必须将服务器恢复到它最初所在的同一 Azure 位置。** 这是因为服务器的备份存储在该特定位置。脚本将默认选择原始资源组的位置以帮助您正确操作。
-   **恢复时间点**: 脚本会自动计算一个在服务器被删除前约 15 分钟的恢复时间点，以确保恢复的数据是一致且有效的状态。
-   **API 版本**: 此脚本使用 `2024-06-01-preview` API 版本来执行恢复操作。

## 免责声明

这些脚本按“原样”提供，不附带任何形式的保证。在确认恢复操作之前，请务必仔细核对脚本显示的操作摘要。用户需对脚本执行的所有操作负责。