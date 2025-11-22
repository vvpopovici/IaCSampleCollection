# Script is ready for the Azure Task
# - task: AzureCLI@2 # Terraform
#   name: Terraform
#   inputs:
#     azureSubscription: $(SERVICE_CONNECTION)
#     scriptType: pscore
#     errorActionPreference: stop
#     failOnStandardError: true
#     scriptLocation: scriptPath
#     # arguments: # arguments are taken from Environment Variables
#     scriptPath: $(INFRA_ROOT_FOLDER)/deploy/scripts/Invoke-Vvpsoll-TerraformApply.ps1

[CmdletBinding()]
param (
  [string] $InfraRepoRootFolder = $env:INFRA_ROOT_FOLDER ? $env:INFRA_ROOT_FOLDER : "${PSScriptRoot}/../..",
  [bool]   $ConfirmApply = $env:TERRAFORM_CONFIRM_APPLY ? @("TRUE", "1").Contains($env:TERRAFORM_CONFIRM_APPLY.ToUpper()) : $true,
  [string] $TfOutputsFile = $env:TFOUTPUTS_FILE ? $env:TFOUTPUTS_FILE : "${PSScriptRoot}/../../terraform_outputs.json",
  # (!!!) DANGEROUS ZONE: If "true", Terraform Plan will DESTROY the resources.
  [ValidateSet("true", "false")]
  [string] $TerraformPlanDestroy = "false"
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

#region Plan
  Write-Host "`n# Required CLI tools"
  "az", "terraform" | ForEach-Object {
    Write-Host "#   - ${_}: " -NoNewline

    if (-not (Get-Command -Name $_ -ErrorAction SilentlyContinue)) {
      Write-Host "missing"
      throw "Missing required CLI tool ${_}."
    }
    Write-Host "available"
  }

  Write-Host "`n# Make sure you ran 'Connect-AzAccount' and/or 'az login' with the correct Subscription and Tenant.`n"
  { az account show } | Invoke-Edv-Command

  & "${InfraRepoRootFolder}/deploy/scripts/Convert-Vvpsoll-TokenToVariable.ps1" `
    -InputFile "${InfraRepoRootFolder}/tf-azure/backend.tf.template" `
    -OutputFile "${InfraRepoRootFolder}/tf-azure/backend.tf" `
    -DisplayContent;
  & "${InfraRepoRootFolder}/deploy/scripts/Convert-Vvpsoll-TokenToVariable.ps1" `
      -InputFile "${InfraRepoRootFolder}/tf-azure/terraform.tfvars.template" `
      -OutputFile "${InfraRepoRootFolder}/tf-azure/terraform.tfvars" `
      -DisplayContent;

  { terraform -chdir="${InfraRepoRootFolder}/tf-azure" fmt } | Invoke-Edv-Command

  { terraform -chdir="${InfraRepoRootFolder}/tf-azure" init -reconfigure } | Invoke-Edv-Command

  { terraform -chdir="${InfraRepoRootFolder}/tf-azure" plan -out="terraform.tfplan" -destroy="${TerraformPlanDestroy}" } | Invoke-Edv-Command

  Write-Host "# Analyze the changes ..."
  $planObj = { terraform -chdir="${InfraRepoRootFolder}/tf-azure" show -no-color -json "terraform.tfplan" } | Invoke-Edv-Command | ConvertFrom-Json

  $changes = @( $planObj.resource_changes.change.actions ) + @(
    $planObj.output_changes.PSObject.Properties `
      | Where-Object MemberType -eq NoteProperty `
      | ForEach-Object { $_.Value.actions }
  )

  $add = @($changes | Where-Object {$_ -contains "create"}).Length
  $change = @($changes | Where-Object {$_ -contains "update"}).Length
  $remove = @($changes | Where-Object {$_ -contains "delete"}).Length
  $totalChanges = $add + $change + $remove
  Write-Host "total changes: $totalChanges ($add to add, $change to change, $remove to remove)"
#endregion Plan

#region Apply
  if ($totalChanges -eq 0) {
    Write-Host "#   No changes to apply."
  }
  else {
    if ($ConfirmApply) {
      $confirmation = Read-Host -Prompt "# Is the plan ok? Is it ok to apply it? (Y/N/<Enter>)"
      if ($confirmation.ToUpper() -notin @('Y', 'YES', '')) {
        Write-Host "# Aborting the apply operation as per user request."
        exit 0
      }
    }

    { terraform -chdir="${InfraRepoRootFolder}/tf-azure" apply -auto-approve "terraform.tfplan" } | Invoke-Edv-Command
  }

  Write-Host "`n# Export the outputs ..."
  { terraform -chdir="${InfraRepoRootFolder}/tf-azure" output -json } | Invoke-Edv-Command | Out-File -FilePath $TfOutputsFile -Encoding utf8
  Write-Host "`n#   Need more exports? Use this:"
  Write-Host "#     > terraform -chdir=${InfraRepoRootFolder}/tf-azure output -json aks > ${TfOutputsFile}.aks.json"

  Write-Host "`n# Convert Terraform Outputs to Environment Variables:"
  $TFOUTPUTS = Get-Content -Path $TfOutputsFile -Raw | ConvertFrom-Json
  $TFOUTPUTS | Get-Member -MemberType NoteProperty | ForEach-Object {
    $varName = "TFOUTPUTS_$($_.Name.ToUpper())"
    $varValue = $($TFOUTPUTS.$($_.Name).value | ConvertTo-Json -Depth 99).Trim('"')
    $varNotSensitive = -not $TFOUTPUTS.$($_.Name).sensitive
    Set-Item -Path env:$varName -Value $varValue -Verbose:$varNotSensitive
  }
#endregion Apply
