<#
.SYNOPSIS
  Sync files to an storage account
.PARAMETER Path
    File or folder content to be uploaded to the Storage Account container (Child folders structure will be kept).
.PARAMETER StorageAccountName
    Existing Storage Account Name
.PARAMETER ResourceGroup
    Resource group name where the storage account exists
.PARAMETER Container
    Container path where the blobs will be copied.
    You can specify a subfolder as '<containername>/childfolder'
.EXAMPLE
    .\Sync-Files2Blob.ps1 -Path ".\output" -StorageAccountName "dummystorageaccount1" -ResourceGroup "DummyRG" -Container "myproject/build1" 

#>
[CmdletBinding()]
param (
    [Parameter(Mandatory,Position=0)]
    [ValidateScript({Test-Path $_ })]
    [string] $Path,
    [Parameter(Mandatory,Position=1)]
    [string] $StorageAccountName,
    [Parameter(Mandatory,Position=2)]
    [string] $ResourceGroup,
    [Parameter(Mandatory,HelpMessage="Container and subcontainer structure, separated by /",Position=3)]
    [string] $Container
)

function Get-FileMd5Hash {
    param (
        $Path=$Null
    )
    $file = [System.IO.File]::Open((Resolve-Path $path),[System.IO.Filemode]::Open, [System.IO.FileAccess]::Read)
    try {
        [System.Convert]::ToBase64String((new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider).ComputeHash($file))
    } finally {
        $file.Dispose()
    }
}

$context = $null
try {$context = Get-AzureRmContext} catch {}
if($null -eq $context.Subscription.Id) { throw 'You must call the Login-AzureRmAccount cmdlet before calling any other cmdlets.' }

$StorageAccount = Get-AzureRmStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroup

if(!$StorageAccount) {
  throw ("Cannot find '{0}' storage account in '{1}' resource group" -f $Name, $ResourceGroupName)
}

if(-not ($Container.Contains('/'))) {
  $StorageAccountContainerName = $Container.ToLower()
  $StorageAccountBlobPrefix = ""
}
else {
  $StorageAccountContainerName = $Container.SubString(0,$Container.IndexOf('/')).ToLower()
  $StorageAccountBlobPrefix = $Container.SubString($Container.IndexOf('/') + 1).ToLower()
}

$StorageAccountKey = (Get-AzureRmStorageAccountKey -Name $StorageAccountName -ResourceGroupName $ResourceGroup)[0].value
$StorageAccountContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

## Create container if required
If (-not (Get-AzureStorageContainer -Context $StorageAccountContext -Name $StorageAccountContainerName -ErrorAction SilentlyContinue)) {
    Write-Verbose "Creating container ""$StorageAccountContainerName"""
    New-AzureStorageContainer -Context $StorageAccountContext -Name $StorageAccountContainerName | out-null
}

$LocalFiles = @(Get-ChildItem -Path $Path -Recurse -File)
$PathObject=get-item $Path

## Add or replace files
foreach ($LocalFileObject in $LocalFiles) {
    if ($StorageAccountBlobPrefix) {
      $Prefix = $StorageAccountBlobPrefix
    }
    else {
      $Prefix = ""
    }

    Write-Verbose "Prefix is now = $Prefix"
    $SubFolder = $LocalFileObject.Directory.ToString().Replace($PathObject.Fullname, '')
    Write-Verbose "SubFolder is now = $SubFolder"

    if ($SubFolder -ne "") {
      $BlobFile="$Prefix/$($SubFolder.Substring(1))/$($LocalFileObject.Name)"
    }
    else {
      $BlobFile="$Prefix/$($LocalFileObject.Name)"
    }

    Write-Verbose "BlobFile is now = $BlobFile"

    $localMD5 = Get-FileMd5Hash -Path $LocalFileObject.Fullname
    $cloudMD5 = (Get-AzureStorageBlob -Blob $BlobFile -Container $StorageAccountContainerName -Context $StorageAccountContext -ErrorAction "SilentlyContinue").ICloudBlob.Properties.ContentMD5
    
    Write-Verbose "localMD5 is now = $localMD5"
    Write-Verbose "cloudMD5 is now = $cloudMD5"

    if ($localMD5 -ne $cloudMD5) {
        Write-Verbose "Uploading ""$($LocalFileObject.Name)"" file to ""$BlobFile""..."
        Set-AzureStorageBlobContent -Blob $BlobFile -Container $StorageAccountContainerName -File $LocalFileObject.Fullname -Context $StorageAccountContext -Force -ConcurrentTaskCount 1 | out-null
    } else {
        Write-Verbose "Skipping ""$($LocalFileObject.Name)"" file upload due hash matches with ""$BlobFile""..."
    }
}

if ($PathObject.PSIsContainer) {
    ## Remove files from blob that don't exist on the source folder
    $existingRemoteFiles = Get-AzureStorageBlob -context $StorageAccountContext -Container $StorageAccountContainerName -Prefix $StorageAccountBlobPrefix

    ForEach ($existingRemoteFile in $existingRemoteFiles) {
        if ($StorageAccountBlobPrefix) {
            $ExpectedFile="$($PathObject.Fullname)\$($existingRemoteFile.Name.replace("$($StorageAccountBlobPrefix)/",''))"
        } 
        else {
            $ExpectedFile="$($PathObject.Fullname)\$($existingRemoteFile.Name)"
        }

        Write-Verbose "ExpectedFile is now = $ExpectedFile"
        
        if (-not (Test-Path -Path "$ExpectedFile")) {
            Write-Verbose "Removing ""$StorageAccountContainerName\$($existingRemoteFile.name)"" due ""$ExpectedFile"" does not exist at origin..."
            Remove-AzureStorageBlob -context $StorageAccountContext -Container $StorageAccountContainerName -Blob $existingRemoteFile.name
        }
    }
}