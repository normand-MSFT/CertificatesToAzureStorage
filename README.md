# Backup your certificates to Azure Storage


## Description
 Whether you provide a SAS Token or opt to have a token generated that expires after a couple of hours, you'll see how easy it to backup your certificates into Azure Storage.


## Scripts

### **Copy-PKIDataToAzureBlob-DynamicSAS.ps1**
#### *Dependencies*: [azcopy.exe](#where-to-download-azcopy), Azure Storage Container, Az PowerShell module, AAD App Registration with *Azure Storage* API permission and storage account owner role


```powershell
# Example with a certificate thumbprint

$parameters = @{

    AzCopyPath = '{path to azcopy.exe}'
    ContainerUrl = '{url to storage container}'
    CertificateFolderPath = '{path to local certificate folder}'
    ResourceGroupName = '{resource group name}'
    TokenDuration = 2
    TenantName = '{tenant name}'
    ApplicationId = '{guid}'
    CredentialType = 'Certificate'
    AppRegistrationCredential = '{certificate thumbprint}'
    Subscription = '{subscription id}'
}

.\Copy-PKIDataToAzureBlob-DynamicSAS.ps1 @parameters
```

```powershell
# Example with a client secret

$parameters = @{

    AzCopyPath = '{path to azcopy.exe}'
    ContainerUrl = '{url to storage container}'
    CertificateFolderPath = '{path to local certificate folder}'
    ResourceGroupName = '{resource group name}'
    TokenDuration = 2
    TenantName = '{tenant name}'
    ApplicationId = '{guid}'
    CredentialType = 'Secret'
    AppRegistrationCredential =  '{client secret}'
    Subscription = '{subscription id}'
}

.\Copy-PKIDataToAzureBlob-DynamicSAS.ps1 @parameters
```

This script will generate a short-lived SAS (Shared Access Signature) token to provide temporary access to the storage container. It supports both a certificate thumbprint and client secret as options. Both can be configured under the app registration section.

For the certificate thumbprint option, you upload the public certificate into app registration section and have the matching private certificate imported into the local certificate store. This is the recommended approach.

### **.\Copy-PKIDataToAzureBlob-StaticSAS.ps1**
#### *Dependencies*: [azcopy.exe](#where-to-download-azcopy), Azure Storage Container, valid SAS token

If you already have an existing SAS token you can use this script to upload the local certificates into the storage container.

```powershell
# Example with a SAS token

$parameters = @{

    AzCopyPath = '{path to azcopy.exe}'
    ContainerUrl = '{url to storage container}'
    CertificateFolderPath = '{path to local certificate folder}'
    SASToken = '{provided SAS token}'
}

.\Copy-PKIDataToAzureBlob-StaticSAS.ps1 @parameters
```

---
## Where to download AzCopy?
[Download the latest copy of AzCopy](https://docs.microsoft.com/azure/storage/common/storage-use-azcopy-v10)

