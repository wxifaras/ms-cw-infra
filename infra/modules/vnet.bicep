// =============================================================================
// Virtual Network + Subnets
// -----------------------------------------------------------------------------
// Deploys vnet-ai-dev (10.10.0.0/23) with four subnets. NSGs are created first
// (nsg.bicep) and their IDs are passed in for association. The GatewaySubnet is
// intentionally left WITHOUT an NSG per Microsoft guidance for VPN gateways.
// Remaining address space (10.10.0.160 - 10.10.1.255) is deliberately left
// unallocated and reserved for future expansion.
// =============================================================================

@description('Name of the virtual network.')
param vnetName string

@description('Azure region for the virtual network.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Address space for the virtual network.')
param addressPrefixes array

@description('CIDR for the GatewaySubnet (VPN gateway).')
param gatewaySubnetPrefix string

@description('Name of the private endpoints subnet.')
param privateEndpointsSubnetName string

@description('CIDR for the private endpoints subnet.')
param privateEndpointsSubnetPrefix string

@description('Name of the compute subnet.')
param computeSubnetName string

@description('CIDR for the compute subnet.')
param computeSubnetPrefix string

@description('Name of the management subnet.')
param managementSubnetName string

@description('CIDR for the management subnet.')
param managementSubnetPrefix string

@description('Resource ID of the NSG to associate with the private endpoints subnet.')
param privateEndpointsNsgId string

@description('Resource ID of the NSG to associate with the compute subnet.')
param computeNsgId string

@description('Resource ID of the NSG to associate with the management subnet.')
param managementNsgId string

@description('Name of the DNS Private Resolver inbound endpoint subnet (delegated to Microsoft.Network/dnsResolvers).')
param dnsResolverInboundSubnetName string

@description('CIDR for the DNS Private Resolver inbound endpoint subnet (min /28).')
param dnsResolverInboundSubnetPrefix string

@description('Custom DNS servers for the virtual network. These are also pushed to P2S VPN clients. Empty = Azure-provided DNS.')
param dnsServers array = []

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: addressPrefixes
    }
    // Custom DNS (DNS Private Resolver inbound endpoint) is pushed to P2S VPN
    // clients so they can resolve private endpoints. Null = Azure-provided DNS.
    dhcpOptions: empty(dnsServers) ? null : {
      dnsServers: dnsServers
    }
    subnets: [
      // GatewaySubnet MUST be named exactly 'GatewaySubnet' and carries no NSG.
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: gatewaySubnetPrefix
        }
      }
      // Private endpoints subnet. privateEndpointNetworkPolicies is 'Enabled'
      // so that the associated NSG rules are enforced on private endpoint NICs
      // (required to allow VPN clients and block Internet ingress).
      {
        name: privateEndpointsSubnetName
        properties: {
          addressPrefix: privateEndpointsSubnetPrefix
          networkSecurityGroup: {
            id: privateEndpointsNsgId
          }
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: computeSubnetName
        properties: {
          addressPrefix: computeSubnetPrefix
          networkSecurityGroup: {
            id: computeNsgId
          }
        }
      }
      {
        name: managementSubnetName
        properties: {
          addressPrefix: managementSubnetPrefix
          networkSecurityGroup: {
            id: managementNsgId
          }
        }
      }
      // Dedicated subnet for the DNS Private Resolver inbound endpoint.
      // Must be delegated to Microsoft.Network/dnsResolvers and carry no NSG.
      {
        name: dnsResolverInboundSubnetName
        properties: {
          addressPrefix: dnsResolverInboundSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.Network.dnsResolvers'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
        }
      }
    ]
  }
}

@description('Resource ID of the virtual network.')
output vnetId string = vnet.id

@description('Name of the virtual network.')
output vnetName string = vnet.name

@description('Resource ID of the GatewaySubnet.')
output gatewaySubnetId string = '${vnet.id}/subnets/GatewaySubnet'

@description('Resource ID of the private endpoints subnet.')
output privateEndpointsSubnetId string = '${vnet.id}/subnets/${privateEndpointsSubnetName}'

@description('Resource ID of the compute subnet.')
output computeSubnetId string = '${vnet.id}/subnets/${computeSubnetName}'

@description('Resource ID of the management subnet.')
output managementSubnetId string = '${vnet.id}/subnets/${managementSubnetName}'

@description('Resource ID of the DNS Private Resolver inbound endpoint subnet.')
output dnsResolverInboundSubnetId string = '${vnet.id}/subnets/${dnsResolverInboundSubnetName}'
