# CMTrace-Setup.ps1
# Downloadt cmtrace.exe vanaf GitHub en plaatst het in System32.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Output "CMTrace installatie gestart: $((Get-Date).ToString('HH:mm:ss'))"

$Destination = "C:\Windows\System32\cmtrace.exe"
$Url = "https://raw.githubusercontent.com/NovofermNL/OSDCloud/main/Files/cmtrace.exe"

if (!(Test-Path $Destination)) {
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
        Write-Output "CMTrace succesvol gedownload naar: $Destination"
    }
    catch {
        Write-Output "FOUT tijdens downloaden van CMTrace: $($_.Exception.Message)"
    }
}
else {
    Write-Output "CMTrace bestaat al in System32, downloaden overgeslagen."
}

Write-Output "CMTrace installatie voltooid: $((Get-Date).ToString('HH:mm:ss'))"
exit 0
