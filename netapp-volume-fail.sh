#!/bin/bash -x
RG=netapp-cmk-fail-rg
NETAPP_ACCOUNT=netapp-acct-1
NETAPP_POOL=netapp-pool-1
NETAPP_VOLUME=netapp-vol-1
KV_NAME=netapp-kv-1
RND=$(echo $RANDOM | grep -o ..$)
CLOUD=$(az cloud show --query name -o tsv)

if [ $CLOUD == "AzureCloud" ]; then
    LOCATION=eastus 
else
    LOCATION=usgovvirginia
fi

SUBSCRIPTION_ID=$(az account show --query id --output tsv)

if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "No subscription id found"
    exit 1
fi

if [ -z "$LOCATION" ]; then
    echo "No location found"
    exit 1
fi

#create resource group
az group create \
    --location $LOCATION \
    --name $RG 

#create vnet and subnet
az network vnet create \
    --name vnet-1 \
    --resource-group $RG \
    --address-prefix 10.0.0.0/16 \
    --subnet-name subnet-1 \
    --subnet-prefixes 10.0.0.0/24

#create subnet for netapp
az network vnet subnet create \
    --resource-group $RG \
    --vnet-name vnet-1 \
    --name subnet-netapp \
    --address-prefixes 10.0.1.0/27 \
    --delegations Microsoft.Netapp/volumes 

SUBNET_ID=$(az network vnet subnet show --vnet-name vnet-1 -n subnet-netapp -g $RG --query id -o tsv)

az keyvault create \
    --location $LOCATION \
    --name $KV_NAME \
    --resource-group $RG \
    --enable-rbac-authorization false \
    --enable-purge-protection

sleep 10

# create private DNS zone
az network private-dns zone create \
    --resource-group $RG \
    --name privatelink.file.core.windows.net

# link private DNS zone to vnet
az network private-dns link vnet create \
    --resource-group $RG \
    --zone-name privatelink.file.core.windows.net \
    --name link-to-vnet \
    --virtual-network vnet-1 \
    --registration-enabled false

# get the keyvault id
kv_resource_id=$(az keyvault show -n $KV_NAME -g $RG --query id -o tsv)

# create key
az keyvault key create \
    --name netapp-key-$RND \
    --vault-name $KV_NAME \
    --kty RSA \
    --size 2048 \
    --ops {decrypt,encrypt,sign,unwrapKey,wrapKey}

# create private endpoint for keyvault
az network private-endpoint create \
    --name keyvault-endpoint \
    --resource-group $RG \
    --vnet-name vnet-1 \
    --subnet subnet-1 \
    --private-connection-resource-id $kv_resource_id \
    --group-ids vault \
    --connection-name keyvault-connection

PE_ID=$(az network private-endpoint show --name keyvault-endpoint -g $RG --query id -o tsv)

# create managed identity
az identity create --name netapp-mi \
    --resource-group $RG

#wait for the managed identity to be created
sleep 10

#get the principal id of the managed identity
MI=$(az identity show -n netapp-mi -g $RG --query principalId -o tsv)


#create netapp account
az netappfiles account create \
    --resource-group $RG \
    --name $NETAPP_ACCOUNT \
    --location $LOCATION \
    --identity-type UserAssigned \
    --user-assigned-identity netapp-mi

# set the policy for the managed identity 
az keyvault set-policy \
    --name $KV_NAME \
    --resource-group $RG \
    --object-id $MI \
    --key-permissions get encrypt decrypt

# Give time for things to settle in AAD
sleep 15

# get the keyvault uri 
key_vault_uri=$(az keyvault show \
    --name $KV_NAME \
    --resource-group $RG \
    --query properties.vaultUri \
    --output tsv)

az netappfiles account update --name $NETAPP_ACCOUNT \
    --resource-group $RG \
    --identity-type UserAssigned \
    --key-source Microsoft.Keyvault \
    --key-vault-uri $key_vault_uri \
    --key-name netapp-key-$RND \
    --keyvault-resource-id $kv_resource_id \
    --user-assigned-identity netapp-mi

#create netapp pool of size 4TB
az netappfiles pool create \
    --resource-group $RG \
    --account-name $NETAPP_ACCOUNT \
    --name $NETAPP_POOL \
    --service-level "Standard" \
    --size 4

# create netapp volume
az netappfiles volume create \
    --resource-group $RG \
    --account-name $NETAPP_ACCOUNT \
    --pool-name $NETAPP_POOL \
    --name netapp-cmk-vol1 \
    --location $LOCATION \
    --service-level standard \
    --usage-threshold 100 \
    --file-path "volume1" \
    --vnet vnet-1 \
    --subnet-id $SUBNET_ID \
    --network-features Standard \
    --protocol-types NFSv4.1 \
    --kerberos-enabled false \
    --encryption-key-source  Microsoft.KeyVault \
    --key-vault-private-endpoint-resource-id $PE_ID \
    --allowed-clients '0.0.0.0/0'

