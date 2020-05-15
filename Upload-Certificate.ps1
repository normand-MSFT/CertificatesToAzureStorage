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
    PS C:\> .\Upload-Certificate.ps1 -DestinationUrl http://mystorageaccount.blob.core.windows.net/mystoragecontainer -GroupName adcsrg
    This example parses the DestinationUrl to come up with the storage account name (mystorageaccount)
    and the storage container name (mystoragecontainer). It does require credentials and uses the Connect-AzAccount
    cmdlet to authenticate you. Optionally, if we setup a service principal and/or
    certificate to authenticate this process will make it better for automated processes.

    Using the above storage account name, resource group name, and storage container it generates a sastoken with a hard-coded two 
    hour duration. 
.EXAMPLE
PS C:\> .\Upload-Certificate.ps1 -DestinationUrl http://mystorageaccount.blob.core.windows.net/mystoragecontainer -SasToken "mytoken"
    This example does not require credentials and simply concatenates the DestinationUrl and SasToken into one
    Uri to use with an azcopy.exe sync command. It requires the user providing a token to the script.
.EXAMPLE
PS C:\> .\Upload-Certificate.ps1 -CreateStorageContainer
    This example requires credentials and uses an ARM template to create a resourcegroup (uses a default value for $GroupName), storageaccount, and storagecontainer. 
    Afterwards, it retrieves a storage account key and generates a 2-hour sas token to use for the remainder of the script.     
.INPUTS
    Inputs (if any)
.OUTPUTS
    Using the switches (-OutEmail and -OutEventLog) you can receive the results of the synchronization process.
.NOTES
    1. The version of azcopy.exe tested is 10.2.1. 
    2. The email functionality was tested against smtp.live.com and required an app password be used if 2FA is configured.
    3. Send-MailMessage isn't used as it is deprecated with no current PowerShell replacement.
#>

[CmdletBinding(DefaultParameterSetName = "Existing")]
param
(
    [Parameter(Helpmessage = "Input the full path to the azcopy.exe executable")]
    [ValidateScript( { if ( -not (Test-Path -Path $_))
            {
                Write-Host "AZCopy.exe not found. Pleae check the path again." 
            } 
        })]        
    [string]
    $Executable = "C:\Users\normand\desktop\azcopy\azcopy.exe",

    [Parameter(Helpmessage = "Sets the local cert folder")]
    [ValidateScript( { Test-Path -Path $_ })]
    [string]
    $Path = "C:\Users\normand\desktop\azcopy\files",

    [Parameter()]
    [string]
    $GroupName = "adcsrg",

    [Parameter(Mandatory = $true, ParameterSetName = "Existing", Helpmessage = "Destination Blob Container Url.")]
    [ValidateNotNullOrEmpty()]
    [string]$DestinationUrl,

    [Parameter(ParameterSetName = "Existing")]
    [string]
    $SASToken,

    [Parameter(ParameterSetName = "New")]
    [switch]
    $CreateStorageContainer,

    [Parameter()]
    [switch]
    $OutEmail,

    [Parameter()]
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
        $DestinationUrl
    )

    $key = (Get-AzStorageAccountKey -ResourceGroupName $GroupName -Name $StorageAccountName)[0].value
    $context = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $key
    $sasToken = New-AzStorageAccountSASToken `
        -Service Blob -ResourceType Service, Container, Object `
        -Permission racwdlup `
        -Context $context `
        -ExpiryTime (Get-Date).AddHours(2)

    Write-Host ("sasToken = {0}" -f $sasToken)
    return ('{0}{1}' -f $DestinationUrl, $sasToken)
}
function New-AzureStorageAccount
{
    $resourceGroupName = New-AzResourceGroup -Name $GroupName -Location "Central US" | Select-Object -ExpandProperty ResourceGroupName
    $deployment = New-AzResourceGroupDeployment `
        -Name TestDeployment `
        -TemplateFile .\Templates\azuredeploy.json `
        -TemplateParameterFile .\Templates\azuredeploy.parameters.json `
        -ResourceGroupName $resourceGroupName `
        -Verbose

    $storageAccountName = $deployment.Outputs.Item('storageAccountName').Value
    $destinationUrl = $deployment.Outputs.Item('DestinationUrl').Value

    $url = Get-SasTokenUrl -StorageAccountName $storageAccountName -DestinationUrl $destinationUrl
    return $url
}

$url = [string]::Empty
if ($PSCmdlet.ParameterSetName -eq "Existing")
{
    if ([string]::IsNullOrEmpty($SASToken))
    {
        if ([string]::IsNullOrEmpty($GroupName))
        {
            Write-Host "Enter a valid resource group name (-GroupName)"
            exit
        }
        Connect-AzAccount | Out-Null
        $uri = New-Object System.Uri($DestinationUrl)
        $storageAccountName = $uri.Host.Split(".")[0]
        $url = Get-SasTokenUrl -StorageAccountName $storageAccountName -DestinationUrl $DestinationUrl
    }
    else
    {
        $url = "{0}{1}" -f $DestinationUrl, $SASToken
    }
}
elseif ($PSCmdlet.ParameterSetName -eq "New")
{
    if ([string]::IsNullOrEmpty($GroupName))
    {
        Write-Host "Enter a valid resource group name (-GroupName)"
        exit
    }
    Connect-AzAccount | Out-Null
    $url = New-AzureStorageAccount
}

if ( (Get-AzCopyVersion) -lt "10.2.1")
{
    $executable = Read-Host "Version of AzCopy.exe found at specified directory is of a lower, unsupported version."
}

$cmd = [string]::Format("""{0}"" sync ""{1}"" ""{2}"" --put-md5 --delete-destination=true", $executable, $Path, $url)    
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
    parameters.Add("Source", $eventSource)

    if ( $null -eq (Get-EventLog -EventLog $eventLog -Source $eventSource ))
    {
        New-EventLog -Source $eventSource -EventLog $eventLog
    }

    Write-EventLog @parameters
}

if ($OutEmail.IsPresent)
{
    $from = "user01@contoso.com"
    $to = "user02@contoso.com"
    $smtpServer = "smtp.contoso.com"

    $emailMessage = New-Object System.Net.Mail.MailMessage($from , $to)
    $emailMessage.Subject = ("Certificate Sync - {0} " -f (Get-Date).ToUniversalTime() ) 
    $emailMessage.Body = $message
 
    $smtpClient = New-Object System.Net.Mail.SmtpClient($smtpServer, 587)
    $smtpClient.EnableSsl = $true

    # Tested originally against smtp.live.com but needed to create an app password because of 2FA issues.
    $smtpClient.Credentials = New-Object System.Net.NetworkCredential( "user01@contoso.com", 'password' )
    $smtpClient.Send($emailMessage)
}
