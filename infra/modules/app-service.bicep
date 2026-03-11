param location string
param tags object
param appServicePlanName string
param appServiceName string
param acrName string
param acrLoginServer string
param applicationInsightsConnectionString string

// AcrPull built-in role definition ID
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'B2'
    tier: 'Basic'
  }
  kind: 'linux'
  properties: {
    reserved: true // Required for Linux plans
  }
}

resource appService 'Microsoft.Web/sites@2023-01-01' = {
  name: appServiceName
  location: location
  tags: union(tags, { 'azd-service-name': 'web' })
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      // App Service pulls from ACR via managed identity — no credentials needed
      acrUseManagedIdentityCreds: true
      linuxFxVersion: 'DOCKER|${acrLoginServer}/web:latest'
      alwaysOn: false
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://${acrLoginServer}'
        }
        {
          name: 'WEBSITES_PORT'
          value: '80'
        }
      ]
    }
  }
}

// Reference the ACR to scope the role assignment correctly
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// Grant AcrPull to the App Service system-assigned managed identity
resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, appService.id, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: appService.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output id string = appService.id
output name string = appService.name
output url string = 'https://${appService.properties.defaultHostName}'
