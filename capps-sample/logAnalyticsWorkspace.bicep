param name string
param tags object
param location string
param dailyQuotaGb int = 1
param retentionInDays int = 30
param keyVaultName string = ''    // Empty means that the key will not be stored in KeyVault
param logAnalyticsWorkspaceKeyId int = 0    // Key id to be stored in KeyVault

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }

    retentionInDays: retentionInDays
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
  }
}

module addKey 'keyVault-secret.bicep' = if(!empty(keyVaultName)) {
  name: '${substring(logAnalyticsWorkspace.name, 0, 59)}-key'
  params: {
    keyVaultName: keyVaultName
    secretName: '${logAnalyticsWorkspace.name}-key'
    secretValue: logAnalyticsWorkspaceKeyId == 0 ? logAnalyticsWorkspace.listKeys().primarySharedKey : logAnalyticsWorkspace.listKeys().secondarySharedKey
  }
}


output oLogAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output oLogAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output oLogAnalyticsWorkspaceCustomerId string = logAnalyticsWorkspace.properties.customerId
