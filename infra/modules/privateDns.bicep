// =============================================================================
// Private DNS Zones + Virtual Network Links
// -----------------------------------------------------------------------------
// Deploys every Private DNS zone required for the Private Link endpoints and
// links each one to the virtual network (auto-registration disabled). The zone
// set is passed in from main.bicep so it stays the single source of truth.
// =============================================================================

@description('Resource ID of the virtual network to link the zones to.')
param vnetId string

@description('Resource tags.')
param tags object = {}

@description('List of Private DNS zone names to create and link.')
param zoneNames array

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in zoneNames: {
  name: zoneName
  location: 'global'
  tags: tags
}]

resource vnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, i) in zoneNames: {
  parent: zones[i]
  name: 'link-${uniqueString(vnetId, zoneName)}'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}]

@description('Array of created Private DNS zone resource IDs.')
output zoneIds array = [for (zoneName, i) in zoneNames: zones[i].id]

@description('Map of zone name -> resource ID for lookup by consumers.')
output zoneMap object = toObject(zoneNames, name => name, name => resourceId('Microsoft.Network/privateDnsZones', name))
