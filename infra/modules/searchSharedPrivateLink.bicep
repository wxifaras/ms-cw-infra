// =============================================================================
// Azure AI Search — Shared Private Link Resource (managed private endpoint)
// -----------------------------------------------------------------------------
// Lets the EXISTING Azure AI Search service reach the storage account privately
// so indexers can read their data source over Private Link (required because the
// storage account has public network access disabled).
//
// This creates a search-managed private endpoint. After deployment the matching
// private endpoint connection on the storage account is in the "Pending" state
// and MUST be approved before the indexer can connect, e.g.:
//
//   az network private-endpoint-connection approve \
//     --resource-group <rg> --name <connName> \
//     --resource-name <storageAccountName> --type Microsoft.Storage/storageAccounts
//
// The search service must be a billable SKU (Basic or higher) — shared private
// link resources are not supported on the Free tier.
// =============================================================================

@description('Name of the existing Azure AI Search service.')
param searchServiceName string

@description('Resource ID of the target resource to connect privately (storage account, Cognitive Services account, etc.).')
param targetResourceId string

@description('Shared private link group ID (sub-resource). Storage: blob/table/queue/file/dfs. Azure OpenAI / AI Foundry: openai_account. Cognitive Services multi-service: cognitiveservices_account.')
@allowed([
  'blob'
  'table'
  'queue'
  'file'
  'dfs'
  'Sql'
  'vault'
  'sites'
  'openai_account'
  'cognitiveservices_account'
  'amlworkspace'
])
param groupId string = 'blob'

@description('Name of the shared private link resource.')
param sharedPrivateLinkResourceName string = 'spl-${searchServiceName}-${groupId}'

@description('Message shown on the target private endpoint connection request.')
param requestMessage string = 'Azure AI Search indexer shared private link (${groupId})'

resource search 'Microsoft.Search/searchServices@2023-11-01' existing = {
  name: searchServiceName
}

resource sharedPrivateLink 'Microsoft.Search/searchServices/sharedPrivateLinkResources@2023-11-01' = {
  parent: search
  name: sharedPrivateLinkResourceName
  properties: {
    privateLinkResourceId: targetResourceId
    groupId: groupId
    requestMessage: requestMessage
  }
}

@description('Resource ID of the shared private link resource.')
output sharedPrivateLinkResourceId string = sharedPrivateLink.id

@description('Name of the shared private link resource.')
output sharedPrivateLinkResourceName string = sharedPrivateLink.name
