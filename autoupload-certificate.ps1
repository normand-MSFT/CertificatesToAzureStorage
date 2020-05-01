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
against any claims or lawsuits, including attorneys’ fees, that arise or result from 
the use or distribution of the Sample Code.
#>

param
(
    [Parameter(Mandatory = $false, 
    HelpMessage= "Destination Blob Container Url.")]
    [String]$DestBlobContainerUrl = "http:\\pki1.markwilab.com\certdata",
    #[String]$DestBlobContainerUrl = "https://markwipkistg.blob.core.windows.net/certdata",

    [Parameter(Mandatory = $false, 
    HelpMessage= "Input the full filePath of the AzCopy.exe, e.g.: C:\Program Files (x86)\Microsoft SDKs\Azure\AzCopy\AzCopy.exe")]
    [String]$AzCopyPath = "C:\Users\Administrator\Desktop\markwi\AzCopy.exe",

    [Parameter(Mandatory = $false, 
    HelpMessage="Sets the local cert folder where we find the CRT and CRL files to upload to blob container.")]
    [String]$LocalCertFolder = "C:\Users\Administrator\Desktop\markwi\files",

    [Parameter(Mandatory = $false, 
    HelpMessage="Your shared access token so you don't need to log into session.")]
    [String]$SASToken = "?sv=2018-03-28&ss=b&srt=sco&sp=rwdlac&se=2019-11-18T04:59:52Z&st=2019-09-17T19:59:52Z&spr=https,http&sig=tNCA%2Fnh9znTeCLsWecOeL8Jl%2BkIUXOhHTgP6kQuoLpA%3D"
    #[String]$SASToken = "?sv=2018-03-28&si=myidentifier&sr=c&sig=8ezkaU03ej%2BHYX%2F89DodkVZtO1T59GZJZlNF%2FH8hPTw%3D"
    
)

function WriteTo-EventLog
{
    param($EventLogParameters, $SourceName = "ADCS_AZCopy")    
    if( (Get-EventLog -LogName Application -Source $SourceName) -eq $null)
    {
        New-EventLog -Source $SourceName -LogName Application
    }

    Write-EventLog @EventLogParameters -Source $SourceName

} # end WriteTo-EventLog

function Check-AZCopyVersion
{
    $AzCmd = [string]::Format("""{0}"" --version",$AzCopyPath)    
    $Result = cmd /c $AzCmd
    $RegexPattern = "\bv?[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?\b"

    $Output = [regex]::Match($Result, $RegexPattern)
    return $Output.Value
} # end Check-AZCopyVersion

if( -not (Test-Path -Path $AzCopyPath))
{
    Write-Host "AZCopy.exe not found at $(Split-Path -Path $AzCopyPath -Parent)."
}

if( ([version](Check-AzCopyVersion)) -lt "10.2.1")
{
    $AzCopyPath = Read-Host "Version of AzCopy.exe found at specified directory is of a lower, unsupported version."
}
        
$AzCopyCmd = [string]::Format("""{0}"" sync ""{1}"" ""{2}{3}"" --put-md5 --delete-destination=true", $AzCopyPath, $LocalCertFolder, $DestBlobContainerUrl, $SASToken)    
$Result = cmd /c $AzCopyCmd

foreach($SearchResult in $Result)
{
    Write-Host $SearchResult
}

$EventLogParameters = @{ LogName = "Application"; Message = ($Result -join "`n") }

if($LASTEXITCODE -ne 0) # Failure Case
{
    $EventLogParameters.Add("EntryType", "Error")
    $EventLogParameters.Add("EventId", 355)
}
else # Success Case
{
    $EventLogParameters.Add("EntryType", "Information")
    $EventLogParameters.Add("EventId", 354)
}

WriteTo-EventLog -EventLogParameters $EventLogParameters