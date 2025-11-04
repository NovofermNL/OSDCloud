pushd %~dp0
:INS_RTL8111
pnputil -i -a "%~dp0Drivers\*.INF"


:success
echo installation_pass >> c:\windows\temp\%driver_name%.log
goto end

:install_fail
echo %driver_name%_installation_fail >> c:\windows\temp\install_fail.log

:end
@echo Done
