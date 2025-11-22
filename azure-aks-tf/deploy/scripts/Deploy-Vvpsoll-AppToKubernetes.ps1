<#
.DESCRIPTION
  Script is ready for the Azure Task.

.EXAMPLE
  - task: AzureCLI@2 # Deploy
    name: Deploy
    inputs:
      azureSubscription: $(SERVICE_CONNECTION)
      scriptType: pscore
      errorActionPreference: stop
      failOnStandardError: true
      scriptLocation: scriptPath
      # arguments: # arguments are taken from Environment Variables
      scriptPath: $(INFRA_ROOT_FOLDER)/deploy/scripts/Deploy-Vvpsoll-AppToKubernetes.ps1

.EXAMPLE
  cd ./tpi-video-analysis-infra;
  ./deploy/scripts/Deploy-Vvpsoll-AppToKubernetes.ps1 -AppRootFolder ../tpi-video-analysis-ui/
  ./deploy/scripts/Deploy-Vvpsoll-AppToKubernetes.ps1 -AppRootFolder ../tpi-upload-video-api/
  ./deploy/scripts/Deploy-Vvpsoll-AppToKubernetes.ps1 -AppRootFolder ../tpi-video-analysis-service/

.EXAMPLE
  cd ./tpi-video-analysis-infra;
  ./deploy/scripts/Deploy-Vvpsoll-AppToKubernetes.ps1 -AppRootFolder ../tpi-video-analysis-ui/ -ImageTag latest
  ./deploy/scripts/Deploy-Vvpsoll-AppToKubernetes.ps1 -AppRootFolder ../tpi-upload-video-api/ -ImageTag latest
  ./deploy/scripts/Deploy-Vvpsoll-AppToKubernetes.ps1 -AppRootFolder ../tpi-video-analysis-service/ -ImageTag latest

.EXAMPLE
  @(
    "../tpi-video-analysis-ui",
    "../tpi-upload-video-api",
    "../tpi-video-analysis-service"
  ) | ./deploy/scripts/Deploy-Vvpsoll-AppToKubernetes.ps1

#>
[CmdletBinding()]
param (
  [Parameter(ValueFromPipeline)]
  [ValidateNotNullOrEmpty()] [ValidateScript({Test-Path $_})]
  [string] $AppRootFolder = $env:APP_ROOT_FOLDER,
  [string] $TfOutputsFile = $env:TFOUTPUTS_FILE ? $env:TFOUTPUTS_FILE : "${PSScriptRoot}/../../terraform_outputs.json",
  [string] $ImageTag = $env:IMAGE_TAG ? $env:IMAGE_TAG : "latest",
  [bool] $AdjustAksApiAuthorizedIpRanges = $env:ADJUST_AKS_API_AUTHORIZED_IP_RANGES ? @("TRUE", "1").Contains($env:ADJUST_AKS_API_AUTHORIZED_IP_RANGES.ToUpper()) : $false
)

begin {
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
    Write-Host "`n# Initialize Variables ... " -NoNewline
    $env:IMAGE_TAG = $ImageTag
    Write-Host "done"

    Write-Host "`n# Convert Terraform Outputs to Environment Variables:"
    $TFOUTPUTS = Get-Content -Path $TfOutputsFile -Raw | ConvertFrom-Json
    $TFOUTPUTS | Get-Member -MemberType NoteProperty | ForEach-Object {
      $varName = "TFOUTPUTS_$($_.Name.ToUpper())"
      $varValue = $($TFOUTPUTS.$($_.Name).value | ConvertTo-Json -Depth 99).Trim('"')
      $varNotSensitive = -not $TFOUTPUTS.$($_.Name).sensitive
      Set-Item -Path env:$varName -Value $varValue -Verbose:$varNotSensitive
    }

    Write-Host "`n# Required CLI tools"
    "az", "kubectl", "kubelogin" | ForEach-Object {
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

      $currentRanges = { az aks show -g $env:TFOUTPUTS_RESOURCE_GROUP_NAME -n $env:TFOUTPUTS_AKS_NAME --query "apiServerAccessProfile.authorizedIpRanges" -o json } | Invoke-Edv-Command
      $currentRanges = $currentRanges | ConvertFrom-Json
      $currentRangesCsv = $currentRanges -join ","

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
  #endregion Initialize
}

process {
  Write-Host "`n### Deploy App from ${AppRootFolder} with ImageTag='${ImageTag}'"
  $appName = $("{0}-{1}" -F
    $(Get-Content -Path "${AppRootFolder}/deploy/repospecifics.env" | ConvertFrom-StringData).SOLUTION_NAME,
    $(Get-Content -Path "${AppRootFolder}/deploy/repospecifics.env" | ConvertFrom-StringData).IDENTIFIER
  ).ToLower()
  $env:APP_NAME = $appName
  $healthUriPath = $(Get-Content -Path "${AppRootFolder}/deploy/repospecifics.env" | ConvertFrom-StringData).HEALTH_URI_PATH

  { & "${PSScriptRoot}/Convert-Vvpsoll-TokenToVariable.ps1" `
      -InputFile "${AppRootFolder}/deploy/kubernetes/${appName}.yaml.template" `
      -OutputFile "${AppRootFolder}/deploy/kubernetes/${appName}.yaml" `
      -DisplayContent
    } | Invoke-Edv-Command

    Write-Host "`n# Delete app from ${AppRootFolder}"
    Write-Host "#   - first try (ignore errors):" -NoNewline
    { kubectl delete -f "${AppRootFolder}/deploy/kubernetes/${appName}.yaml" -n $env:TFOUTPUTS_SOLUTION_NAME --ignore-not-found=true --wait=true --timeout=180s *>&1 } | Invoke-Edv-Command -ErrorAction SilentlyContinue
    Write-Host "#   - second try (catch errors):" -NoNewline
    { kubectl delete -f "${AppRootFolder}/deploy/kubernetes/${appName}.yaml" -n $env:TFOUTPUTS_SOLUTION_NAME --ignore-not-found=true --wait=true --timeout=180s } | Invoke-Edv-Command

    Write-Host "`n# Deploy app from ${AppRootFolder}"
    { kubectl apply -f "${AppRootFolder}/deploy/kubernetes/${appName}.yaml" -n $env:TFOUTPUTS_SOLUTION_NAME } | Invoke-Edv-Command
  #endregion

  #region Validate
    if ( [system.string]::IsNullOrEmpty($healthUriPath) ) {
      Write-Host "`n# No health check path specified."
    }
    else {
      $endpoint = "https://${env:TFOUTPUTS_AKS_INGRESS_FQDN}${healthUriPath}"
      Write-Host "`n### Validating health at '${endpoint}'"

      $iterations = 4; $i = 0
      while ($i -le $iterations) {
        Write-Host "# Iteration ${i}/${iterations}: " -NoNewline
        try     { $request = Invoke-WebRequest -Uri $endpoint -ConnectionTimeoutSeconds 5 -Verbose:$false }
        catch   { $errorMessage = $_ }
        finally { Write-Host "result '$($request.StatusCode)$($request.StatusDescription)$($errorMessage.Exception.Message)', retrying in 5 secs..." }
        Start-Sleep -Seconds 5
        $i++
      }
      Write-Host "# Final Decisive Attempt: " -NoNewline
      try     { $request = Invoke-WebRequest -Uri $endpoint -ConnectionTimeoutSeconds 5 -Verbose:$false }
      catch   { $errorMessage = $_ }
      finally { Write-Host "result '$($request.StatusCode)$($request.StatusDescription)$($errorMessage.Exception.Message)'." }
    }
  #endregion Validate
}

end {
  { kubectl get all -n $env:TFOUTPUTS_SOLUTION_NAME } | Invoke-Edv-Command
  { kubectl get ingress -n $env:TFOUTPUTS_SOLUTION_NAME } | Invoke-Edv-Command

  if ($AdjustAksApiAuthorizedIpRanges) {
    if ($currentRangesCsv -eq $updatedRangesCsv) {
      Write-Host "`n# No changes required to AKS API Authorized IP Ranges."
    }
    else {
      Write-Host "`n# Restoring AKS API Authorized IP Ranges."
      { az aks update -g $env:TFOUTPUTS_RESOURCE_GROUP_NAME -n $env:TFOUTPUTS_AKS_NAME --api-server-authorized-ip-ranges=$currentRangesCsv --query "apiServerAccessProfile.authorizedIpRanges" } | Invoke-Edv-Command | ConvertFrom-Json | ConvertTo-Json -Compress
    }
  }
}
