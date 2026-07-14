# Networking Infrastructure (Bicep)

Production-ready, modular Bicep that deploys a private networking layer for an
existing Azure environment: a hub virtual network, a Point-to-Site VPN gateway,
Private Endpoints + Private DNS for every supported service, and least-privilege
Network Security Groups. Existing resources are referenced with the `existing`
keyword and are **never recreated**.

## Project structure

```
infra/
  main.bicep                       # Orchestrator (resourceGroup scope)
  main.parameters.json             # Configurable values
  README.md
  modules/
    nsg.bicep                      # Generic NSG (called 3x)
    vnet.bicep                     # VNet (5 subnets) + VNet DNS server
    vpnGateway.bicep               # Public IP + P2S VPN gateway (OpenVPN/Entra)
    privateDns.bicep               # 8 Private DNS zones + VNet links
    privateEndpoints.bicep         # Generic PE + DNS zone group (reused)
    storageNetworking.bicep        # Storage: blob/file/queue/table PEs + lockdown
    cosmosNetworking.bicep         # Cosmos DB PE + lockdown
    aiNetworking.bicep             # AI Services + AI Foundry PEs + lockdown
    dnsResolver.bicep              # Azure DNS Private Resolver + inbound endpoint
    searchSharedPrivateLink.bicep  # AI Search shared private link (storage/Foundry/multi-service, reused)
```

## What gets deployed

| Area | Resource |
| --- | --- |
| Virtual network | Hub VNet `10.10.0.0/23` |
| Subnets | `GatewaySubnet` `10.10.0.0/26`, `snet-private-endpoints` `10.10.0.64/27`, `snet-compute` `10.10.0.96/27`, `snet-management` `10.10.0.128/27`, `snet-dns-inbound` `10.10.0.160/28` (delegated to the DNS resolver) |
| Reserved | `10.10.0.176/28` – `10.10.1.255` left unallocated for future growth |
| VPN | Zone-redundant Standard Public IP + Route-based VPN gateway (`VpnGw2AZ`), OpenVPN, Microsoft Entra ID auth, client pool `172.16.10.0/24`, split tunneling |
| Private DNS | `cognitiveservices`, `openai`, `services.ai`, `documents`, `blob`, `file`, `queue`, `table` privatelink zones + VNet links |
| DNS resolution | Azure DNS Private Resolver with a static inbound endpoint at **10.10.0.164**; the VNet's DNS server is set to this IP so in-VNet resources resolve private endpoints automatically |
| Private Endpoints | Storage (blob/file/queue/table), Cosmos DB (`Sql`), AI Services (`account`), AI Foundry (`account`) |
| AI Search private links | Shared private links (managed private endpoints) from the search service to: storage `blob` (indexer data source), AI Foundry `openai_account` (chat-completion skills), and the multi-service Cognitive account `cognitiveservices_account` (indexer skills) |
| NSGs | One per data subnet (private-endpoints / compute / management), least-privilege |

## Existing resources (referenced, not created)

| Resource | Type | Action |
| --- | --- | --- |
| Storage account | Storage | 4 private endpoints + public access disabled |
| Cosmos DB account | Cosmos DB | Private endpoint + public access disabled |
| AI Services (multi-service) | AI Services multi-service | Private endpoint + public access disabled + AI Search shared private link (`cognitiveservices_account`) |
| AI Foundry account | AI Foundry (Cognitive Services) | Private endpoint + public access disabled + AI Search shared private link (`openai_account`) |
| AI Search service | AI Search | Shared private links to storage blob, AI Foundry, and the multi-service account (managed private endpoints for indexers/skills) |
| AI Foundry project | AI Foundry Project | **No PE** — sub-resource of the Foundry account |
| Bing Search account | Bing Search | **No PE** — Private Link is not supported for Bing Search |

## AI Search shared private links (managed private endpoints)

The AI Search service reaches private-only dependencies through
**shared private link resources** (`Microsoft.Search/searchServices/sharedPrivateLinkResources`).
Each one provisions a Microsoft-managed private endpoint on the search side and a
corresponding private endpoint connection on the target that must be **approved**.

| Shared private link | Target | Group ID | Purpose |
| --- | --- | --- | --- |
| storage blob link | Storage account | `blob` | Indexer data source (read blobs) |
| AI Foundry link | AI Foundry account | `openai_account` | Chat-completion skills |
| multi-service link | Multi-service account | `cognitiveservices_account` | Indexer cognitive skills |

Approval behaviour:
- **Storage** connections **auto-approve** (same subscription) — no action needed.
- **Cognitive Services** connections (AI Foundry, multi-service) come up
  **Pending** and must be approved once:
  ```bash
  # Find the pending connection name
  az network private-endpoint-connection list \
    --id <cognitiveAccountResourceId> \
    --query "[?properties.privateLinkServiceConnectionState.status=='Pending'].name" -o tsv
  # Approve it
  az network private-endpoint-connection approve \
    --id <cognitiveAccountResourceId>/privateEndpointConnections/<connectionName> \
    --description "Approved for AI Search"
  ```

> The search service must be a billable SKU (Basic or higher) — use
> `standard` or above. Shared private link resources are created serially (AI Search does
> not allow concurrent creation), which the template enforces via `dependsOn`.
> The managed private endpoint object lives in a Microsoft-owned subscription;
> opening it from the portal returns a "wrong issuer" 401 — that is expected.
> Manage/verify from the search service's **Networking → Shared private access**
> blade instead.

## Service limitations (by design)

- **Bing Search** does not support Private Link / private endpoints — no private
  networking is possible; it is intentionally left untouched.
- **AI Foundry Project** is a sub-resource of the Foundry account and has no
  dedicated private endpoint; securing the parent account covers it.
- **AI Foundry Hub** — none exists in the resource group, so none is configured.
  (A hub-based Azure ML workspace would instead use the `amlworkspace` group ID
  with the `privatelink.api.azureml.ms` / `privatelink.notebooks.azure.net` zones.)
- **Routing** uses Azure **system routes**. No User Defined Routes are created.

## Prerequisites

1. Azure CLI (`az`) authenticated to the target subscription:
   ```bash
   az login
   az account set --subscription "<subscription-id>"
   ```
2. Owner/Contributor + Network Contributor on the resource group.
3. The four existing accounts already provisioned in the resource group.
4. For P2S Entra ID auth, an administrator must register/consent the **Azure VPN
   Client** enterprise application in the tenant (one-time). This template uses
   the Microsoft-registered app ID `41b23e61-6c1e-4545-b367-cd054e0ed4b4`
   (`aadAudience`); register it with
   `az ad sp create --id 41b23e61-6c1e-4545-b367-cd054e0ed4b4` or grant admin
   consent via the sign-in URL.

> **Match live configuration before locking down.** Disabling public access on an
> existing service redeploys that resource with a PUT. Verify the shape
> parameters in `main.parameters.json` match the live resources, otherwise the
> deployment may fail or reset configuration:
> - Storage: `storageAccountSku`, `storageAccountKind`, `location`
> - Cosmos: `cosmosKind`, `cosmosPrimaryRegion`, `cosmosConsistencyLevel`, `cosmosCapabilities`
> - AI Services / AI Foundry: `aiServicesKind`/`aiFoundryKind`, `aiServicesSku`/`aiFoundrySku`, and (if set) the custom subdomains
>
> To stage the rollout, deploy first with `disablePublicNetworkAccess=false`
> (creates the private endpoints only), validate DNS resolution over the VPN,
> then redeploy with `disablePublicNetworkAccess=true`.

## Existing-account names (supplied via a local settings file)

The five existing-resource account names are **not** stored in the committed
templates. They are required parameters supplied at deploy time from a local,
git-ignored JSON file that the deploy script reads:

| Settings key | Bicep parameter |
| --- | --- |
| `aiServicesAccountName` | `aiServicesAccountName` |
| `aiFoundryAccountName` | `aiFoundryAccountName` |
| `cosmosAccountName` | `cosmosAccountName` |
| `storageAccountName` | `storageAccountName` |
| `searchServiceName` | `searchServiceName` |

Set them up once by copying the template and editing your values:

```powershell
Copy-Item infra/deploy.local.json.example infra/deploy.local.json
# edit infra/deploy.local.json with your account names
```

`infra/deploy.local.json` is git-ignored (see `.gitignore`); only the
`deploy.local.json.example` template is committed. Example contents:

```json
{
  "aiServicesAccountName": "<your-ai-services-account>",
  "aiFoundryAccountName": "<your-ai-foundry-account>",
  "cosmosAccountName": "<your-cosmos-account>",
  "storageAccountName": "<your-storage-account>",
  "searchServiceName": "<your-search-service>"
}
```

## Deploy

Use the wrapper script — it reads `infra/deploy.local.json` (failing fast if the
file is missing or any value is blank) and passes the names as parameter
overrides on top of `main.parameters.json`:

```powershell
./infra/deploy.ps1 -ResourceGroup <your-resource-group>
```

Point at a different settings file with `-SettingsFile <path>` (e.g. per
environment). Set the region and Cosmos primary region to match your resource
group before deploying (edit `location` and `cosmosPrimaryRegion` in
`main.parameters.json`).

## Validate before deploying

```powershell
# Compile / lint
az bicep build --file infra/main.bicep

# Preview changes — confirm EXISTING accounts show as "Modify", not "Create"
./infra/deploy.ps1 -ResourceGroup <your-resource-group> -WhatIf
```

Re-running with `-WhatIf` after a successful deploy should report **no changes**
(idempotency).

## Changing the VPN gateway SKU

If `VpnGw2AZ` is unavailable in your region, override the SKU:

```bash
az deployment group create -g <rg> \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json vpnGatewaySku=VpnGw2
```

Zone-redundant SKUs end in `AZ` and provision a zone-redundant Public IP;
non-AZ SKUs provision a regional (non-zonal) Public IP automatically.

## Post-deployment — download & configure the VPN client

Private endpoints are only reachable when the client resolves the service names
to their private IPs. Resources **inside** the VNet do this automatically (the
VNet DNS server is the resolver at `10.10.0.164`). **Point-to-Site VPN clients do
not inherit VNet DNS**, so the downloaded Entra profile must be edited to point
at the resolver — otherwise storage/Cosmos/AI names resolve to public IPs and are
blocked (public access is disabled).

1. On the gateway's **Point-to-site configuration** blade, click **Download VPN
   client**, then unzip. The Entra profile is `AzureVPN/azurevpnconfig.xml`.
2. Edit `azurevpnconfig.xml` and add the following `<clientconfig>` block just
   before the closing `</AzVpnProfile>` tag. The `<dnsserver>` is the DNS Private
   Resolver inbound IP (**10.10.0.164**); the suffixes route the private-zone
   lookups to it:

   ```xml
   <clientconfig>
     <dnsservers>
       <DnsServerEntry>
         <dnsserver>10.10.0.164</dnsserver>
       </DnsServerEntry>
     </dnsservers>
     <dnssuffixes>
       <DnsSuffixEntry><dnssuffix>.blob.core.windows.net</dnssuffix></DnsSuffixEntry>
       <DnsSuffixEntry><dnssuffix>.file.core.windows.net</dnssuffix></DnsSuffixEntry>
       <DnsSuffixEntry><dnssuffix>.queue.core.windows.net</dnssuffix></DnsSuffixEntry>
       <DnsSuffixEntry><dnssuffix>.table.core.windows.net</dnssuffix></DnsSuffixEntry>
       <DnsSuffixEntry><dnssuffix>.documents.azure.com</dnssuffix></DnsSuffixEntry>
       <DnsSuffixEntry><dnssuffix>.cognitiveservices.azure.com</dnssuffix></DnsSuffixEntry>
       <DnsSuffixEntry><dnssuffix>.openai.azure.com</dnssuffix></DnsSuffixEntry>
       <DnsSuffixEntry><dnssuffix>.services.ai.azure.com</dnssuffix></DnsSuffixEntry>
     </dnssuffixes>
     <excluderoutes i:nil="true" />
     <includeroutes i:nil="true" />
   </clientconfig>
   ```

3. Import the edited `azurevpnconfig.xml` into the **Azure VPN Client** and
   connect, signing in with a user from the tenant.

> The `<clientconfig>` block is only required for P2S VPN clients. If the DNS
> resolver IP ever changes, update `<dnsserver>` to match the VNet's DNS server
> (`az network vnet show -n <your-vnet-name> -g <rg> --query dhcpOptions.dnsServers`).

### Verify

- After connecting, confirm private resolution:
  ```bash
  nslookup <your-storage-account>.blob.core.windows.net   # resolves to a 10.10.0.64/27 address
  ```
- The VPN gateway can take 30–45 minutes to provision on first deploy; it
  deploys in parallel with the private-link modules.

## Outputs

- `vnetId` — virtual network resource ID
- `vpnGatewayId` — VPN gateway resource ID
- `vpnGatewayPublicIp` — VPN gateway public IP address
- `privateEndpointIds` — object of all private endpoint resource IDs
- `privateDnsZoneIds` — array of all Private DNS zone resource IDs
- `dnsResolverId` — DNS Private Resolver resource ID
- `dnsResolverInboundIp` — DNS Private Resolver inbound IP (use as the VPN client DNS server)
- `searchSharedPrivateLinkResourceId` — AI Search shared private link to storage blob
- `searchFoundrySharedPrivateLinkResourceId` — AI Search shared private link to AI Foundry (`openai_account`)
- `searchMultiServiceSharedPrivateLinkResourceId` — AI Search shared private link to the multi-service account (`cognitiveservices_account`)

## Notes on AVM

Modules are authored to Azure Verified Module / Well-Architected conventions
(parameterised, tagged, secure-by-default, output-complete) using native
`Microsoft.Network/*` resources for full control over the P2S Entra
configuration, DNS zone groups, and predictable idempotency. To adopt AVM
public-registry modules instead, the equivalents are
`br/public:avm/res/network/virtual-network`,
`br/public:avm/res/network/network-security-group`,
`br/public:avm/res/network/private-dns-zone`,
`br/public:avm/res/network/private-endpoint`,
`br/public:avm/res/network/virtual-network-gateway`, and
`br/public:avm/res/network/dns-resolver`.
