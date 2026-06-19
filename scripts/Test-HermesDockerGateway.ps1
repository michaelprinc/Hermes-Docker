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
$repoRoot = Resolve-Path (Join-Path $moduleRoot '..\..')

. (Join-Path $repoRoot '.github\scripts\Common-Functions.ps1')

function Read-HermesDockerEnvFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $values
    }

    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ($line -match '^\s*$' -or $line -match '^\s*#') {
            continue
        }

        $parts = $line -split '=', 2
        if ($parts.Count -ne 2) {
            continue
        }

        $values[$parts[0].Trim()] = $parts[1].Trim()
    }

    return $values
}

try {
    $composePath = Join-Path $moduleRoot 'docker-compose.yml'
    $composeEnvPath = Join-Path $moduleRoot '.env'
    $hermesCliCommand = 'export VIRTUAL_ENV=/opt/hermes/.venv; export PATH="$VIRTUAL_ENV/bin:$PATH"; /opt/hermes/hermes'

    if (-not (Test-Path -LiteralPath $composeEnvPath)) {
        throw "Docker env file was not found at '$composeEnvPath'. Copy .env.example to .env first."
    }

    $baseArgs = @('compose', '--env-file', $composeEnvPath, '-f', $composePath)
    $composeEnvValues = Read-HermesDockerEnvFile -Path $composeEnvPath

    if ($PSCmdlet.ShouldProcess($composePath, 'Run Docker Hermes gateway verification')) {
        $runningServices = & docker @baseArgs 'ps' '--status' 'running' '--services'
        if ($LASTEXITCODE -ne 0) {
            throw "docker compose ps failed with exit code $LASTEXITCODE"
        }

        if (-not ($runningServices -contains 'hermes-gateway')) {
            throw 'Hermes gateway container is not running.'
        }

        & docker @baseArgs 'exec' '-T' 'hermes-gateway' 'sh' '-lc' "$hermesCliCommand version" | Out-Null
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

        $modelMode = if ($composeEnvValues.ContainsKey('HERMES_AGENT_MODEL_MODE')) { $composeEnvValues['HERMES_AGENT_MODEL_MODE'] } else { 'Local' }
        $expectedProvider = switch ($modelMode) {
            'Codex' { 'openai-codex' }
            'Local' { 'custom' }
            default { if ($composeEnvValues.ContainsKey('HERMES_MODEL_PROVIDER')) { $composeEnvValues['HERMES_MODEL_PROVIDER'] } else { 'auto' } }
        }
        $expectedModel = switch ($modelMode) {
            'Codex' { if ($composeEnvValues.ContainsKey('HERMES_CODEX_MODEL')) { $composeEnvValues['HERMES_CODEX_MODEL'] } else { 'gpt-5.4' } }
            'Local' { if ($composeEnvValues.ContainsKey('HERMES_LOCAL_MODEL_ID')) { $composeEnvValues['HERMES_LOCAL_MODEL_ID'] } else { 'qwen36_35b_a3b_mtp_iq3xxs_rx6800_cache_mtp_256k' } }
            default { if ($composeEnvValues.ContainsKey('HERMES_MODEL_DEFAULT')) { $composeEnvValues['HERMES_MODEL_DEFAULT'] } else { 'gpt-5.4' } }
        }
        $expectedBaseUrl = switch ($modelMode) {
            'Codex' { '' }
            'Local' { if ($composeEnvValues.ContainsKey('HERMES_LOCAL_MODEL_BASE_URL')) { $composeEnvValues['HERMES_LOCAL_MODEL_BASE_URL'] } else { 'http://host.docker.internal:8068/v1' } }
            default { if ($composeEnvValues.ContainsKey('HERMES_MODEL_BASE_URL')) { $composeEnvValues['HERMES_MODEL_BASE_URL'] } else { '' } }
        }
        $expectedProfile = if ($composeEnvValues.ContainsKey('HERMES_PROFILE_NAME')) { $composeEnvValues['HERMES_PROFILE_NAME'] } else { 'software-development' }

                & docker @baseArgs 'exec' '-T' `
            '-e' "EXPECTED_PROVIDER=$expectedProvider" `
            '-e' "EXPECTED_MODEL=$expectedModel" `
            '-e' "EXPECTED_BASE_URL=$expectedBaseUrl" `
            '-e' "EXPECTED_PROFILE=$expectedProfile" `
            'hermes-gateway' 'python3' '-c' @"
from pathlib import Path
import os
import re

def read_model_values(path):
    lines = Path(path).read_text(encoding='utf-8-sig').splitlines()
    model_lines = []
    in_model = False

    for line in lines:
        if line.strip() == 'model:':
            in_model = True
            continue
        if in_model and line and not line.startswith((' ', '\t')):
            break
        if in_model:
            model_lines.append(line)

    values = {}
    for line in model_lines:
        match = re.match(r'^\s*([A-Za-z0-9_]+):\s*(.*?)\s*$', line)
        if match:
            value = match.group(2).strip()
            if len(value) >= 2 and value[0] in "'\"" and value[-1] == value[0]:
                value = value[1:-1]
            values[match.group(1)] = value
    return values

expected = {
    'provider': os.environ['EXPECTED_PROVIDER'],
    'default': os.environ['EXPECTED_MODEL'],
    'base_url': os.environ['EXPECTED_BASE_URL'],
}

paths = ['/opt/data/config.yaml']
profile = os.environ.get('EXPECTED_PROFILE', '')
if profile:
    paths.append(f'/opt/data/profiles/{profile}/config.yaml')
    paths.append(f'/opt/data/.hermes/profiles/{profile}/config.yaml')

ok = True
for path in paths:
    values = read_model_values(path)
    if not all(values.get(key) == value for key, value in expected.items()):
        ok = False
        break

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
        $dashboardChatFlagDetected = $false

        if ($hasTraceback) {
            throw 'Hermes runtime logs contain an exception or traceback.'
        }

        if ($hasDiscordConnectionSignal) {
            throw 'Discord appears to be active in the Hermes runtime logs, but this MVP must keep it disabled.'
        }

        if ($runningServices -contains 'hermes-dashboard') {
            $dashboardPort = if ($composeEnvValues.ContainsKey('HERMES_DASHBOARD_PORT')) { $composeEnvValues['HERMES_DASHBOARD_PORT'] } else { '9119' }
            $dashboardResponse = Invoke-WebRequest -Uri "http://127.0.0.1:$dashboardPort/" -UseBasicParsing
            $dashboardChatFlagDetected = $dashboardResponse.Content -match 'window\.__HERMES_DASHBOARD_EMBEDDED_CHAT__=true'

            if (-not $dashboardChatFlagDetected) {
                throw 'Hermes dashboard Chat tab is not enabled.'
            }
        }

        Write-AuditLog -Action 'Hermes:DockerGatewayTest' -Result 'Success' -Details @{
            ComposePath = $composePath
            LogTail = $LogTail
            RunningServices = @($runningServices)
            TracebackDetected = $hasTraceback
            DiscordConnectionSignalDetected = $hasDiscordConnectionSignal
            DashboardChatFlagDetected = $dashboardChatFlagDetected
        }

        [pscustomobject]@{
            RunningServices = $runningServices
            TracebackDetected = $hasTraceback
            DiscordConnectionSignalDetected = $hasDiscordConnectionSignal
            DashboardChatFlagDetected = $dashboardChatFlagDetected
        }
    }
} catch {
    Write-AuditLog -Action 'Hermes:DockerGatewayTest' -Result 'Failed' -Details @{
        Error = $_.Exception.Message
    }
    throw
}
