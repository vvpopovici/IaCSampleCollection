# Script is ready for the Azure Task
# - task: AzurePowerShell@5 # Initialize
#   name: Initialize
#   inputs:
#     azureSubscription: $(SERVICE_CONNECTION)
#     errorActionPreference: stop
#     failOnStandardError: true
#     pwsh: true
#     azurePowerShellVersion: LatestVersion
#     ScriptType: FilePath
#     # ScriptArguments: # arguments are taken from Environment Variables
#     ScriptPath: $(INFRA_ROOT_FOLDER)/deploy/scripts/Initialize-Vvpsoll-Infrastructure.ps1

[CmdletBinding()]
param (
  [string] $InfraRepoRootFolder = $env:INFRA_ROOT_FOLDER ? $env:INFRA_ROOT_FOLDER : "${PSScriptRoot}/../..",
  [string] $SolutionName = "vvpsoll",
  [string] $Customer = $env:CUSTOMER ? $env:CUSTOMER : "vvp",
  [string] $EnvName = $env:ENV_NAME ? $env:ENV_NAME : "demo",
  [string] $Location = "germanywestcentral",
  [string] $AksAdminGroupName = "vvp\\\\Vvproj-AiVision-group",
  # EntraID Object ID of $AksAdminGroupName
  [string] $AksAdminObjectId = "<Get the Object ID from EntraID>" ,
  [string] $LetsEncryptEmail = "vvp.vvp@vvp.com",
  # Use Let's Encrypt staging server, which has high rate limits,
  # but you will have ERR_CERT_AUTHORITY_INVALID/SEC_ERROR_UNKNOWN_ISSUER error when browsing.
  # Use this only when debugging the deployment to not exceed the rate limits.
  # Otherwise you might be blocked for some days.
  [ValidateSet("https://acme-staging-v02.api.letsencrypt.org/directory", "https://acme-v02.api.letsencrypt.org/directory")]
  [string] $LetsEncryptServer = $env:LETSENCRYPT_SERVER ? $env:LETSENCRYPT_SERVER : "https://acme-staging-v02.api.letsencrypt.org/directory",
  # Additional Subnets to be allowed to access Storage Accounts
  [string[]] $SubnetIds = @("/subscriptions/<Get it from Azure Portal>/resourceGroups/rg-vvproj-buildagents/providers/Microsoft.Network/virtualNetworks/vnt-vvproj-buildagents/subnets/default"),
  [bool] $SetAksToRunning = $env:SET_AKS_TO_RUNNING ? @("TRUE", "1").Contains($env:SET_AKS_TO_RUNNING.ToUpper()) : $true
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
  { Import-Module -Name Az.Accounts, Az.Resources, Az.Storage, Az.Aks -Force -Verbose:$false } | Invoke-Edv-Command 4>$null # Hide Verbose messages (stream 4)

  Write-Host "`n# Initialize Variables ... " -NoNewline
    $env:SOLUTION_NAME = $SolutionName
    $env:CUSTOMER = $Customer
    $env:ENV_NAME = $EnvName
    $env:LOCATION = $Location
    $env:SUFFIX = "${env:SOLUTION_NAME}-${env:CUSTOMER}-${env:ENV_NAME}"
    $env:SUFFIX_NO_DASHES = "${env:SOLUTION_NAME}${env:CUSTOMER}${env:ENV_NAME}"
    $env:TFBACKEND_RESOURCE_GROUP_NAME = "rg-${env:SUFFIX}"
    $env:TFBACKEND_STORAGEACCOUNT_NAME = "satfbackend${env:SUFFIX_NO_DASHES}"
    $env:TFBACKEND_CONTAINER_NAME = "tfbackend-${env:SUFFIX}"
    $env:RESOURCE_GROUP_NAME = "rg-${env:SUFFIX}"
    $env:AKS_ADMIN_GROUP_OBJECT_ID = $AksAdminObjectId
    $env:AKS_ADMIN_GROUP_NAME = $AksAdminGroupName
    $env:LETSENCRYPT_EMAIL = $LetsEncryptEmail
    $env:LETSENCRYPT_SERVER = $LetsEncryptServer
    Write-Host "done"

  Write-Host "`n# Make sure you ran 'Connect-AzAccount' and/or 'az login' with the correct Subscription and Tenant.`n"
  $account = { Get-AzContext } | Invoke-Edv-Command
  $account | Format-Table | Out-String | Write-Host

  Write-Host "`n# Get Current User info..."
    $env:USER_OBJECT_ID = if ($account.Account.Type -eq 'User') { $(Get-AzADUser -UserPrincipalName $account.Account.Id).Id } else { $(Get-AzADServicePrincipal -ApplicationId $account.Account.Id).Id }
    Write-Host "#   Got env:USER_OBJECT_ID=${env:USER_OBJECT_ID}"
    $env:SUBSCRIPTION_NAME = $account.Subscription.Name
    Write-Host "#   Got env:SUBSCRIPTION_NAME=${env:SUBSCRIPTION_NAME}"
    $env:SUBSCRIPTION_ID = $account.Subscription.Id
    Write-Host "#   Got env:SUBSCRIPTION_ID=${env:SUBSCRIPTION_ID}"

  Write-Host "`n# Set Environment Variables in a CI/CD Pipeline: "
  if ( -not [system.string]::IsNullOrEmpty($env:SYSTEM_DEFINITIONID) ) { # It's a sign that the script runs in Azure DevOps.
    Write-Host "#   - Azure DevOps ..."
    Write-Host "##vso[task.setvariable variable=TFOUTPUTS_FILE; issecret=false; isoutput=true]${env:TFOUTPUTS_FILE}";
    Write-Host "##vso[task.setvariable variable=SOLUTION_NAME; issecret-false; isoutput-true]${env:SOLUTION_NAME}"
    Write-Host "##vso[task.setvariable variable=CUSTOMER; issecret-false; isoutput-true]${env:CUSTOMER}"
    Write-Host "##vso[task.setvariable variable=ENV_NAME; issecret-false; isoutput-true]${env:ENV_NAME}"
    Write-Host "##vso[task.setvariable variable=LOCATION; issecret-false; isoutput-true]${env:LOCATION}"
    Write-Host "##vso[task.setvariable variable=SUFFIX; issecret-false; isoutput-true]${env:SUFFIX}"
    Write-Host "##vso[task.setvariable variable=SUFFIX_NO_DASHES; issecret-false; isoutput-true]${env:SUFFIX_NO_DASHES}"
    Write-Host "##vso[task.setvariable variable=TFBACKEND_RESOURCE_GROUP_NAME; issecret-false; isoutput-true]${env:TFBACKEND_RESOURCE_GROUP_NAME}"
    Write-Host "##vso[task.setvariable variable=TFBACKEND_STORAGEACCOUNT_NAME; issecret-false; isoutput-true]${env:TFBACKEND_STORAGEACCOUNT_NAME}"
    Write-Host "##vso[task.setvariable variable=TFBACKEND_CONTAINER_NAME; issecret-false; isoutput-true]${env:TFBACKEND_CONTAINER_NAME}"
    Write-Host "##vso[task.setvariable variable=RESOURCE_GROUP_NAME; issecret-false; isoutput-true]${env:RESOURCE_GROUP_NAME}"
    Write-Host "##vso[task.setvariable variable=AKS_ADMIN_GROUP_OBJECT_ID; issecret-false; isoutput-true]${env:AKS_ADMIN_GROUP_OBJECT_ID}"
    Write-Host "##vso[task.setvariable variable=AKS_ADMIN_GROUP_NAME; issecret-false; isoutput-true]${env:AKS_ADMIN_GROUP_NAME}"
    Write-Host "##vso[task.setvariable variable=LETSENCRYPT_EMAIL; issecret-false; isoutput-true]${env:LETSENCRYPT_EMAIL}"
    Write-Host "##vso[task.setvariable variable=LETSENCRYPT_SERVER; issecret-false; isoutput-true]${env:LETSENCRYPT_SERVER}"
    Write-Host "##vso[task.setvariable variable=USER_OBJECT_ID; issecret-false; isoutput-true]${env:USER_OBJECT_ID}"
    Write-Host "##vso[task.setvariable variable=SUBSCRIPTION_NAME; issecret-false; isoutput-true]${env:SUBSCRIPTION_NAME}"
    Write-Host "##vso[task.setvariable variable=SUBSCRIPTION_ID; issecret-false; isoutput-true]${env:SUBSCRIPTION_ID}"
    Write-Host "#       ... done"
  }
  else {
    Write-Host "#   Not in an Azure DevOps Pipeline."
  }
#endregion Initialize

#region TF Backend
  Write-Host "`n# Azure Resource Group ${env:TFBACKEND_RESOURCE_GROUP_NAME} in ${env:LOCATION}: " -NoNewline
    if (Get-AzResourceGroup -Name $env:TFBACKEND_RESOURCE_GROUP_NAME -ErrorAction SilentlyContinue -OutVariable "resourceGroup") {
      Write-Host "already there."
    } else {
      Write-Host "creating..."
      { New-AzResourceGroup -Name $env:TFBACKEND_RESOURCE_GROUP_NAME -Location $env:LOCATION -Force -Verbose -OutVariable "resourceGroup" } | Invoke-Edv-Command | Format-Table | Out-String
    }

  Write-Host "`n# Storage Account ${env:TFBACKEND_STORAGEACCOUNT_NAME} in ${env:TFBACKEND_RESOURCE_GROUP_NAME}: " -NoNewline
    if (Get-AzStorageAccount -Name $env:TFBACKEND_STORAGEACCOUNT_NAME -ResourceGroupName $env:TFBACKEND_RESOURCE_GROUP_NAME -ErrorAction SilentlyContinue) {
      Write-Host "already there."
    } else {
      Write-Host "creating..."
      { New-AzStorageAccount -Name $env:TFBACKEND_STORAGEACCOUNT_NAME -ResourceGroupName $env:TFBACKEND_RESOURCE_GROUP_NAME -Location $env:LOCATION -SkuName 'Standard_LRS' -Verbose } | Invoke-Edv-Command | Format-Table | Out-String
    }

  Write-Host "`n# Update Azure Storage Account ${env:TFBACKEND_STORAGEACCOUNT_NAME} in ${env:TFBACKEND_RESOURCE_GROUP_NAME}"
    $arguments = @{
      Name                 = $env:TFBACKEND_STORAGEACCOUNT_NAME
      ResourceGroupName    = $env:TFBACKEND_RESOURCE_GROUP_NAME
      MinimumTlsVersion    = 'TLS1_2'
      EnableHttpsTrafficOnly = $true
      AllowBlobPublicAccess = $false
      AllowSharedKeyAccess = $false
      EnableLocalUser      = $false
      PublicNetworkAccess  = 'Enabled'
      NetworkRuleSet       = @{
        # DefaultAction = 'Allow'
        DefaultAction = 'Deny'
        Bypass        = 'AzureServices'
        VirtualNetworkRules = $SubnetIds | ForEach-Object { @{ VirtualNetworkResourceId = $_; Action = 'Allow' } }
      }
      Verbose = $true
    }
    Write-Host "`n# PS> Set-AzStorageAccount $($arguments | ConvertTo-Json)"
    { Set-AzStorageAccount @arguments | Select-Object -Property ResourceGroupName, StorageAccountName, CreationTime } | Invoke-Edv-Command | Out-String
#endregion TF Backend

#region Networking
  Write-Host "`n# Update Network RuleSet"
  # $IPs = @( $(Invoke-WebRequest -Uri https://ipinfo.io/ip).Content )
  # Write-Host "#   Current Public IP: $($IPs -join ', ')"
  $IPs = @()
  $IPs += Get-Content -Path "${InfraRepoRootFolder}/tf-azure/allowed-ips-vvp-addresses-short.json" | ConvertFrom-Json `
    | ForEach-Object { if ($_.ip) { if (@("31", "32") -contains $_.subnet) {$_.ip} else { '{0}/{1}' -F $_.ip, $_.subnet } } }
  $IPs += Get-Content -Path "${InfraRepoRootFolder}/tf-azure/allowed-ips-extra.json" | ConvertFrom-Json `
    | ForEach-Object { if ($_.ip) { if (@("31", "32") -contains $_.subnet) {$_.ip} else { '{0}/{1}' -F $_.ip, $_.subnet } } }
  $IPs = $IPs | Select-Object -Unique | Sort-Object
  $({ Add-AzStorageAccountNetworkRule -ResourceGroupName $env:TFBACKEND_RESOURCE_GROUP_NAME -Name $env:TFBACKEND_STORAGEACCOUNT_NAME -IPAddressOrRange $IPs -Verbose } | Invoke-Edv-Command | Format-Table | Out-String) -replace " ", ":" -replace "(`r`n|`n|`r| )", ";"

  Write-Host "`n# Remove not provided IPs"
  $NetworkRuleSet = { Get-AzStorageAccountNetworkRuleSet -ResourceGroupName $env:TFBACKEND_RESOURCE_GROUP_NAME -Name $env:TFBACKEND_STORAGEACCOUNT_NAME } | Invoke-Edv-Command

  foreach ( $ip in $NetworkRuleSet.ipRules.ipAddressOrRange ) {
    if ($IPs -notcontains "$ip") {
      Write-Host "#   IP ${ip} not provided, removing..."
      { Remove-AzStorageAccountNetworkRule -ResourceGroupName $env:TFBACKEND_RESOURCE_GROUP_NAME -Name $env:TFBACKEND_STORAGEACCOUNT_NAME -IPAddressOrRange $ip -Verbose } | Invoke-Edv-Command | Format-Table | Out-String
    }
  }
#endregion Networking

#region Roles
  Write-Host "`n# Role Assignments for UserId=${env:USER_OBJECT_ID} over Resource Group=${env:TFBACKEND_RESOURCE_GROUP_NAME}"
  $currentRoleAssignments = { Get-AzRoleAssignment -ObjectId $env:USER_OBJECT_ID -Scope $resourceGroup.ResourceId -ErrorAction SilentlyContinue } | Invoke-Edv-Command

  @('Contributor', 'User Access Administrator', 'Storage Blob Data Contributor') | ForEach-Object {
    $role = $_
    Write-Host "#   - role assignment '$role': " -NoNewline
    if ($currentRoleAssignments.RoleDefinitionName -contains $role) {
      Write-Host "already there"
    } else {
      Write-Host "assigning..."
      { New-AzRoleAssignment -ObjectId $env:USER_OBJECT_ID -RoleDefinitionName $role -Scope $resourceGroup.ResourceId -Verbose } | Invoke-Edv-Command | Format-Table | Out-String
    }
  }
#endregion Roles

#region Validate Networking
  Write-Host "`n# Waiting for network rules to propagate..."
  $maxAttempts = 10
  $sleepInterval = 5
  $ctx = New-AzStorageContext -StorageAccountName $env:TFBACKEND_STORAGEACCOUNT_NAME -UseConnectedAccount

  for ($i = 1; $i -le $maxAttempts; $i++) {
    Write-Host "#   Attempt ${i}/${maxAttempts}: checking storage access..."
    try {
      Get-AzStorageContainer -Context $ctx | Out-Null
      Write-Host "#   Access confirmed."
      break
    }
    catch {
      Write-Host "#   Access denied. Retrying in ${sleepInterval}s..."
      { Start-Sleep -Seconds $sleepInterval } | Invoke-Edv-Command
    }
  }
  if ($i -gt $maxAttempts) { throw "Timed out waiting for network rules to propagate." }
#endregion Validate Networking

#region Container
  Write-Host "`n# Container ${env:TFBACKEND_CONTAINER_NAME} in ${env:TFBACKEND_STORAGEACCOUNT_NAME}: " -NoNewline
  # $ctx defined earlier
  if (Get-AzStorageContainer -Name $env:TFBACKEND_CONTAINER_NAME -Context $ctx -ErrorAction SilentlyContinue) {
    Write-Host "already there."
  } else {
    Write-Host "creating..."
    { New-AzStorageContainer -Name $env:TFBACKEND_CONTAINER_NAME -Context $ctx } | Invoke-Edv-Command | Format-Table | Out-String
  }
#endregion Container

#region Lease
  Write-Host "`n# Check availability (lease status) of the file (blob) terraform.tfstate from the Storage Account ${env:TFBACKEND_STORAGEACCOUNT_NAME}, Container ${env:TFBACKEND_CONTAINER_NAME}"
  $blob = Get-AzStorageBlob -Container $env:TFBACKEND_CONTAINER_NAME -Context $ctx | Where-Object { $_.Name -eq "terraform.tfstate" }

  if ($blob) {
    Write-Host "#   File exists."

    $blob = Get-AzStorageBlob -Container $env:TFBACKEND_CONTAINER_NAME -Blob "terraform.tfstate" -Context $ctx
    Write-Host "#   File's Lease status: $($blob.BlobProperties.LeaseStatus)"

    if ($blob.BlobProperties.LeaseStatus -eq "Locked") {
      Write-Host "#   Break the lease using .NET method:"
      { $blob.ICloudBlob.BreakLease(0) } | Invoke-Edv-Command | Format-Table | Out-String
    }
  }
#endregion Lease

#region TF Landing
  Write-Host "`n# Azure Resource Group ${env:RESOURCE_GROUP_NAME} in ${env:LOCATION}: " -NoNewline

  if (Get-AzResourceGroup -Name $env:RESOURCE_GROUP_NAME -ErrorAction SilentlyContinue -OutVariable "resourceGroup") {
    Write-Host "already there."
  } else {
    Write-Host "creating..."
    { New-AzResourceGroup -Name $env:RESOURCE_GROUP_NAME -Location $env:LOCATION -Force -Verbose -OutVariable "resourceGroup" } | Invoke-Edv-Command | Format-Table | Out-String
  }
#endregion TF Landing

#region Roles
  Write-Host "`n# Role Assignments for UserId=${env:USER_OBJECT_ID} over Resource Group=${env:RESOURCE_GROUP_NAME}"
  $currentRoleAssignments = { Get-AzRoleAssignment -ObjectId $env:USER_OBJECT_ID -Scope $resourceGroup.ResourceId -ErrorAction SilentlyContinue } | Invoke-Edv-Command

  @('Contributor', 'User Access Administrator', 'Azure Service Bus Data Owner', 'Key Vault Secrets Officer', 'AcrPull', 'AcrPush') | ForEach-Object {
    $role = $_
    Write-Host "#   - role assignment '$role': " -NoNewline
    if ($currentRoleAssignments | Where-Object { $_.RoleDefinitionName -eq $role }) {
      Write-Host "already there."
    } else {
      Write-Host "assigning..."
      { New-AzRoleAssignment -ObjectId $env:USER_OBJECT_ID -RoleDefinitionName $role -Scope $resourceGroup.ResourceId -Verbose } | Invoke-Edv-Command | Format-Table | Out-String
    }
  }
#endregion TF Backend

#region Start AKS
  if ( $SetAksToRunning) {
    Write-Host "`n# Set AKS PowerState to Running..."
    $aks = { Get-AzAksCluster -ResourceGroupName $env:RESOURCE_GROUP_NAME -Name "aks-${env:SUFFIX}" -ErrorAction SilentlyContinue } | Invoke-Edv-Command

    if ($aks) {
      Write-Host "#   AKS PowerState = $($aks.PowerState.Code)"
      if ($aks.PowerState.Code -eq "Stopped") {
        Start-AzAksCluster -InputObject $aks -Verbose
        $aks = { Get-AzAksCluster -ResourceGroupName $env:RESOURCE_GROUP_NAME -Name "aks-${env:SUFFIX}" -ErrorAction SilentlyContinue } | Invoke-Edv-Command
        Write-Host "#   AKS PowerState = $($aks.PowerState.Code)"
      }
    }
    else {
      Write-Host "#   AKS not found: ${env:RESOURCE_GROUP_NAME} / aks-${env:SUFFIX}"
    }
  }
#endregion Start AKS

Write-Host "`n# You are ready to run Terraform commands having:"
Write-Host "#   - Backend in '$($account.Subscription.Name)/${env:TFBACKEND_RESOURCE_GROUP_NAME} / ${env:TFBACKEND_STORAGEACCOUNT_NAME} / ${env:TFBACKEND_CONTAINER_NAME}'."
Write-Host "#   - Landing zone in '$($account.Subscription.Name) / ${env:RESOURCE_GROUP_NAME}'.`n"
