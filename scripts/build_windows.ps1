# ==============================================================================
# Sen Việt (VieLotusIM) - Windows Native TSF Build & Packaging Script (PowerShell)
# ==============================================================================

param (
    [string]$Configuration = "Release",
    [string]$Version = "1.1.1",
    [ValidateSet("x64", "arm64")]
    [string]$Arch = $(if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }),
    [switch]$SkipTests = $false
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = (Resolve-Path "$scriptDir\..").Path
$windowsDir = "$rootDir\scripts\windows"
$distWindowsDir = "$rootDir\dist\windows"
$binStagingDir = "$windowsDir\bin"
$tsfSourceDir = "$rootDir\CrossPlatform\windows-tsf"
$cmakeArch = if ($Arch -eq "arm64") { "ARM64" } else { "x64" }
$swiftTriple = if ($Arch -eq "arm64") { "aarch64-unknown-windows-msvc" } else { "x86_64-unknown-windows-msvc" }

Write-Host "🌸 === Sen Việt (VieLotusIM): Build Windows Native TSF TIP ($Arch) ===" -ForegroundColor Cyan
Write-Host "📂 Thư mục gốc: $rootDir"

$isOpenCorePublic = -not (Test-Path "$rootDir\Sources\VieLotusCore")

# 3. Create staging directory for Inno Setup
Write-Host "📁 Bước 1: Chuẩn bị thư mục staging ($binStagingDir)..." -ForegroundColor Green
if (Test-Path $binStagingDir) {
    Remove-Item "$binStagingDir\*" -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $binStagingDir | Out-Null
New-Item -ItemType Directory -Force -Path $distWindowsDir | Out-Null

if ($isOpenCorePublic) {
    Write-Host "🔒 Chế độ Open-Core Public Repo: Sử dụng prebuilt VieLotusCAPI.dll từ Binaries\windows\$Arch..." -ForegroundColor Cyan
    $prebuiltDir = if (Test-Path "$rootDir\Binaries\windows\$Arch") { "$rootDir\Binaries\windows\$Arch" } else { "$rootDir\Binaries\windows" }
    if (-not (Test-Path "$prebuiltDir\VieLotusCAPI.dll")) {
        Write-Error "❌ Lỗi: Không tìm thấy prebuilt VieLotusCAPI.dll tại $prebuiltDir"
        exit 1
    }
    Copy-Item "$prebuiltDir\*.dll" -Destination $binStagingDir -Force
    if (Test-Path "$rootDir\Resources\typing-modes.yml") {
        $coreResourcesDst = "$binStagingDir\VietLotusIM_VieLotusCore.resources"
        New-Item -ItemType Directory -Force -Path $coreResourcesDst | Out-Null
        Copy-Item "$rootDir\Resources\typing-modes.yml" -Destination $coreResourcesDst -Force
    }
} else {
    # 1. Check for Swift toolchain
    if (-not (Get-Command swift -ErrorAction SilentlyContinue)) {
        Write-Error "❌ Lỗi: Không tìm thấy 'swift' trong PATH. Vui lòng cài đặt Swift 6.0+ cho Windows."
        exit 1
    }

    # 2. Build Swift Core & C-ABI Library
    Write-Host "📦 Bước 2: Biên dịch VieLotusCAPI.dll ($swiftTriple) bằng Swift 6..." -ForegroundColor Green
    Set-Location $rootDir
    $hostArch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
    if ($Arch -ne $hostArch) {
        swift build -c release --triple $swiftTriple --product VieLotusCAPI
    } else {
        swift build -c release --product VieLotusCAPI
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Lỗi: swift build VieLotusCAPI thất bại (exit code $LASTEXITCODE)."
        exit $LASTEXITCODE
    }

    if (-not $SkipTests -and ($Arch -eq $hostArch)) {
        Write-Host "🧪 Bước 2b: Chạy unit tests (CAPITests & LocalLoopbackBridgeTests) trên Windows..." -ForegroundColor Green
        swift test --filter "CAPITests|LocalLoopbackBridgeTests"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "❌ Lỗi: swift test thất bại (exit code $LASTEXITCODE)."
            exit $LASTEXITCODE
        }
    }

    # Bundle VieLotusCore desktop resource files (typing-modes.yml) for relocated Windows installs
    $coreTypingModes = "$rootDir\Sources\VieLotusCore\Resources\typing-modes.yml"
    $coreResourcesDst = "$binStagingDir\VietLotusIM_VieLotusCore.resources"
    if (Test-Path $coreTypingModes) {
        New-Item -ItemType Directory -Force -Path $coreResourcesDst | Out-Null
        Copy-Item $coreTypingModes -Destination $coreResourcesDst -Force
        Write-Host "   📦 Đã copy typing-modes.yml -> $coreResourcesDst"
    }

    # Copy built Core DLL & import library (.lib) — prefer matching triple and release build directory
    $builtCoreDll = Get-ChildItem -Path "$rootDir\.build" -Filter "VieLotusCAPI.dll" -Recurse |
        Sort-Object { $_.FullName -notmatch $swiftTriple }, { $_.FullName -notmatch 'release' } |
        Select-Object -First 1
    if ($builtCoreDll) {
        Copy-Item $builtCoreDll.FullName -Destination "$binStagingDir\VieLotusCAPI.dll" -Force
        Write-Host "   ✅ Đã copy: $($builtCoreDll.FullName) -> $binStagingDir\VieLotusCAPI.dll"
    } else {
        Write-Error "❌ Lỗi: Không tìm thấy VieLotusCAPI.dll sau khi build."
        exit 1
    }

    $builtCoreLib = Get-ChildItem -Path "$rootDir\.build" -Filter "VieLotusCAPI.lib" -Recurse |
        Sort-Object { $_.FullName -notmatch $swiftTriple }, { $_.FullName -notmatch 'release' } |
        Select-Object -First 1
    if ($builtCoreLib) {
        Copy-Item $builtCoreLib.FullName -Destination "$binStagingDir\VieLotusCAPI.lib" -Force
        Write-Host "   ✅ Đã copy: $($builtCoreLib.FullName) -> $binStagingDir\VieLotusCAPI.lib"
    }
}

# 3. Bundle ALL Swift Windows Runtime DLLs if not already present in staging
if (-not (Test-Path "$binStagingDir\swiftCore.dll")) {
    $runtimeBinDirs = [System.Collections.Generic.List[string]]::new()

    # 3a. Check PATH entries for swiftCore.dll
    foreach ($pathEntry in ($env:PATH -split ';')) {
        if ($pathEntry -and (Test-Path (Join-Path $pathEntry "swiftCore.dll"))) {
            $runtimeBinDirs.Add($pathEntry)
        }
    }

    # 3b. Walk up parent directories from swift.exe to locate Runtimes\*\usr\bin
    $swiftCmd = Get-Command swift -ErrorAction SilentlyContinue
    if ($swiftCmd) {
        $curr = Split-Path -Parent $swiftCmd.Source
        for ($i = 0; $i -lt 6 -and $curr; $i++) {
            $runtimesDir = Join-Path $curr "Runtimes"
            if (Test-Path $runtimesDir) {
                $foundCores = Get-ChildItem -Path $runtimesDir -Filter "swiftCore.dll" -Recurse -ErrorAction SilentlyContinue
                foreach ($fc in $foundCores) {
                    $runtimeBinDirs.Add($fc.DirectoryName)
                }
            }
            $curr = Split-Path -Parent $curr
        }
    }

    # 3c. Check standard Swift Windows installation roots
    $extraRoots = @(
        "$env:SDKROOT\usr\bin",
        "$env:LOCALAPPDATA\Programs\Swift\Runtimes",
        "$env:ProgramFiles\Swift\Runtimes",
        "C:\Library\Developer\Runtimes"
    )
    foreach ($root in $extraRoots) {
        if ($root -and (Test-Path $root)) {
            $foundCores = Get-ChildItem -Path $root -Filter "swiftCore.dll" -Recurse -ErrorAction SilentlyContinue
            foreach ($fc in $foundCores) {
                $runtimeBinDirs.Add($fc.DirectoryName)
            }
        }
    }

    $selectedRuntimeDir = $runtimeBinDirs | Select-Object -First 1
    if (-not $selectedRuntimeDir) {
        Write-Error "❌ Lỗi: Không tìm thấy thư mục Swift Runtime (swiftCore.dll) để đóng gói."
        exit 1
    }

    Write-Host "   📦 Sao chép toàn bộ Swift Runtime DLLs từ: $selectedRuntimeDir" -ForegroundColor Cyan
    Get-ChildItem -Path $selectedRuntimeDir -Filter "*.dll" | ForEach-Object {
        Copy-Item $_.FullName -Destination "$binStagingDir\$($_.Name)" -Force
        Write-Host "      + $($_.Name)"
    }

    # 3d. Bundle MSVC Redistributable DLLs (vcruntime140.dll, vcruntime140_1.dll, msvcp140.dll) for clean Windows VMs
    $vcDllNames = @("vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll", "concrt140.dll")
    foreach ($vcDll in $vcDllNames) {
        $sysVcPath = Join-Path "$env:SystemRoot\System32" $vcDll
        if (Test-Path $sysVcPath) {
            Copy-Item $sysVcPath -Destination "$binStagingDir\$vcDll" -Force
            Write-Host "      + $vcDll (MSVC Runtime)"
        }
    }
}

# 3e. Verify mandatory Swift Runtime DLLs exist in staging
$mandatoryDlls = @(
    "VieLotusCAPI.dll",
    "swiftCore.dll",
    "swiftCRT.dll",
    "swiftWinSDK.dll",
    "swiftDispatch.dll",
    "Foundation.dll",
    "FoundationEssentials.dll",
    "BlocksRuntime.dll"
)
foreach ($reqDll in $mandatoryDlls) {
    if (-not (Test-Path "$binStagingDir\$reqDll")) {
        Write-Error "❌ Lỗi: Thiếu DLL bắt buộc trong staging: $reqDll"
        exit 1
    }
}

# 4. Build Windows TSF TIP DLL via CMake & MSVC (Static CRT /MT + Dynamic LoadLibraryExW)
Write-Host "🔨 Bước 4: Biên dịch VieLotusTIP.dll ($cmakeArch, C++20 COM In-Process)..." -ForegroundColor Green
$tsfBuildDir = "$rootDir\build-tsf-$Arch"
if (Get-Command cmake -ErrorAction SilentlyContinue) {
    cmake -B $tsfBuildDir -S $tsfSourceDir -A $cmakeArch -DCMAKE_BUILD_TYPE=$Configuration
    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Lỗi: cmake configure VieLotusTIP thất bại (exit code $LASTEXITCODE)."
        exit $LASTEXITCODE
    }
    cmake --build $tsfBuildDir --config $Configuration
    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Lỗi: cmake build VieLotusTIP thất bại (exit code $LASTEXITCODE)."
        exit $LASTEXITCODE
    }
} else {
    Write-Error "❌ Lỗi: Không tìm thấy 'cmake'."
    exit 1
}

$builtTipDll = Get-ChildItem -Path $tsfBuildDir -Filter "VieLotusTIP.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($builtTipDll) {
    Copy-Item $builtTipDll.FullName -Destination "$binStagingDir\VieLotusTIP.dll" -Force
    Write-Host "   ✅ Đã copy: $($builtTipDll.FullName) -> $binStagingDir\VieLotusTIP.dll"
} else {
    Write-Error "❌ Lỗi: Không tìm thấy VieLotusTIP.dll sau khi build."
    exit 1
}

# 5. Check for Inno Setup Compiler (ISCC.exe)
$isccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (Get-Command ISCC -ErrorAction SilentlyContinue) {
    $iscc = "ISCC"
} elseif (Test-Path $isccPath) {
    $iscc = $isccPath
} else {
    $iscc = $null
}

if ($iscc -and (Test-Path "$binStagingDir\VieLotusTIP.dll")) {
    Write-Host "📦 Bước 5: Đóng gói VieLotus-Setup-$Arch.exe (v$Version) qua Inno Setup..." -ForegroundColor Green
    & $iscc "/DMyAppVersion=$Version" "/DMyAppArch=$Arch" "$windowsDir\VieLotus-Setup.iss"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Lỗi: Inno Setup đóng gói thất bại (exit code $LASTEXITCODE)."
        exit $LASTEXITCODE
    }
    Write-Host "✅ Tạo bộ cài đặt thành công tại: $distWindowsDir\VieLotus-Setup-$Arch.exe" -ForegroundColor Cyan
} else {
    Write-Host "ℹ️  Cấu trúc staging đã sẵn sàng tại: $binStagingDir" -ForegroundColor Yellow
}
