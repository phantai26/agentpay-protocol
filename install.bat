@echo off
REM AgentPay Protocol - Windows Installation Script
REM Run this in Command Prompt or PowerShell

echo ==================================================
echo AgentPay Protocol - Installation (Windows)
echo ==================================================
echo.

REM Check Node.js
echo Checking prerequisites...
echo.

where node >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Node.js not found!
    echo Please install from: https://nodejs.org/
    pause
    exit /b 1
) else (
    echo [OK] Node.js installed
)

where npm >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] npm not found!
    pause
    exit /b 1
) else (
    echo [OK] npm installed
)

where python >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Python not found!
    echo Please install from: https://python.org/
    pause
    exit /b 1
) else (
    echo [OK] Python installed
)

where pip >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] pip not found!
    pause
    exit /b 1
) else (
    echo [OK] pip installed
)

echo.
echo ==================================================
echo Installing Smart Contract Dependencies
echo ==================================================
echo.

cd contracts
if not exist package.json (
    echo [ERROR] package.json not found!
    pause
    exit /b 1
)

echo Installing Node.js packages...
call npm install
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] npm install failed
    pause
    exit /b 1
)
echo [OK] Smart contract dependencies installed!

cd ..
echo.

echo ==================================================
echo Installing Python Dependencies
echo ==================================================
echo.

cd skill
if not exist requirements.txt (
    echo [ERROR] requirements.txt not found!
    pause
    exit /b 1
)

echo Installing Python packages...
pip install -r requirements.txt
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] pip install failed
    pause
    exit /b 1
)
echo [OK] Python dependencies installed!

cd ..
echo.

echo ==================================================
echo Setting Up Environment
echo ==================================================
echo.

if not exist .env (
    if exist .env.example (
        echo Creating .env file...
        copy .env.example .env
        echo [OK] .env file created!
        echo.
        echo [WARNING] Please edit .env and add your PRIVATE_KEY
        echo.
        echo Get testnet tokens from:
        echo   - ETH: https://faucet.quicknode.com/arbitrum/sepolia
        echo   - USDC: https://faucet.circle.com
    ) else (
        echo [ERROR] .env.example not found!
        pause
        exit /b 1
    )
) else (
    echo [INFO] .env file already exists
)

echo.

echo ==================================================
echo Verifying Installation
echo ==================================================
echo.

echo Testing smart contract compilation...
cd contracts
call npx hardhat compile --quiet
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Contract compilation failed
    pause
    exit /b 1
)
echo [OK] Smart contracts compile successfully!

cd ..
echo.

echo Testing Python imports...
cd skill
python -c "from bridge_skill import MultiChainBridgeSkill; print('[OK] Python imports work!')"
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Python import test failed
    pause
    exit /b 1
)

cd ..
echo.

REM Create deployments directory
if not exist contracts\deployments mkdir contracts\deployments
type nul > contracts\deployments\.gitkeep

echo ==================================================
echo Installation Complete!
echo ==================================================
echo.
echo Next steps:
echo.
echo 1. Edit .env file:
echo    notepad .env
echo    - Add your PRIVATE_KEY
echo.
echo 2. Get testnet tokens:
echo    - ETH: https://faucet.quicknode.com/arbitrum/sepolia
echo    - USDC: https://faucet.circle.com
echo.
echo 3. Deploy contracts:
echo    cd contracts
echo    npm run deploy:arbitrum
echo.
echo 4. Run demo:
echo    cd skill
echo    python agentpay_client.py
echo.
echo ==================================================
echo Happy hacking!
echo ==================================================
echo.

pause
