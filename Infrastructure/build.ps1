$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$artifactARMTemplatesFolder = "$here\output\armtemplates"
$artifactScriptsFolder = "$here\output\scripts"

"Cleaning Up Output folder ($($here)\output)"
if (Test-Path "$here\output" ) {
  Get-ChildItem "$here\output" -Recurse | Remove-Item -Force -Recurse
}

"Creating folder structure"
[array]($artifactARMTemplatesFolder, $artifactScriptsFolder) | foreach-object {
  if (-not (Test-Path $_)) {
    New-Item -Path $_ -ItemType Directory -Force | Out-Null
  }
}

"Copying all .json ARM templates"
get-childitem -Path "$here" -Filter *.json -Force | Copy-Item -Destination $artifactARMTemplatesFolder -Force
get-childitem -Path "$here\linked" -Filter *.json -Force | Copy-Item -Destination $artifactARMTemplatesFolder -Force

if(Test-Path "$here\Scripts"){
  "Copying Scripts folder"
  get-childitem -Path "$here\scripts" -Recurse -Force | Copy-Item -Destination $artifactScriptsFolder -Force 
}

"Done! ($($here)\output)"