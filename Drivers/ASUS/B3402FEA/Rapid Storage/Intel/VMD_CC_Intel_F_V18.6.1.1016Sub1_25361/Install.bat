rem ===================
rem   IRST V1.2
rem ===================
pushd %~dp0
SET  APP_NAME= Intel RST Driver
SET  INF_PATH=%~dp0RST
SET  RETURN_CODE=0
SET  APP_LOG=C:\Windows\logs\iRST.log
SET  inbox_VMD=


IF NOT EXIST C:\Windows\logs\ MD C:\Windows\logs\
REM ===================================
ECHO [%TIME%] == The Installation of %APP_NAME%== > %APP_LOG%

:ChkOEM1
for /f %%i in ( 'dir /b C:\Windows\INF\oem*.inf' ) do call :findinbox %%i
goto :ChkREG

:findinbox
set oemstr=%1
find /i "CatalogFile=iaStorVD.cat" C:\Windows\INF\%oemstr%
if %errorlevel%==0 SET inbox_VMD=%oemstr%
goto :eof

:ChkREG
:: Check Registry first
reg query "HKLM\SYSTEM\ControlSet001\Services\iaStorAC\Parameters\Device\NvmeApstEnabled" >> %APP_LOG% 2>&1
if /i not "%errorlevel%"=="0" goto :Ins_Drv
reg delete "HKLM\SYSTEM\ControlSet001\Services\iaStorAC\Parameters\Device\NvmeApstEnabled" /f >> %APP_LOG% 2>&1
timeout /t 5 /nobreak

:Ins_Drv
REM Run Silent Install Command:
rem ================ install iaStorVD.inf ===========================
echo "find inf file %INF_PATH%\iaStorVD.inf, start to install ..." >> %APP_LOG%
start /w devcon.exe update "%INF_PATH%\iaStorVD.inf" "PCI\VEN_8086&DEV_9A0B&SUBSYS_00008086" >> %APP_LOG% 2>&1
if /i not %errorlevel%==0 set RETURN_CODE=1


:UN_Drv
REM Run Silent UnInstall Command:
rem ================ Uninstall inbox iaStorVD.inf ===========================
echo delete %inbox_VMD% ... >> %APP_LOG%
start /w devcon.exe -f dp_delete %inbox_VMD% >> %APP_LOG% 2>&1
if exist C:\Windows\INF\%inbox_VMD% set RETURN_CODE=1
echo RETURN_CODE is %errorlevel%  >> %APP_LOG%


:END
start /w pnputil /add-driver %INF_PATH%\*.inf /install >> %APP_LOG% 2>&1
if /i not %errorlevel%==0 set RETURN_CODE=1
echo RETURN_CODE is %errorlevel%  >> %APP_LOG%
popd
exit /b %RETURN_CODE%