//region Common params
  @maxLength(8)
  @minLength(3)
  param app string = 'learn'
  @maxLength(8)
  @minLength(3)
  param env string = 'vvp'
  param location string = resourceGroup().location
  param updatedOn string = utcNow('yyyy-MM-dd HH:mm:ss')
  param team string = 'platform'
  @description('App Service User Id(Object Id). It is required to configure access to Key Vault.')
  param currentUserId string
  @description('App Service User type. In CI/CD use "ServicePrincipal". If running locally, use "User". It is required to configure accesses for Key Valut.')
  @allowed([
    'ServicePrincipal'
    'User'
  ])
  param currentUserType string
//endregion Common params

//region This deployment specific params
  param logAnalyticsWorkspaceName string = 'log-${app}-${env}'    // Log Analytics is a must for Container Apps
  param logAnalyticsWorkspaceKeyId int = 0

  param virtualNetworkName string = 'vnet-${app}-${env}'
  param virtualNetworkCidr string = '10.0.0.0/16'
  param subnetKubeName string = 'snet-${app}-kube-${env}'
  param subnetKubeCidr string = '10.0.0.0/23' // '../23' is a must for Container Apps Environment

  @maxLength(24)
  param keyVaultName string = 'kv-${app}-${env}'

  @minLength(5)
  @maxLength(50)
  param acrName string = 'acr${app}${env}'
  @allowed([
    0
    1
  ])
  param acrKeyId int = 0

  param containerEnvName string = 'cenv-${app}-${env}'
  param deployCapp bool = false    // The list of Container Apps Names to deploy. This is used to skip the deployment of the apps when Container Registry is empty yet.
  param containerAppName string = 'capp-${app}-${env}'
  param containerAppPort int = 5000
  param containerAppImage string = '${acrName}.azurecr.io/helloworld:latest'
//endregion This deployment specific params

//region Variables
  var tags = {
    Application: app
    Environment: env
    UpdatedOn: updatedOn
    Team: team
  }
//endregion Variables

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkCidr
      ]
    }
  }

  resource subnetKube 'subnets' = {
    name: subnetKubeName
    properties: {
      addressPrefix: subnetKubeCidr
      privateEndpointNetworkPolicies: 'Disabled'
      serviceEndpoints: [
        {
          service: 'Microsoft.Storage'
          locations: [ location ]
        }
        {
          service: 'Microsoft.CognitiveServices'
          locations: [ location ]
        }
      ]
      delegations: []
    }

  }
}

module logAnalyticsWorkspace './logAnalyticsWorkspace.bicep' = {
  name: '${logAnalyticsWorkspaceName}-deploy'
  params: {
    name: logAnalyticsWorkspaceName
    tags: tags
    location: location
    keyVaultName: '' // Empty value means Key Vault is not required. After KeyVault is created we re-run this module with KeyVault name.
  }
}

module keyVault './keyVault.bicep' = {
  name: '${keyVaultName}-deploy'
  params: {
    tags: tags
    location: location
    keyVaultName: keyVaultName
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.outputs.oLogAnalyticsWorkspaceName
  }
}

module logAnalyticsWorkspaceKey './logAnalyticsWorkspace.bicep' = {
  name: '${logAnalyticsWorkspaceName}-key-deploy'
  params: {
    name: logAnalyticsWorkspace.outputs.oLogAnalyticsWorkspaceName
    tags: tags
    location: location
    keyVaultName: keyVault.outputs.oKeyVaultName
    logAnalyticsWorkspaceKeyId: logAnalyticsWorkspaceKeyId
  }
}

module keyVaultSecretUserRole './keyVault-rbac.bicep' = {
  name: '${keyVaultName}-rbac-deploy'
  params: {
    currentUserId: currentUserId
    currentUserType: currentUserType
    keyVaultName: keyVault.outputs.oKeyVaultName
  }
}

module acr './containerRegistry.bicep' = {
  name: '${acrName}-deploy'
  params: {
    acrName: acrName
    acrKeyId: acrKeyId
    tags: tags
    location: location
    keyVaultName: keyVault.outputs.oKeyVaultName
  }
}

module containerEnv './containerEnvironment.bicep' = {
  name: '${containerEnvName}-deploy'
  params: {
    containerEnvName: containerEnvName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    virtualNetworkName: virtualNetwork.name
    subnetName: virtualNetwork::subnetKube.name
    tags: tags
    location: location
  }
}

module containerApp './containerApp.bicep' = if (deployCapp) {
  name: '${containerAppName}-deploy'
  params: {
    containerEnvName: containerEnv.outputs.oContainerEnvName
    containerAppName: containerAppName
    tcpPort: containerAppPort
    imageName: containerAppImage
    // fileShare: ''
    acrName: acr.outputs.oAcrName
    acrKeyId: acr.outputs.oAcrKeyId
    ingress: {
      external: true
      targetPort: containerAppPort
      exposedPort: containerAppPort
      transport: 'Tcp'
      ipSecurityRestrictions: []
    }
    env: [
      {
        name: 'VOLUME_PATH'
        value: '/volume'
      }
      {
        name: 'PORT'
        value: '${containerAppPort}'
      }
    ]
    tags: tags
    location: location
  }
}


output oMessage string = 'All fine!'

output oResourceGroupName string = resourceGroup().name
output oVnetName string = virtualNetwork.name
output oSubnetKube string = virtualNetwork::subnetKube.name
output oLogAnalyticsWorkspaceName string = logAnalyticsWorkspace.outputs.oLogAnalyticsWorkspaceName
output oKeyVaultName string = keyVault.outputs.oKeyVaultName
output oAcrName string = acr.outputs.oAcrName
output oAcrLoginServer string = acr.outputs.oAcrLoginServer
output oContainerEnv string = containerEnv.outputs.oContainerEnvName
output oContainerEnvIp string = containerEnv.outputs.oContainerEnvIp
output oContainerEnvFqdn string = containerEnv.outputs.oContainerEnvFqdn
output oDeployCapp bool = deployCapp


