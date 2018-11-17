[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [String]$ResourceGroupName,
    [Parameter(Mandatory)]
    [String]$AppInsightsStorageAccountName,
    [int]$SasTokenExpiryYears = 50
)

Write-Host "ResourceGroupName is now = $ResourceGroupName"
Write-Host "AppInsightsStorageAccountName is now = $AppInsightsStorageAccountName"
Write-Host "SasTokenExpiryYears is now = $SasTokenExpiryYears"

Write-Host "Retrieving Storage Account information"
$StorageInfo = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $AppInsightsStorageAccountName
$storageAccountId = $StorageInfo.ID
$storageLocation = $StorageInfo.Location

Write-Host "storageAccountId is now = $storageAccountId"
Write-Host "storageLocation is now = $storageLocation"

Write-Host "Get AppInsights instances"
$AppInsightsResources = Get-AzureRmApplicationInsights -ResourceGroupName $ResourceGroupName
Write-Host ("Found {0} instance(s)" -f $AppInsightsResources.Length)

foreach($AppInsights in $AppInsightsResources)
{
  Write-Host ("############ Configuring {0} ############" -f $AppInsights.Name)
	$AppInsightsName = $AppInsights.Name
  $containerName = $AppInsights.Name.ToLower().Replace("-","")
  
  Write-Host "AppInsightsName is now = $AppInsightsName"
  Write-Host "containerName is now = $containerName"

	#Check if Storage container exists 
	$currentcontainer = Get-AzureStorageContainer -Name $containerName -ErrorAction SilentlyContinue -Context $StorageInfo.Context

  #If exists, move to next step. If not, create container
  Write-Host "Verifying if '$containerName' container exists...."
	If($currentcontainer)
	{
		Write-Host "It does. Moving to next step"
	}
	else
	{
    Write-Host "It doesn't. Proceeding to create it."
		New-AzureStorageContainer -Name $containerName -Context $StorageInfo.Context
		Write-Host "Created $containerName in $AppInsightsStorageAccountName storage account"
	}

  ################# Configure Continuous Export ###########################
  Write-Host "Verifying if 'Continuous Export' is already configured"
	$ExportRule = Get-AzureRmApplicationInsightsContinuousExport -ResourceGroupName $ResourceGroupName -Name $AppInsightsName -ErrorAction SilentlyContinue

	If($ExportRule)
	{
		Write-Host "The export is already defined."
	}
	else
	{
    Write-Host "The export is NOT already defined. Defining it..."

    Write-Host "Generating SAS Token..."
    $containerSasToken = New-AzureStorageContainerSASToken -Name $containerName -ExpiryTime (Get-Date).AddYears($SasTokenExpiryYears) -Permission w -Context $StorageInfo.Context
    Write-Host "containerSasToken is now = $containerSasToken"

    $StorageSASUri = ("{0}{1}{2}" -f $StorageInfo.Context.BlobEndPoint, $containerName, $containerSasToken)
    Write-Host "StorageSASUri is now = $StorageSASUri"

		New-AzureRmApplicationInsightsContinuousExport -ResourceGroupName $ResourceGroupName -Name $AppInsightsName -DocumentType "Request","Trace", "Custom Event" -StorageAccountId $storageAccountId -StorageLocation $storageLocation -StorageSASUri $StorageSASUri -Verbose
    Write-Host "The export rule has been created"
    
    Write-Host "Taking a 15 second break..."
    Start-Sleep -Seconds 15
    Write-Host "Ready to keep going"
	}
}


# End - Actual script -------------------------------------------------------------------------------------------------------------------------------