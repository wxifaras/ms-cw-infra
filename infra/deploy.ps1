<#
.SYNOPSIS
    Deploys (or previews) the AI Engineering Assistant networking infrastructure.

.DESCRIPTION
    The five existing-resource account names are read from a local settings file
    (default: infra/deploy.local.json) that is git-ignored and never committed.
    Copy infra/deploy.local.json.example to infra/deploy.local.json, fill in the
    values, then run this script. It validates the file, then invokes the Bicep
    deployment, passing the names as parameter overrides on top of
    infra/main.parameters.json.

    Settings file (JSON) — all five keys are required and non-empty:
      {
        "aiServicesAccountName": "...",
        "aiFoundryAccountName":  "...",
        "cosmosAccountName":     "...",
        "storageAccountName":    "...",
        "searchServiceName":     "..."
      }

.PARAMETER ResourceGroup
    Target resource group for the deployment.

.PARAMETER SettingsFile
    Path to the JSON settings file. Defaults to infra/deploy.local.json next to
    this script.

.PARAMETER WhatIf
    Run `az deployment group what-if` instead of creating the deployment.

.EXAMPLE
    Copy-Item infra/deploy.local.json.example infra/deploy.local.json
    # edit infra/deploy.local.json with your account names
    ./infra/deploy.ps1 -ResourceGroup rg-ai-dev -WhatIf
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [string]$SettingsFile,

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$scriptDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateFile   = Join-Path $scriptDir 'main.bicep'
$parametersFile = Join-Path $scriptDir 'main.parameters.json'

if ([string]::IsNullOrWhiteSpace($SettingsFile)) {
    $SettingsFile = Join-Path $scriptDir 'deploy.local.json'
}

if (-not (Test-Path -LiteralPath $SettingsFile)) {
    Write-Error ("Settings file not found: {0}. Copy 'deploy.local.json.example' to 'deploy.local.json' and fill in the account names." -f $SettingsFile)
    exit 1
}

try {
    $settings = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json
}
catch {
    Write-Error ("Failed to parse settings file '{0}' as JSON: {1}" -f $SettingsFile, $_.Exception.Message)
    exit 1
}

# Bicep parameters that must be supplied by the settings file.
$requiredParams = @(
    'aiServicesAccountName',
    'aiFoundryAccountName',
    'cosmosAccountName',
    'storageAccountName',
    'searchServiceName'
)

# Fail fast if any value is missing or blank.
$missing = @()
$overrides = @()
foreach ($name in $requiredParams) {
    $value = $settings.$name
    if ([string]::IsNullOrWhiteSpace($value)) {
        $missing += $name
    }
    else {
        $overrides += "$name=$value"
    }
}

if ($missing.Count -gt 0) {
    Write-Error ("Missing or blank value(s) in '{0}': {1}." -f $SettingsFile, ($missing -join ', '))
    exit 1
}

$action = if ($WhatIf) { 'what-if' } else { 'create' }

$azArgs = @(
    'deployment', 'group', $action,
    '--resource-group', $ResourceGroup,
    '--template-file', $templateFile,
    '--parameters', $parametersFile
) + '--parameters' + $overrides

Write-Host "Running: az $($azArgs -join ' ')"
& az @azArgs
exit $LASTEXITCODE
