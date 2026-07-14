// =============================================================================
// Network Security Group (generic, reusable)
// -----------------------------------------------------------------------------
// Creates a single NSG from a caller-supplied set of security rules. Invoked
// once per subnet (private-endpoints / compute / management) from main.bicep.
// Follows AVM/WAF conventions: parameterised, tagged, secure-by-default,
// idempotent (name-stable), and exposes outputs for downstream association.
// =============================================================================

@description('Name of the network security group.')
param nsgName string

@description('Azure region for the NSG.')
param location string

@description('Resource tags applied to the NSG.')
param tags object = {}

@description('Array of securityRules objects (Microsoft.Network/networkSecurityGroups/securityRules shape).')
param securityRules array = []

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: securityRules
  }
}

@description('Resource ID of the created NSG.')
output nsgId string = nsg.id

@description('Name of the created NSG.')
output nsgName string = nsg.name
