param location string
param tags object
param openAiName string
param aiHubName string
param aiProjectName string
param storageAccountName string
param keyVaultName string
param applicationInsightsId string
param principalId string = ''

// GPT-4.1 deployment config — model name: gpt-4.1, version: 2025-04-14 (GA, per Azure docs)
param gpt4ModelName string = 'gpt-4.1'
param gpt4ModelVersion string = '2025-04-14'
param gpt4DeploymentCapacity int = 10 // 10K TPM

// Role definition IDs
var cognitiveServicesOpenAiContributorRoleId = 'a001fd3d-188f-4b5d-821b-7da978bf7442'
var cognitiveServicesOpenAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
var keyVaultAdministratorRoleId = '00482a5a-887f-4fb3-b363-3b7fe8e74483'
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// Storage Account — required by AI Hub
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

// Key Vault — required by AI Hub, RBAC-authorised (no access policies)
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

// Azure OpenAI account — hosts GPT-4.1 deployment; Phi is accessed via AI Project serverless endpoint
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: openAiName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: openAiName
    publicNetworkAccess: 'Enabled'
  }
}

// GPT-4 model deployment
resource gpt4Deployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: openAiAccount
  name: 'gpt-4.1'
  sku: {
    // GlobalStandard routes traffic globally — required for gpt-4.1 in westus3
    name: 'GlobalStandard'
    capacity: gpt4DeploymentCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: gpt4ModelName
      version: gpt4ModelVersion
    }
  }
}

// AI Hub — organises AI resources and provides a shared environment for projects
resource aiHub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: aiHubName
  location: location
  tags: tags
  kind: 'Hub'
  identity: { type: 'SystemAssigned' }
  sku: { name: 'Basic', tier: 'Basic' }
  properties: {
    friendlyName: aiHubName
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: applicationInsightsId
  }
}

// AI Project — scoped workspace under the hub for ZavaStorefront AI features
resource aiProject 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: aiProjectName
  location: location
  tags: tags
  kind: 'Project'
  identity: { type: 'SystemAssigned' }
  sku: { name: 'Basic', tier: 'Basic' }
  properties: {
    friendlyName: aiProjectName
    hubResourceId: aiHub.id
  }
}

// Connect AI Hub to the OpenAI account using an API key
resource openAiConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-04-01' = {
  parent: aiHub
  name: 'openai-connection'
  properties: {
    category: 'AzureOpenAI'
    target: openAiAccount.properties.endpoint
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: openAiAccount.listKeys().key1
    }
    metadata: {
      ApiType: 'Azure'
      ApiVersion: '2024-05-01-preview'
      ResourceId: openAiAccount.id
    }
  }
}

// AI Hub system identity — needs to read/write Key Vault secrets
resource hubKeyVaultAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, aiHub.id, keyVaultAdministratorRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultAdministratorRoleId)
    principalId: aiHub.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'AI Hub Key Vault Administrator'
  }
}

// AI Hub system identity — needs storage blob access for dataset/model artefacts
resource hubStorageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, aiHub.id, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: aiHub.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'AI Hub Storage Blob Data Contributor'
  }
}

// AI Hub system identity — Cognitive Services OpenAI Contributor on the OpenAI account
resource hubOpenAiContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiAccount.id, aiHub.id, cognitiveServicesOpenAiContributorRoleId)
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAiContributorRoleId)
    principalId: aiHub.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'AI Hub OpenAI Contributor'
  }
}

// Developer role assignment: allows the deploying principal to call OpenAI APIs directly
resource developerOpenAiUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(openAiAccount.id, principalId, cognitiveServicesOpenAiUserRoleId)
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAiUserRoleId)
    principalId: principalId
    principalType: 'User'
    description: 'Developer OpenAI User'
  }
}

// Phi-4 serverless endpoint — available in westus3 via AI Project model catalog
// Uses Consumption (pay-per-token) billing; no reserved capacity needed
resource phi4Endpoint 'Microsoft.MachineLearningServices/workspaces/serverlessEndpoints@2024-04-01' = {
  parent: aiProject
  name: 'phi-4'
  location: location
  tags: tags
  sku: { name: 'Consumption' }
  properties: {
    authMode: 'Key'
    modelSettings: {
      modelId: 'azureml://registries/azureml/models/Phi-4/versions/1'
    }
  }
}

output aiHubName string = aiHub.name
output aiProjectName string = aiProject.name
output openAiEndpoint string = openAiAccount.properties.endpoint
output openAiAccountId string = openAiAccount.id
output phi4EndpointUrl string = phi4Endpoint.properties.inferenceEndpoint.uri
