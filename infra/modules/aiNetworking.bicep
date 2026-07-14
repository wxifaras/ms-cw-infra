// =============================================================================
// Azure AI Services + Azure AI Foundry Networking (existing accounts)
// -----------------------------------------------------------------------------
// Handles the two Cognitive Services accounts:
//   - multiwxdev001 : Azure AI Services multi-service account
//   - aifwxdev001   : Azure AI Foundry (Cognitive Services 'AIServices' account)
//
// For each account this module:
//   - References the EXISTING account via the `existing` keyword.
//   - Creates a Private Endpoint (groupId 'account') wired to the
//     cognitiveservices, openai and services.ai Private DNS zones.
//   - Disables public network access after the private endpoint is created.
//
// SERVICE LIMITATIONS (intentionally NOT deployed):
//   - Bing Search (bingcustwxdev001): Azure Bing Search does NOT support
//     Private Link / private endpoints. No private networking is possible.
//   - Azure AI Foundry Project (projDev001): a project is a sub-resource of the
//     Foundry account and has NO dedicated private endpoint. Securing the parent
//     Foundry account private endpoint covers the project.
//   - Azure AI Foundry Hub: no hub resource exists in the resource group, so
//     none is configured. (A hub-based Azure ML workspace would instead use the
//     amlworkspace group ID with privatelink.api.azureml.ms / notebooks zones.)
//
// IMPORTANT: Disabling public access requires (re)declaration and ARM performs
// a PUT. kind, sku and customSubDomainName MUST match the live accounts.
// =============================================================================

@description('Name of the existing Azure AI Services multi-service account.')
param aiServicesAccountName string

@description('Name of the existing Azure AI Foundry account.')
param aiFoundryAccountName string

@description('Kind of the AI Services account (must match the live account).')
param aiServicesKind string = 'CognitiveServices'

@description('Kind of the AI Foundry account (must match the live account).')
param aiFoundryKind string = 'AIServices'

@description('SKU of the AI Services account (must match the live account).')
param aiServicesSku string = 'S0'

@description('SKU of the AI Foundry account (must match the live account).')
param aiFoundrySku string = 'S0'

@description('Custom subdomain of the AI Services account (must match the live account).')
param aiServicesCustomSubDomain string = ''

@description('Custom subdomain of the AI Foundry account (must match the live account).')
param aiFoundryCustomSubDomain string = ''

@description('Region of the existing accounts (must match the live accounts).')
param location string

@description('Resource tags.')
param tags object = {}

@description('Resource ID of the subnet that hosts the private endpoints.')
param subnetId string

@description('Resource ID of privatelink.cognitiveservices.azure.com.')
param cognitiveServicesZoneId string

@description('Resource ID of privatelink.openai.azure.com.')
param openAiZoneId string

@description('Resource ID of privatelink.services.ai.azure.com.')
param servicesAiZoneId string

@description('Disable public network access after the private endpoints are created.')
param disablePublicNetworkAccess bool = true

resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: aiServicesAccountName
}

resource aiFoundry 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: aiFoundryAccountName
}

// All Cognitive Services private endpoints resolve across the three AI zones.
var aiDnsZoneConfigs = [
  {
    name: 'cognitiveservices'
    zoneId: cognitiveServicesZoneId
  }
  {
    name: 'openai'
    zoneId: openAiZoneId
  }
  {
    name: 'servicesai'
    zoneId: servicesAiZoneId
  }
]

module aiServicesPrivateEndpoint 'privateEndpoints.bicep' = {
  name: 'pe-${aiServicesAccountName}'
  params: {
    name: 'pe-${aiServicesAccountName}'
    location: location
    tags: tags
    subnetId: subnetId
    targetResourceId: aiServices.id
    groupIds: [
      'account'
    ]
    privateDnsZoneConfigs: aiDnsZoneConfigs
  }
}

module aiFoundryPrivateEndpoint 'privateEndpoints.bicep' = {
  name: 'pe-${aiFoundryAccountName}'
  params: {
    name: 'pe-${aiFoundryAccountName}'
    location: location
    tags: tags
    subnetId: subnetId
    targetResourceId: aiFoundry.id
    groupIds: [
      'account'
    ]
    privateDnsZoneConfigs: aiDnsZoneConfigs
  }
}

// Lock down public access only after the private endpoints exist.
resource aiServicesLockdown 'Microsoft.CognitiveServices/accounts@2024-10-01' = if (disablePublicNetworkAccess) {
  name: aiServicesAccountName
  location: location
  kind: aiServicesKind
  sku: {
    name: aiServicesSku
  }
  properties: {
    customSubDomainName: empty(aiServicesCustomSubDomain) ? aiServicesAccountName : aiServicesCustomSubDomain
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
    }
  }
  dependsOn: [
    aiServicesPrivateEndpoint
  ]
}

resource aiFoundryLockdown 'Microsoft.CognitiveServices/accounts@2024-10-01' = if (disablePublicNetworkAccess) {
  name: aiFoundryAccountName
  location: location
  kind: aiFoundryKind
  sku: {
    name: aiFoundrySku
  }
  properties: {
    customSubDomainName: empty(aiFoundryCustomSubDomain) ? aiFoundryAccountName : aiFoundryCustomSubDomain
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
    }
  }
  dependsOn: [
    aiFoundryPrivateEndpoint
  ]
}

@description('Resource ID of the AI Services private endpoint.')
output aiServicesPrivateEndpointId string = aiServicesPrivateEndpoint.outputs.privateEndpointId

@description('Resource ID of the AI Foundry private endpoint.')
output aiFoundryPrivateEndpointId string = aiFoundryPrivateEndpoint.outputs.privateEndpointId
