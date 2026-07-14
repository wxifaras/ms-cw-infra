// =============================================================================
// Private Endpoint + Private DNS Zone Group (generic, reusable)
// -----------------------------------------------------------------------------
// Creates a single private endpoint against a target resource and wires its
// DNS zone group so records are auto-registered in the supplied Private DNS
// zone(s). Reused by the storage / cosmos / ai networking modules.
// =============================================================================

@description('Name of the private endpoint.')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Resource ID of the subnet hosting the private endpoint.')
param subnetId string

@description('Resource ID of the target resource to connect privately.')
param targetResourceId string

@description('Group IDs (sub-resources) for the private link connection, e.g. [ blob ], [ Sql ], [ account ].')
param groupIds array

@description('Private DNS zone configs: array of objects { name: string, zoneId: string }.')
param privateDnsZoneConfigs array

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    customNetworkInterfaceName: '${name}-nic'
    privateLinkServiceConnections: [
      {
        name: '${name}-conn'
        properties: {
          privateLinkServiceId: targetResourceId
          groupIds: groupIds
        }
      }
    ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for cfg in privateDnsZoneConfigs: {
      name: cfg.name
      properties: {
        privateDnsZoneId: cfg.zoneId
      }
    }]
  }
}

@description('Resource ID of the private endpoint.')
output privateEndpointId string = privateEndpoint.id

@description('Name of the private endpoint.')
output privateEndpointName string = privateEndpoint.name
