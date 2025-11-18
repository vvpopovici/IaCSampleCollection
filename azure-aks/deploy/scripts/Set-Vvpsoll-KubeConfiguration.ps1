# Script is ready for the Azure Task
# - task: AzureCLI@2 # KubeConfiguration
#   name: KubeConfiguration
#   inputs:
#     azureSubscription: $(SERVICE_CONNECTION)
#     scriptType: pscore
#     errorActionPreference: stop
#     failOnStandardError: true
#     scriptLocation: scriptPath
#     # arguments: # arguments are taken from Environment Variables
#     scriptPath: $(INFRA_ROOT_FOLDER)/deploy/scripts/Set-Vvpsoll-KubeConfiguration.ps1

[CmdletBinding()]
param (
  [string] $InfraRepoRootFolder = $env:INFRA_ROOT_FOLDER ? $env:INFRA_ROOT_FOLDER : "${PSScriptRoot}/../..",
  [string] $TfOutputsFile = $env:TFOUTPUTS_FILE ? $env:TFOUTPUTS_FILE : "${PSScriptRoot}/../../terraform_outputs.json",
  [bool] $AdjustAksApiAuthorizedIpRanges = $env:ADJUST_AKS_API_AUTHORIZED_IP_RANGES ? @("TRUE", "1").Contains($env:ADJUST_AKS_API_AUTHORIZED_IP_RANGES.ToUpper()) : $false,
  [switch] $InitializeVvpsollInfrastructure
)

if ($InitializeVvpsollInfrastructure) {
  # The recommended way to initialize the infrastructure is to do that separately, before running this script.
  & "${InfraRepoRootFolder}/deploy/scripts/Initialize-Vvpsoll-Infrastructure.ps1" `
    -InfraRepoRootFolder $InfraRepoRootFolder `
    -TfOutputsFile $TfOutputsFile
}

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
  Write-Host "`n# Convert Terraform Outputs to Environment Variables:"
  $TFOUTPUTS = Get-Content -Path $TfOutputsFile -Raw | ConvertFrom-Json
  $TFOUTPUTS | Get-Member -MemberType NoteProperty | ForEach-Object {
    $varName = "TFOUTPUTS_$($_.Name.ToUpper())"
    $varValue = $($TFOUTPUTS.$($_.Name).value | ConvertTo-Json -Depth 99).Trim('"')
    $varNotSensitive = -not $TFOUTPUTS.$($_.Name).sensitive
    Set-Item -Path env:$varName -Value $varValue -Verbose:$varNotSensitive
  }

  Write-Host "`n# Required CLI tools"
  "az", "kubectl", "helm" | ForEach-Object {
    Write-Host "#   - ${_}: " -NoNewline

    if (-not (Get-Command -Name $_ -ErrorAction SilentlyContinue)) {
      Write-Host "missing"
      throw "Missing required CLI tool ${_}."
    }
    Write-Host "available"
  }

  Write-Host "`n# Make sure you ran 'Connect-AzAccount' and/or 'az login' with the correct Subscription and Tenant.`n"
  { az account show } | Invoke-Edv-Command

  if ($AdjustAksApiAuthorizedIpRanges) {
    Write-Host "`n# Adjusting Aks Api Authorized Ip Ranges"
    $currentPublicIp = "{0}/32" -F $(Invoke-WebRequest -Uri https://ipinfo.io/ip).Content
    Write-Host "#   Current Public IP: ${currentPublicIp}"

    $currentRanges = { az aks show -g $env:TFOUTPUTS_RESOURCE_GROUP_NAME -n $env:TFOUTPUTS_AKS_NAME --query "apiServerAccessProfile.authorizedIpRanges" -o json } | Invoke-Edv-Command | ConvertFrom-Json

    $updatedRanges = $currentRanges
    if ($currentRanges -contains $currentPublicIp) {
      Write-Host "#   Current Public IP is already in the authorized IP ranges."
    }
    else {
      Write-Host "#   Current Public IP is NOT in the authorized IP ranges. Going to add it..."
      $updatedRanges += @($currentPublicIp)
      $updatedRangesCsv = $updatedRanges -join ","
      { az aks update -g $env:TFOUTPUTS_RESOURCE_GROUP_NAME -n $env:TFOUTPUTS_AKS_NAME --api-server-authorized-ip-ranges=$updatedRangesCsv --query "apiServerAccessProfile.authorizedIpRanges" } | Invoke-Edv-Command | ConvertFrom-Json | ConvertTo-Json -Compress
    }
  }

  Write-Host "`n# Connect kubectl to AKS ...";
  { az aks get-credentials --resource-group $env:TFOUTPUTS_RESOURCE_GROUP_NAME --name $env:TFOUTPUTS_AKS_NAME --overwrite-existing --only-show-errors } | Invoke-Edv-Command
  # kubelogin is required when AKS is integrated with Microsoft Entra ID.
  { kubelogin convert-kubeconfig -l azurecli } | Invoke-Edv-Command

  { kubectl get nodes } | Invoke-Edv-Command
#endregion

#region Ingress
  if ( helm repo list -o json | ConvertFrom-Json | Where-Object { $_.name -eq "ingress-nginx" } ) {
    Write-Host "`n# Ingress-Nginx Helm repo is already added."
  }
  else {
    { helm repo add "ingress-nginx" "https://kubernetes.github.io/ingress-nginx" } | Invoke-Edv-Command
    { helm repo update } | Invoke-Edv-Command
  }

  # The default Ingress-Nginx
  { helm upgrade --install "ingress-nginx" "ingress-nginx/ingress-nginx" --version 4.13.0 `
    --namespace "ingress-nginx" --create-namespace --hide-notes `
    --set controller.ingressClassResource.default=true `
    --set controller.replicaCount=1 `
    --set controller.admissionWebhooks.enabled=false `
    --set controller.service.type="LoadBalancer" `
    --set controller.service.externalTrafficPolicy="Local" `
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"="/healthz" `
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-resource-group"="${env:TFOUTPUTS_RESOURCE_GROUP_NAME}" `
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"="${env:TFOUTPUTS_AKS_INGRESS_DOMAIN_LABEL}" `
    --set controller.service.loadBalancerIP="${env:TFOUTPUTS_AKS_INGRESS_PUBLIC_IP}"
  } | Invoke-Edv-Command
#endregion Ingress

#region Cert Manager
  if ( helm repo list -o json | ConvertFrom-Json | Where-Object { $_.name -eq "jetstack" } ) {
    Write-Host "`n# Jetstack Helm repo is already added."
  }
  else {
    { helm repo add "jetstack" "https://charts.jetstack.io" } | Invoke-Edv-Command
    { helm repo update } | Invoke-Edv-Command
  }

  { helm upgrade --install "cert-manager" "jetstack/cert-manager" `
    --namespace "cert-manager" --create-namespace --hide-notes `
    --version 1.18.2 `
    --set crds.enabled=true } | Invoke-Edv-Command
#endregion Cert Manager

#region Others
  & "${InfraRepoRootFolder}/deploy/scripts/Convert-Vvpsoll-TokenToVariable.ps1" `
      -InputFile "${InfraRepoRootFolder}/deploy/kubernetes/nvidia-gpu-plugin.yaml.template" `
      -OutputFile "${InfraRepoRootFolder}/deploy/kubernetes/nvidia-gpu-plugin.yaml" `
      -DisplayContent
  { kubectl apply -f "${InfraRepoRootFolder}/deploy/kubernetes/nvidia-gpu-plugin.yaml" } | Invoke-Edv-Command

  & "${InfraRepoRootFolder}/deploy/scripts/Convert-Vvpsoll-TokenToVariable.ps1" `
      -InputFile "${InfraRepoRootFolder}/deploy/kubernetes/letsencrypt-clusterissuer.yaml.template" `
      -OutputFile "${InfraRepoRootFolder}/deploy/kubernetes/letsencrypt-clusterissuer.yaml" `
      -DisplayContent
  { kubectl apply -f "${InfraRepoRootFolder}/deploy/kubernetes/letsencrypt-clusterissuer.yaml" -n cert-manager } | Invoke-Edv-Command

  & "${InfraRepoRootFolder}/deploy/scripts/Convert-Vvpsoll-TokenToVariable.ps1" `
      -InputFile "${InfraRepoRootFolder}/deploy/kubernetes/namespace.yaml.template" `
      -OutputFile "${InfraRepoRootFolder}/deploy/kubernetes/namespace.yaml" `
      -DisplayContent
  { kubectl apply -f "${InfraRepoRootFolder}/deploy/kubernetes/namespace.yaml" } | Invoke-Edv-Command

  & "${InfraRepoRootFolder}/deploy/scripts/Convert-Vvpsoll-TokenToVariable.ps1" `
      -InputFile "${InfraRepoRootFolder}/deploy/kubernetes/keyvault-secretproviderclass.yaml.template" `
      -OutputFile "${InfraRepoRootFolder}/deploy/kubernetes/keyvault-secretproviderclass.yaml" `
      -DisplayContent
  { kubectl apply -f "${InfraRepoRootFolder}/deploy/kubernetes/keyvault-secretproviderclass.yaml" } | Invoke-Edv-Command

#endregion Others

{ kubectl get all -n ingress-nginx } | Invoke-Edv-Command
{ kubectl get all -n cert-manager } | Invoke-Edv-Command
{ kubectl get all -n gpu-resources } | Invoke-Edv-Command
{ kubectl get clusterissuer -n cert-manager } | Invoke-Edv-Command
{ kubectl get SecretProviderClass -n $env:TFOUTPUTS_SOLUTION_NAME } | Invoke-Edv-Command

if ($AdjustAksApiAuthorizedIpRanges) {
  $currentRangesCsv = $currentRanges -join ","
  if ($currentRangesCsv -eq $updatedRangesCsv) {
    Write-Host "`n# No changes required to AKS API Authorized IP Ranges."
  }
  else {
    Write-Host "`n# Restoring AKS API Authorized IP Ranges to Initial State:"
    Write-Host "#   - Initial IP Ranges: ${currentRangesCsv}"
    Write-Host "#   - Updated IP Ranges: ${updatedRangesCsv}"
    { az aks update -g $env:TFOUTPUTS_RESOURCE_GROUP_NAME -n $env:TFOUTPUTS_AKS_NAME --api-server-authorized-ip-ranges=$currentRangesCsv --query "apiServerAccessProfile.authorizedIpRanges" 2>&1} | Invoke-Edv-Command | ConvertFrom-Json | ConvertTo-Json -Compress
  }
}
