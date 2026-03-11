targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment (e.g. dev)')
param environmentName string

@description('Azure region for all resources. westus3 is required for Foundry model access.')
param location string = 'westus3'

@description('Principal ID of the deploying user or service principal, used for developer role assignments.')
param principalId string = ''

var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module monitoring './modules/monitoring.bicep' = {
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: 'log-${resourceToken}'
    applicationInsightsName: 'appi-${resourceToken}'
  }
}

module acr './modules/acr.bicep' = {
  scope: rg
  params: {
    location: location
    tags: tags
    name: 'cr${resourceToken}'
  }
}

module appService './modules/app-service.bicep' = {
  scope: rg
  params: {
    location: location
    tags: tags
    appServicePlanName: 'asp-${resourceToken}'
    appServiceName: 'app-${resourceToken}'
    acrName: acr.outputs.name
    acrLoginServer: acr.outputs.loginServer
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
  }
}

module aiFoundry './modules/ai-foundry.bicep' = {
  scope: rg
  params: {
    location: location
    tags: tags
    openAiName: 'oai-${resourceToken}'
    aiHubName: 'aih-${resourceToken}'
    aiProjectName: 'aip-${resourceToken}'
    storageAccountName: 'st${resourceToken}'
    keyVaultName: 'kv-${resourceToken}'
    applicationInsightsId: monitoring.outputs.applicationInsightsId
    principalId: principalId
  }
}

// Outputs consumed by AZD and application configuration
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = acr.outputs.name
output SERVICE_WEB_NAME string = appService.outputs.name
output AZURE_APP_SERVICE_URL string = appService.outputs.url
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.applicationInsightsConnectionString
output AZURE_AI_PROJECT_NAME string = aiFoundry.outputs.aiProjectName
output AZURE_AI_HUB_NAME string = aiFoundry.outputs.aiHubName
output AZURE_OPENAI_ENDPOINT string = aiFoundry.outputs.openAiEndpoint
output AZURE_PHI4_ENDPOINT_URL string = aiFoundry.outputs.phi4EndpointUrl
