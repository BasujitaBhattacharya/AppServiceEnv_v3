targetScope = 'resourceGroup'

// reference to the BICEP naming module
param naming object

@description('Azure region where the resources will be deployed in')
param location string = resourceGroup().location

@description('CIDR of the SPOKE vnet i.e. 192.168.0.0/24')
param vnetSpokeAddressSpace string

@description('CIDR of the subnet that will hold the app services plan')
param subnetSpokeAppSvcAddressSpace string

@description('CIDR of the subnet that will hold devOps agents etc ')
param subnetSpokeDevOpsAddressSpace string

@description('CIDR of the subnet that will hold the private endpoints of the supporting services')
param subnetSpokePrivateEndpointAddressSpace string

@description('Internal IP of the Azure firewall deployed in Hub. Used for creating UDR to route all vnet egress traffic through Firewall. If empty no UDR')
param firewallInternalIp string

@description('if empty, private dns zone will be deployed in the current RG scope')
param vnetHubResourceId string = ''

@description('Resource tags that we might need to add to all resources (i.e. Environment, Cost center, application name etc)')
param tags object

@description('Create (or not) a UDR for the App Service Subnet, to route all egress traffic through Hub Azure Firewall')
param enableEgressLockdown bool

@description('Enable or disable WAF policies for the deployed Azure Front Door')
param enableWaf bool

@description('Deploy (or not) a redis cache')
param deployRedis bool

@description('Deploy (or not) an Azure SQL with default database ')
param deployAzureSql bool

@description('Deploy (or not) an Azure app configuration')
param deployAppConfig bool

@description('Deploy (or not) an Azure virtual machine (to be used as jumphost)')
param deployJumpHost bool

@description('Optional S1 is default. Defines the name, tier, size, family and capacity of the App Service Plan. Plans ending to _AZ, are deplying at least three instances in three Availability Zones. EP* is only for functions')
@allowed([ 'B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1V3', 'P2V3', 'P3V3', 'P1V3_AZ', 'P2V3_AZ', 'P3V3_AZ', 'EP1', 'EP2', 'EP3' ])
param webAppPlanSku string

@description('Kind of server OS of the App Service Plan')
param webAppBaseOs string

@description('optional, default value is azureuser')
param adminUsername string

@description('mandatory, the password of the admin user')
@secure()
param adminPassword string

@description('Conditional. The Azure Active Directory (AAD) administrator authentication. Required if no `administratorLogin` & `administratorLoginPassword` is provided.')
param sqlServerAdministrators object = {}

var resourceNames = {
  storageAccount: naming.storageAccount.nameUnique
  vnetSpoke: '${naming.virtualNetwork.name}-spoke'
  snetAppSvc: 'snet-appSvc-${naming.virtualNetwork.name}-spoke'
  snetDevOps: 'snet-devOps-${naming.virtualNetwork.name}-spoke'
  snetPe: 'snet-pe-${naming.virtualNetwork.name}-spoke'
  appSvcUserAssignedManagedIdentity: '${naming.userAssignedManagedIdentity.name}-appSvc'
  keyvault: naming.keyVault.nameUnique
  logAnalyticsWs: naming.logAnalyticsWorkspace.name
  appInsights: naming.applicationInsights.name
  aspName: naming.appServicePlan.name
  webApp: naming.appService.nameUnique
  vmWindowsJumpbox: '${naming.windowsVirtualMachine.name}-win-jumpbox'
  redisCache: naming.redisCache.nameUnique
  sqlServer: naming.mssqlServer.nameUnique
  sqlDb:'sample-db'
  appConfig: naming.appConfiguration.nameUnique
  frontDoor: naming.frontDoor.name
  frontDoorEndPoint: 'webAppLza-${ take( uniqueString(resourceGroup().id, subscription().id), 6) }'  //globally unique
  frontDoorWaf: naming.frontDoorFirewallPolicy.name
  routeTable: naming.routeTable.name
  routeEgressLockdown: '${naming.route.name}-egress-lockdown'
}

var udrRoutes = [
                  {
                    name: 'defaultEgressLockdown'
                    properties: {
                      addressPrefix: '0.0.0.0/0'
                      nextHopIpAddress: firewallInternalIp 
                      nextHopType: 'VirtualAppliance'
                    }
                  }
                ]

var subnets = [ 
  {
    name: resourceNames.snetAppSvc
    properties: {
      addressPrefix: subnetSpokeAppSvcAddressSpace
      privateEndpointNetworkPolicies: 'Enabled'  
      delegations: [
        {
          name: 'delegation'
          properties: {
            serviceName: 'Microsoft.Web/serverfarms'
          }
        }
      ]
      // networkSecurityGroup: {
      //   id: nsgAca.outputs.nsgID
      // } 
      // routeTable: {
      //   id: !empty(firewallInternalIp) && (enableEgressLockdown) ? routeTableToFirewall.outputs.resourceId : ''
      // } 
      routeTable: !empty(firewallInternalIp) && (enableEgressLockdown) ? {
        id: routeTableToFirewall.outputs.resourceId 
      } : null
    } 
  }
  {
    name: resourceNames.snetDevOps
    properties: {
      addressPrefix: subnetSpokeDevOpsAddressSpace
      privateEndpointNetworkPolicies: 'Enabled'    
    }
  }
  {
    name: resourceNames.snetPe
    properties: {
      addressPrefix: subnetSpokePrivateEndpointAddressSpace
      privateEndpointNetworkPolicies: 'Disabled'    
    }
  }
]

var virtualNetworkLinks = [
  {
    vnetName: vnetSpoke.outputs.vnetName
    vnetId: vnetSpoke.outputs.vnetId
    registrationEnabled: false
  }
  {
    vnetName: vnetHub.name
    vnetId: vnetHub.id
    registrationEnabled: false
  }
]

var vnetHubSplitTokens = !empty(vnetHubResourceId) ? split(vnetHubResourceId, '/') : array('')

resource vnetHub  'Microsoft.Network/virtualNetworks@2022-07-01' existing = {
  scope: resourceGroup(vnetHubSplitTokens[2], vnetHubSplitTokens[4])
  name: vnetHubSplitTokens[8]
}

module vnetSpoke '../../shared/bicep/network/vnet.bicep' = {
  name: 'vnetSpoke-Deployment'
  params: {    
    name: resourceNames.vnetSpoke
    location: location
    tags: tags    
    vnetAddressSpace:  vnetSpokeAddressSpace
    subnetsInfo: subnets
  }
}


module routeTableToFirewall '../../shared/bicep/network/udr.bicep' = if (!empty(firewallInternalIp) &&  (enableEgressLockdown) ) {
  name: 'routeTableToFirewall-Deployment'
  params: {
    name: resourceNames.routeTable
    location: location
    tags: tags
    routes: udrRoutes
  }
}

resource snetAppSvc 'Microsoft.Network/virtualNetworks/subnets@2022-07-01' existing = {
  name: '${vnetSpoke.outputs.vnetName}/${resourceNames.snetAppSvc}'
}

resource snetDevOps 'Microsoft.Network/virtualNetworks/subnets@2022-07-01' existing = {
  name: '${vnetSpoke.outputs.vnetName}/${resourceNames.snetDevOps}'
}

resource snetPe 'Microsoft.Network/virtualNetworks/subnets@2022-07-01' existing = {
  name: '${vnetSpoke.outputs.vnetName}/${resourceNames.snetPe}'
}

module appSvcUserAssignedManagedIdenity '../../shared/bicep/managed-identity.bicep' = {
  name: 'appSvcUserAssignedManagedIdenity-Deployment'
  params: {
    name: resourceNames.appSvcUserAssignedManagedIdentity
    location: location
    tags: tags
  }
}

module logAnalyticsWs '../../shared/bicep/log-analytics-ws.bicep' = {
  name: 'logAnalyticsWs-Deployment'
  params: {
    name: resourceNames.logAnalyticsWs
    location: location
    tags: tags
  }
}

module keyvault 'modules/keyvault.module.bicep' = {
  name: take('${resourceNames.keyvault}-keyvaultModule-Deployment', 64)
  params: {
    name: resourceNames.keyvault
    location: location
    tags: tags   
    vnetHubResourceId: vnetHubResourceId    
    subnetPrivateEndpointId: snetPe.id
    virtualNetworkLinks: virtualNetworkLinks
  }
}

module webApp 'modules/app-service.module.bicep' = {
  name: 'webAppModule-Deployment'
  params: {
    appServicePlanName: resourceNames.aspName
    webAppName: resourceNames.webApp
    location: location
    logAnalyticsWsId: logAnalyticsWs.outputs.logAnalyticsWsId
    subnetIdForVnetInjection: snetAppSvc.id
    tags: tags
    vnetHubResourceId: vnetHubResourceId
    webAppBaseOs: webAppBaseOs
    subnetPrivateEndpointId: snetPe.id
    virtualNetworkLinks: virtualNetworkLinks   
    appConfigurationName: resourceNames.appConfig
    sku: webAppPlanSku
    keyvaultName: keyvault.outputs.keyvaultName
    //docs for envintoment(): > https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-deployment#example-1
    sqlDbConnectionString: (deployAzureSql) ?  'Server=tcp:${sqlServerAndDefaultDb.outputs.sqlServerName}${environment().suffixes.sqlServerHostname};Authentication=Active Directory Default;Database=${resourceNames.sqlDb};' : ''
    redisConnectionStringSecretName: (deployRedis) ? redisCache.outputs.redisConnectionStringSecretName : ''
    deployAppConfig: deployAppConfig 
  }
}

module afd '../../shared/bicep/network/front-door.bicep' = {
  name: take ('AzureFrontDoor-${resourceNames.frontDoor}-deployment', 64)
  params: {
    afdName: resourceNames.frontDoor
    diagnosticWorkspaceId: logAnalyticsWs.outputs.logAnalyticsWsId
    endpointName: resourceNames.frontDoorEndPoint
    originGroupName: resourceNames.frontDoorEndPoint
    origins: [
      {
          name: webApp.outputs.webAppName  //1-50 Alphanumerics and hyphens
          hostname: webApp.outputs.webAppHostName
          enabledState: true
          privateLinkOrigin: {
            privateEndpointResourceId: webApp.outputs.webAppResourceId
            privateLinkResourceType: 'sites'
            privateEndpointLocation: webApp.outputs.webAppLocation
          }
      }
    ]
    skuName:'Premium_AzureFrontDoor'
    wafPolicyName: (enableWaf) ?  resourceNames.frontDoorWaf : ''
  }
}

//TODO: Check with username/password AAD join and DevOps Agent
module vmWindows '../../shared/bicep/compute/jumphost-win11.bicep' = if (deployJumpHost) {
  name: 'vmWindows-Deployment'
  params: {
    name:  resourceNames.vmWindowsJumpbox 
    location: location
    tags: tags
    adminPassword: adminPassword
    adminUsername: adminUsername
    subnetId: snetDevOps.id
    enableAzureAdJoin: true
  }
}

// TODO: We need feature flag to deploy or not Redis - should not be default
module redisCache 'modules/redis.module.bicep' = if (deployRedis) {
  name: take('${resourceNames.redisCache}-redisModule-Deployment', 64)
  params: {
    name: resourceNames.redisCache
    location: location
    tags: tags
    logAnalyticsWsId: logAnalyticsWs.outputs.logAnalyticsWsId  
    vnetHubResourceId: vnetHubResourceId
    subnetPrivateEndpointId: snetPe.id
    virtualNetworkLinks: virtualNetworkLinks
    keyvaultName: keyvault.outputs.keyvaultName
  }
}

//TODO: conditional deployment of SQL
module sqlServerAndDefaultDb 'modules/sql-database.module.bicep' = if (deployAzureSql) {
  name: take('${resourceNames.sqlServer}-sqlServer-Deployment', 64)
  params: {
    name: resourceNames.sqlServer
    databaseName: resourceNames.sqlDb
    location: location
    tags: tags 
    vnetHubResourceId: vnetHubResourceId
    subnetPrivateEndpointId: snetPe.id
    virtualNetworkLinks: virtualNetworkLinks
    administrators: sqlServerAdministrators
  }
}


output vnetSpokeName string = vnetSpoke.outputs.vnetName
output vnetSpokeId string = vnetSpoke.outputs.vnetId
//output sampleAppIngress string = webApp.outputs.fqdn
