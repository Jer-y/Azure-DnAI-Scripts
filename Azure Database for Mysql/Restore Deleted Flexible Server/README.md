[Read this document in Chinese (简体中文)](README-zh.md)

---

# Azure Database for MySQL Flexible Server Restore Scripts

A collection of interactive scripts designed to simplify the process of restoring a deleted Azure Database for MySQL Flexible Server. If you have ever accidentally deleted a server, these scripts provide a guided, step-by-step wizard to help you recover it.

This repository contains two equivalent scripts for different operating systems:
* `Restore-DeletedAzMySQLFlexibleServer.ps1`: For **Windows** users with PowerShell.
* `restore_azmysql_flexible_server.sh`: For **Linux, macOS, or WSL** users with Bash.

## The Problem

When an Azure Database for MySQL Flexible Server is deleted, the backups are retained for **5 days**, allowing for a point-in-time restore. 

These scripts automate that entire process, providing an easy-to-use interactive interface. If the scripts do not execute successfully, please refer to the [manual operation guide](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/how-to-restore-dropped-server).

## Features

- **Interactive Wizard**: Guides you through each step of the restore process.
- **Dual-Shell Support**: Provides both PowerShell for Windows and Bash for Linux/macOS.
- **Multi-Language**: Supports both English and Chinese (中文).
- **Auto-Discovery**: Automatically searches the Azure activity log to find recently deleted servers in your specified resource group.
- **Cloud Environment Selection**: Allows you to target different Azure clouds (e.g., Azure Global, Azure China).
- **Simplified API Call**: Handles the complexity of constructing and sending the REST API request to Azure for the restore operation.

## Prerequisites

Before running the scripts, please ensure you have the following installed:

#### For Windows (Using PowerShell)
- **Azure CLI**: [Install Guide](https://aka.ms/azure-cli)
- **PowerShell 5.1** or higher (comes standard with Windows 10/11).

#### For Linux, macOS, or WSL (Using Bash)
- **Azure CLI**: [Install Guide](https://aka.ms/azure-cli)
- **jq**: A lightweight and flexible command-line JSON processor.
  - On Debian/Ubuntu: `sudo apt-get install jq`
  - On macOS (with Homebrew): `brew install jq`
  - On Fedora/CentOS: `sudo dnf install jq`

## How to Use

1.  **Download the Script**: Download the appropriate script for your operating system.
    -   For Windows: `Restore-DeletedAzMySQLFlexibleServer.ps1`
    -   For Linux/macOS: `restore_azmysql_flexible_server.sh`

2.  **Open a Terminal**:
    -   On Windows, open a **PowerShell** terminal.
    -   On Linux/macOS, open a **Bash** terminal.

3.  **Run the Script**:
    -   **For Bash**, you may need to make the script executable first:
        ```bash
        chmod +x restore_azmysql_flexible_server.sh
        ./restore_azmysql_flexible_server.sh
        ```
    -   **For PowerShell**:
        ```powershell
        # You may need to change the execution policy for the current session
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
        .\Restore-DeletedAzMySQLFlexibleServer.ps1
        ```

4.  **Follow the Prompts**: The script will guide you through the following steps:
    -   Selecting a language.
    -   Logging into your Azure account.
    -   Choosing the correct subscription.
    -   Specifying the resource group where the server was located.
    -   Selecting the deleted server from a list.
    -   Choosing a location to restore to.
    -   Providing a new, unique name for the restored server.
    -   Confirming the restore operation.

## ⚠️ Important Notes

-   **5-Day Restore Window**: You can only restore a server within **5 days** of its deletion. After this period, the backups are permanently deleted.
-   **Restore Location**: **You MUST restore the server to the same Azure location where it was originally hosted.** This is because the server backups are stored in that specific location. The script will default to the original resource group's location to help you.
-   **Restore Point**: The script automatically calculates a restore point approximately 15 minutes *before* the server was deleted to ensure a valid and consistent state.
-   **API Version**: This script uses the `2024-06-01-preview` API version for the restore operation.

## Disclaimer

These scripts are provided as-is, without warranty of any kind. Always review the summary of actions before confirming the restore operation. The user is responsible for any actions taken by the script.
