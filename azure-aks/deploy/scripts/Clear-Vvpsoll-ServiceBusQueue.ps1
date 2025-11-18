[CmdletBinding()]
param (
  [string] $ResourceGroupName = $env:TFOUTPUTS_RESOURCE_GROUP_NAME ? $env:TFOUTPUTS_RESOURCE_GROUP_NAME : "rg-vvpsoll-vvp-demo",
  [string] $AzureServiceBusName = $env:TFOUTPUTS_SERVICEBUS_NAME ? $env:TFOUTPUTS_SERVICEBUS_NAME : "sb-vvpsoll-vvp-demo"
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
  { Import-Module -Name Az.Accounts, Az.ServiceBus -Force -Verbose:$false } | Invoke-Edv-Command 4>$null # Hide Verbose messages (stream 4)

  Write-Host "`n# Make sure you ran 'Connect-AzAccount' and/or 'az login' with the correct Subscription and Tenant.`n"
  $account = { Get-AzContext } | Invoke-Edv-Command
  $account | Format-Table | Out-String | Write-Host
#endregion Initialize

Write-Host "# Get all queues in the namespace" -NoNewline
$queues = { Get-AzServiceBusQueue -NamespaceName $AzureServiceBusName -ResourceGroup $ResourceGroupName -ErrorAction SilentlyContinue } | Invoke-Edv-Command
Write-Host "#   Found queues: $($queues.Name | ConvertTo-Json -Compress)."

foreach ($queue in $queues) {
  Write-Host "`n# Deleting queue '$($queue.Name)'" -NoNewline
  { Remove-AzServiceBusQueue -Name $($queue.Name) -NamespaceName $AzureServiceBusName -ResourceGroup $ResourceGroupName -Verbose } | Invoke-Edv-Command
}

Write-Host "`n# Recreate queues after deletion"
foreach ($queue in $queues) {
  Write-Host "`n# Creating queue '$($queue.Name)'" -NoNewline
  { New-AzServiceBusQueue -Name $($queue.Name) -NamespaceName $AzureServiceBusName -ResourceGroup $($queue.ResourceGroupName) -MaxSizeInMegabytes $($queue.MaxSizeInMegabytes) -LockDuration $($queue.LockDuration) -Verbose } | Invoke-Edv-Command | Select-Object -Property Name, MaxSizeInMegabytes, LockDuration | Format-Table | Out-String | Write-Host
}
