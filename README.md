SentinelOne Windows Agent Tools

This repository contains a collection of PowerShell scripts designed to automate administration and maintenance tasks for the SentinelOne Windows Agent.

These scripts leverage the official SentinelOne CLI utility (SentinelCtl) and the Management Console API to perform actions securely and efficiently.

## Configuration Options

Each script in this repository supports two primary methods of execution, allowing you to choose the approach that best fits your automation workflow or manual deployment.

### Option 1: Pre-configuring Parameters Inside the Script
You can open any script in a text editor and populate the default values directly within the parameter block at the top of the file. For example:
- SITE: The base URL of your SentinelOne Management Console.
- TOKEN: Your Management Console API token.
- SITE_TOKEN: The target Site Token.

Once these values are saved inside the script, you can execute it without passing any additional arguments.

### Option 2: Passing Parameters via Command Line
Alternatively, you can keep the script files generic and pass the required parameters dynamically at execution time. This is the recommended method for integration with orchestration tools, RMM, or deployment systems.
Example:

```.\S1-Rebind.ps1 -SITE "https://your-console.sentinelone.net" -TOKEN "YOUR_API_TOKEN" -SITE_TOKEN "YOUR_TARGET_SITE_TOKEN"```

To do this, specify the parameter flags and their values in the command line when calling the script.

## Dry Run Mode

All scripts include a DryRun switch designed for safe testing and verification before any modifications are applied to the endpoint.

When the DryRun flag is active:
- The script validates administrative privileges and environment paths.
- It performs read-only operations, such as communicating with the SentinelOne Management API to retrieve the agent UUID and passphrase.
- It displays the retrieved information (with sensitive data masked) and exits without stopping services, unloading the agent, or modifying its configuration.

To use this feature, append the DryRun switch to your execution command.

Example:

```.\S1-Rebind.ps1 -SITE "https://your-console.sentinelone.net" -TOKEN "YOUR_API_TOKEN" -SITE_TOKEN "YOUR_TARGET_SITE_TOKEN" -DryRun```

## Prerequisites
- The scripts must be executed within an elevated PowerShell session with administrative privileges.
- Network connectivity to the SentinelOne Management Console is required to query the API.

## Disclaimer
These tools interact with the tamper-protection and core services of the SentinelOne Agent. Always conduct thorough testing on a small, representative group of non-critical endpoints before utilizing these scripts for mass deployment or migration.
