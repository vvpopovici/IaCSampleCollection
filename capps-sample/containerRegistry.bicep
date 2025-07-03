@description('Name of Key Vault where to store acr key')
param keyVaultName string
@minLength(5)
@maxLength(50)
@description('Provide a globally unique name of your Azure Container Registry')
param acrName string
@description('ACR has 2 access keys: password (0) and password2 (1). Which to be stored in KeyVault for future use? 0 or 1? Switch the values when doing secrets rotation.')
@allowed([
  0
  1
])
param acrKeyId int
@description('Common config for all resources i.e. tags, location etc')
param tags object
param location string

resource acr 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'    // 'Basic', 'Standard', 'Premium'
  }
  properties: {
    adminUserEnabled: true
  }
  tags: tags
}

module addKey './keyVault-secret.bicep' = {
  name: '${acr.name}-key'
  params: {
    keyVaultName: keyVaultName
    secretName: '${acr.name}-key'
    secretValue: acr.listCredentials().passwords[acrKeyId].value
  }
}

output oAcrName string = acr.name
output oAcrLoginServer string = acr.properties.loginServer
output oAcrKeyId int = acrKeyId
output oAcrKeyName string = addKey.name
