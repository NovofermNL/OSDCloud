[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ===== SYSTEEMINSTELLINGEN =====

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\USB" -Name "DisableSelectiveSuspend" -Type DWord -Value 1 -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "SearchOnTaskbarMode" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableCloudOptimizedContent" -Type DWord -Value 1 -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows" -Name "CEIPEnable" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Office\16.0\Outlook\AutoDiscover" -Name "ExcludeHttpsRootDomain" -Type DWord -Value 1 -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "HideRecommendedSection" -Type DWord -Value 1 -Force
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "ForceClassicControlPanel" -Type DWord -Value 1 -Force
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Type DWord -Value 0 -Force

$veBase = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
Set-ItemProperty -Path "$veBase\ControlAnimations" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\AnimateMinMax" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\TaskbarAnimations" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\DWMAeroPeekEnabled" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\MenuAnimation" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\TooltipAnimation" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\SelectionFade" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\DWMSaveThumbnailEnabled" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\CursorShadow" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\ListviewShadow" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\ThumbnailsOrIcon" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\ListviewAlphaSelect" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\DragFullWindows" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\ComboBoxAnimation" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\FontSmoothing" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\ListBoxSmoothScrolling" -Name "DefaultValue" -Type DWord -Value 0 -Force
Set-ItemProperty -Path "$veBase\DropShadow" -Name "DefaultValue" -Type DWord -Value 0 -Force

# ===== DEFAULT USER PROFIEL =====
$DefaultUserHive = "C:\Users\Default\NTUSER.DAT"
$MountPoint = "HKU\DefUser"

# Load NTUSER.DAT
reg load $MountPoint $DefaultUserHive | Out-Null

# ShowTaskViewButton
Set-ItemProperty -Path "Registry::$MountPoint\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
    -Name "ShowTaskViewButton" -Type DWord -Value 0

# VisualFXSetting (normaal onder HKCU → hier Default User)
Set-ItemProperty -Path "Registry::$MountPoint\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" `
    -Name "VisualFXSetting" -Type DWord -Value 2

# AutoEndTasks (REG_SZ)
New-Item -Path "Registry::$MountPoint\Control Panel\Desktop" -Force | Out-Null
Set-ItemProperty -Path "Registry::$MountPoint\Control Panel\Desktop" -Name "AutoEndTasks" -Type String -Value "1"

# Hive ontkoppelen
reg unload $MountPoint | Out-Null

Write-Output "Klaar met toepassen van systeem- en default user-instellingen."
exit 0
