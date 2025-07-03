@description('Key Vault name')
param keyVaultName string
@description('App Service User Id(Object Id)')
param currentUserId string
@description('App Service User type')
@allowed([
  'ServicePrincipal'
  'User'
])
param currentUserType string

resource keyVault 'Microsoft.KeyVault/vaults@2024-12-01-preview' existing = {
  name: keyVaultName
}

@description('This is the built-in "Key Vault Secrets User" role. See https://docs.microsoft.com/azure/role-based-access-control/built-in-roles#key-vault-secrets-user')
resource keyVaultSecretUserRole 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' existing = {
  scope: subscription()
  name: '4633458b-17de-408a-b874-0445c86b69e6'
}

@description('Grant the app service identity with "Key Vault Secrets User" role permissions over the key vault. This allows reading secret contents.')
resource keyVaultSecretUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(resourceGroup().id, currentUserId, keyVaultSecretUserRole.id)
  properties: {
    roleDefinitionId: keyVaultSecretUserRole.id
    principalId:    currentUserId
    principalType:  currentUserType
  }
}

