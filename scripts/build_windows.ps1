# ==============================================================================
# Sen Việt (VieLotusIM) - Windows Native TSF Build & Packaging Script (PowerShell)
# Builds Universal x64 + ARM64 VieLotusTIP.dll & Inno Setup Installers
# ==============================================================================

param (
    [string]$Configuration = "Release",
    [string]$Version = "1.1.1",
    [ValidateSet("x64", "arm64", "all")]
    [string]$Arch = "all",
    [switch]$SkipTests = $false
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = (Resolve-Path "$scriptDir\..").Path
$windowsDir = "$rootDir\scripts\windows"
$distWindowsDir = "$rootDir\dist\windows"
$binStagingDir = "$windowsDir\bin"
$tsfSourceDir = "$rootDir\CrossPlatform\windows-tsf"

Write-Host "🌸 === Sen Việt (VieLotusIM): Build Windows Native TSF TIP ($Arch) ===" -ForegroundColor Cyan
Write-Host "📂 Thư mục gốc: $rootDir"

$isOpenCorePublic = -not (Test-Path "$rootDir\Sources\VieLotusCore")

# 1. Create staging directories for Inno Setup
Write-Host "📁 Bước 1: Chuẩn bị thư mục staging ($binStagingDir)..." -ForegroundColor Green
if (Test-Path $binStagingDir) {
    Remove-Item "$binStagingDir\*" -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $binStagingDir | Out-Null
New-Item -ItemType Directory -Force -Path "$binStagingDir\x64" | Out-Null
New-Item -ItemType Directory -Force -Path "$binStagingDir\arm64" | Out-Null
New-Item -ItemType Directory -Force -Path $distWindowsDir | Out-Null

# Bundle typing-modes.yml resource
$coreTypingModes = if (Test-Path "$rootDir\Sources\VieLotusCore\Resources\typing-modes.yml") {
    "$rootDir\Sources\VieLotusCore\Resources\typing-modes.yml"
} elseif (Test-Path "$rootDir\Resources\typing-modes.yml") {
    "$rootDir\Resources\typing-modes.yml"
} else {
    $null
}
if ($coreTypingModes) {
    $coreResourcesDst = "$binStagingDir\VietLotusIM_VieLotusCore.resources"
    New-Item -ItemType Directory -Force -Path $coreResourcesDst | Out-Null
    Copy-Item $coreTypingModes -Destination $coreResourcesDst -Force
    Write-Host "   📦 Đã copy typing-modes.yml -> $coreResourcesDst"
}

# 2. Optional: Build Swift C-ABI Library if full source & Swift toolchain are present
$hostArch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
if (-not $isOpenCorePublic -and (Get-Command swift -ErrorAction SilentlyContinue)) {
    Write-Host "📦 Bước 2: Biên dịch VieLotusCAPI.dll ($hostArch) bằng Swift 6..." -ForegroundColor Green
    Set-Location $rootDir
    swift build -c release --product VieLotusCAPI
    if ($LASTEXITCODE -eq 0) {
        if (-not $SkipTests) {
            Write-Host "🧪 Bước 2b: Chạy unit tests (CAPITests) trên Windows..." -ForegroundColor Green
            swift test --filter "CAPITests"
            if ($LASTEXITCODE -ne 0) {
                Write-Error "❌ Lỗi: swift test thất bại (exit code $LASTEXITCODE)."
                exit $LASTEXITCODE
            }
        }
        $builtCoreDll = Get-ChildItem -Path "$rootDir\.build" -Filter "VieLotusCAPI.dll" -Recurse |
            Sort-Object { $_.FullName -notmatch 'release' } |
            Select-Object -First 1
        if ($builtCoreDll) {
            Copy-Item $builtCoreDll.FullName -Destination "$binStagingDir\VieLotusCAPI.dll" -Force
            Write-Host "   ✅ Đã copy: $($builtCoreDll.FullName) -> $binStagingDir\VieLotusCAPI.dll"
        }
    }
}

# 3. Build Windows TSF TIP DLL (VieLotusTIP.dll) for x64 and ARM64 via CMake & MSVC (/MT static CRT)
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Error "❌ Lỗi: Không tìm thấy 'cmake'."
    exit 1
}

$archesToBuild = if ($Arch -eq "all") { @("x64", "arm64") } else { @($Arch) }
foreach ($targetArch in $archesToBuild) {
    $cmakeArch = if ($targetArch -eq "arm64") { "ARM64" } else { "x64" }
    Write-Host "🔨 Bước 3 ($targetArch): Biên dịch VieLotusTIP.dll ($cmakeArch, C++20 Static /MT COM In-Process)..." -ForegroundColor Green
    $tsfBuildDir = "$rootDir\build-tsf-$targetArch"
    cmake -B $tsfBuildDir -S $tsfSourceDir -A $cmakeArch -DCMAKE_BUILD_TYPE=$Configuration
    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Lỗi: cmake configure VieLotusTIP ($targetArch) thất bại (exit code $LASTEXITCODE)."
        exit $LASTEXITCODE
    }
    cmake --build $tsfBuildDir --config $Configuration
    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Lỗi: cmake build VieLotusTIP ($targetArch) thất bại (exit code $LASTEXITCODE)."
        exit $LASTEXITCODE
    }

    $builtTipDll = Get-ChildItem -Path $tsfBuildDir -Filter "VieLotusTIP.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($builtTipDll) {
        Copy-Item $builtTipDll.FullName -Destination "$binStagingDir\$targetArch\VieLotusTIP.dll" -Force
        Copy-Item $builtTipDll.FullName -Destination "$binStagingDir\VieLotusTIP.dll" -Force
        Copy-Item $builtTipDll.FullName -Destination "$distWindowsDir\VieLotusTIP-$targetArch.dll" -Force
        Write-Host "   ✅ Đã copy: $($builtTipDll.FullName) -> $binStagingDir\$targetArch\VieLotusTIP.dll"
    } else {
        Write-Error "❌ Lỗi: Không tìm thấy VieLotusTIP.dll ($targetArch) sau khi build."
        exit 1
    }
}

# Also try building the opposite architecture so the Inno Setup installer is always Universal (x64 + ARM64)
foreach ($extraArch in @("x64", "arm64")) {
    if (-not (Test-Path "$binStagingDir\$extraArch\VieLotusTIP.dll")) {
        $cmakeArch = if ($extraArch -eq "arm64") { "ARM64" } else { "x64" }
        $tsfBuildDir = "$rootDir\build-tsf-$extraArch"
        cmake -B $tsfBuildDir -S $tsfSourceDir -A $cmakeArch -DCMAKE_BUILD_TYPE=$Configuration
        if ($LASTEXITCODE -eq 0) {
            cmake --build $tsfBuildDir --config $Configuration
            $builtExtra = Get-ChildItem -Path $tsfBuildDir -Filter "VieLotusTIP.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($builtExtra) {
                Copy-Item $builtExtra.FullName -Destination "$binStagingDir\$extraArch\VieLotusTIP.dll" -Force
                Copy-Item $builtExtra.FullName -Destination "$distWindowsDir\VieLotusTIP-$extraArch.dll" -Force
                Write-Host "   ✅ Đã bổ sung kiến trúc $extraArch vào bộ cài Universal: $($builtExtra.FullName)"
            }
        }
    }
}

# 4. Check for Inno Setup Compiler (ISCC.exe) and package installers
$isccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (Get-Command ISCC -ErrorAction SilentlyContinue) {
    $iscc = "ISCC"
} elseif (Test-Path $isccPath) {
    $iscc = $isccPath
} else {
    $iscc = $null
}

if ($iscc -and (Test-Path "$binStagingDir\VieLotusTIP.dll")) {
    $installersToBuild = if ($Arch -eq "all") { @("x64", "arm64") } else { @($Arch) }
    foreach ($instArch in $installersToBuild) {
        Write-Host "📦 Bước 4 ($instArch): Đóng gói VieLotus-Setup-$instArch.exe (v$Version) qua Inno Setup..." -ForegroundColor Green
        & $iscc "/DMyAppVersion=$Version" "/DMyAppArch=$instArch" "$windowsDir\VieLotus-Setup.iss"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "❌ Lỗi: Inno Setup đóng gói ($instArch) thất bại (exit code $LASTEXITCODE)."
            exit $LASTEXITCODE
        }
        Write-Host "✅ Tạo bộ cài đặt thành công tại: $distWindowsDir\VieLotus-Setup-$instArch.exe" -ForegroundColor Cyan
    }
} else {
    Write-Host "ℹ️  Cấu trúc staging đã sẵn sàng tại: $binStagingDir" -ForegroundColor Yellow
}
