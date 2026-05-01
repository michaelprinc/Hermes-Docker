<#
.SYNOPSIS
    Verifies Dockerized Hermes gateway readiness.

.DESCRIPTION
    Validates that the Hermes container is running, the generated bootstrap home
    was applied, the CLI is usable, and Discord is still disabled.

.EXAMPLE
    .\hermes-docker\scripts\Test-HermesDockerGateway.ps1 -Verbose
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [int]$LogTail = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Resolve-Path (Join-Path $moduleRoot '..')

. (Join-Path $repoRoot '.github\scripts\Common-Functions.ps1')

try {
    $composePath = Join-Path $moduleRoot 'docker-compose.yml'
    $composeEnvPath = Join-Path $moduleRoot '.env'
    $hermesCliPath = '/opt/hermes/.venv/bin/hermes'

    if (-not (Test-Path -LiteralPath $composeEnvPath)) {
        throw "Docker env file was not found at '$composeEnvPath'. Copy .env.example to .env first."
    }

    $baseArgs = @('compose', '--env-file', $composeEnvPath, '-f', $composePath)

    if ($PSCmdlet.ShouldProcess($composePath, 'Run Docker Hermes gateway verification')) {
        $runningServices = & docker @baseArgs 'ps' '--status' 'running' '--services'
        if ($LASTEXITCODE -ne 0) {
            throw "docker compose ps failed with exit code $LASTEXITCODE"
        }

        if (-not ($runningServices -contains 'hermes-gateway')) {
            throw 'Hermes gateway container is not running.'
        }

        & docker @baseArgs 'exec' '-T' 'hermes-gateway' $hermesCliPath 'version' | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "hermes version failed with exit code $LASTEXITCODE"
        }

        & docker @baseArgs 'exec' '-T' 'hermes-gateway' 'sh' '-lc' 'test -f /opt/data/config.yaml && test -f /opt/data/.env'
        if ($LASTEXITCODE -ne 0) {
            throw 'Hermes bootstrap files were not materialized into /opt/data.'
        }

                & docker @baseArgs 'exec' '-T' 'hermes-gateway' 'python3' '-c' @"
from pathlib import Path
lines = Path('/opt/data/.env').read_text(encoding='utf-8-sig').splitlines()
raise SystemExit(0 if 'DISCORD_BOT_TOKEN=' in lines else 1)
"@
        if ($LASTEXITCODE -ne 0) {
            throw 'Discord token placeholder is not disabled in the bootstrap env file.'
        }

                & docker @baseArgs 'exec' '-T' 'hermes-gateway' 'python3' '-c' @"
from pathlib import Path
import os

mode = os.environ.get('HERMES_DOCKER_MODEL_MODE', 'Configured')
config_text = Path('/opt/data/config.yaml').read_text(encoding='utf-8-sig')

if mode == 'Codex':
        ok = 'provider: "openai-codex"' in config_text
elif mode == 'Local':
        ok = 'provider: "custom"' in config_text and 'base_url: "http://host.docker.internal:' in config_text
else:
        ok = 'provider: "' in config_text

raise SystemExit(0 if ok else 1)
"@
        if ($LASTEXITCODE -ne 0) {
            throw 'Hermes model configuration did not match the selected ModelMode.'
        }

        $logOutput = & docker @baseArgs 'logs' '--tail' $LogTail 'hermes-gateway'
        if ($LASTEXITCODE -ne 0) {
            throw "docker compose logs failed with exit code $LASTEXITCODE"
        }

        $logText = ($logOutput -join [Environment]::NewLine)
        $hasTraceback = $logText -match '(?i)traceback|fatal:|exception:'
        $hasDiscordConnectionSignal = $logText -match '(?i)discord.*(connected|logged in|gateway ready|starting provider)'

        if ($hasTraceback) {
            throw 'Hermes runtime logs contain an exception or traceback.'
        }

        if ($hasDiscordConnectionSignal) {
            throw 'Discord appears to be active in the Hermes runtime logs, but this MVP must keep it disabled.'
        }

        Write-AuditLog -Action 'Hermes:DockerGatewayTest' -Result 'Success' -Details @{
            ComposePath = $composePath
            LogTail = $LogTail
            RunningServices = @($runningServices)
            TracebackDetected = $hasTraceback
            DiscordConnectionSignalDetected = $hasDiscordConnectionSignal
        }

        [pscustomobject]@{
            RunningServices = $runningServices
            TracebackDetected = $hasTraceback
            DiscordConnectionSignalDetected = $hasDiscordConnectionSignal
        }
    }
} catch {
    Write-AuditLog -Action 'Hermes:DockerGatewayTest' -Result 'Failed' -Details @{
        Error = $_.Exception.Message
    }
    throw
}