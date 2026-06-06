<#
.SYNOPSIS
    Starts the Dockerized Hermes gateway runtime.

.DESCRIPTION
    Synchronizes runtime files and starts the Hermes container through docker
    compose.

.EXAMPLE
    .\hermes-docker\scripts\Start-HermesDockerGateway.ps1 -Verbose
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [switch]$SkipSync,

    [Parameter(Mandatory = $false)]
    [switch]$NoBuild,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Configured', 'Codex', 'Local')]
    [string]$ModelMode = $(if ([string]::IsNullOrWhiteSpace($env:HERMES_AGENT_MODEL_MODE)) { 'Local' } else { $env:HERMES_AGENT_MODEL_MODE }),

    [Parameter(Mandatory = $false)]
    [string]$LocalModelBaseUrl = $(if ([string]::IsNullOrWhiteSpace($env:HERMES_LOCAL_MODEL_BASE_URL)) { 'http://host.docker.internal:8068/v1' } else { $env:HERMES_LOCAL_MODEL_BASE_URL }),

    [Parameter(Mandatory = $false)]
    [string]$LocalModelId = $(if ([string]::IsNullOrWhiteSpace($env:HERMES_LOCAL_MODEL_ID)) { 'qwen36_35b_a3b_mtp_iq3xxs_rx6800_cache_mtp_256k' } else { $env:HERMES_LOCAL_MODEL_ID }),

    [Parameter(Mandatory = $false)]
    [string]$LocalModelApiKey = $(if ([string]::IsNullOrWhiteSpace($env:HERMES_LOCAL_MODEL_API_KEY)) { 'local-model' } else { $env:HERMES_LOCAL_MODEL_API_KEY }),

    [Parameter(Mandatory = $false)]
    [string]$CodexModel = $(if ([string]::IsNullOrWhiteSpace($env:HERMES_CODEX_MODEL)) { 'gpt-5.4' } else { $env:HERMES_CODEX_MODEL })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Resolve-Path (Join-Path $moduleRoot '..\..')

. (Join-Path $repoRoot '.github\scripts\Common-Functions.ps1')

try {
    $syncScriptPath = Join-Path $PSScriptRoot 'Sync-HermesDockerConfig.ps1'
    $composePath = Join-Path $moduleRoot 'docker-compose.yml'
    $composeEnvPath = Join-Path $moduleRoot '.env'

    if (-not (Test-Path -LiteralPath $composeEnvPath)) {
        throw "Docker env file was not found at '$composeEnvPath'. Copy .env.example to .env first."
    }

    if (-not $SkipSync) {
        $syncArgs = @{
            ModelMode = $ModelMode
            LocalModelBaseUrl = $LocalModelBaseUrl
            LocalModelId = $LocalModelId
            LocalModelApiKey = $LocalModelApiKey
            CodexModel = $CodexModel
        }
        if ($VerbosePreference -ne 'SilentlyContinue') {
            $syncArgs['Verbose'] = $true
        }
        & $syncScriptPath @syncArgs
    }

    $arguments = @('compose', '--env-file', $composeEnvPath, '-f', $composePath, 'up', '-d')
    if (-not $NoBuild) {
        $arguments += '--build'
    }

    if ($PSCmdlet.ShouldProcess($composePath, 'Start Hermes Docker gateway container')) {
        & docker @arguments
        if ($LASTEXITCODE -ne 0) {
            throw "docker compose up failed with exit code $LASTEXITCODE"
        }

        Write-AuditLog -Action 'Hermes:DockerGatewayStart' -Result 'Success' -Details @{
            ComposePath = $composePath
            ComposeEnvPath = $composeEnvPath
            NoBuild = $NoBuild.IsPresent
            SkipSync = $SkipSync.IsPresent
            ModelMode = $ModelMode
        }
    }
} catch {
    Write-AuditLog -Action 'Hermes:DockerGatewayStart' -Result 'Failed' -Details @{
        Error = $_.Exception.Message
    }
    throw
}
