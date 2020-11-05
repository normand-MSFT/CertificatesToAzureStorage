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
    PS C:\Scripts> .\Copy-PKIDataToAzureBlob-DynamicSAS.ps1 `
     -AzCopyPath c:\path\to\azcopy.exe `
     -ContainerUrl http://mystorageaccount.blob.core.windows.net/mystoragecontainer `
     -CertificateFolderPath c:\mycertificates
     -SasToken '?sv=ABC...'

    This example does not require credentials and simply concatenates the ContainerUrl and SasToken into one
    url to use with azcopy.exe. It requires the user have a valid SaS token. The certificates in $CertificateFolderPath
    are then synced into the $ContainerUrl.
.INPUTS
    Inputs (if any)
.OUTPUTS
   An event log entry and / or email. For further customizations look at lines 96-118 for event log
   and lines 120-135 for smtp configuration.

.NOTES
    1. The version of azcopy.exe tested is 10.2.1 and 10.6.1
    2. The email functionality was tested against smtp.live.com and required an app password be used if 2FA is configured.
    3. Send-MailMessage (and the underlying SmtpClient is deprecated). For more information, please see

DE0005: SmtpClient shouldn't be used
https://github.com/dotnet/platform-compat/blob/master/docs/DE0005.md

#>

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

    [Parameter(HelpMessage = 'Enter a valid storage container url')]
    [ValidateNotNullOrEmpty()]
    [string]
    $ContainerUrl = '{storage container url}',

    [Parameter(HelpMessage = 'Enter a valid, non-expired SAS Token')]
    [ValidateNotNullOrEmpty()]
    [string]
    $SASToken = '{SAS-Token}',

    [Parameter()]
    [switch]
    $OutEmail,

    [Parameter()]
    [switch]
    $OutEventLog
)

function Get-AZCopyVersion
{
    $cmd = [string]::Format("""{0}"" --version", $AzCopyPath)
    $result = cmd.exe /c $cmd
    $pattern = "\bv?[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?\b"
    $output = [regex]::Match($result, $pattern)
    return ([version]$output.Value)
} # end Get-AZCopyVersion


if ( (Get-AzCopyVersion) -lt '10.2.1')
{
    $AzCopyPath = Read-Host "Version of AzCopy.exe found at specified directory is of a lower, unsupported version."
}

$url = "{0}{1}" -f $ContainerUrl, $SASToken

$cmd = [string]::Format("""{0}"" sync ""{1}"" ""{2}"" --put-md5 --delete-destination=true", $AzCopyPath, $CertificateFolderPath, $url)
$result = cmd.exe /c $cmd

$result | ForEach-Object { Write-Host $_ }
$message = $result -join "`n"

if ($OutEventLog.isPresent)
{
    $eventParameters = @{ LogName = 'Application'; Message = $message; Source = 'ADCS_AZCopy' }


    if ($LASTEXITCODE -ne 0) # Failure Case
    {
        $eventParameters.Add('EntryType', 'Error')
        $eventParameters.Add('EventId', 355)
    }
    else # Success Case
    {
        $eventParameters.Add('EntryType', 'Information')
        $eventParameters.Add('EventId', 354)
    }

    if ( [System.Diagnostics.EventLog]::SourceExists($eventlogParameters.Source) -eq $false)
    {
        New-EventLog -Source $eventParameters.Source -LogName $eventParameters.LogName
    }

    Write-EventLog @eventParameters
}

if ($OutEmail.IsPresent)
{
    $from = 'user01@contoso.com'
    $to = 'user02@contoso.com'
    $smtpServer = 'smtp.contoso.com'

    $emailMessage = New-Object System.Net.Mail.MailMessage($from , $to)
    $emailMessage.Subject = ('Certificate Sync - {0} ' -f (Get-Date).ToUniversalTime() )
    $emailMessage.Body = $message

    $smtpClient = New-Object System.Net.Mail.SmtpClient($smtpServer, 587)
    $smtpClient.EnableSsl = $true

    $smtpClient.Credentials = New-Object System.Net.NetworkCredential( "user01@contoso.com", 'password' )
    $smtpClient.Send($emailMessage)
}
