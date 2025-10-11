@echo off
echo Setting JAVA_HOME to JDK 11...

REM Force JAVA_HOME to JDK 11 only
if exist "C:\Program Files\Java\jdk-11" (
    set JAVA_HOME=C:\Program Files\Java\jdk-11
) else (
    echo JDK 11 not found at C:\Program Files\Java\jdk-11
    echo Please install JDK 11 (not JDK 17/21).
    pause
    exit /b 1
)

echo JAVA_HOME set to: %JAVA_HOME%
setx JAVA_HOME "%JAVA_HOME%" /M
set PATH=%JAVA_HOME%\bin;%PATH%
setx PATH "%PATH%" /M
echo JAVA_HOME and PATH updated successfully!
echo Restart your terminal/IDE for changes to take effect.
pause
