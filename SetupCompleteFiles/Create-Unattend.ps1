$OSDrive = (Get-Volume | Where-Object {
    $_.DriveLetter -and (Test-Path ("{0}:\Windows\System32" -f $_.DriveLetter))
} | Select-Object -First 1).DriveLetter
$OSRoot = "$OSDrive`:"

$UnattendXml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <InputLocale>0409:00020409</InputLocale>
      <UserLocale>nl-NL</UserLocale>
    </component>
  </settings>
</unattend>
"@

$Panther = Join-Path $OSRoot 'Windows\Panther'
$UnattendPath = Join-Path $Panther 'Unattend.xml'
$UnattendXml | Out-File -FilePath $UnattendPath -Encoding utf8 -Force

Use-WindowsUnattend -Path $OSRoot -UnattendPath $UnattendPath
