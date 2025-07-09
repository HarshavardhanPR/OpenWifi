@echo off

REM Define Vivado Installation Directory
set XILINX_DIR=D:\Apps\v_log\Vivado\2021.1

REM Define Path to your system_project.tcl file
set TCL_FILENAME=openofdm_rx.tcl

REM Define Project-Specific Arguments (BOARD_NAME and NUM_CLK_PER_US)
REM IMPORTANT: Adjust these values to match your target board and clock frequency!
set BOARD_NAME=zed_fmcs2
set CLK_FREQ_MHZ=100

REM Define additional optional arguments for the TCL script (if needed)
REM For openofdm_rx, the 3rd argument is for SAMPLE_FILE. Uncomment and set if you need.
REM set ARG3_OPT="C:/path/to/your/sample_file.txt"
REM set ARG4_OPT=""
REM set ARG5_OPT=""
REM set ARG6_OPT=""
REM set ARG7_OPT=""

echo.
echo --- Starting Vivado Project Creation ---
echo Vivado Directory: %XILINX_DIR%
echo TCL File: %TCL_FILENAME%
echo Board Name: %BOARD_NAME%
echo Clock Frequency: %CLK_FREQ_MHZ%
echo.

REM Check if Vivado installation directory exists
if not exist "%XILINX_DIR%\settings64.bat" (
    echo Error: Vivado 2021.1 installation not found at "%XILINX_DIR%".
    echo Please correct XILINX_DIR in this script.
    goto :eof
)

REM Check if TCL file exists
if not exist "%TCL_FILENAME%" (
    echo Error: TCL file "%TCL_FILENAME%" not found.
    echo Please ensure you are running this script from the correct directory or fix TCL_FILENAME path.
    goto :eof
)

REM Source Vivado settings and run the TCL script
call "%XILINX_DIR%\settings64.bat"
vivado -source %TCL_FILENAME% -tclargs %BOARD_NAME% %CLK_FREQ_MHZ% %ARG3_OPT% %ARG4_OPT% %ARG5_OPT% %ARG6_OPT% %ARG7_OPT%

echo.
echo --- Vivado Project Creation Finished ---
pause