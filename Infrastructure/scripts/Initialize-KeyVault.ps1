param 
(
  [Parameter(Mandatory)]
  [string] $KeyVaultName,
  [Parameter(Mandatory)]
  [string] $Product,
  [Parameter(Mandatory)]
  [String] $Application,
  [string] $Prefix = "ClientRequestUniversalEntitiesConnectionString",
  [Parameter(Mandatory)]
  [ValidateScript(
    {
      if(!([System.Text.RegularExpressions.RegEx]::IsMatch($_,"(Dev|QA|UAT|Prod)\d?\d?"))) {
        throw "Environment name should begin with Dev, QA, UAT or Prod followed with up to two digits (not required)"
      }
      else {
        return $true
      }
    }
  )]
  [string] $EnvironmentName,
  [switch] $BlobEncryptionSecret
)

function New-SWRandomPassword {
    <#
    .Synopsis
       Generates one or more complex passwords designed to fulfill the requirements for Active Directory
    .DESCRIPTION
       Generates one or more complex passwords designed to fulfill the requirements for Active Directory
    .EXAMPLE
       New-SWRandomPassword
       C&3SX6Kn

       Will generate one password with a length between 8  and 12 chars.
    .EXAMPLE
       New-SWRandomPassword -MinPasswordLength 8 -MaxPasswordLength 12 -Count 4
       7d&5cnaB
       !Bh776T"Fw
       9"C"RxKcY
       %mtM7#9LQ9h

       Will generate four passwords, each with a length of between 8 and 12 chars.
    .EXAMPLE
       New-SWRandomPassword -InputStrings abc, ABC, 123 -PasswordLength 4
       3ABa

       Generates a password with a length of 4 containing atleast one char from each InputString
    .EXAMPLE
       New-SWRandomPassword -InputStrings abc, ABC, 123 -PasswordLength 4 -FirstChar abcdefghijkmnpqrstuvwxyzABCEFGHJKLMNPQRSTUVWXYZ
       3ABa

       Generates a password with a length of 4 containing atleast one char from each InputString that will start with a letter from 
       the string specified with the parameter FirstChar
    .OUTPUTS
       [String]
    .NOTES
       Written by Simon Wåhlin, blog.simonw.se
       I take no responsibility for any issues caused by this script.
    .FUNCTIONALITY
       Generates random passwords
    .LINK
       http://blog.simonw.se/powershell-generating-random-password-for-active-directory/
   
    #>
    [CmdletBinding(DefaultParameterSetName='FixedLength',ConfirmImpact='None')]
    [OutputType([String])]
    Param
    (
        # Specifies minimum password length
        [Parameter(Mandatory=$false,
                   ParameterSetName='RandomLength')]
        [ValidateScript({$_ -gt 0})]
        [Alias('Min')] 
        [int]$MinPasswordLength = 8,
        
        # Specifies maximum password length
        [Parameter(Mandatory=$false,
                   ParameterSetName='RandomLength')]
        [ValidateScript({
                if($_ -ge $MinPasswordLength){$true}
                else{Throw 'Max value cannot be lesser than min value.'}})]
        [Alias('Max')]
        [int]$MaxPasswordLength = 12,

        # Specifies a fixed password length
        [Parameter(Mandatory=$false,
                   ParameterSetName='FixedLength')]
        [ValidateRange(1,2147483647)]
        [int]$PasswordLength = 8,
        
        # Specifies an array of strings containing charactergroups from which the password will be generated.
        # At least one char from each group (string) will be used.
        [String[]]$InputStrings = @('abcdefghijkmnpqrstuvwxyz', 'ABCEFGHJKLMNPQRSTUVWXYZ', '0123456789', '!#%&'),

        # Specifies a string containing a character group from which the first character in the password will be generated.
        # Useful for systems which requires first char in password to be alphabetic.
        [String] $FirstChar,
        
        # Specifies number of passwords to generate.
        [ValidateRange(1,2147483647)]
        [int]$Count = 1
    )
    Begin {
        Function Get-Seed{
            # Generate a seed for randomization
            $RandomBytes = New-Object -TypeName 'System.Byte[]' 4
            $Random = New-Object -TypeName 'System.Security.Cryptography.RNGCryptoServiceProvider'
            $Random.GetBytes($RandomBytes)
            [BitConverter]::ToUInt32($RandomBytes, 0)
        }
    }
    Process {
        For($iteration = 1;$iteration -le $Count; $iteration++){
            $Password = @{}
            # Create char arrays containing groups of possible chars
            [char[][]]$CharGroups = $InputStrings

            # Create char array containing all chars
            $AllChars = $CharGroups | ForEach-Object {[Char[]]$_}

            # Set password length
            if($PSCmdlet.ParameterSetName -eq 'RandomLength')
            {
                if($MinPasswordLength -eq $MaxPasswordLength) {
                    # If password length is set, use set length
                    $PasswordLength = $MinPasswordLength
                }
                else {
                    # Otherwise randomize password length
                    $PasswordLength = ((Get-Seed) % ($MaxPasswordLength + 1 - $MinPasswordLength)) + $MinPasswordLength
                }
            }

            # If FirstChar is defined, randomize first char in password from that string.
            if($PSBoundParameters.ContainsKey('FirstChar')){
                $Password.Add(0,$FirstChar[((Get-Seed) % $FirstChar.Length)])
            }
            # Randomize one char from each group
            Foreach($Group in $CharGroups) {
                if($Password.Count -lt $PasswordLength) {
                    $Index = Get-Seed
                    While ($Password.ContainsKey($Index)){
                        $Index = Get-Seed                        
                    }
                    $Password.Add($Index,$Group[((Get-Seed) % $Group.Count)])
                }
            }

            # Fill out with chars from $AllChars
            for($i=$Password.Count;$i -lt $PasswordLength;$i++) {
                $Index = Get-Seed
                While ($Password.ContainsKey($Index)){
                    $Index = Get-Seed                        
                }
                $Password.Add($Index,$AllChars[((Get-Seed) % $AllChars.Count)])
            }
            Write-Output -InputObject $(-join ($Password.GetEnumerator() | Sort-Object -Property Name | Select-Object -ExpandProperty Value))
        }
    }
}

$dbUserName = "{0}{1}{2}user" -f $Product.ToLower(), $Application, $EnvironmentName.ToLower()
$dbUserSecretName = "{0}UserID" -f $Prefix
$dbPasswordSecretName = "{0}Password" -f $Prefix
$blobEncryptionSecretName = "{0}-blob-encryption" -f $Product.ToLower()

if(!(Get-AzureRmKeyVault -VaultName $KeyVaultName)) {
  throw "KeyVault ($KeyVaultName) cannot be found. Make sure it exists"
}

$DBUserSecret = Get-AzureKeyVaultSecret -VaultName $keyVaultName -Name $dbUserSecretName
if($DBUserSecret)
{
    Write-Host "Secret: $dbUserSecretName already exists"
}
else 
{
    $secUserName = $dbUserName | ConvertTo-SecureString -AsPlainText -Force
    Set-AzureKeyVaultSecret -VaultName $keyVaultName -Name $dbUserSecretName -SecretValue $secUserName
}
"VSTS Variable API_DBUserName is now = $dbUserName"
Write-Host "##vso[task.setvariable variable=API_DBUserName]$dbUserName"

$DBPasswordSecret = Get-AzureKeyVaultSecret -VaultName $keyVaultName -Name $dbPasswordSecretName
if($DBPasswordSecret)
{
    Write-Host "Secret: $dbPasswordSecretName already exists"
    $NewPassword = $DBPasswordSecret.SecretValueText
}
else 
{
    $NewPassword =  New-SWRandomPassword -PasswordLength 20
    $secPassword = $NewPassword | ConvertTo-SecureString -AsPlainText -Force
    Set-AzureKeyVaultSecret -VaultName $keyVaultName -Name $dbPasswordSecretName -SecretValue $secPassword
}
"VSTS Variable API_DBUserPassword is now = {0}" -f ("*" * $NewPassword.Length)
Write-Host "##vso[task.setvariable variable=API_DBUserPassword;issecret=true]$NewPassword"

if($BlobEncryptionSecret)
{
	$Key = Get-AzureKeyVaultKey -VaultName $keyVaultName -Name $blobEncryptionSecretName
	
	if(!$Key)
	{
		Write-Host "Adding Key: $blobEncryptionSecretName to KeyVault: $KeyVaultName"
		Add-AzureKeyVaultKey -VaultName $keyVaultName -Name $blobEncryptionSecretName -Destination Software
		Write-Host (Get-AzureKeyVaultKey -VaultName $keyVaultName -Name $blobEncryptionSecretName).Id
	}
	else
	{
		Write-Host "Key: $blobEncryptionSecretName Already Exists"
	}
}