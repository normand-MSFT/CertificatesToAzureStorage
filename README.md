# CertificatesToAzureStorage


## Description
This script provides the user two options using AZCopy with which to backup certificates into an Azure Storage Container. It uses AZCopy to perform the heavy lifting whereas the script uses the PowerShell Az module to generate a short-lived SAS (Shared Access Signature) token to provide permissions to upload the local certificates into the storage container. This can easily be set up as a recurring scheduled task. 

## Prerequisites
There are two items that this script needs to run. 
1. Storage Account and container
2. App Registration 

This app registration needs the **Azure Storage** API permission and the owner role against the storage account where your container resides.

* ###### Using a certificate thumbprint
For this to work correctly, you need to upload a public certificate into the app registration section under **Certificates and Secrets**. Additionally the client needs the private certificate imported into the local certificate store otherwise you will get an error. 

**_Certificates are the recommended approach._**

* ###### Using a client secret
Not as secure as a certificate thumbprint but valid nonetheless. You can generate a client secret under the **Certificates and Secrets** section under your app registration.

## Where to download AzCopy?
[Download the latest copy of AzCopy](https://aka.ms/downloadazcopy)

[Getting Started with AzCopy](https://azure.microsoft.com/en-us/documentation/articles/storage-use-azcopy/)

## Usage

```
Get-Help .\Add-CertificateToAzureStorageContainer.ps1
```
