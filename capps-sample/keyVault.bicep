param tags object
param location string
@maxLength(24)
param keyVaultName string
@description('Name of Log Workspace')
param logAnalyticsWorkspaceName string


resource keyVault 'Microsoft.KeyVault/vaults@2024-12-01-preview' = {
  name: keyVaultName
  location: location
  properties: {
    accessPolicies: []
    enablePurgeProtection: true
    enableSoftDelete: true
    enabledForTemplateDeployment: true
    enableRbacAuthorization: true
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
  }
  tags: tags
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource service 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceName)) {
  scope: keyVault
  name: 'diag-audit-logs'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
      category: 'AuditEvent'
      enabled: true
      }
    ]
  }
}

output oKeyVaultName string = keyVault.name
