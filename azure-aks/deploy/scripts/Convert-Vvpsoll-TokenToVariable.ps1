<#
.SYNOPSIS
  This script substitutes tokens like {{ variable }} in the $InputFile file with the name of the corresponding Environment Variables.

.NOTES
  In an Azure DevOps Pipeline consider using the task qetza.replacetokens.replacetokens-task.replacetokens@6, https://github.com/qetza/replacetokens-task

.EXAMPLE
  ./deploy/scripts/Convert-Vvpsoll-TokenToVariable.ps1 -InputFile "./web.Dev.config" -OutputFile "./web.config"
#>

[CmdletBinding()]
param (
  [Parameter(Mandatory)] [ValidateNotNullOrEmpty()]
  [string] $InputFile,
  [string] $OutputFile = $InputFile,
  [string] $TokenStart = "{{",
  [string] $TokenEnd = "}}",
  [switch] $DisplayContent,
  [bool] $FailOnMissingVariable = $true
)

$ErrorActionPreference, $WarningPreference, $InformationPreference = "Stop", "Continue", "Continue"
$Verbose = $VerbosePreference -notin @("SilentlyContinue");

if (-not (Test-Path $InputFile)) {
  Write-Error "Input file '$InputFile' does not exist."
  exit 1
}

Write-Host "# Substituting variables in '$InputFile', outputting to '$OutputFile'"

$content = Get-Content -Path $InputFile -Raw

# Build regex pattern for tokens
$pattern = [regex]::Escape($TokenStart) + '\s*(\w+)\s*' + [regex]::Escape($TokenEnd)

# Find unique tokens
$uniqueTokens = [regex]::Matches($content, $pattern) | ForEach-Object { $_.Groups[1].Value.Trim() } | Sort-Object -Unique

foreach ($tokenName in $uniqueTokens) {
  $tokenValue = [System.Environment]::GetEnvironmentVariable($tokenName)
  Write-Host "# Variable `$env:${tokenName}: " -NoNewline

  if ($null -eq $tokenValue) {
    Write-Host "NOT declared."
    if ($FailOnMissingVariable) {
      Write-Error "Variable `$env:${tokenName} NOT declared."
      exit 1
    }
    else {
      Write-Warning "Variable `$env:${tokenName} NOT declared."
    }
    $tokenValue = ""
  } else {
    Write-Host "found"
  }

  Write-Host "#    Substituting with '$tokenValue'"
  $content = $content -replace ("{0}\s*{1}\s*{2}" -f [regex]::Escape($TokenStart), $tokenName, [regex]::Escape($TokenEnd)), $tokenValue
}

Write-Host "# Save substituted content to $OutputFile"
Set-Content -Path $OutputFile -Value $content -Force -Encoding UTF8 -Verbose:$Verbose

if ($DisplayContent) {
  Write-Host "# Final $OutputFile content:"
  Get-Content -Path $OutputFile -Raw
} else {
  Write-Host "# Content display skipped."
}
