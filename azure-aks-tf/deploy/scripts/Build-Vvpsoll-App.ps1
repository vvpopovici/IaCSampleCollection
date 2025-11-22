<#
.DESCRIPTION
  Script is ready for Azure task.

.EXAMPLE
  - task: AzureCLI@2 # BuildPush
    name: BuildPush
    inputs:
      azureSubscription: $(SERVICE_CONNECTION)
      scriptType: pscore
      errorActionPreference: stop
      failOnStandardError: true
      scriptLocation: scriptPath
      # arguments: # arguments are taken from Environment Variables
      scriptPath: $(INFRA_ROOT_FOLDER)/deploy/scripts/Build-Vvpsoll-App.ps1

.EXAMPLE
  cd ./tpi-video-analysis-infra;
  ./deploy/scripts/Build-Vvpsoll-App.ps1 -AppRootFolder ../tpi-video-analysis-ui/ -PushDockerImages $false
  ./deploy/scripts/Build-Vvpsoll-App.ps1 -AppRootFolder ../tpi-upload-video-api/ -PushDockerImages $false
  ./deploy/scripts/Build-Vvpsoll-App.ps1 -AppRootFolder ../tpi-video-analysis-service/_models/ -PushDockerImages $false
  ./deploy/scripts/Build-Vvpsoll-App.ps1 -AppRootFolder ../vvproj-ml/ -PushDockerImages $false
  ./deploy/scripts/Build-Vvpsoll-App.ps1 -AppRootFolder ../tpi-video-analysis-lib/ -PushDockerImages $false
  ./deploy/scripts/Build-Vvpsoll-App.ps1 -AppRootFolder ../tpi-video-analysis-service/ -PushDockerImages $false

.EXAMPLE
  @(
    "../tpi-video-analysis-ui",
    "../tpi-upload-video-api",
    "../tpi-video-analysis-service/_models",
    "../vvproj-ml",
    "../tpi-video-analysis-lib",
    "../tpi-video-analysis-service"
  ) | ./deploy/scripts/Build-Vvpsoll-App.ps1

#>
[CmdletBinding()]
param (
  [Parameter(ValueFromPipeline)]
  [ValidateNotNullOrEmpty()] [ValidateScript({Test-Path $_})]
  [string] $AppRootFolder = $env:APP_ROOT_FOLDER,
  [bool] $BuildDockerImages = $true,
  [bool] $PushDockerImages = $true,
  [switch] $SkipAcrLogin,
  [string] $TfOutputsFile = $env:TFOUTPUTS_FILE ? $env:TFOUTPUTS_FILE : "${PSScriptRoot}/../../terraform_outputs.json",
  [string] $ImageTag = $env:IMAGE_TAG ? $env:IMAGE_TAG : $(Get-Date -Format "yyyyMMdd-HHmmss"),
  # Used when building VVPSOLL SERVICE. Just ignore it for other apps.
  [string] $VVPSOLL_LIB_IMAGE = "vvpsoll-lib:latest",
  # Used when building VVPSOLL UI. Just ignore it for other apps.
  [string] $VITE_API_BASE_URL = $env:VITE_API_BASE_URL ? $env:VITE_API_BASE_URL : "http://localhost:8000"
)

begin {
  $ErrorActionPreference, $VerbosePreference, $WarningPreference, $InformationPreference = "Stop", "Continue", "Continue", "Continue";

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
    if ($PushDockerImages) {
      Write-Host "`n# Convert Terraform Outputs to Environment Variables:"
      $TFOUTPUTS = Get-Content -Path $TfOutputsFile -Raw | ConvertFrom-Json
      $TFOUTPUTS | Get-Member -MemberType NoteProperty | ForEach-Object {
        $varName = "TFOUTPUTS_$($_.Name.ToUpper())"
        $varValue = $($TFOUTPUTS.$($_.Name).value | ConvertTo-Json -Depth 99).Trim('"')
        $varNotSensitive = -not $TFOUTPUTS.$($_.Name).sensitive
        Set-Item -Path env:$varName -Value $varValue -Verbose:$varNotSensitive
      }
    }

    Write-Host "`n# Required CLI tools"
    "az", "docker" | ForEach-Object {
      Write-Host "#   - ${_}: " -NoNewline

      if (-not (Get-Command -Name $_ -ErrorAction SilentlyContinue)) {
        Write-Host "missing"
        throw "Missing required CLI tool ${_}."
      }
      Write-Host "available"
    }

    Write-Host "`n# Make sure you ran 'Connect-AzAccount' and/or 'az login' with the correct Subscription and Tenant.`n"
    { az account show } | Invoke-Edv-Command

    if ( $SkipAcrLogin ){ Write-Host "`n# Skip ACR Login." }
    else {
      { az acr login --name $env:TFOUTPUTS_CONTAINER_REGISTRY_NAME --resource-group $env:TFOUTPUTS_RESOURCE_GROUP_NAME } | Invoke-Edv-Command
    }
  #endregion Initialize
}

process {
  Write-Host "`n### Build and Push Docker Image for App in folder: $AppRootFolder`n"
  $appName = $("{0}-{1}" -F
    $(Get-Content -Path "${AppRootFolder}/deploy/repospecifics.env" | ConvertFrom-StringData).SOLUTION_NAME,
    $(Get-Content -Path "${AppRootFolder}/deploy/repospecifics.env" | ConvertFrom-StringData).IDENTIFIER
  ).ToLower()
  $dockerfile = "${AppRootFolder}/deploy/Dockerfile"

  if ( $BuildDockerImages ) {
    { docker rmi $appName -f 2>&1 } | Invoke-Edv-Command

    { docker build -f "${dockerfile}" `
      --build-arg APP_VERSION=$ImageTag `
      --build-arg VITE_API_BASE_URL=$VITE_API_BASE_URL `
      --build-arg VVPSOLL_LIB_IMAGE=$VVPSOLL_LIB_IMAGE `
      -t $appName `
      "${AppRootFolder}" --progress=plain 2>&1
    } | Invoke-Edv-Command
  }
  else {
    Write-Host "`n# Skip Docker building."
  }

  if ( $PushDockerImages ) {
    if ($ImageTag -ne "latest") { { docker tag $appName "${env:TFOUTPUTS_CONTAINER_REGISTRY_LOGIN_SERVER}/${appName}:${ImageTag}" } | Invoke-Edv-Command }
    { docker tag $appName "${env:TFOUTPUTS_CONTAINER_REGISTRY_LOGIN_SERVER}/${appName}:latest" } | Invoke-Edv-Command

    if ($ImageTag -ne "latest") { { docker push "${env:TFOUTPUTS_CONTAINER_REGISTRY_LOGIN_SERVER}/${appName}:${ImageTag}" } | Invoke-Edv-Command }
    { docker push "${env:TFOUTPUTS_CONTAINER_REGISTRY_LOGIN_SERVER}/${appName}:latest" } | Invoke-Edv-Command
  }
  else {
    Write-Host "`n# Skip Docker Pushing."
  }

  Set-Item -Path "env:IMAGE_REGISTRY" -Value $env:TFOUTPUTS_CONTAINER_REGISTRY_LOGIN_SERVER -Verbose
  Set-Item -Path "env:IMAGE_REPO_$($appName.ToUpper().Replace('-','_'))" -Value $appName -Verbose
  Set-Item -Path "env:IMAGE_TAG_$($appName.ToUpper().Replace('-','_'))" -Value $ImageTag -Verbose
    Write-Host "##vso[task.setvariable variable=IMAGE_REGISTRY; issecret=false; isoutput=true]${env:IMAGE_REGISTRY}";
    Write-Host "##vso[task.setvariable variable=IMAGE_REPO_$($appName.ToUpper().Replace('-','_')); issecret=false; isoutput=true]${appName}";
    Write-Host "##vso[task.setvariable variable=IMAGE_TAG_$($appName.ToUpper().Replace('-','_')); issecret=false; isoutput=true]${ImageTag}";

  Write-Host "`n# Run this on your host: docker run --rm -it --name ${appName} ${appName}:latest`n"
}

end {}
