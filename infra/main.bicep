// =============================================================================
// main.bicep — Networking infrastructure for the AI Engineering Assistant
// -----------------------------------------------------------------------------
// Scope: resourceGroup
// Deploys (net-new):
//   - Virtual Network + 4 subnets (Gateway / private-endpoints / compute / mgmt)
//   - 3 Network Security Groups (least-privilege) and subnet associations
//   - Point-to-Site VPN Gateway (Route-based, OpenVPN, Entra ID, split tunnel)
//   - 8 Private DNS zones + VNet links
//   - Private Endpoints + DNS zone groups for every supported existing service
//
// Configures (existing, referenced via `existing` — never recreated):
//   - Storage (stwxdev001): PEs for blob/file/queue/table + public access off
//   - Cosmos DB (cosmoswxdev001): PE + public access off
//   - AI Services (multiwxdev001) + AI Foundry (aifwxdev001): PE + public off
//
// Not deployed (documented limitations):
//   - Bing Search (bingcustwxdev001): no Private Link support.
//   - AI Foundry Project (projDev001): sub-resource, no dedicated PE.
//   - User Defined Routes: none — Azure system routes are used throughout.
//
// Single-command deploy:
//   az deployment group create -g <rg> \
//     --template-file infra/main.bicep \
//     --parameters infra/main.parameters.json
// =============================================================================

targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// General
// -----------------------------------------------------------------------------
@description('Azure region for all net-new networking resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Tags applied to all deployed resources.')
param tags object = {
  workload: 'ai-engineering-assistant'
  environment: 'dev'
  managedBy: 'bicep'
}

@description('Disable public network access on supported existing services after private endpoints are configured.')
param disablePublicNetworkAccess bool = true

// -----------------------------------------------------------------------------
// Virtual Network
// -----------------------------------------------------------------------------
@description('Name of the virtual network.')
param vnetName string = 'vnet-ai-dev'

@description('Address space for the virtual network.')
param vnetAddressPrefixes array = [
  '10.10.0.0/23'
]

@description('CIDR for the GatewaySubnet.')
param gatewaySubnetPrefix string = '10.10.0.0/26'

@description('Name of the private endpoints subnet.')
param privateEndpointsSubnetName string = 'snet-private-endpoints'

@description('CIDR for the private endpoints subnet.')
param privateEndpointsSubnetPrefix string = '10.10.0.64/27'

@description('Name of the compute subnet.')
param computeSubnetName string = 'snet-compute'

@description('CIDR for the compute subnet.')
param computeSubnetPrefix string = '10.10.0.96/27'

@description('Name of the management subnet.')
param managementSubnetName string = 'snet-management'

@description('CIDR for the management subnet.')
param managementSubnetPrefix string = '10.10.0.128/27'

@description('Name of the DNS Private Resolver inbound endpoint subnet.')
param dnsResolverInboundSubnetName string = 'snet-dns-inbound'

@description('CIDR for the DNS Private Resolver inbound endpoint subnet (min /28).')
param dnsResolverInboundSubnetPrefix string = '10.10.0.160/28'

@description('Static private IP for the DNS Private Resolver inbound endpoint. Also set as the VNet DNS server and pushed to P2S VPN clients. Must be inside the inbound subnet (first usable IP is .164 in a /28).')
param dnsResolverInboundIp string = '10.10.0.164'

@description('Name of the DNS Private Resolver.')
param dnsResolverName string = 'dnspr-ai-dev'

@description('Name of the DNS Private Resolver inbound endpoint.')
param dnsResolverInboundEndpointName string = 'inbound'
// Reserved for future expansion: 10.10.0.176/28 - 10.10.1.255 (left unallocated).

// -----------------------------------------------------------------------------
// NSG names
// -----------------------------------------------------------------------------
@description('NSG name for the private endpoints subnet.')
param privateEndpointsNsgName string = 'nsg-snet-private-endpoints'

@description('NSG name for the compute subnet.')
param computeNsgName string = 'nsg-snet-compute'

@description('NSG name for the management subnet.')
param managementNsgName string = 'nsg-snet-management'

// -----------------------------------------------------------------------------
// VPN gateway
// -----------------------------------------------------------------------------
@description('Name of the VPN gateway.')
param vpnGatewayName string = 'vpngw-ai-dev'

@description('Name of the VPN gateway Public IP.')
param vpnPublicIpName string = 'pip-vpngw-ai-dev'

@description('VPN gateway SKU. Change if VpnGw2AZ is unavailable in the region.')
param vpnGatewaySku string = 'VpnGw2AZ'

@description('VPN client address pool (must not overlap the VNet).')
param vpnClientAddressPool string = '172.16.10.0/24'

@description('Entra ID tenant GUID for P2S authentication. Defaults to the deployment subscription tenant.')
param aadTenantId string = subscription().tenantId

@description('Entra audience for the Azure VPN Client. Default is the Microsoft-registered Azure VPN Client application ID.')
param aadAudience string = '41b23e61-6c1e-4545-b367-cd054e0ed4b4'

// -----------------------------------------------------------------------------
// Existing resources (referenced via `existing`; never recreated)
// -----------------------------------------------------------------------------
@description('Existing Azure AI Services multi-service account name.')
param aiServicesAccountName string

@description('Existing Azure AI Foundry account name.')
param aiFoundryAccountName string

@description('Existing Azure Cosmos DB account name.')
param cosmosAccountName string

@description('Existing Azure Storage account name.')
param storageAccountName string

@description('Existing Azure AI Search service name (used for the indexer shared private link to storage).')
param searchServiceName string

@description('Storage sub-resource the AI Search indexer connects to via the shared private link.')
param searchSharedPrivateLinkGroupId string = 'blob'

@description('Shared private link group ID for the AI Search -> AI Foundry connection (chat completion skills).')
param searchFoundryGroupId string = 'openai_account'

@description('Shared private link group ID for the AI Search -> multi-service Cognitive account connection (indexer skills).')
param searchMultiServiceGroupId string = 'cognitiveservices_account'

// bingcustwxdev001 (Bing Search) — no Private Link support; intentionally unused.
// projDev001 (AI Foundry Project) — sub-resource, no dedicated PE; intentionally unused.

// -----------------------------------------------------------------------------
// Existing-resource shape parameters (must match live resources for the
// public-access lockdown PUT to succeed without altering configuration)
// -----------------------------------------------------------------------------
@description('Storage account SKU (must match the live account).')
param storageAccountSku string = 'Standard_LRS'

@description('Storage account kind (must match the live account).')
param storageAccountKind string = 'StorageV2'

@description('Cosmos account kind (must match the live account).')
param cosmosKind string = 'GlobalDocumentDB'

@description('Cosmos primary write region (must match the live account).')
param cosmosPrimaryRegion string = location

@description('Cosmos default consistency level (must match the live account).')
param cosmosConsistencyLevel string = 'Session'

@description('Cosmos capabilities array (must match the live account).')
param cosmosCapabilities array = []

@description('AI Services account kind (must match the live account).')
param aiServicesKind string = 'CognitiveServices'

@description('AI Foundry account kind (must match the live account).')
param aiFoundryKind string = 'AIServices'

@description('AI Services account SKU (must match the live account).')
param aiServicesSku string = 'S0'

@description('AI Foundry account SKU (must match the live account).')
param aiFoundrySku string = 'S0'

@description('AI Services custom subdomain (blank = use account name).')
param aiServicesCustomSubDomain string = ''

@description('AI Foundry custom subdomain (blank = use account name).')
param aiFoundryCustomSubDomain string = ''

// -----------------------------------------------------------------------------
// Private DNS zones (single source of truth)
// -----------------------------------------------------------------------------
var privateDnsZoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.documents.azure.com'
  'privatelink.blob.${environment().suffixes.storage}'
  'privatelink.file.${environment().suffixes.storage}'
  'privatelink.queue.${environment().suffixes.storage}'
  'privatelink.table.${environment().suffixes.storage}'
]

// Concrete zone names used for lookups into the privateDns zoneMap output.
var cognitiveServicesZoneName = 'privatelink.cognitiveservices.azure.com'
var openAiZoneName = 'privatelink.openai.azure.com'
var servicesAiZoneName = 'privatelink.services.ai.azure.com'
var documentsZoneName = 'privatelink.documents.azure.com'
var blobZoneName = 'privatelink.blob.${environment().suffixes.storage}'
var fileZoneName = 'privatelink.file.${environment().suffixes.storage}'
var queueZoneName = 'privatelink.queue.${environment().suffixes.storage}'
var tableZoneName = 'privatelink.table.${environment().suffixes.storage}'

// -----------------------------------------------------------------------------
// Least-privilege NSG rule sets
// -----------------------------------------------------------------------------
// Common hardening: allow intra-VNet, allow VPN client pool where needed, and
// explicitly deny all Internet ingress (belt-and-suspenders over the platform
// default DenyAllInBound). Outbound is left on Azure defaults so workloads can
// reach Azure control/data planes and receive OS updates.

var privateEndpointsNsgRules = [
  {
    name: 'Allow-VpnClients-To-PrivateEndpoints'
    properties: {
      description: 'Allow P2S VPN clients to reach private endpoints (HTTPS + SMB file shares).'
      priority: 200
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourceAddressPrefix: vpnClientAddressPool
      sourcePortRange: '*'
      destinationAddressPrefix: privateEndpointsSubnetPrefix
      destinationPortRanges: [
        '443'
        '445'
      ]
    }
  }
  {
    name: 'Allow-Vnet-Inbound'
    properties: {
      description: 'Allow intra-VNet traffic to private endpoints.'
      priority: 300
      direction: 'Inbound'
      access: 'Allow'
      protocol: '*'
      sourceAddressPrefix: 'VirtualNetwork'
      sourcePortRange: '*'
      destinationAddressPrefix: 'VirtualNetwork'
      destinationPortRange: '*'
    }
  }
  {
    name: 'Deny-Internet-Inbound'
    properties: {
      description: 'Deny all inbound traffic originating from the Internet.'
      priority: 4096
      direction: 'Inbound'
      access: 'Deny'
      protocol: '*'
      sourceAddressPrefix: 'Internet'
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '*'
    }
  }
]

var computeNsgRules = [
  {
    name: 'Allow-VpnClients-Management'
    properties: {
      description: 'Allow P2S VPN clients to manage compute workloads (SSH/RDP/HTTPS).'
      priority: 200
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourceAddressPrefix: vpnClientAddressPool
      sourcePortRange: '*'
      destinationAddressPrefix: computeSubnetPrefix
      destinationPortRanges: [
        '22'
        '3389'
        '443'
      ]
    }
  }
  {
    name: 'Allow-Vnet-Inbound'
    properties: {
      description: 'Allow intra-VNet traffic.'
      priority: 300
      direction: 'Inbound'
      access: 'Allow'
      protocol: '*'
      sourceAddressPrefix: 'VirtualNetwork'
      sourcePortRange: '*'
      destinationAddressPrefix: 'VirtualNetwork'
      destinationPortRange: '*'
    }
  }
  {
    name: 'Deny-Internet-Inbound'
    properties: {
      description: 'Deny all inbound traffic originating from the Internet.'
      priority: 4096
      direction: 'Inbound'
      access: 'Deny'
      protocol: '*'
      sourceAddressPrefix: 'Internet'
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '*'
    }
  }
]

var managementNsgRules = [
  {
    name: 'Allow-VpnClients-Management'
    properties: {
      description: 'Allow P2S VPN clients to reach management/jumpbox hosts (SSH/RDP).'
      priority: 200
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourceAddressPrefix: vpnClientAddressPool
      sourcePortRange: '*'
      destinationAddressPrefix: managementSubnetPrefix
      destinationPortRanges: [
        '22'
        '3389'
      ]
    }
  }
  {
    name: 'Allow-Vnet-Inbound'
    properties: {
      description: 'Allow intra-VNet traffic.'
      priority: 300
      direction: 'Inbound'
      access: 'Allow'
      protocol: '*'
      sourceAddressPrefix: 'VirtualNetwork'
      sourcePortRange: '*'
      destinationAddressPrefix: 'VirtualNetwork'
      destinationPortRange: '*'
    }
  }
  {
    name: 'Deny-Internet-Inbound'
    properties: {
      description: 'Deny all inbound traffic originating from the Internet.'
      priority: 4096
      direction: 'Inbound'
      access: 'Deny'
      protocol: '*'
      sourceAddressPrefix: 'Internet'
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '*'
    }
  }
]

// -----------------------------------------------------------------------------
// Network Security Groups (created before the VNet so subnets can associate)
// -----------------------------------------------------------------------------
module privateEndpointsNsg 'modules/nsg.bicep' = {
  name: 'nsg-private-endpoints'
  params: {
    nsgName: privateEndpointsNsgName
    location: location
    tags: tags
    securityRules: privateEndpointsNsgRules
  }
}

module computeNsg 'modules/nsg.bicep' = {
  name: 'nsg-compute'
  params: {
    nsgName: computeNsgName
    location: location
    tags: tags
    securityRules: computeNsgRules
  }
}

module managementNsg 'modules/nsg.bicep' = {
  name: 'nsg-management'
  params: {
    nsgName: managementNsgName
    location: location
    tags: tags
    securityRules: managementNsgRules
  }
}

// -----------------------------------------------------------------------------
// Virtual Network
// -----------------------------------------------------------------------------
module vnet 'modules/vnet.bicep' = {
  name: 'vnet'
  params: {
    vnetName: vnetName
    location: location
    tags: tags
    addressPrefixes: vnetAddressPrefixes
    gatewaySubnetPrefix: gatewaySubnetPrefix
    privateEndpointsSubnetName: privateEndpointsSubnetName
    privateEndpointsSubnetPrefix: privateEndpointsSubnetPrefix
    computeSubnetName: computeSubnetName
    computeSubnetPrefix: computeSubnetPrefix
    managementSubnetName: managementSubnetName
    managementSubnetPrefix: managementSubnetPrefix
    dnsResolverInboundSubnetName: dnsResolverInboundSubnetName
    dnsResolverInboundSubnetPrefix: dnsResolverInboundSubnetPrefix
    dnsServers: [
      dnsResolverInboundIp
    ]
    privateEndpointsNsgId: privateEndpointsNsg.outputs.nsgId
    computeNsgId: computeNsg.outputs.nsgId
    managementNsgId: managementNsg.outputs.nsgId
  }
}

// -----------------------------------------------------------------------------
// Private DNS zones + VNet links
// -----------------------------------------------------------------------------
module privateDns 'modules/privateDns.bicep' = {
  name: 'private-dns'
  params: {
    vnetId: vnet.outputs.vnetId
    tags: tags
    zoneNames: privateDnsZoneNames
  }
}

// -----------------------------------------------------------------------------
// DNS Private Resolver (gives P2S VPN clients private-endpoint DNS resolution)
// -----------------------------------------------------------------------------
module dnsResolver 'modules/dnsResolver.bicep' = {
  name: 'dns-resolver'
  params: {
    dnsResolverName: dnsResolverName
    inboundEndpointName: dnsResolverInboundEndpointName
    location: location
    tags: tags
    vnetId: vnet.outputs.vnetId
    inboundSubnetId: vnet.outputs.dnsResolverInboundSubnetId
    inboundStaticIp: dnsResolverInboundIp
  }
  dependsOn: [
    privateDns
  ]
}

// -----------------------------------------------------------------------------
// VPN Gateway (long-running; independent of the private-link modules)
// -----------------------------------------------------------------------------
module vpnGateway 'modules/vpnGateway.bicep' = {
  name: 'vpn-gateway'
  params: {
    location: location
    tags: tags
    publicIpName: vpnPublicIpName
    gatewayName: vpnGatewayName
    gatewaySubnetId: vnet.outputs.gatewaySubnetId
    vpnGatewaySku: vpnGatewaySku
    vpnClientAddressPool: vpnClientAddressPool
    aadTenantId: aadTenantId
    aadAudience: aadAudience
  }
}

// -----------------------------------------------------------------------------
// Storage networking (4 private endpoints + public access lockdown)
// -----------------------------------------------------------------------------
module storageNetworking 'modules/storageNetworking.bicep' = {
  name: 'storage-networking'
  params: {
    storageAccountName: storageAccountName
    storageAccountSku: storageAccountSku
    storageAccountKind: storageAccountKind
    location: location
    tags: tags
    subnetId: vnet.outputs.privateEndpointsSubnetId
    blobZoneId: privateDns.outputs.zoneMap[blobZoneName]
    fileZoneId: privateDns.outputs.zoneMap[fileZoneName]
    queueZoneId: privateDns.outputs.zoneMap[queueZoneName]
    tableZoneId: privateDns.outputs.zoneMap[tableZoneName]
    disablePublicNetworkAccess: disablePublicNetworkAccess
  }
}

// -----------------------------------------------------------------------------
// Cosmos DB networking (private endpoint + public access lockdown)
// -----------------------------------------------------------------------------
module cosmosNetworking 'modules/cosmosNetworking.bicep' = {
  name: 'cosmos-networking'
  params: {
    cosmosAccountName: cosmosAccountName
    location: location
    tags: tags
    subnetId: vnet.outputs.privateEndpointsSubnetId
    documentsZoneId: privateDns.outputs.zoneMap[documentsZoneName]
    disablePublicNetworkAccess: disablePublicNetworkAccess
    cosmosKind: cosmosKind
    cosmosPrimaryRegion: cosmosPrimaryRegion
    cosmosConsistencyLevel: cosmosConsistencyLevel
    cosmosCapabilities: cosmosCapabilities
  }
}

// -----------------------------------------------------------------------------
// AI Services + AI Foundry networking (private endpoints + public access lockdown)
// -----------------------------------------------------------------------------
module aiNetworking 'modules/aiNetworking.bicep' = {
  name: 'ai-networking'
  params: {
    aiServicesAccountName: aiServicesAccountName
    aiFoundryAccountName: aiFoundryAccountName
    aiServicesKind: aiServicesKind
    aiFoundryKind: aiFoundryKind
    aiServicesSku: aiServicesSku
    aiFoundrySku: aiFoundrySku
    aiServicesCustomSubDomain: aiServicesCustomSubDomain
    aiFoundryCustomSubDomain: aiFoundryCustomSubDomain
    location: location
    tags: tags
    subnetId: vnet.outputs.privateEndpointsSubnetId
    cognitiveServicesZoneId: privateDns.outputs.zoneMap[cognitiveServicesZoneName]
    openAiZoneId: privateDns.outputs.zoneMap[openAiZoneName]
    servicesAiZoneId: privateDns.outputs.zoneMap[servicesAiZoneName]
    disablePublicNetworkAccess: disablePublicNetworkAccess
  }
}

// -----------------------------------------------------------------------------
// AI Search shared private link to storage (managed private endpoint for indexers)
// Created after the storage networking module so the storage account exists and
// its public access is already locked down before the search connection is made.
// -----------------------------------------------------------------------------
module searchSharedPrivateLink 'modules/searchSharedPrivateLink.bicep' = {
  name: 'search-shared-private-link'
  params: {
    searchServiceName: searchServiceName
    targetResourceId: resourceId('Microsoft.Storage/storageAccounts', storageAccountName)
    groupId: searchSharedPrivateLinkGroupId
  }
  dependsOn: [
    storageNetworking
  ]
}

// -----------------------------------------------------------------------------
// AI Search shared private link to AI Foundry (openai_account) for chat completion
// skills, and to the multi-service Cognitive account (cognitiveservices_account)
// for indexer skills. Created after aiNetworking so the accounts are locked down
// before the search connections are made.
// -----------------------------------------------------------------------------
module searchFoundrySharedPrivateLink 'modules/searchSharedPrivateLink.bicep' = {
  name: 'search-spl-foundry'
  params: {
    searchServiceName: searchServiceName
    targetResourceId: resourceId('Microsoft.CognitiveServices/accounts', aiFoundryAccountName)
    groupId: searchFoundryGroupId
    sharedPrivateLinkResourceName: 'spl-${aiFoundryAccountName}-openai'
    requestMessage: 'AI Search indexer shared private link to AI Foundry (chat completion skills)'
  }
  dependsOn: [
    aiNetworking
  ]
}

module searchMultiServiceSharedPrivateLink 'modules/searchSharedPrivateLink.bicep' = {
  name: 'search-spl-multiservice'
  params: {
    searchServiceName: searchServiceName
    targetResourceId: resourceId('Microsoft.CognitiveServices/accounts', aiServicesAccountName)
    groupId: searchMultiServiceGroupId
    sharedPrivateLinkResourceName: 'spl-${aiServicesAccountName}-cognitiveservices'
    requestMessage: 'AI Search indexer shared private link to multi-service Cognitive account (skills)'
  }
  dependsOn: [
    aiNetworking
    searchFoundrySharedPrivateLink
  ]
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------
@description('Resource ID of the virtual network.')
output vnetId string = vnet.outputs.vnetId

@description('Resource ID of the VPN gateway.')
output vpnGatewayId string = vpnGateway.outputs.vpnGatewayId

@description('Public IP address of the VPN gateway.')
output vpnGatewayPublicIp string = vpnGateway.outputs.publicIpAddress

@description('Resource IDs of every private endpoint created.')
output privateEndpointIds object = {
  storage: storageNetworking.outputs.privateEndpointIds
  cosmos: cosmosNetworking.outputs.privateEndpointId
  aiServices: aiNetworking.outputs.aiServicesPrivateEndpointId
  aiFoundry: aiNetworking.outputs.aiFoundryPrivateEndpointId
}

@description('Resource IDs of every Private DNS zone created.')
output privateDnsZoneIds array = privateDns.outputs.zoneIds

@description('Resource ID of the DNS Private Resolver.')
output dnsResolverId string = dnsResolver.outputs.dnsResolverId

@description('Inbound DNS resolver IP pushed to VPN clients as their DNS server.')
output dnsResolverInboundIp string = dnsResolver.outputs.inboundEndpointIp

@description('Resource ID of the AI Search shared private link to storage.')
output searchSharedPrivateLinkResourceId string = searchSharedPrivateLink.outputs.sharedPrivateLinkResourceId

@description('Resource ID of the AI Search shared private link to AI Foundry (openai_account).')
output searchFoundrySharedPrivateLinkResourceId string = searchFoundrySharedPrivateLink.outputs.sharedPrivateLinkResourceId

@description('Resource ID of the AI Search shared private link to the multi-service Cognitive account (cognitiveservices_account).')
output searchMultiServiceSharedPrivateLinkResourceId string = searchMultiServiceSharedPrivateLink.outputs.sharedPrivateLinkResourceId
