// =============================================================================
// Azure DNS Private Resolver + Inbound Endpoint
// -----------------------------------------------------------------------------
// Provides private DNS resolution for clients that are NOT inside the VNet
// (e.g. Point-to-Site VPN clients). The inbound endpoint receives DNS queries
// and resolves them using the VNet's DNS view, which includes every Private DNS
// zone linked to the VNet — so privatelink.* names resolve to private endpoint
// IPs.
//
// The VNet's dhcpOptions.dnsServers is set to this inbound endpoint's static IP
// (in vnet.bicep); the Azure VPN Gateway then pushes that DNS server to P2S
// clients in the downloaded profile. A STATIC inbound IP is used so the VNet DNS
// value is known up front and there is no dependency cycle.
// =============================================================================

@description('Name of the DNS Private Resolver.')
param dnsResolverName string

@description('Name of the inbound endpoint.')
param inboundEndpointName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Resource ID of the virtual network to attach the resolver to.')
param vnetId string

@description('Resource ID of the delegated inbound endpoint subnet.')
param inboundSubnetId string

@description('Static private IP for the inbound endpoint (must be within the inbound subnet and match the VNet DNS server value).')
param inboundStaticIp string

resource dnsResolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: dnsResolverName
  location: location
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource inboundEndpoint 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  parent: dnsResolver
  name: inboundEndpointName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        subnet: {
          id: inboundSubnetId
        }
        privateIpAllocationMethod: 'Static'
        privateIpAddress: inboundStaticIp
      }
    ]
  }
}

@description('Resource ID of the DNS Private Resolver.')
output dnsResolverId string = dnsResolver.id

@description('Private IP address of the inbound endpoint (use as the DNS server for VPN clients).')
output inboundEndpointIp string = inboundStaticIp
