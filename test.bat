@echo off
REM Tests the ALB: 10 HTTPS requests plus a check of the HTTP -> HTTPS redirect.
REM Run from the folder that contains main.tf.

for /f %%u in ('terraform output -raw alb_dns_name') do set URL=%%u

echo Testing https://%URL%
echo.

for /L %%i in (1,1,10) do curl.exe -k -s https://%URL% | findstr /C:"Instance ID"

echo.
echo HTTP redirect check:
curl.exe -s -I http://%URL% | findstr /C:"HTTP" /C:"Location"
