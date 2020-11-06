<#
This Sample Code is provided for the purpose of illustration only and is not intended
to be used in a production environment.  THIS SAMPLE CODE AND ANY RELATED INFORMATION
ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS
FOR A PARTICULAR PURPOSE.  We grant You a nonexclusive, royalty-free right to use and
modify the Sample Code and to reproduce and distribute the object code form of the
Sample Code, provided that You agree: (i) to not use Our name, logo, or trademarks to
market Your software product in which the Sample Code is embedded; (ii) to include a
valid copyright notice on Your software product in which the Sample Code is embedded;
and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and
against any claims or lawsuits, including attorneys' fees, that arise or result from
the use or distribution of the Sample Code.
#>

#Requires -Modules Az.Accounts, Az.Storage

<#
.SYNOPSIS
    Script demonstrating certificate synchronization of on-premise folder with an azure storage container.
.DESCRIPTION
    This script, while can be used to sync anything files with an azure storage container, is designed to demonstrate
    how we can sync certificates in a local directory with an azure storage container. This allows us to use the
    container as a backup.
.EXAMPLE
    PS C:\Scripts> .\Copy-PKIDataToAzureBlob-DynamicSAS.ps1 `
     -AzCopyPath c:\azcopy.exe
     -ContainerUrl http://mystorageaccount.blob.core.windows.net/mystoragecontainer `
     -CertificateFolderPath c:\mycertificates
     -ResourceGroupName adcsrg `
     -TokenDurationInHours 3 `
     -TenantName contoso.onmicrosoft.com `
     -ApplicationId '12345' `
     -CredentialType Secret `
     -AppRegistrationCredential '12345'

    This example parses the ContainerUrl to retrieve the storage account name and storage container name. It
    uses the Connect-AzAccount cmdlet to authenticate using an ClientId and application secret. For this to work
    the user needs to create an app registration in Azure Active Directory and provide it an appropriate access role
    for the storage account.

    Using the above storage account name, resource group name, and storage container it generates a SaS token with a
    3 hour duration.

.EXAMPLE
    PS C:\Scripts> .\Copy-PKIDataToAzureBlob-DynamicSAS.ps1 `
     -AzCopyPath c:\azcopy.exe
     -ContainerUrl http://mystorageaccount.blob.core.windows.net/mystoragecontainer `
     -CertificateFolderPath c:\mycertificates
     -ResourceGroupName adcsrg `
     -TokenDurationInHours 3 `
     -TenantName contoso.onmicrosoft.com `
     -ApplicationId '12345' `
     -CredentialType Certificate
     -AppRegistrationCredential '12345'

    This example parses the ContainerUrl to retrieve the storage account name and storage container name. It
    uses the Connect-AzAccount cmdlet to authenticate using an application id and certificate thumbprint. For this to work a few things need
    to happen:

    1. A public certificate with public key uploaded into app registration area of the Azure Portal
    2. The private key imported into the local certificate store where the script is running.
    3. App registration has storage account owner role where the storage container resides.

.INPUTS
    Inputs (if any)
.OUTPUTS
    Using the switch '-OutEventLog' you can receive the results of the synchronization process.#>

[CmdletBinding()]
param
(
    [Parameter(HelpMessage = 'Enter path to the azcopy.exe executable')]
    [ValidateNotNullOrEmpty()]
    [string]
    $AzCopyPath = '{Path to Azcopy.exe}',

    [Parameter(HelpMessage = 'Enter the path for the local folder to be synchronized,')]
    [ValidateNotNullOrEmpty()]
    [Alias('Path')]
    [string]
    $CertificateFolderPath = '{Path to local certificates folder}',

    [Parameter(HelpMessage = "Enter the storage account's resource group name")]
    [ValidateNotNullOrEmpty()]
    [string]
    $ResourceGroupName = '{resource group name for storage account}',

    [Parameter(HelpMessage = 'Enter your tenant name or ID')]
    [ValidateNotNullOrEmpty()]
    [string]
    $TenantName = '{tenant name or id}',

    [Parameter(HelpMessage = 'Enter your app registration application id')]
    [ValidateNotNullOrEmpty()]
    [Alias('ClientId')]
    [string]
    $ApplicationId = '{appid for app registration}',

    [Parameter(HelpMessage = 'Enter type of credential used: certificate or secret')]
    [ValidateSet('Certificate', 'Secret')]
    $CredentialType = '{certificate or secret}',

    [Parameter(HelpMessage = 'Enter your application secret or certificate thumbprint')]
    [string]
    $AppRegistrationCredential = '{client secret or certificate thumbprint}',

    [Parameter(HelpMessage = 'Enter SAS token duration (in hours)')]
    [int]
    $TokenDurationInHours = 2,

    [Parameter(HelpMessage = 'Enter a valid storage container url')]
    [Alias('ContainerUrl')]
    [ValidateNotNullOrEmpty()]
    [uri]
    $ContainerUri = '{storage container url}',

    [Parameter(HelpMessage = 'Use to send report to event log on local machine')]
    [switch]
    $OutEventLog,

    [Parameter(HelpMessage = 'Mininum supported AZCopy version')]
    [version]
    $AzCopyMinSupportVersion = '10.2.1',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]
    $Subscription = '{subscription id}',

    [Parameter(HelpMessage = 'The event source to assign event to. This works with the -OutEventLog switch.')]
    [string]
    $EventSource = 'ADCS_AZCopy',

    [Parameter(HelpMessage = 'The selected event log to write events against.')]
    [string]
    $EventLog = 'Application'
)

function Get-AZCopyVersion
{
    $cmd = [string]::Format("""{0}"" --version", $AzCopyPath)
    $result = cmd.exe /c $cmd
    $pattern = '\bv?[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?\b'
    $output = [regex]::Match($result, $pattern)
    return ([version]$output.Value)
}

function Get-SASTokenUrl
{
    param
    (
        $StorageAccountName,
        $ContainerUrl
    )

    $key = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].value
    $context = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $key

    $tokenParameters = @{
        Service      = 'Blob'
        ResourceType = @('Service', 'Container', 'Object')
        Permission   = 'rwdl'
        Context      = $context
        ExpiryTime   = (Get-Date).AddHours($TokenDurationInHours)
    }

    $sasToken = New-AzStorageAccountSASToken @tokenParameters
    return ('{0}/{1}' -f $ContainerUrl, $sasToken)
}

if (-not (Test-Path -Path $AzCopyPath))
{
    Write-Error -Message 'AzCopy executable path does not exist'
    exit
}

if (-not (Test-Path -Path $CertificateFolderPath))
{
    Write-Error -Message 'The local certificate folder path does not exist'
    exit
}

$azCopyVersion = Get-AzCopyVersion
while ($azCopyVersion -lt $AzCopyMinSupportVersion)
{
    $AzCopyPath = Read-Host ('Version of AzCopy.exe found is of a lower, unsupported version. Please use at least version {0}.' -f $AzCopyMinSupportVersion)
    $azCopyVersion = Get-AZCopyVersion
}

$url = [string]::Empty

$parameters = @{
    ServicePrincipal = $true
    Tenant           = $TenantName
    Subscription     = $Subscription
}

try
{
    if ($CredentialType -eq 'Secret')
    {
        $securePassword = ConvertTo-SecureString -String $AppRegistrationCredential -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential -ArgumentList $ApplicationId, $securePassword
        Connect-AzAccount @parameters -Credential $credential | Out-Null
    }
    else
    {
        Connect-AzAccount @parameters -ApplicationId $ApplicationId -CertificateThumbprint $AppRegistrationCredential | Out-Null
    }

    $storageAccountName = $ContainerUri.Host.Split('.')[0]
    $url = Get-SASTokenUrl -StorageAccountName $storageAccountName -ContainerUrl $ContainerUri.AbsoluteUri


    $cmd = [string]::Format("""{0}"" sync ""{1}"" ""{2}"" --put-md5 --delete-destination=true", $AzCopyPath, $CertificateFolderPath, $url)
    $result = cmd.exe /c $cmd

    $result | ForEach-Object { Write-Host $_ }
    $message = $result -join "`n"

    if ($OutEventLog)
    {
        $eventlogParameters = @{ Source = $EventSource; LogName = $EventLog; Message = $message }
        if ($LASTEXITCODE -ne 0) # Failure Case
        {
            $eventlogParameters.Add('EntryType', 'Error')
            $eventlogParameters.Add('EventId', 355)
        }
        else # Success Case
        {
            $eventlogParameters.Add('EntryType', 'Information')
            $eventlogParameters.Add('EventId', 354)
        }

        if ( [System.Diagnostics.EventLog]::SourceExists($eventlogParameters.Source) -eq $false)
        {
            New-EventLog -Source $eventlogParameters.Source -LogName $eventlogParameters.LogName
        }

        Write-EventLog @eventlogParameters
    }
}
catch
{
    Write-Host ($_.Exception.GetBaseException().Message)
    Write-Host 'Exiting script'
    exit
}
