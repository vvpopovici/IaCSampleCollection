# Deploy a Container App

```powershell
#region Set Subscription
  $SubscriptionName, $SubscriptionId = 'Vasile Popovici - VS Prof Subscr', '34e8edd7-0778-437c-87a8-77d284221066';
  $ErrorActionPreference, $VerbosePreference, $ProgressPreference = 'Stop', 'Continue', 'SilentlyContinue';
  $Verbose = $( $VerbosePreference -notin 'SilentlyContinue' );
  $azContext = Get-AzContext -ListAvailable | Where-Object { $_.Subscription.Name -eq $SubscriptionName }; if ($azContext) { Set-AzContext -Context $azContext } else { $azContext = Connect-AzAccount -DeviceCode; $azContext };
  $currentUserId = $azContext.Account.ExtendedProperties.HomeAccountId.Split('.')[0]; $currentUserId;
  Set-Location -Path 'C:\Repos\EnRepos\capps-sample';
#endregion
#region Variables
  $app, $env = "learn", "vvp";
  $Location = "West Europe";
  $ResourceGroupName = "rg-${app}-${env}";
#endregion

$rg = New-AzResourceGroup -Location $Location -Name $ResourceGroupName -Force -Verbose; $rg
# Remove-AzResourceGroup -Name $ResourceGroupName

# Deploy infra without Container App
$suffix = '00'
$arguments = @{
  ResourceGroupName = $ResourceGroupName;
  TemplateFile = ".\capps-deploy.bicep";
  Mode = "Incremental";
  Verbose = $true;
  app = ${app};
  env = ${env};
  CurrentUserId = $currentUserId;
  CurrentUserType = "User";
  keyVaultName = "kv-${app}-${env}-${suffix}";
  deployCapp = $false
}; $arguments;
New-AzResourceGroupDeployment @arguments;

# Populate ACR with HelloWorld
Set-Location -Path "C:\Repos\EnRepos\capps-sample\HelloWorld-Docker"
$acr = Get-AzContainerRegistry -ResourceGroupName $ResourceGroupName -Name "acr${app}${env}"
$acrCreds = Get-AzContainerRegistryCredential -Registry $acr; $acrCreds
# $acrCreds = Get-AzContainerRegistryCredential -ResourceGroupName $ResourceGroupName -Name "acr${app}${env}"; $acrCreds
docker login $acr.LoginServer -u $($acrCreds.Username) -p "$($acrCreds.Password)"
$imageName, $imageTag = "$($acr.LoginServer)/helloworld", "latest"
docker build ./ -t "${imageName}:${imageTag}" -f Dockerfile
docker push "${imageName}:${imageTag}"
Set-Location -Path "C:\Repos\EnRepos\capps-sample\"


# Deploy infra including Container App
$suffix = '00'
$arguments = @{
  ResourceGroupName = $ResourceGroupName;
  TemplateFile = ".\capps-deploy.bicep";
  Mode = "Incremental";
  Verbose = $true;
  app = ${app};
  env = ${env};
  CurrentUserId = $currentUserId;
  CurrentUserType = "User";
  keyVaultName = "kv-${app}-${env}-${suffix}";
  deployCapp = $true
}; $arguments;
New-AzResourceGroupDeployment @arguments;

$deployment = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name 'capps-deploy'
# Check the scaling OUT
"### $(Get-Date) Replicas count = $($(Get-AzContainerAppRevision -ContainerAppName "capp-${app}-${env}" -ResourceGroupName $ResourceGroupName | Where-Object -Property Active -EQ $true).Replica)"
while ($true) {
  $res = curl -sS "capp-${app}-${env}.$($deployment.Outputs.oContainerEnvFqdn.Value):5000";
  $res[3]
  "### $(Get-Date) Replicas count = $($(Get-AzContainerAppRevision -ContainerAppName "capp-${app}-${env}" -ResourceGroupName $ResourceGroupName | Where-Object -Property Active -EQ $true).Replica)"
}

# Wait the scaling IN
while ($true) {
  "### $(Get-Date) Replicas count = $($(Get-AzContainerAppRevision -ContainerAppName "capp-${app}-${env}" -ResourceGroupName $ResourceGroupName | Where-Object -Property Active -EQ $true).Replica)"
  Start-Sleep -Second 5
}

# The logs confirm the scaling behavior https://learn.microsoft.com/en-us/azure/container-apps/scale-app?pivots=azure-cli#scale-behavior
  # ### 08/25/2023 11:26:29 Replicas count = 0
  # ... 17 secs to pull and start 1 replica
  # Hostname=capp-learn-vvp--688n1hc-7c4688885-fxlm7, Private IP=10.0.0.46<br>
  # ### 08/25/2023 11:26:46 Replicas count = 1
  # ... 17 secs to pull and start the second replica
  # Hostname=capp-learn-vvp--688n1hc-7c4688885-fxlm7, Private IP=10.0.0.46<br>
  # ### 08/25/2023 11:27:01 Replicas count = 2
  # PS 7.3.6 > # Wait the scaling IN
  # ### 08/25/2023 11:27:20 Replicas count = 2
  # ... 5 mins to scale IN
  # ### 08/25/2023 11:32:22 Replicas count = 1
  # ### 08/25/2023 11:32:37 Replicas count = 1
  # ### 08/25/2023 11:32:43 Replicas count = 0
  # ... 5.5 mins to scale IN to 0 replicas

# ================================================
docker run --rm -it -v ./:/host/ -w /host/ python:3.9-slim-buster bash
```
