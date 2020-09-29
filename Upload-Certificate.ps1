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

<#
.SYNOPSIS
    Script demonstrating certificate synchronization of on-premise folder with an azure storage container.
.DESCRIPTION
    This script, while can be used to sync anything files with an azure storage container, is designed to demonstrate
    how we can sync certificates in a local directory with an azure storage container. This allows us to use the
    container as a backup.
.EXAMPLE
    PS C:\Scripts> .\Upload-Certificate.ps1 `
     -ContainerUrl http://mystorageaccount.blob.core.windows.net/mystoragecontainer `
     -CertificateFolderPath c:\mycertificates
     -ResourceGroupName adcsrg `
     -TimeDuration 3 `
     -TenantName contoso.onmicrosoft.com `
     -ApplicationId '12345' `
     -ApplicationSecret '12345'
    
    This example parses the ContainerUrl to retrieve the storage account name and storage container name. It
    uses the Connect-AzAccount cmdlet to authenticate using an applicationid and application secret. For this to work
    the user needs to create an app registration in Azure Active Directory and provide it an appropriate access role 
    for the storage account. Alternatively we can decide to use a certificate thumbprint. The certificates in 
    $CertificateFolderPath are then synced into the $ContainerUrl.

    Using the above storage account name, resource group name, and storage container it generates a SaS token with a
    3 hour duration.
.EXAMPLE
    PS C:\Scripts> .\Upload-Certificate.ps1 `
     -ContainerUrl http://mystorageaccount.blob.core.windows.net/mystoragecontainer `
     -CertificateFolderPath c:\mycertificates
     -SasToken '?sv=ABC...'
    
    This example does not require credentials and simply concatenates the ContainerUrl and SasToken into one
    url to use with azcopy.exe. It requires the user have a valid SaS token. The certificates in $CertificateFolderPath
    are then synced into the $ContainerUrl.
.INPUTS
    Inputs (if any)
.OUTPUTS
    Using the switch -OutEventLog you can receive the results of the synchronization process. 
    To customize the variables for -OutEventLog, look for the following and modify accordingly.

    if ($OutEventLog.isPresent)
    {
        $parameters = @{ eventLog = "Application"; message = $message }
        if ($LASTEXITCODE -ne 0) # Failure Case
        {
            $parameters.Add("EntryType", "Error")
            $parameters.Add("EventId", 355)
        }
        else # Success Case
        {
            $parameters.Add("EntryType", "Information")
            $parameters.Add("EventId", 354)
        }

        $eventSource = "ADCS_AZCopy"
        parameters.Add("Source", $eventSource)

        if ( $null -eq (Get-EventLog -EventLog $eventLog -Source $eventSource ))
        {
            New-EventLog -Source $eventSource -EventLog $eventLog
        }

        Write-EventLog @parameters
    }


.NOTES
The version of azcopy.exe tested is 10.2.1. 
#>

[CmdletBinding(DefaultParameterSetName = "ExistingToken")]
param
(
    [Parameter(HelpMessage = "Enter path to the azcopy.exe executable")]
    [ValidateScript( { if ( -not (Test-Path -Path $_))
            {
                Write-Host "AZCopy.exe not found. Pleae check the path again." 
            } 
        })]        
    [string]
    $Executable = "{Path}\azcopy.exe",

    [Parameter(HelpMessage = "Enter your local certificates folder")]
    [Alias("Path")]
    [ValidateScript( { Test-Path -Path $_ })]
    [string]
    $CertificateFolderPath = "{CertificateFolderPath}",

    [Parameter(ParameterSetName = "NewToken", HelpMessage = "Enter your resource group name")]
    [ValidateNotNullOrEmpty()]
    [string]
    $ResourceGroupName = "{ResourceGroup}",

    [Parameter(ParameterSetName = "NewToken", HelpMessage = "Enter your tenant name")]
    [Alias("TenantId")]
    [string]
    $TenantName = "{TenantName}",

    [Parameter(ParameterSetName = "NewToken", HelpMessage = "Enter your application id")]
    [ValidateNotNullOrEmpty()]
    [string]
    $ApplicationId = "{ApplicationId}",

    [Parameter(ParameterSetName = "NewToken", HelpMessage = "Enter your application secret")]
    [ValidateNotNullOrEmpty()]
    [string]
    $ApplicationSecret = "{ApplicationSecret}",

    [Parameter(ParameterSetName = "NewToken", HelpMessage = "Enter SAS token duration (in hours)")]
    [int]
    $TokenDuration = 2,
    
    [Parameter(Mandatory = $true, HelpMessage = "Enter a valid storage container url")]
    [Alias("DestinationUrl")]
    [ValidateNotNullOrEmpty()]
    [string]$ContainerUrl = "{StorageContainerUrl}",

    [Parameter(ParameterSetName = "ExistingToken", HelpMessage = "Enter your SAS token")]
    [ValidateNotNullOrEmpty()]
    [string]
    $SasToken = '{SAS-Token}',

    [Parameter(HelpMessage = "Use to send report to event log")]
    [switch]
    $OutEventLog
)

function Get-AZCopyVersion
{
    $cmd = [string]::Format("""{0}"" --version", $Executable)    
    $result = cmd.exe /c $cmd
    $pattern = "\bv?[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?\b"
    $output = [regex]::Match($result, $pattern)
    return ([version]$output.Value)
} # end Get-AZCopyVersion

function Get-SasTokenUrl
{
    param
    (
        $StorageAccountName,
        $ContainerUrl
    )

    $storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].value
    $context = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageAccountKey
    $token = New-AzStorageAccountSASToken `
        -Service Blob -ResourceType Service, Container, Object `
        -Permission rwdl `
        -Context $context `
        -ExpiryTime (Get-Date).AddHours($TokenDuration)

    Write-Host ("SAS Token = {0}" -f $token)
    return ('{0}{1}' -f $ContainerUrl, $token)
} # end Get-SasTokenUrl


if ( (Get-AzCopyVersion) -lt "10.2.1")
{
    $executable = Read-Host "Version of AzCopy.exe found at specified directory is of a lower, unsupported version."
}

$url = [string]::Empty
if ($PSCmdlet.ParameterSetName -eq "ExistingToken")
{
    $url = "{0}{1}" -f $ContainerUrl, $SasToken
}
elseif ($PSCmdlet.ParameterSetName -eq "NewToken")
{
    $SecurePassword = ConvertTo-SecureString -String $ApplicationSecret -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential -ArgumentList $ApplicationId, $SecurePassword
    Connect-AzAccount -Credential $Credential -ServicePrincipal -Tenant $TenantName | Out-Null
    $uri = New-Object System.Uri($ContainerUrl)
    $storageAccountName = $uri.Host.Split(".")[0]
    $url = Get-SasTokenUrl -StorageAccountName $storageAccountName -ContainerUrl $ContainerUrl
}

$cmd = [string]::Format("""{0}"" sync ""{1}"" ""{2}"" --put-md5 --delete-destination=true", $executable, $CertificateFolderPath, $url)    
$result = cmd.exe /c $cmd

$result | ForEach-Object { Write-Host $_ }
$message = $result -join "`n"

if ($OutEventLog.isPresent)
{
    $parameters = @{ eventLog = "Application"; message = $message }
    if ($LASTEXITCODE -ne 0) # Failure Case
    {
        $parameters.Add("EntryType", "Error")
        $parameters.Add("EventId", 355)
    }
    else # Success Case
    {
        $parameters.Add("EntryType", "Information")
        $parameters.Add("EventId", 354)
    }

    $eventSource = "ADCS_AZCopy"
    $parameters.Add("Source", $eventSource)

    if ( $null -eq (Get-EventLog -EventLog $eventLog -Source $eventSource ))
    {
        New-EventLog -Source $eventSource -EventLog $eventLog
    }

    Write-EventLog @parameters
}
