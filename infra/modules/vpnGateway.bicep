// =============================================================================
// Point-to-Site VPN Gateway (Route-based, OpenVPN, Microsoft Entra ID auth)
// -----------------------------------------------------------------------------
// Deploys:
//   - Zone-redundant Standard Public IP
//   - Route-based Virtual Network Gateway (SKU parameterised, default VpnGw2AZ)
//   - Gateway IP configuration bound to the GatewaySubnet
//   - Point-to-Site configuration: OpenVPN protocol + Entra ID (AAD) auth
//
// Split tunneling: This is the DEFAULT P2S behaviour. Only routes to the VNet
// address space (and any explicitly advertised routes) are pushed to clients;
// a default route (0.0.0.0/0) is NOT advertised, so Internet-bound client
// traffic egresses locally. No forced-tunnel/UDR configuration is applied.
// =============================================================================

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Name of the VPN gateway Public IP.')
param publicIpName string

@description('Name of the Virtual Network Gateway.')
param gatewayName string

@description('Resource ID of the GatewaySubnet.')
param gatewaySubnetId string

@description('VPN gateway SKU. Zone-redundant SKUs (VpnGw#AZ) are recommended. Parameterised so it can be changed if VpnGw2AZ is unavailable in the region.')
@allowed([
  'VpnGw1'
  'VpnGw2'
  'VpnGw3'
  'VpnGw1AZ'
  'VpnGw2AZ'
  'VpnGw3AZ'
  'VpnGw4AZ'
  'VpnGw5AZ'
])
param vpnGatewaySku string = 'VpnGw2AZ'

@description('VPN client address pool (must NOT overlap the VNet address space).')
param vpnClientAddressPool string

@description('Entra ID (Azure AD) tenant GUID used for P2S authentication.')
param aadTenantId string

@description('Entra ID audience (application ID) for the Azure VPN Client. Default is the Microsoft-registered Azure VPN Client app.')
param aadAudience string

@description('VPN client tunnel protocols.')
param vpnClientProtocols array = [
  'OpenVPN'
]

// Whether the Public IP should be zone-redundant. AZ gateway SKUs require a
// zone-redundant Standard Public IP; classic SKUs must use no zones.
var isZoneRedundantSku = endsWith(vpnGatewaySku, 'AZ')

// Use environment() so the login endpoint resolves correctly across clouds.
var aadTenantUri = '${environment().authentication.loginEndpoint}${aadTenantId}/'
var aadIssuerUri = 'https://sts.windows.net/${aadTenantId}/'

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  zones: isZoneRedundantSku ? [ '1', '2', '3' ] : null
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = {
  name: gatewayName
  location: location
  tags: tags
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    enableBgp: false
    activeActive: false
    sku: {
      name: vpnGatewaySku
      tier: vpnGatewaySku
    }
    ipConfigurations: [
      {
        name: 'vnetGatewayConfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: gatewaySubnetId
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    // Point-to-Site VPN configuration: OpenVPN + Microsoft Entra ID auth.
    vpnClientConfiguration: {
      vpnClientAddressPool: {
        addressPrefixes: [
          vpnClientAddressPool
        ]
      }
      vpnClientProtocols: vpnClientProtocols
      vpnAuthenticationTypes: [
        'AAD'
      ]
      aadTenant: aadTenantUri
      aadAudience: aadAudience
      aadIssuer: aadIssuerUri
    }
  }
}

@description('Resource ID of the VPN gateway.')
output vpnGatewayId string = vpnGateway.id

@description('Name of the VPN gateway.')
output vpnGatewayName string = vpnGateway.name

@description('Public IP address allocated to the VPN gateway.')
output publicIpAddress string = publicIp.properties.ipAddress

@description('Resource ID of the VPN gateway Public IP.')
output publicIpId string = publicIp.id
