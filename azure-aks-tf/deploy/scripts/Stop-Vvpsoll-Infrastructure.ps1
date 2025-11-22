# Script is ready for the Azure Task
# - task: AzurePowerShell@5 # Stop Infra
#   name: Stop_Infra
#   inputs:
#     azureSubscription: $(SERVICE_CONNECTION)
#     errorActionPreference: stop
#     failOnStandardError: true
#     pwsh: true
#     azurePowerShellVersion: LatestVersion
#     ScriptType: FilePath
#     # ScriptArguments: # arguments are taken from Environment Variables
#     ScriptPath: $(INFRA_ROOT_FOLDER)/deploy/scripts/Stop-Vvpsoll-Infrastructure.ps1

[CmdletBinding()]
param (
  [string] $TfOutputsFile = $env:TFOUTPUTS_FILE ? $env:TFOUTPUTS_FILE : "${PSScriptRoot}/../../terraform_outputs.json"
)

$ErrorActionPreference, $VerbosePreference, $WarningPreference, $InformationPreference = "Stop", "Continue", "Continue", "Continue"

#region Inputs
  # For debugging - let's output here what arguments this script received
  Write-Verbose "Got the following arguments:"
  $arguments = $MyInvocation.MyCommand.Path    # full path to the script
  (Get-Command -Name $MyInvocation.MyCommand.Path).Parameters.Keys | ForEach-Object {
    $value = Get-Variable $_ -ValueOnly -ErrorAction SilentlyContinue
    if (-not [system.string]::IsNullOrEmpty($value)) {
      $arguments = ("{0} -{1}:{2}" -F $arguments, $_, $($value -join ','))
    }
  }
  Write-Verbose "PS> ${arguments}"
#endregion Inputs

function Invoke-Edv-Command {
  [CmdletBinding()]
  param ([Parameter(ValueFromPipeline)][scriptblock] $ScriptBlock)
  process {
    Write-Host "`n# PS> $($ExecutionContext.InvokeCommand.ExpandString($ScriptBlock.ToString().Replace("`n", " ").Replace("`r", " ")))"
    $PSNativeCommandUseErrorActionPreference = $true
    Invoke-Command -ScriptBlock $ScriptBlock
  }
}

#region Initialize
  { Import-Module -Name Az.Accounts, Az.Aks -Force -Verbose:$false } | Invoke-Edv-Command 4>$null # Hide Verbose messages (stream 4)

  Write-Host "`n# Convert Terraform Outputs to Environment Variables:"
  $TFOUTPUTS = Get-Content -Path $TfOutputsFile -Raw | ConvertFrom-Json
  $TFOUTPUTS | Get-Member -MemberType NoteProperty | ForEach-Object {
    $varName = "TFOUTPUTS_$($_.Name.ToUpper())"
    $varValue = $($TFOUTPUTS.$($_.Name).value | ConvertTo-Json -Depth 99).Trim('"')
    $varNotSensitive = -not $TFOUTPUTS.$($_.Name).sensitive
    Set-Item -Path env:$varName -Value $varValue -Verbose:$varNotSensitive
  }

  Write-Host "`n# Make sure you ran 'Connect-AzAccount' and/or 'az login' with the correct Subscription and Tenant.`n"
  { Get-AzContext } | Invoke-Edv-Command | Format-Table | Out-String | Write-Host
#endregion

#region Stop AKS
  if (-not ([system.string]::IsNullOrWhiteSpace($env:TFOUTPUTS_RESOURCE_GROUP_NAME) -or [string]::IsNullOrWhiteSpace($env:TFOUTPUTS_AKS_NAME))) {
    Write-Host "`n# Set AKS PowerState to Stopping. " -NoNewline
    $aks = { Get-AzAksCluster -ResourceGroupName $env:TFOUTPUTS_RESOURCE_GROUP_NAME -Name $env:TFOUTPUTS_AKS_NAME -ErrorAction SilentlyContinue } | Invoke-Edv-Command
    Write-Host "Current AKS PowerState = $($aks.PowerState.Code)"
    if ($aks) {
      if ($aks.PowerState.Code -ne "Stopped") {
        { Stop-AzAksCluster -InputObject $aks -Verbose } | Invoke-Edv-Command

        $aks = { Get-AzAksCluster -ResourceGroupName $env:TFOUTPUTS_RESOURCE_GROUP_NAME -Name $env:TFOUTPUTS_AKS_NAME } | Invoke-Edv-Command
        Write-Host "`n# Final AKS PowerState = $($aks.PowerState.Code)";
      }
    }
    else {
      Write-Host "# AKS Cluster '${env:TFOUTPUTS_RESOURCE_GROUP_NAME} / ${env:TFOUTPUTS_AKS_NAME}' was not found."
    }
  }
  else {
    Write-Host "# Skipping AKS Stop as TFOUTPUTS_RESOURCE_GROUP_NAME or TFOUTPUTS_AKS_NAME is not set."
  }
#endregion Stop AKS
