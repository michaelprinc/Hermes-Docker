<#
.SYNOPSIS
    Generates Docker runtime config for Hermes Agent.

.DESCRIPTION
    Creates a bootstrap Hermes home for the local Docker runtime, including
    config.yaml and .env files, while keeping Discord disabled by default.

.EXAMPLE
    .\hermes-docker\scripts\Sync-HermesDockerConfig.ps1 -Verbose
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Configured', 'Codex', 'Local')]
    [string]$ModelMode = $(if ([string]::IsNullOrWhiteSpace($env:HERMES_AGENT_MODEL_MODE)) { 'Local' } else { $env:HERMES_AGENT_MODEL_MODE }),

    [Parameter(Mandatory = $false)]
    [string]$ConfiguredModelProvider = $(if ([string]::IsNullOrWhiteSpace($env:HERMES_MODEL_PROVIDER)) { 'auto' } else { $env:HERMES_MODEL_PROVIDER }),

    [Parameter(Mandatory = $false)]
    [string]$ConfiguredModelDefault = $(if ([string]::IsNullOrWhiteSpace($env:HERMES_MODEL_DEFAULT)) { 'gpt-5.4' } else { $env:HERMES_MODEL_DEFAULT }),

    [Parameter(Mandatory = $false)]
    [string]$ConfiguredModelBaseUrl = $(if ($null -eq $env:HERMES_MODEL_BASE_URL) { '' } else { $env:HERMES_MODEL_BASE_URL }),

    [Parameter(Mandatory = $false)]
    [string]$ConfiguredModelApiKey = $(if ($null -eq $env:HERMES_MODEL_API_KEY) { '' } else { $env:HERMES_MODEL_API_KEY }),

    [Parameter(Mandatory = $false)]
    [string]$CodexModel = $(if ([string]::IsNullOrWhiteSpace($env:HERMES_CODEX_MODEL)) { 'gpt-5.4' } else { $env:HERMES_CODEX_MODEL }),

    [Parameter(Mandatory = $false)]
    [string]$LocalModelBaseUrl = $(if ([string]::IsNullOrWhiteSpace($env:HERMES_LOCAL_MODEL_BASE_URL)) { 'http://host.docker.internal:8068/v1' } else { $env:HERMES_LOCAL_MODEL_BASE_URL }),

    [Parameter(Mandatory = $false)]
    [string]$LocalModelId = $(if ([string]::IsNullOrWhiteSpace($env:HERMES_LOCAL_MODEL_ID)) { 'qwen36_35b_a3b_mtp_iq3xxs_rx6800_cache_mtp_256k' } else { $env:HERMES_LOCAL_MODEL_ID }),

    [Parameter(Mandatory = $false)]
    [string]$LocalModelApiKey = $(if ([string]::IsNullOrWhiteSpace($env:HERMES_LOCAL_MODEL_API_KEY)) { 'local-model' } else { $env:HERMES_LOCAL_MODEL_API_KEY }),

    [Parameter(Mandatory = $false)]
    [bool]$DiscordEnabled = $(if ([string]::IsNullOrWhiteSpace($env:HERMES_DISCORD_ENABLED)) { $false } else { [System.Convert]::ToBoolean($env:HERMES_DISCORD_ENABLED) }),

    [Parameter(Mandatory = $false)]
    [bool]$DiscordRequireMention = $(if ([string]::IsNullOrWhiteSpace($env:HERMES_DISCORD_REQUIRE_MENTION)) { $true } else { [System.Convert]::ToBoolean($env:HERMES_DISCORD_REQUIRE_MENTION) }),

    [Parameter(Mandatory = $false)]
    [bool]$DiscordAutoThread = $(if ([string]::IsNullOrWhiteSpace($env:HERMES_DISCORD_AUTO_THREAD)) { $true } else { [System.Convert]::ToBoolean($env:HERMES_DISCORD_AUTO_THREAD) })
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Resolve-Path (Join-Path $moduleRoot '..\..')

. (Join-Path $repoRoot '.github\scripts\Common-Functions.ps1')

function ConvertTo-HermesDockerBool {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Value
    )

    if ($Value) {
        return 'true'
    }

    return 'false'
}

function Resolve-HermesDockerModelConfig {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Configured', 'Codex', 'Local')]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$ConfiguredProvider,

        [Parameter(Mandatory = $true)]
        [string]$ConfiguredDefault,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ConfiguredBaseUrl,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ConfiguredApiKey,

        [Parameter(Mandatory = $true)]
        [string]$CodexModelName,

        [Parameter(Mandatory = $true)]
        [string]$LocalBaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$LocalModelName,

        [Parameter(Mandatory = $true)]
        [string]$LocalApiKey
    )

    switch ($Mode) {
        'Codex' {
            return [pscustomobject]@{
                Provider = 'openai-codex'
                Default  = $CodexModelName
                BaseUrl  = ''
                ApiKey   = ''
            }
        }
        'Local' {
            return [pscustomobject]@{
                Provider = 'custom'
                Default  = $LocalModelName
                BaseUrl  = $LocalBaseUrl
                ApiKey   = $LocalApiKey
            }
        }
        default {
            return [pscustomobject]@{
                Provider = $ConfiguredProvider
                Default  = $ConfiguredDefault
                BaseUrl  = $ConfiguredBaseUrl
                ApiKey   = $ConfiguredApiKey
            }
        }
    }
}

function Get-HermesDockerConfigContent {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Model,

        [Parameter(Mandatory = $true)]
        [bool]$DiscordEnabled,

        [Parameter(Mandatory = $true)]
        [bool]$DiscordRequireMention,

        [Parameter(Mandatory = $true)]
        [bool]$DiscordAutoThread
    )

    $discordRequireMentionValue = ConvertTo-HermesDockerBool -Value $DiscordRequireMention
    $discordAutoThreadValue = ConvertTo-HermesDockerBool -Value $DiscordAutoThread
    $discordEnabledValue = ConvertTo-HermesDockerBool -Value $DiscordEnabled

    return @"
model:
  default: "$($Model.Default)"
  provider: "$($Model.Provider)"
  base_url: "$($Model.BaseUrl)"
  api_key: "$($Model.ApiKey)"

terminal:
  backend: "local"
  cwd: "."
  timeout: 180
  docker_mount_cwd_to_workspace: false

agent:
  max_turns: 60
  tool_use_enforcement:
    - "codex"
    - "gemma"

streaming:
  enabled: false

platform_toolsets:
  cli: [hermes-cli]
  discord: [hermes-discord]

discord:
  require_mention: $discordRequireMentionValue
  auto_thread: $discordAutoThreadValue
  free_response_channels: ""

metadata:
  docker_runtime:
    discord_enabled: $discordEnabledValue
"@
}

function Get-HermesDockerBootstrapEnvContent {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$DiscordEnabled
    )

    $discordTokenLine = if ($DiscordEnabled) { 'DISCORD_BOT_TOKEN=replace-me-before-enabling-discord' } else { 'DISCORD_BOT_TOKEN=' }

    return @"
$discordTokenLine
OPENAI_API_KEY=
OPENAI_BASE_URL=
"@
}

try {
    $runtimeDir = Join-Path $moduleRoot 'runtime'
    $bootstrapDir = Join-Path $runtimeDir 'bootstrap'
    $configPath = Join-Path $bootstrapDir 'config.yaml'
    $envPath = Join-Path $bootstrapDir '.env'
    $runtimeEnvPath = Join-Path $runtimeDir 'hermes.runtime.env'
    $templateEnvPath = Join-Path $moduleRoot 'config\runtime.template.env'

    foreach ($path in @($runtimeDir, $bootstrapDir)) {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }

    $resolvedModel = Resolve-HermesDockerModelConfig `
        -Mode $ModelMode `
        -ConfiguredProvider $ConfiguredModelProvider `
        -ConfiguredDefault $ConfiguredModelDefault `
        -ConfiguredBaseUrl $ConfiguredModelBaseUrl `
        -ConfiguredApiKey $ConfiguredModelApiKey `
        -CodexModelName $CodexModel `
        -LocalBaseUrl $LocalModelBaseUrl `
        -LocalModelName $LocalModelId `
        -LocalApiKey $LocalModelApiKey

    $configContent = Get-HermesDockerConfigContent `
        -Model $resolvedModel `
        -DiscordEnabled $DiscordEnabled `
        -DiscordRequireMention $DiscordRequireMention `
        -DiscordAutoThread $DiscordAutoThread
    $bootstrapEnvContent = Get-HermesDockerBootstrapEnvContent -DiscordEnabled $DiscordEnabled

    $templateLines = Get-Content -LiteralPath $templateEnvPath -Encoding UTF8
    $runtimeEnvContent = foreach ($line in $templateLines) {
        if ($line -match '^HERMES_DOCKER_MODEL_MODE=') {
            "HERMES_DOCKER_MODEL_MODE=$ModelMode"
        } elseif ($line -match '^HERMES_DOCKER_DISCORD_ENABLED=') {
            "HERMES_DOCKER_DISCORD_ENABLED=$(ConvertTo-HermesDockerBool -Value $DiscordEnabled)"
        } else {
            $line
        }
    }

    if ($PSCmdlet.ShouldProcess($configPath, 'Write Hermes Docker config bootstrap')) {
        Set-Content -LiteralPath $configPath -Value $configContent -Encoding UTF8
    }

    if ($PSCmdlet.ShouldProcess($envPath, 'Write Hermes Docker bootstrap env')) {
        Set-Content -LiteralPath $envPath -Value $bootstrapEnvContent -Encoding UTF8
    }

    if ($PSCmdlet.ShouldProcess($runtimeEnvPath, 'Write Hermes Docker runtime env file')) {
        Set-Content -LiteralPath $runtimeEnvPath -Value $runtimeEnvContent -Encoding UTF8
    }

    Write-AuditLog -Action 'Hermes:DockerSync' -Result 'Success' -Details @{
        RuntimeDirectory = $runtimeDir
        BootstrapDirectory = $bootstrapDir
        ConfigPath = $configPath
        EnvPath = $envPath
        RuntimeEnvPath = $runtimeEnvPath
        ModelMode = $ModelMode
        ResolvedProvider = $resolvedModel.Provider
        ResolvedModel = $resolvedModel.Default
        DiscordEnabled = $DiscordEnabled
    }

    [pscustomobject]@{
        BootstrapDirectory = $bootstrapDir
        ConfigPath = $configPath
        EnvPath = $envPath
        RuntimeEnvPath = $runtimeEnvPath
        ModelMode = $ModelMode
        ResolvedProvider = $resolvedModel.Provider
        ResolvedModel = $resolvedModel.Default
        DiscordEnabled = $DiscordEnabled
    }
} catch {
    Write-AuditLog -Action 'Hermes:DockerSync' -Result 'Failed' -Details @{
        Error = $_.Exception.Message
    }
    throw
}
