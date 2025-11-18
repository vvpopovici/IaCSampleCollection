[CmdletBinding()]
param (
  [string] $ResourceGroupName = $env:TFOUTPUTS_RESOURCE_GROUP_NAME ? $env:TFOUTPUTS_RESOURCE_GROUP_NAME : "rg-vvpsoll-vvp-demo",
  [string] $AzureContainerRegistryName = $env:TFOUTPUTS_CONTAINER_REGISTRY_NAME ? $env:TFOUTPUTS_CONTAINER_REGISTRY_NAME : "acrvvpsollvvpdemo",
  [int] $KeepLatestTagsCount = 2
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
  { Import-Module -Name Az.Accounts, Az.ContainerRegistry -Force -Verbose:$false } | Invoke-Edv-Command 4>$null # Hide Verbose messages (stream 4)

  Write-Host "`n# Make sure you ran 'Connect-AzAccount' and/or 'az login' with the correct Subscription and Tenant.`n"
  $account = { Get-AzContext } | Invoke-Edv-Command
  $account | Format-Table | Out-String | Write-Host
#endregion Initialize

Write-Host "# Get all repositories in the ACR" -NoNewline
$repositories = { Get-AzContainerRegistryRepository -RegistryName $AzureContainerRegistryName -ErrorAction SilentlyContinue } | Invoke-Edv-Command

Write-Host "#   Found repositories: $($repositories | ConvertTo-Json -Compress)"

foreach ($repo in $repositories) {
  Write-Host "`n# Processing repository '${repo}'" -NoNewline

  # Get all tags
  $tags = { Get-AzContainerRegistryTag -RegistryName $AzureContainerRegistryName -RepositoryName $repo } | Invoke-Edv-Command
  Write-Host "#   Found tags:`n$($tags.Tags | Select-Object -Property Name, LastUpdateTime, Digest | ConvertTo-Json)"

  # Sort by LastUpdateTime (newest first) and skip the first 2 (keep them), the rest to be removed
  $tagsToRemove = $tags.Tags | Sort-Object -Property LastUpdateTime -Descending | Select-Object -Skip $KeepLatestTagsCount
  Write-Host "#   Tags to remove:`n$($tagsToRemove | Select-Object -Property Name, LastUpdateTime, Digest | ConvertTo-Json)"

  foreach ($tag in $tagsToRemove) {
    { Remove-AzContainerRegistryTag -Name $tag.Name -RepositoryName $repo -RegistryName $AzureContainerRegistryName -Verbose } | Invoke-Edv-Command
  }
}
