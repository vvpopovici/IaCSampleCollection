
[CmdletBinding()]
param (
  [Parameter(ValueFromPipelineByPropertyName)] [ValidateNotNullOrEmpty()]
  [string] $DockerComposeFile = "${PSScriptRoot}/docker-compose.yaml",

  [Parameter(ValueFromPipelineByPropertyName)] [ValidateNotNullOrEmpty()]
  [ValidateSet("auto","tty", "plain", "json", "quiet")]
  [string] $ProgressType = "plain",

  [Parameter(ValueFromPipelineByPropertyName)] [ValidateNotNullOrEmpty()]
  [string] $ProjectName = "self-hosted-agent",

  [Parameter(ValueFromPipelineByPropertyName)] [ValidateNotNullOrEmpty()]
  [switch] $BuildImages
)

function Invoke-Edv-Command {
  [CmdletBinding()]
  param ([Parameter(ValueFromPipeline)][scriptblock] $ScriptBlock)
  process {
    Write-Host "`n# PS> $($ExecutionContext.InvokeCommand.ExpandString($ScriptBlock.ToString().Replace("`n", " ").Replace("`r", " ")))"
    $PSNativeCommandUseErrorActionPreference = $true
    Invoke-Command -ScriptBlock $ScriptBlock
  }
}

$ErrorActionPreference, $VerbosePreference, $WarningPreference, $InformationPreference = "Stop", "Continue", "Continue", "Continue"

if ( Test-Path -Path "${PSScriptRoot}/.env" ) {
  Write-Host "# Environment file .env exists. Ready to run docker-compose."
}
else {
  throw "# Environment file .env does not exist. Exiting."
}

if ($BuildImages) {
  { docker-compose --file "${DockerComposeFile}" --progress $ProgressType `
      build
  } | Invoke-Edv-Command

  { docker-compose --file "${DockerComposeFile}" --progress $ProgressType `
      down --volumes --remove-orphans
  } | Invoke-Edv-Command
}

{ docker-compose --file "${DockerComposeFile}" --progress $ProgressType `
    up -d --remove-orphans --timestamps
} | Invoke-Edv-Command

{ docker-compose --file "${DockerComposeFile}" `
    logs --follow --tail 50 --timestamps
} | Invoke-Edv-Command
