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
$attachment01 = [string]::Empty

if ($PSCmdlet.ParameterSetName -eq "Existing")
{
    if ([string]::IsNullOrEmpty($SASToken))
    {
        Connect-AzAccount | Out-Null
        # https://adcsstoragepycid7lo446jk.blob.core.windows.net/certspycid7lo446jk
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
    Connect-AzAccount | Out-Null
    $url = New-AzureStorageAccount
}

if ( (Get-AzCopyVersion) -lt "10.2.1")
{
    $Executable = Read-Host "Version of AzCopy.exe found at specified directory is of a lower, unsupported version."
}

$cmd = [string]::Format("""{0}"" sync ""{1}"" ""{2}"" --put-md5 --delete-destination=true", $Executable, $Path, $url)    
$result = cmd.exe /c $cmd

$result | ForEach-Object { Write-Host $_ }
$message = $result -join "`n"

# https://github.com/Azure/azure-storage-azcopy/issues/874
# The log file reference ($attachment01) in azcopy output is invalid. The file 
# does not exist.

if ($OutEventLog.isPresent)
{
    $parameters = @{ EventLog = "Application"; message = $message }
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

    if ( $null -eq (Get-EventLog -EventLog $EventLog -Source $EventSource ))
    {
        New-EventLog -Source $EventSource -EventLog $EventLog
    }

    Write-EventLog @Parameters -Source $EventSource  
}

if ($OutEmail.IsPresent)
{
    $from = "user01@contoso.com"
    $to = "user02@contoso.com"
    $smtpServer = "smtp.contoso.com"

    $emailMessage = New-Object System.Net.Mail.MailMessage($from , $to)
    $emailMessage.Subject = ("Certificate Sync - {0} " -f (Get-Date).ToUniversalTime() ) 
    $emailMessage.Body = $message
 
    $smtpClient = New-Object System.Net.Mail.smtpClient($smtpServer, 587)
    $smtpClient.EnableSsl = $true

    # Tested originally against smtp.live.com but needed to create an app password because of 2FA issues.
    $smtpClient.Credentials = New-Object System.Net.NetworkCredential( "user01@contoso.com", 'password' );
    $smtpClient.Send($emailMessage)
}
