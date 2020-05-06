
#requires

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



[CmdletBinding(DefaultParameterSetName = "EventLog")]
param
(
    [Parameter(Mandatory = $true, HelpMessage = "Destination Blob Container Url.")]
    [String]$BlobContainerUrl,

    [Parameter(Mandatory = $false, HelpMessage = "Input the full filePath of the AzCopy.exe, e.g.: C:\Program Files (x86)\Microsoft SDKs\Azure\AzCopy\AzCopy.exe")]
    [ValidateScript( { if ( -not (Test-Path -Path $_))
            {
                Write-Host "AZCopy.exe not found at $(Split-Path -Path $_ -Parent)."
            } 
        })]        
    [String]$AZCopyExecutable,

    [Parameter(Mandatory = $false, HelpMessage = "Sets the local cert folder where we find the CRT and CRL files to upload to blob container.")]
    [ValidateScript( { Test-Path -Path $_ })]
    [String]$CertificateFolder,

    [Parameter(Mandatory = $true, HelpMessage = "Your shared access token so you don't need to log into session.")]
    [String]$SASToken,

    [Parameter(ParameterSetName = "EventLog")]    
    [ValidateSet("System", "Application", "Security")]
    $EventLog,

    [Parameter(ParameterSetName = "EventLog")]
    $EventSource,
    
    [Parameter(ParameterSetName = "Mail")]
    $SMTPServer

)

function Write-EventlogWrapper
{
    param($EventLogParameters)    
    if ( $null -eq (Get-EventLog -EventLog $EventLog -Source $EventSource
    ))
    {
        New-EventLog -Source $EventSource
         -EventLog $EventLog
    }

    Write-EventLog @EventLogParameters -Source $EventSource


} # end Write-EventlogWrapper

function Get-AZCopyVersion
{
    $AzCmd = [string]::Format("""{0}"" --version", $AZCopyExecutable)    
    $Result = cmd.exe /c $AzCmd
    $RegexPattern = "\bv?[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?\b"

    $Output = [regex]::Match($Result, $RegexPattern)
    return ([version]$Output.Value)

} # end Get-AZCopyVersion

if ( (Get-AzCopyVersion) -lt "10.2.1")
{
    $AZCopyExecutable = Read-Host "Version of AzCopy.exe found at specified directory is of a lower, unsupported version."
}
        
$AzCopyCmd = [string]::Format("""{0}"" sync ""{1}"" ""{2}{3}"" --put-md5 --delete-destination=true", $AZCopyExecutable, $CertificateFolder, $BlobContainerUrl, $SASToken)    
$Result = cmd.exe /c $AzCopyCmd

$Result.foreach({ Write-Host $_ })

$Message = $Result -join "`n"

if ($PSCmdlet.ParameterSetName -eq "Eventlog")
{
    $EventLogParameters = @{ EventLog = "Application"; Message = $Message }

    if ($LASTEXITCODE -ne 0) # Failure Case
    {
        $EventLogParameters.Add("EntryType", "Error")
        $EventLogParameters.Add("EventId", 355)
    }
    else # Success Case
    {
        $EventLogParameters.Add("EntryType", "Information")
        $EventLogParameters.Add("EventId", 354)
    }

    Write-EventlogWrapper -EventLogParameters $EventLogParameters

}
elseif ($PSCmdlet.ParameterSetName -eq "Mail")
{

    $body = Get-Content -Path .\body.htm | Out-String 
    $bodyAsHtml = [string]::format($body, 
        "Certificate Upload Notification", 
        "Last sync time: {0}" -f (Get-Date).ToString(),
        "Contoso, LLC - a Microsoft property"
        $Message,
        "Contoso IT Support"
    
        $parameters = @{
        SMTPServer = $SMTPServer
        Port = $port
        From = $from 
        To = $to 
        Subject = $subject
        Body = $body
    }

    # This will use the credentials of the logged on user otherwise we can pass a PSCredential object into the Credential parameter. 
    Send-MailMessage @parameters -UseSsl

}
