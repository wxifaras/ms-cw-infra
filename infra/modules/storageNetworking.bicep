// =============================================================================
// Storage Account Networking (existing account: not recreated)
// -----------------------------------------------------------------------------
// - References the EXISTING storage account via the `existing` keyword.
// - Creates Private Endpoints for blob, file, queue and table sub-resources,
//   each wired to its Private DNS zone.
// - Disables public network access and denies all default network traffic
//   AFTER the private endpoints are in place (dependency-ordered).
//
// NOTE ON IDEMPOTENT UPDATE: To toggle public access on a pre-existing account
// the account must be (re)declared. ARM performs a PUT, so the immutable and
// key properties below (sku, kind, region) MUST match the live account. They
// are surfaced as parameters; supply the real values in the parameter file.
// =============================================================================

@description('Name of the existing storage account.')
param storageAccountName string

@description('SKU of the existing storage account (must match the live account).')
param storageAccountSku string = 'Standard_LRS'

@description('Kind of the existing storage account (must match the live account).')
param storageAccountKind string = 'StorageV2'

@description('Region of the existing storage account (must match the live account).')
param location string

@description('Resource tags.')
param tags object = {}

@description('Resource ID of the subnet that hosts the private endpoints.')
param subnetId string

@description('Resource ID of privatelink.blob.core.windows.net.')
param blobZoneId string

@description('Resource ID of privatelink.file.core.windows.net.')
param fileZoneId string

@description('Resource ID of privatelink.queue.core.windows.net.')
param queueZoneId string

@description('Resource ID of privatelink.table.core.windows.net.')
param tableZoneId string

@description('Disable public network access after private endpoints are created.')
param disablePublicNetworkAccess bool = true

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

var storagePeDefs = [
  {
    suffix: 'blob'
    groupId: 'blob'
    zoneId: blobZoneId
  }
  {
    suffix: 'file'
    groupId: 'file'
    zoneId: fileZoneId
  }
  {
    suffix: 'queue'
    groupId: 'queue'
    zoneId: queueZoneId
  }
  {
    suffix: 'table'
    groupId: 'table'
    zoneId: tableZoneId
  }
]

module storagePrivateEndpoints 'privateEndpoints.bicep' = [for def in storagePeDefs: {
  name: 'pe-${storageAccountName}-${def.suffix}'
  params: {
    name: 'pe-${storageAccountName}-${def.suffix}'
    location: location
    tags: tags
    subnetId: subnetId
    targetResourceId: storage.id
    groupIds: [
      def.groupId
    ]
    privateDnsZoneConfigs: [
      {
        name: def.suffix
        zoneId: def.zoneId
      }
    ]
  }
}]

// Lock down public access only after all private endpoints exist.
resource storageLockdown 'Microsoft.Storage/storageAccounts@2023-05-01' = if (disablePublicNetworkAccess) {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountSku
  }
  kind: storageAccountKind
  properties: {
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
  }
  dependsOn: [
    storagePrivateEndpoints
  ]
}

@description('Resource IDs of the storage private endpoints.')
output privateEndpointIds array = [for (def, i) in storagePeDefs: storagePrivateEndpoints[i].outputs.privateEndpointId]
