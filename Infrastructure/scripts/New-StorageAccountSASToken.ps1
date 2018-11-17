param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $Name,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ResourceGroupName,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ContainerPath,
    [ValidateSet('Read','Write','Delete','List','Add','Create')]
    [string[]] $Permissions = "Read",
    [ValidateNotNullOrEmpty()]
    [int] $Duration = 1
)

$context = $null
try {$context = Get-AzureRmContext} catch {}
if($null -eq $context.Subscription.Id) { throw 'You must call the Login-AzureRmAccount cmdlet before calling any other cmdlets.' }

$StorageAccount = Get-AzureRmStorageAccount -Name $Name -ResourceGroupName $ResourceGroupName

if(!$StorageAccount) {
  throw ("Cannot find '{0}' storage account in '{1}' resource group" -f $Name, $ResourceGroupName)
}

$StorageAccountKey = (Get-AzureRmStorageAccountKey -Name $Name -ResourceGroupName $ResourceGroupName)[0].value
$StorageAccountContext = New-AzureStorageContext -StorageAccountName $Name -StorageAccountKey $StorageAccountKey

$StorageAccountContainerName = ($ContainerPath.split('/')[0]).ToLower()

If(!(Get-AzureStorageContainer -Context $StorageAccountContext -Name $StorageAccountContainerName -ErrorAction SilentlyContinue)) {
  throw ("Cannot find '{0}' container in '{1}' storage account at {2} resource group" -f $StorageAccountContainerName, $Name, $ResourceGroupName)
}

$artifactSasToken = New-AzureStorageContainerSASToken -Container $StorageAccountContainerName -Context $StorageAccountContext -Permission (($Permissions | foreach-object { $_[0] }) -join "") -StartTime (Get-Date) -ExpiryTime ((Get-Date).AddHours($Duration))
$artifactsURI = "{0}{1}/" -f $StorageAccount.PrimaryEndpoints.Blob, $ContainerPath.tolower()

if (Test-Path Env:AGENT_MACHINENAME) {
  ## VSTS Context
  Write-Host "##vso[task.setvariable variable=artifactSasToken;issecret=true]$artifactSasToken"
  Write-Host "##vso[task.setvariable variable=artifactsURI;issecret=false]$artifactsURI"
}
else {
  New-Object PSObject -Property @{
    artifactsURI = $artifactsURI
    artifactSasToken = $artifactSasToken
  }
}