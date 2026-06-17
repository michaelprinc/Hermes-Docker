---
name: "ps-quality"
description: "Use the ps-quality MCP server to analyze, repair, and generate PowerShell scripts with parser diagnostics and project quality checks."
version: "1.0.0"
author: "Michael Princ"
tags: [powershell, mcp, script-quality, diagnostics, software-development]
metadata:
  hermes:
    tags: [powershell, static-analysis, mcp]
    required_mcp_servers: [ps-quality]
---

# PS Quality MCP

Use this skill whenever creating, reviewing, or modifying PowerShell scripts in this workspace.

## When to Use

- Before editing an existing `.ps1` file with non-trivial logic.
- After editing any `.ps1` file to check parser errors and project quality rules.
- When parser errors point to unclear quoting, encoding, BOM, or invisible-character issues.
- When scaffolding a new auditable automation script.

## Tool Selection

- Use `ps_analyze_script` for read-only quality and parser diagnostics.
- Use `ps_debug_parser_diagnostics` when a parser error needs exact line and column context.
- Use `ps_inspect_script_bytes` for encoding, BOM, or hidden-character problems.
- Use `ps_repair_script` only for low-risk mechanical repairs.
- Use `ps_verify_and_repair_script` when a script needs analyze, repair, and re-check in one flow.
- Use `ps_generate_script_template` for new script scaffolds.

## Project Standards

- Prefer `[CmdletBinding(SupportsShouldProcess)]`, `-WhatIf`, `Write-Verbose`, and try/catch error handling.
- For WordPress automation, preserve audit logging through `Write-AuditLog`.
- Do not apply write-back repairs without understanding the diff.
- Keep backups enabled for any MCP-assisted write-back repair.
