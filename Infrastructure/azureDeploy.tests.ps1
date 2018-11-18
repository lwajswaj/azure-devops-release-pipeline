Param(
  [string] $FilePath = "*.json"
)

Function Test-AzureJson {
  Param(
    [string]
    $FilePath
  )

  Context "JSON Structure" {
    
    $templateProperties = (get-content "$FilePath" -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue)

    It "should be less than 1 Mb" {
      Get-Item $FilePath | Select-Object -ExpandProperty Length | Should -BeLessOrEqual 1073741824
    }

    It "Converts from JSON" {
      $templateProperties | Should -Not -BeNullOrEmpty
    }

    It "should have a `$schema section" {
      $templateProperties."`$schema" | Should -Not -BeNullOrEmpty
    }

    It "should have a contentVersion section" {
      $templateProperties.contentVersion | Should -Not -BeNullOrEmpty
    }

    It "should have a parameters section" {
      $templateProperties.parameters | Should -Not -BeNullOrEmpty
    }

    It "should have less than 256 parameters" {
      $templateProperties.parameters.Length | Should -BeLessOrEqual 256
    }

    It "might have a variables section" {
      $result = $null -ne $templateProperties.variables
      if ($result) {
        $result | Should -Be $true
      }
      else {
        Set-TestInconclusive -Message "Section isn't mandatory, however it's a group practice to have it defined"
      }
    }
    
    It "must have a resources section" {
      $templateProperties.resources | Should -Not -BeNullOrEmpty
    }

    It "might have an outputs section" {
      $result = $null -ne $templateProperties.outputs
      if ($result) {
        $result | Should -Be $true
      }
      else {
        Set-TestInconclusive -Message "Section isn't mandatory, however it's a group practice to have it defined"
      }
    }
  }

  ## Functions validations
  $jsonMainTemplate = Get-Content "$FilePath"
  $objMainTemplate = $jsonMainTemplate | ConvertFrom-Json -ErrorAction SilentlyContinue
  $objMainTemplateWithoutFunctions=$objMainTemplate | Select-Object ($objMainTemplate.psobject.properties.Name | Where-Object { $_ -ne "functions" }) -ErrorAction "SilentlyContinue"
  
  $parametersUsage = [System.Text.RegularExpressions.RegEx]::Matches(($objMainTemplateWithoutFunctions | Out-String), "parameters(\(\'\w*\'\))") | Select-Object -ExpandProperty Value -Unique
  Context "Referenced Parameters (excluding functions)" {
    ForEach($parameterUsage In $parametersUsage)
    {
      $parameterUsage = $parameterUsage.SubString($parameterUsage.IndexOf("'") + 1).Replace("')","")
    
      It "should have a parameter called $parameterUsage" {
        $objMainTemplate.parameters.$parameterUsage | Should -Not -Be $null
      }
    }
  }

  $variablesUsage = [System.Text.RegularExpressions.RegEx]::Matches(($objMainTemplateWithoutFunctions | Out-String), "variables(\(\'\w*\'\))") | Select-Object -ExpandProperty Value -Unique
  [array]$variables=$null
  $variables+=$objMainTemplate.variables.psobject.Properties.name | Where-Object { $_ -ne "copy" }
  $variables+=$objMainTemplate.variables.copy | select -expandproperty name
  Context "Referenced Variables (excluding functions)" {
    ForEach($variableUsage In $variablesUsage)
    {
      $variableUsage = $variableUsage.SubString($variableUsage.IndexOf("'") + 1).Replace("')","")
      It "should have a variable called $variableUsage" {
        $variables -contains $variableUsage | Should -Be $True
      }
    }
  }


  ## Functions validations
  $objMainTemplateWithFunctions=$objMainTemplate | Select-Object "functions"
  $functionMembers=$objMainTemplateWithFunctions.functions.members.psobject.properties.name
  foreach ($functionMember in $functionMembers) {
    Context "Referenced member $FunctionMember at functions" {
      $parametersUsage=[System.Text.RegularExpressions.RegEx]::Matches(($objMainTemplateWithFunctions.functions.members.$FunctionMember.output | out-string), "parameters(\(\'\w*\'\))") | Select-Object -ExpandProperty Value -Unique 
      foreach ($parameterUsage in $parametersUsage) {
        $parameterUsage = $parameterUsage.SubString($parameterUsage.IndexOf("'") + 1).Replace("')","")
        It "should have a parameter called ""$parameterUsage""" {
          $objMainTemplateWithFunctions.functions.members.$FunctionMember.parameters | where-object { $_.name -eq $parameterUsage } | Should -Not -Be $null
        }

        It "parameter ""$parameterUsage"" should not have a default value" {
          ($objMainTemplateWithFunctions.functions.members.$FunctionMember.parameters | where-object { $_.name -eq $parameterUsage }).defaultValue | Should -Be $null
        }
      }

      It "should not have a variables section" {
        $objMainTemplateWithFunctions.functions.members.$FunctionMember.variables | Should -Be $null
      }

      It "should not contains a ""variables"" reference" {
        $objMainTemplateWithFunctions.functions.members.$FunctionMember.output -match "variables" | Should -Be $False
      }

      It "should not contains a ""reference"" function" {
        $objMainTemplateWithFunctions.functions.members.$FunctionMember.output -match "reference" | Should -Be $False
      }

      It "should not contains a ""user-defined function""" {
        $objMainTemplateWithFunctions.functions.members.$FunctionMember.output -match "function" | Should -Be $False
      }
    }
    
  }
  ## End Functions validations

  Context "Missing opening or closing square brackets" {
    For($i=0;$i -lt $jsonMainTemplate.Length;$i++) {
      $Matches = [System.Text.RegularExpressions.Regex]::Matches($jsonMainTemplate[$i],"\"".*\""")

      ForEach($Match In $Matches) {
        $PairCharNumber = ($Match.Value.Length - $Match.Value.Replace("[","").Replace("]","").Length) % 2

        if($PairCharNumber -ne 0) {
          Write-Host $Match.Value
          It "should have same amount of opening and closing square brackets (Line $($i + 1))" {
            $PairCharNumber | Should -Be 0
          }

          break
        }
      }
    }
  }

  Context "Missing opening or closing parenthesis" {
    For($i=0;$i -lt $jsonMainTemplate.Length;$i++) {
      $Matches = [System.Text.RegularExpressions.Regex]::Matches($jsonMainTemplate[$i],"\"".*\""")

      ForEach($Match In $Matches) {
        $PairCharNumber = ($Match.Value.Length - $Match.Value.Replace("(","").Replace(")","").Length) % 2

        if($PairCharNumber -ne 0) {
          It "should have same amount of opening and closing parenthesis (Line $($i + 1))" {
            $PairCharNumber | Should -Be 0
          }

          break
        }
      }
    }
  }

  $linkedTemplates = $objMainTemplate.resources | Where-Object -Property Type -IEQ -Value "Microsoft.Resources/deployments"
  
  if($null -ne $linkedTemplates)
  {
    ForEach($linkedTemplate In $linkedTemplates)
    {
      If($null -ne $linkedTemplate.properties.templateLink.uri)
      {
        $linkedTemplateFileName = [System.Text.RegularExpressions.RegEx]::Matches($linkedTemplate.properties.templateLink.uri, "\'\w*\.json\??\'").Value
        $linkedTemplateFileName = $linkedTemplateFileName.SubString($linkedTemplateFileName.IndexOf("'") + 1).Replace("'","").Replace('?','')

        Context "linked Template: $linkedTemplateFileName" {
          It "should exist the linked template at $WorkingFolder\linked\$linkedTemplateFileName" {
            "$WorkingFolder\linked\$linkedTemplateFileName" | Should -Exist
          }

          if(Test-Path "$WorkingFolder\linked\$linkedTemplateFileName")
          {
            $linkedParameters = (Get-Content "$WorkingFolder\linked\$linkedTemplateFileName" | ConvertFrom-Json).parameters
            $requiredlinkedParameters = $linkedParameters | Get-Member -MemberType NoteProperty | Where-Object -FilterScript {$null -eq $linkedParameters.$($_.Name).defaultValue} | ForEach-Object -Process {$_.Name}

            
            ForEach($requiredlinkedParameter In $requiredlinkedParameters)
            {
              It "should define the paramter: $requiredlinkedParameter" {
                $linkedTemplate.properties.parameters.$requiredlinkedParameter | Should -Not -BeNullOrEmpty
              }

              It "should set a value for $requiredlinkedParameter" {
                $linkedTemplate.properties.parameters.$requiredlinkedParameter.Value | Should -Not -BeNullOrEmpty
              }
            }
          }
        }
      }
    }
  }
}

Function Test-PowershellScript {
  Param(
    [string]$FilePath
  )

  It "is a valid Powershell Code"{
    $psFile = Get-Content -Path $FilePath -ErrorAction Stop
    $errors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize($psFile, [ref]$errors)
    $errors.Count | Should -Be 0
  }
}

$WorkingFolder = Split-Path -Parent $MyInvocation.MyCommand.Path

if($FilePath -notmatch "\*") {
  $armTemplates = Get-ChildItem $FilePath | Where-Object -FilterScript {(Get-Content -Path $_.FullName -Raw) -ilike "*schema.management.azure.com/*/deploymentTemplate.json*"}
}
else {
  $armTemplates = Get-ChildItem -Path "$WorkingFolder" -Filter $FilePath -recurse -File | Where-Object -FilterScript {(Get-Content -Path $_.FullName -Raw) -ilike "*schema.management.azure.com/*/deploymentTemplate.json*"}
}

$powershellScripts = Get-ChildItem -Path "$WorkingFolder" -Filter "*.ps1" -Exclude "*.tests.*" -Recurse -File

#region ARM Template
ForEach($armTemplate In $armTemplates)
{
  Describe $armTemplate.FullName.Replace($WorkingFolder,"") {
    Test-AzureJson -FilePath $armTemplate.FullName
  }
  $jsonMainTemplate = Get-Content $armTemplate.FullName
  $objMainTemplate = $jsonMainTemplate | ConvertFrom-Json -ErrorAction SilentlyContinue
  $mainlinkedTemplates = $null

  If($objMainTemplate.resources | Where-Object -Property Type -IEQ -Value "Microsoft.Resources/deployments")
  {
    $mainlinkedTemplates = [System.Text.RegularExpressions.RegEx]::Matches($($objMainTemplate.resources | Where-Object -Property Type -IEQ -Value "Microsoft.Resources/deployments" | ForEach-Object -Process {$_.properties.templateLink.uri}), "\'\w*\.json\??\'") | Select-Object -ExpandProperty Value -Unique
  }

  ForEach($linkedTemplate In $mainlinkedTemplates)
  {
    $linkedTemplate = $linkedTemplate.SubString($linkedTemplate.IndexOf("'") + 1).Replace("'","").Replace('?','')
    
    Describe "linked: $WorkingFolder\linked\$linkedTemplate" {
      It "Should exist" {
        "$WorkingFolder\linked\$linkedTemplate" | Should -Exist
      }

      if(Test-Path $WorkingFolder\linked\$linkedTemplate)
      {
        Test-AzureJson -FilePath $WorkingFolder\linked\$linkedTemplate
      }
    }
  }
}
#endregion

#region Powershell Scripts
ForEach($powershellScript In $powershellScripts) {
  Describe $powershellScript.FullName.Replace($WorkingFolder,"") {
    Test-PowershellScript -FilePath $powershellScript.FullName
  }
}
#endregion