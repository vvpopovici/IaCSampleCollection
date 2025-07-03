param containerEnvName string
param containerAppName string
param tcpPort int
param imageName string
// param fileShare string = 'volume-data'
param acrName string
param acrKeyId int = 0
param ingress object = {
  external: true    // false=Limited to Cont Environment. true=Limited to VNET.
  targetPort: tcpPort
  exposedPort: tcpPort
  transport: 'Tcp'
  ipSecurityRestrictions: [
    {
      name: 'all-internet'
      ipAddressRange: '0.0.0.0/0'
      action: 'Allow'
    }
  ]
}
param env array = [
  {
    name: 'PORT'
    value: '${tcpPort}'
  }
]
param location string = resourceGroup().location
param tags object = {}


resource acr 'Microsoft.ContainerRegistry/registries@2025-04-01' existing = {
  name: acrName
}

resource containerEnv 'Microsoft.App/managedEnvironments@2025-02-02-preview' existing = {
  name: containerEnvName
}
// resource containerEnvFileShare 'Microsoft.App/managedEnvironments/storages@2022-10-01' existing = {
//   name: fileShare
// }

resource containerApp 'Microsoft.App/containerApps@2025-02-02-preview' = {
  name: containerAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: ingress
      registries: [
        {
          server: acr.properties.loginServer
          username: acr.name
          passwordSecretRef: 'reg-${acr.name}'
        }
      ]
      secrets: [
        {
          name: 'reg-${acr.name}'
          // value: '@Microsoft.KeyVault(SecretUri=https://${keyVault.name}${environment().suffixes.keyvaultDns}/secrets/${acrKeyKeyVaultSecretName}/)'
          value: acr.listCredentials().passwords[acrKeyId].value
        }
      ]
    }
    template: {
      containers: [
        {
          image: imageName
          name: containerAppName
          env: env
          resources: {    // [cpu: 0.25, memory: 0.5Gi]; [cpu: 0.5, memory: 1.0Gi]; [cpu: 0.75, memory: 1.5Gi]; [cpu: 1.0, memory: 2.0Gi]; [cpu: 1.25, memory: 2.5Gi]; [cpu: 1.5, memory: 3.0Gi]; [cpu: 1.75, memory: 3.5Gi]; [cpu: 2.0, memory: 4.0Gi]
            cpu: '0.25'    // Ignore the warning here about expected type of int. The deployment is fine like that.
            memory: '0.5Gi'
          }
          // volumeMounts: [
          //   {
          //     volumeName: containerEnvFileShare.name
          //     mountPath: '/volume'
          //   }
          // ]
          probes: [
            {
              type: 'liveness'
              httpGet: {
                path: '/'
                port: tcpPort
                // httpHeaders: [
                //   {
                //     name: 'Custom-Header'
                //     value: 'liveness probe'
                //   }
                // ]
              }
              initialDelaySeconds: 7
              periodSeconds: 3
            }
            {
              type: 'readiness'
              tcpSocket: {
                port: tcpPort
              }
              initialDelaySeconds: 10
              periodSeconds: 3
            }
            {
              type: 'startup'
              httpGet: {
                path: '/'
                port: tcpPort
                // httpHeaders: [
                //   {
                //     name: 'Custom-Header'
                //     value: 'startup probe'
                //   }
                // ]
              }
              initialDelaySeconds: 3
              periodSeconds: 3
            }
          ]
        }

      ]
      scale: {
        minReplicas: 0
        maxReplicas: 2
        rules: [
          {
            name: 'concurrent2conn'
            tcp: {
              metadata: {
                concurrentConnections: '2'
              }
            }
          }
        ]
      }
      // volumes: [
      //   {
      //     name: containerEnvFileShare.name
      //     storageType: 'AzureFile'
      //     storageName: containerEnvFileShare.name
      //   }
      // ]
    }
  }
  tags: tags
}


output oName string = containerApp.name
output oFqdn string = containerApp.properties.configuration.ingress.fqdn
output oPort int = containerApp.properties.configuration.ingress.exposedPort
