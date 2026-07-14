// =============================================================================
// Cosmos DB Networking (existing account: not recreated)
// -----------------------------------------------------------------------------
// - References the EXISTING Cosmos DB account via the `existing` keyword.
// - Creates a Private Endpoint (groupId 'Sql') wired to
//   privatelink.documents.azure.com.
// - Disables public network access after the private endpoint is created.
//
// IMPORTANT: Disabling public access on an existing Cosmos account requires a
// (re)declaration and ARM performs a PUT. The following account-defining
// properties MUST match the live account or the deployment will fail / reset
// configuration: kind, databaseAccountOfferType, locations, consistencyPolicy
// and capabilities. They are surfaced as parameters — supply the real values.
// =============================================================================

@description('Name of the existing Cosmos DB account.')
param cosmosAccountName string

@description('Region of the existing Cosmos DB account (must match the live account).')
param location string

@description('Resource tags.')
param tags object = {}

@description('Resource ID of the subnet that hosts the private endpoint.')
param subnetId string

@description('Resource ID of privatelink.documents.azure.com.')
param documentsZoneId string

@description('Disable public network access after the private endpoint is created.')
param disablePublicNetworkAccess bool = true

@description('Cosmos account kind (must match the live account).')
param cosmosKind string = 'GlobalDocumentDB'

@description('Primary write region of the existing account (must match the live account).')
param cosmosPrimaryRegion string

@description('Database account offer type (must match the live account).')
param cosmosDatabaseAccountOfferType string = 'Standard'

@description('Default consistency level (must match the live account).')
@allowed([
  'Eventual'
  'ConsistentPrefix'
  'Session'
  'BoundedStaleness'
  'Strong'
])
param cosmosConsistencyLevel string = 'Session'

@description('Capabilities of the existing account, e.g. [ { name: EnableServerless } ] (must match the live account).')
param cosmosCapabilities array = []

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosAccountName
}

module cosmosPrivateEndpoint 'privateEndpoints.bicep' = {
  name: 'pe-${cosmosAccountName}-sql'
  params: {
    name: 'pe-${cosmosAccountName}-sql'
    location: location
    tags: tags
    subnetId: subnetId
    targetResourceId: cosmos.id
    groupIds: [
      'Sql'
    ]
    privateDnsZoneConfigs: [
      {
        name: 'documents'
        zoneId: documentsZoneId
      }
    ]
  }
}

// Lock down public access only after the private endpoint exists.
// NOTE: The account region (cosmosPrimaryRegion) may differ from the private
// endpoint region (location). The private endpoint is regional and lives in the
// VNet subnet; cross-region private endpoints to Cosmos are supported.
resource cosmosLockdown 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = if (disablePublicNetworkAccess) {
  name: cosmosAccountName
  location: cosmosPrimaryRegion
  kind: cosmosKind
  properties: {
    databaseAccountOfferType: cosmosDatabaseAccountOfferType
    consistencyPolicy: {
      defaultConsistencyLevel: cosmosConsistencyLevel
    }
    locations: [
      {
        locationName: cosmosPrimaryRegion
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: cosmosCapabilities
    publicNetworkAccess: 'Disabled'
    isVirtualNetworkFilterEnabled: true
    networkAclBypass: 'AzureServices'
  }
  dependsOn: [
    cosmosPrivateEndpoint
  ]
}

@description('Resource ID of the Cosmos DB private endpoint.')
output privateEndpointId string = cosmosPrivateEndpoint.outputs.privateEndpointId
