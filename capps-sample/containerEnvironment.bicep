param containerEnvName string
param tags object
param location string
param virtualNetworkName string
param subnetName string
param logAnalyticsWorkspaceName string
param logAnalyticsWorkspaceKeyId int = 0

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: virtualNetworkName
  resource subnet 'subnets' existing = {
    name: subnetName
  }
}

resource containerEnv 'Microsoft.App/managedEnvironments@2025-02-02-preview' = {
  name: containerEnvName
  location: location
  properties: {
    vnetConfiguration: {
      internal: false
      infrastructureSubnetId: virtualNetwork::subnet.id
    }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspaceKeyId == 0 ? logAnalyticsWorkspace.listKeys().primarySharedKey : logAnalyticsWorkspace.listKeys().secondarySharedKey
      }
    }
    zoneRedundant: false
  }
  tags: tags
}


output oContainerEnvName string = containerEnv.name
output oContainerEnvIp string = containerEnv.properties.staticIp
output oContainerEnvFqdn string = containerEnv.properties.defaultDomain

