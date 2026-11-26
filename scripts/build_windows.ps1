# ==============================================================================
# Sen Việt (VieLotusIM) - Windows Native TSF Build & Packaging Script (PowerShell)
# Builds Universal x64 + ARM64X (ARM64 + ARM64EC) + x86 (WOW64) TIP DLLs,
# VieLotusSettings.exe & Microsoft Store MSIXBundle
# ==============================================================================

param (
    [string]$Configuration = "Release",
    [string]$Version = "2.0.11",
    [string]$MsixVersion = "",
    [ValidateSet("x64", "arm64", "all")]
    [string]$Arch = "all",
    [switch]$SkipTests = $false,
    [switch]$FetchStoreStub = $false
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($MsixVersion)) {
    $MsixVersion = "$Version.0"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = (Resolve-Path "$scriptDir\..").Path
$windowsDir = "$rootDir\scripts\windows"
$distWindowsDir = "$rootDir\dist\windows"
$binStagingDir = "$windowsDir\bin"
$tsfSourceDir = "$rootDir\CrossPlatform\windows-tsf"

Write-Host "🌸 === Sen Việt (VieLotusIM): Build Windows Native TSF TIP ($Arch) ===" -ForegroundColor Cyan
Write-Host "📂 Thư mục gốc: $rootDir"

$isOpenCorePublic = -not (Test-Path "$rootDir\Sources\VieLotusCore")

# 1. Create staging directories
Write-Host "📁 Bước 1: Chuẩn bị thư mục staging ($binStagingDir)..." -ForegroundColor Green
if (Test-Path $binStagingDir) {
    Remove-Item "$binStagingDir\*" -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $binStagingDir | Out-Null
New-Item -ItemType Directory -Force -Path "$binStagingDir\x64" | Out-Null
New-Item -ItemType Directory -Force -Path "$binStagingDir\arm64" | Out-Null
New-Item -ItemType Directory -Force -Path "$binStagingDir\x86" | Out-Null
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

# 3. Build Windows TSF TIP DLLs (x64, ARM64X dual-ABI [ARM64 + ARM64EC], and 32-bit x86 WOW64) via CMake & MSVC (/MT static CRT)
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Error "❌ Lỗi: Không tìm thấy 'cmake'."
    exit 1
}

function Invoke-BuildTsfArch {
    param([string]$TargetArch)

    if ($TargetArch -eq "arm64") {
        Write-Host "🔨 Bước 3 (arm64 — Pass 1/3): Biên dịch ARM64 native + ghi /LINKREPROFULLPATHRSP..." -ForegroundColor Green
        $tsfBuildArm64 = "$rootDir\build-tsf-arm64"
        $tsfBuildArm64Ec = "$rootDir\build-tsf-arm64ec"
        $arm64ReproDir = "$rootDir\build-tsf-arm64-repro"

        foreach ($cleanDir in @($arm64ReproDir, $tsfBuildArm64Ec)) {
            if (Test-Path $cleanDir) {
                Remove-Item $cleanDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        New-Item -ItemType Directory -Force -Path $arm64ReproDir | Out-Null

        cmake -B $tsfBuildArm64 -S $tsfSourceDir -A ARM64 -DCMAKE_BUILD_TYPE=$Configuration -DVIELOTUS_ARM64X_PASS=ARM64 "-DVIELOTUS_ARM64X_REPRO_DIR=$arm64ReproDir"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "❌ Lỗi: cmake configure VieLotusTIP (ARM64 pass 1) thất bại (exit code $LASTEXITCODE)."
            exit $LASTEXITCODE
        }
        cmake --build $tsfBuildArm64 --config $Configuration
        if ($LASTEXITCODE -ne 0) {
            Write-Error "❌ Lỗi: cmake build VieLotusTIP (ARM64 pass 1) thất bại (exit code $LASTEXITCODE)."
            exit $LASTEXITCODE
        }

        $builtSettingsExe = Get-ChildItem -Path $tsfBuildArm64 -Filter "VieLotusSettings.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $builtSettingsExe) {
            Write-Error "❌ Lỗi: Không tìm thấy VieLotusSettings.exe (arm64) sau Pass 1."
            exit 1
        }
        Copy-Item $builtSettingsExe.FullName -Destination "$binStagingDir\arm64\VieLotusSettings.exe" -Force
        Copy-Item $builtSettingsExe.FullName -Destination "$binStagingDir\VieLotusSettings.exe" -Force
        Write-Host "   ✅ Đã copy: $($builtSettingsExe.FullName) -> $binStagingDir\arm64\VieLotusSettings.exe"

        $rspArm64 = "$arm64ReproDir\VieLotusTIP-arm64.rsp"
        if (-not (Test-Path $rspArm64)) {
            Write-Error "❌ Lỗi: Không tìm thấy $rspArm64 sau ARM64 /LINKREPROFULLPATHRSP pass 1."
            exit 1
        }

        Write-Host "🔨 Bước 3 (arm64 — Pass 2/3): Biên dịch ARM64EC + ghi /LINKREPROFULLPATHRSP..." -ForegroundColor Green
        cmake -B $tsfBuildArm64Ec -S $tsfSourceDir -A ARM64EC -DCMAKE_BUILD_TYPE=$Configuration -DVIELOTUS_BUILD_SETTINGS=OFF -DVIELOTUS_ARM64X_PASS=ARM64EC "-DVIELOTUS_ARM64X_REPRO_DIR=$arm64ReproDir"
        if ($LASTEXITCODE -ne 0) {
            Write-Error "❌ Lỗi: cmake configure VieLotusTIP (ARM64EC pass 2) thất bại (exit code $LASTEXITCODE)."
            exit $LASTEXITCODE
        }
        cmake --build $tsfBuildArm64Ec --config $Configuration
        if ($LASTEXITCODE -ne 0) {
            Write-Error "❌ Lỗi: cmake build VieLotusTIP (ARM64EC pass 2) thất bại (exit code $LASTEXITCODE)."
            exit $LASTEXITCODE
        }

        $rspArm64Ec = "$arm64ReproDir\VieLotusTIP-arm64ec.rsp"
        if (-not (Test-Path $rspArm64Ec)) {
            Write-Error "❌ Lỗi: Không tìm thấy $rspArm64Ec sau ARM64EC /LINKREPROFULLPATHRSP pass 2."
            exit 1
        }

        Write-Host "🔗 Bước 3 (arm64 — Pass 3/3): Liên kết trực tiếp link.exe /MACHINE:ARM64X (ARM64 + ARM64EC dual-ABI)..." -ForegroundColor Green
        $vsLink = Get-ChildItem -Path "${env:ProgramFiles}\Microsoft Visual Studio" -Filter "link.exe" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "Hostx64\\arm64\\link\.exe$" } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if (-not $vsLink) {
            $vsLink = Get-ChildItem -Path "${env:ProgramFiles}\Microsoft Visual Studio" -Filter "link.exe" -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match "Hostx64\\x64\\link\.exe$" } |
                Sort-Object FullName -Descending |
                Select-Object -First 1
        }
        if (-not $vsLink) {
            Write-Error "❌ Lỗi: Không tìm thấy MSVC link.exe để liên kết ARM64X."
            exit 1
        }
        $linkExe = $vsLink.FullName

        $allObjs = New-Object System.Collections.Generic.List[string]
        $allLibs = New-Object System.Collections.Generic.List[string]
        $libPaths = New-Object System.Collections.Generic.List[string]
        $seenObjs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $seenLibs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $seenLibPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $resFile = $null

        foreach ($rspFile in @($rspArm64, $rspArm64Ec)) {
            foreach ($rawLine in (Get-Content -Path $rspFile)) {
                $line = $rawLine.Trim()
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if ($line.StartsWith('"') -and $line.EndsWith('"') -and $line.Length -ge 2) {
                    $line = $line.Substring(1, $line.Length - 2)
                }
                if ($line -match '^[/-]LIBPATH:(.+)$') {
                    $lp = $Matches[1].Trim('"')
                    if ((Test-Path $lp) -and $seenLibPaths.Add($lp)) { $libPaths.Add($lp) }
                    continue
                }
                if ($line.StartsWith('/') -or $line.StartsWith('-')) { continue }
                if (-not (Test-Path $line)) { continue }
                if ($line -match '\.obj$') {
                    if ($seenObjs.Add($line)) { $allObjs.Add($line) }
                } elseif ($line -match '\.res$') {
                    if (-not $resFile) { $resFile = $line }
                } elseif ($line -match '\.lib$') {
                    if ($seenLibs.Add($line)) { $allLibs.Add($line) }
                }
            }
        }

        # Derive MSVC CRT & Windows SDK arm64 / arm64ec library directories so /DEFAULTLIB resolves for both slices
        $msvcRoot = Split-Path (Split-Path (Split-Path (Split-Path $linkExe)))
        foreach ($cand in @("$msvcRoot\lib\arm64", "$msvcRoot\lib\arm64ec", "$msvcRoot\lib\arm64\arm64ec")) {
            if ((Test-Path $cand) -and $seenLibPaths.Add($cand)) { $libPaths.Add($cand) }
        }
        foreach ($libPath in $allLibs) {
            if ($libPath -match '^(.*Windows Kits\\10\\Lib\\[^\\]+)\\') {
                $sdkVerDir = $Matches[1]
                foreach ($cand in @("$sdkVerDir\um\arm64", "$sdkVerDir\ucrt\arm64")) {
                    if ((Test-Path $cand) -and $seenLibPaths.Add($cand)) { $libPaths.Add($cand) }
                }
            }
        }
        if ($allObjs.Count -lt 2) {
            Write-Error "❌ Lỗi: Không đủ .obj inputs để liên kết ARM64X ($($allObjs.Count) objects)."
            exit 1
        }

        $arm64xOutDir = "$rootDir\build-tsf-arm64x"
        New-Item -ItemType Directory -Force -Path $arm64xOutDir | Out-Null
        $arm64xOutDll = "$arm64xOutDir\VieLotusTIP.dll"
        $arm64xOutLib = "$arm64xOutDir\VieLotusTIP.lib"
        $arm64xLinkRsp = "$arm64ReproDir\arm64x-link.rsp"

        $rspLines = New-Object System.Collections.Generic.List[string]
        $rspLines.Add("/NOLOGO")
        $rspLines.Add("/DLL")
        $rspLines.Add("/MACHINE:ARM64X")
        $rspLines.Add("/OPT:REF")
        $rspLines.Add("/OPT:ICF")
        $rspLines.Add("/INCREMENTAL:NO")
        $rspLines.Add("/DYNAMICBASE")
        $rspLines.Add("/NXCOMPAT")
        $rspLines.Add("/SUBSYSTEM:WINDOWS")
        $rspLines.Add("/OUT:`"$arm64xOutDll`"")
        $rspLines.Add("/IMPLIB:`"$arm64xOutLib`"")
        $rspLines.Add("/DEF:`"$tsfSourceDir\VieLotusTIP.def`"")
        $rspLines.Add("/DEFARM64NATIVE:`"$tsfSourceDir\VieLotusTIP.def`"")
        foreach ($lp in $libPaths) { $rspLines.Add("/LIBPATH:`"$lp`"") }
        foreach ($obj in $allObjs) { $rspLines.Add("`"$obj`"") }
        if ($resFile) { $rspLines.Add("`"$resFile`"") }
        foreach ($lib in $allLibs) { $rspLines.Add("`"$lib`"") }

        [System.IO.File]::WriteAllLines($arm64xLinkRsp, $rspLines.ToArray(), [System.Text.UTF8Encoding]::new($false))
        Write-Host "   🔧 Linking ARM64X: $($allObjs.Count) .obj + $($allLibs.Count) .lib + $($libPaths.Count) libpaths via $linkExe"
        & $linkExe "@$arm64xLinkRsp"
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $arm64xOutDll)) {
            Write-Error "❌ Lỗi: link.exe /MACHINE:ARM64X thất bại (exit code $LASTEXITCODE)."
            exit 1
        }

        Copy-Item $arm64xOutDll -Destination "$binStagingDir\arm64\VieLotusTIP.dll" -Force
        Copy-Item $arm64xOutDll -Destination "$binStagingDir\VieLotusTIP.dll" -Force
        Copy-Item $arm64xOutDll -Destination "$distWindowsDir\VieLotusTIP-arm64.dll" -Force
        Write-Host "   ✅ Đã liên kết ARM64X: $arm64xOutDll -> $binStagingDir\arm64\VieLotusTIP.dll"
    } else {
        Write-Host "🔨 Bước 3 ($TargetArch): Biên dịch VieLotusTIP.dll ($TargetArch, C++20 Static /MT COM In-Process)..." -ForegroundColor Green
        $tsfBuildDir = "$rootDir\build-tsf-$TargetArch"
        cmake -B $tsfBuildDir -S $tsfSourceDir -A x64 -DCMAKE_BUILD_TYPE=$Configuration
        if ($LASTEXITCODE -ne 0) {
            Write-Error "❌ Lỗi: cmake configure VieLotusTIP ($TargetArch) thất bại (exit code $LASTEXITCODE)."
            exit $LASTEXITCODE
        }
        cmake --build $tsfBuildDir --config $Configuration
        if ($LASTEXITCODE -ne 0) {
            Write-Error "❌ Lỗi: cmake build VieLotusTIP ($TargetArch) thất bại (exit code $LASTEXITCODE)."
            exit $LASTEXITCODE
        }

        $builtTipDll = Get-ChildItem -Path $tsfBuildDir -Filter "VieLotusTIP.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($builtTipDll) {
            Copy-Item $builtTipDll.FullName -Destination "$binStagingDir\$TargetArch\VieLotusTIP.dll" -Force
            Copy-Item $builtTipDll.FullName -Destination "$binStagingDir\VieLotusTIP.dll" -Force
            Copy-Item $builtTipDll.FullName -Destination "$distWindowsDir\VieLotusTIP-$TargetArch.dll" -Force
            Write-Host "   ✅ Đã copy: $($builtTipDll.FullName) -> $binStagingDir\$TargetArch\VieLotusTIP.dll"
        } else {
            Write-Error "❌ Lỗi: Không tìm thấy VieLotusTIP.dll ($TargetArch) sau khi build."
            exit 1
        }

        $builtSettingsExe = Get-ChildItem -Path $tsfBuildDir -Filter "VieLotusSettings.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($builtSettingsExe) {
            Copy-Item $builtSettingsExe.FullName -Destination "$binStagingDir\$TargetArch\VieLotusSettings.exe" -Force
            Copy-Item $builtSettingsExe.FullName -Destination "$binStagingDir\VieLotusSettings.exe" -Force
            Write-Host "   ✅ Đã copy: $($builtSettingsExe.FullName) -> $binStagingDir\$TargetArch\VieLotusSettings.exe"
        }
    }
}

$archesToBuild = if ($Arch -eq "all") { @("x64", "arm64") } else { @($Arch) }
foreach ($targetArch in $archesToBuild) {
    Invoke-BuildTsfArch -TargetArch $targetArch
}

# Build 32-bit (Win32 / x86) VieLotusTIP32.dll so 32-bit apps (Zalo PC 32-bit, Steam, legacy Win32) work on both x64 & ARM64
Write-Host "🔨 Bước 3 (x86 / Win32 WOW64): Biên dịch VieLotusTIP32.dll (32-bit C++20 Static /MT COM In-Process)..." -ForegroundColor Green
$tsfBuildX86 = "$rootDir\build-tsf-x86"
cmake -B $tsfBuildX86 -S $tsfSourceDir -A Win32 -DCMAKE_BUILD_TYPE=$Configuration -DVIELOTUS_BUILD_SETTINGS=OFF
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Lỗi: cmake configure VieLotusTIP32 (Win32/x86) thất bại (exit code $LASTEXITCODE)."
    exit $LASTEXITCODE
}
cmake --build $tsfBuildX86 --config $Configuration
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Lỗi: cmake build VieLotusTIP32 (Win32/x86) thất bại (exit code $LASTEXITCODE)."
    exit $LASTEXITCODE
}
$builtTipDll32 = Get-ChildItem -Path $tsfBuildX86 -Filter "VieLotusTIP32.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $builtTipDll32) {
    Write-Error "❌ Lỗi: Không tìm thấy VieLotusTIP32.dll (Win32/x86) sau khi build."
    exit 1
}
Copy-Item $builtTipDll32.FullName -Destination "$binStagingDir\x86\VieLotusTIP32.dll" -Force
Copy-Item $builtTipDll32.FullName -Destination "$distWindowsDir\VieLotusTIP32.dll" -Force
Write-Host "   ✅ Đã copy 32-bit WOW64: $($builtTipDll32.FullName) -> $binStagingDir\x86\VieLotusTIP32.dll"

# 4. Verify PE hygiene, PE Machine headers, and ARM64X dual-ABI LoadConfig (CHPE + DVRT)
Write-Host "🛡️ Bước 4: Kiểm tra vệ sinh PE, kiến trúc & xác thực ARM64X dual-ABI..." -ForegroundColor Green
$forbiddenStrings = @(
    "Zone.Identifier",
    "ExecutionPolicy Bypass",
    "ping 127.0.0.1",
    "icacls.exe",
    "wininet.dll",
    "VieLotusSetupElevated"
)
$expectedBinaries = @(
    @{ RelPath = "x64\VieLotusSettings.exe";   Machines = @(0x8664);         RequireArm64X = $false },
    @{ RelPath = "x64\VieLotusTIP.dll";        Machines = @(0x8664);         RequireArm64X = $false },
    @{ RelPath = "arm64\VieLotusSettings.exe"; Machines = @(0xAA64);         RequireArm64X = $false },
    @{ RelPath = "arm64\VieLotusTIP.dll";      Machines = @(0xAA64, 0x8664); RequireArm64X = $true  },
    @{ RelPath = "x86\VieLotusTIP32.dll";      Machines = @(0x014C);         RequireArm64X = $false }
)
$dumpbinExe = $null
$dumpbinCmd = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
if ($dumpbinCmd) {
    $dumpbinExe = $dumpbinCmd.Source
} else {
    $vsDumpbin = Get-ChildItem -Path "${env:ProgramFiles}\Microsoft Visual Studio" -Filter "dumpbin.exe" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "Hostx64\\x64\\dumpbin\.exe$" } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($vsDumpbin) { $dumpbinExe = $vsDumpbin.FullName }
}
foreach ($spec in $expectedBinaries) {
    $binPath = Join-Path $binStagingDir $spec.RelPath
    if (-not (Test-Path $binPath)) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($binPath)

    # Scan for any embedded secondary PE header (MZ + valid PE\0\0) beyond offset 0
    for ($i = 1; $i -lt ($bytes.Length - 64); $i++) {
        if ($bytes[$i] -eq 0x4D -and $bytes[$i + 1] -eq 0x5A) {
            $peOffScan = [System.BitConverter]::ToUInt32($bytes, $i + 0x3C)
            if ($peOffScan -ge 0x40 -and $peOffScan -le 0x400 -and ($i + $peOffScan + 4) -lt $bytes.Length) {
                if ($bytes[$i + $peOffScan] -eq 0x50 -and $bytes[$i + $peOffScan + 1] -eq 0x45 -and
                    $bytes[$i + $peOffScan + 2] -eq 0x00 -and $bytes[$i + $peOffScan + 3] -eq 0x00) {
                    Write-Error "❌ Phát hiện PE nhúng bên trong $binPath tại offset 0x$($i.ToString('X'))!"
                    exit 1
                }
            }
        }
    }

    $asciiText = [System.Text.Encoding]::ASCII.GetString($bytes)
    $utf16Text = [System.Text.Encoding]::Unicode.GetString($bytes)
    foreach ($needle in $forbiddenStrings) {
        if ($asciiText.Contains($needle) -or $utf16Text.Contains($needle)) {
            Write-Error "❌ Phát hiện chuỗi bị cấm '$needle' bên trong $binPath!"
            exit 1
        }
    }
    if ($spec.RelPath -like "*VieLotusTIP*.dll") {
        foreach ($tipNeedle in @("CurrentVersion\Run", "CreateToolhelp32Snapshot", "gdiplus.dll", "dwmapi.dll")) {
            if ($asciiText.Contains($tipNeedle) -or $utf16Text.Contains($tipNeedle)) {
                Write-Error "❌ Phát hiện phụ thuộc/chuỗi không được phép '$tipNeedle' bên trong Thin TIP DLL $binPath!"
                exit 1
            }
        }
    }

    # Verify PE signature and Machine architecture
    $peOff = [System.BitConverter]::ToUInt32($bytes, 0x3C)
    if (($peOff + 24) -ge $bytes.Length -or
        $bytes[$peOff] -ne 0x50 -or $bytes[$peOff + 1] -ne 0x45 -or
        $bytes[$peOff + 2] -ne 0x00 -or $bytes[$peOff + 3] -ne 0x00) {
        Write-Error "❌ PE header không hợp lệ trong $binPath!"
        exit 1
    }
    $machine = [System.BitConverter]::ToUInt16($bytes, $peOff + 4)
    if ($spec.Machines -notcontains $machine) {
        $expStr = ($spec.Machines | ForEach-Object { "0x{0:X4}" -f $_ }) -join "|"
        Write-Error ("❌ Sai kiến trúc PE cho {0}: kỳ vọng {1}, thực tế 0x{2:X4}!" -f $spec.RelPath, $expStr, $machine)
        exit 1
    }

    if ($spec.RequireArm64X) {
        $numSections = [System.BitConverter]::ToUInt16($bytes, $peOff + 6)
        $optSize = [System.BitConverter]::ToUInt16($bytes, $peOff + 20)
        $optOff = $peOff + 24
        $magic = [System.BitConverter]::ToUInt16($bytes, $optOff)
        if ($magic -ne 0x020B) {
            Write-Error ("❌ {0} không phải PE32+ (Magic=0x{1:X4})!" -f $spec.RelPath, $magic)
            exit 1
        }
        $numDirs = [System.BitConverter]::ToUInt32($bytes, $optOff + 108)
        if ($numDirs -le 10) {
            Write-Error "❌ $($spec.RelPath) thiếu IMAGE_DIRECTORY_ENTRY_LOAD_CONFIG (ARM64X)!"
            exit 1
        }
        $loadCfgRva = [System.BitConverter]::ToUInt32($bytes, $optOff + 192)
        $loadCfgDirSize = [System.BitConverter]::ToUInt32($bytes, $optOff + 196)
        if ($loadCfgRva -eq 0 -or $loadCfgDirSize -lt 230) {
            Write-Error "❌ $($spec.RelPath) thiếu LoadConfig directory hợp lệ cho ARM64X (RVA=$loadCfgRva, Size=$loadCfgDirSize)!"
            exit 1
        }

        $secTableOff = $optOff + $optSize
        $loadCfgFileOff = -1
        for ($s = 0; $s -lt $numSections; $s++) {
            $sh = $secTableOff + ($s * 40)
            $secVSize = [System.BitConverter]::ToUInt32($bytes, $sh + 8)
            $secVA = [System.BitConverter]::ToUInt32($bytes, $sh + 12)
            $secRawSize = [System.BitConverter]::ToUInt32($bytes, $sh + 16)
            $secRawPtr = [System.BitConverter]::ToUInt32($bytes, $sh + 20)
            $secSpan = [Math]::Max($secVSize, $secRawSize)
            if ($loadCfgRva -ge $secVA -and $loadCfgRva -lt ($secVA + $secSpan)) {
                $loadCfgFileOff = [int]($secRawPtr + ($loadCfgRva - $secVA))
                break
            }
        }
        if ($loadCfgFileOff -lt 0 -or ($loadCfgFileOff + 230) -gt $bytes.Length) {
            Write-Error "❌ Không thể ánh xạ LoadConfig RVA 0x$($loadCfgRva.ToString('X')) sang file offset trong $($spec.RelPath)!"
            exit 1
        }

        $lcStructSize = [System.BitConverter]::ToUInt32($bytes, $loadCfgFileOff)
        $chpeMetaPtr = [System.BitConverter]::ToUInt64($bytes, $loadCfgFileOff + 200)
        $dvrtOffset = [System.BitConverter]::ToUInt32($bytes, $loadCfgFileOff + 224)
        $dvrtSection = [System.BitConverter]::ToUInt16($bytes, $loadCfgFileOff + 228)
        Write-Host ("   🔎 ARM64X inspect: {0} ({1} bytes, Machine=0x{2:X4}, LCSize={3}, CHPE=0x{4:X}, DVRT_Sec={5}, DVRT_Off=0x{6:X})" -f $spec.RelPath, $bytes.Length, $machine, $lcStructSize, $chpeMetaPtr, $dvrtSection, $dvrtOffset)

        if ($dumpbinExe) {
            $hdrOut = (& $dumpbinExe /headers $binPath 2>&1) -join "`n"
            $lcOut = (& $dumpbinExe /loadconfig $binPath 2>&1) -join "`n"
            ($hdrOut -split "`n" | Where-Object { $_ -match "machine \(|ARM64X|ARM64EC" } | Select-Object -First 6) | ForEach-Object {
                Write-Host "      [dumpbin /headers] $($_.Trim())"
            }
            ($lcOut -split "`n" | Where-Object { $_ -match "Hybrid|ARM64|Dynamic Value|Code Range|Metadata|Relocation" } | Select-Object -First 18) | ForEach-Object {
                Write-Host "      [dumpbin /loadconfig] $($_.Trim())"
            }
            if ($hdrOut -notmatch "\(ARM64X\)") {
                Write-Error "❌ dumpbin /headers không xác nhận (ARM64X) trên $($spec.RelPath)!"
                exit 1
            }
            if ($lcOut -notmatch "ARM64EC" -or $lcOut -notmatch "ARM64X") {
                Write-Error "❌ dumpbin /loadconfig thiếu metadata ARM64EC/ARM64X trên $($spec.RelPath)!"
                exit 1
            }
        }

        if ($lcStructSize -lt 230 -or $chpeMetaPtr -eq 0 -or $dvrtSection -eq 0) {
            Write-Error ("❌ {0} KHÔNG phải binary ARM64X (LCSize={1}, CHPEMetadata=0x{2:X}, DVRT_Sec={3}, DVRT_Off=0x{4:X})!" -f $spec.RelPath, $lcStructSize, $chpeMetaPtr, $dvrtSection, $dvrtOffset)
            exit 1
        }
        Write-Host ("   ✅ PE hygiene + ARM64X PASS: {0} ({1} bytes, Machine=0x{2:X4}, CHPE=0x{3:X}, DVRT_Sec={4}, DVRT_Off=0x{5:X})" -f $spec.RelPath, $bytes.Length, $machine, $chpeMetaPtr, $dvrtSection, $dvrtOffset)
    } else {
        Write-Host ("   ✅ PE hygiene + Arch PASS: {0} ({1} bytes, Machine=0x{2:X4})" -f $spec.RelPath, $bytes.Length, $machine)
    }
}

# 5. Package Microsoft Store MSIX & MSIXBundle (Partner Center: NidoHoldings.SenVitVieLotusIM)
$makeappxCmd = Get-Command makeappx.exe -ErrorAction SilentlyContinue
if (-not $makeappxCmd) {
    $sdkMakeAppx = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Filter "makeappx.exe" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "x64" } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if ($sdkMakeAppx) {
        $makeappx = $sdkMakeAppx.FullName
    } else {
        $makeappx = $null
    }
} else {
    $makeappx = $makeappxCmd.Source
}

if ($makeappx) {
    $msixDistDir = "$distWindowsDir\msix"
    $msixStageBase = "$rootDir\build-msix"
    New-Item -ItemType Directory -Force -Path $msixDistDir | Out-Null
    if (Test-Path $msixStageBase) {
        Remove-Item $msixStageBase -Recurse -Force -ErrorAction SilentlyContinue
    }
    $bundleInputDir = "$msixStageBase\bundle-in"
    New-Item -ItemType Directory -Force -Path $bundleInputDir | Out-Null

    if (-not (Test-Path "$binStagingDir\x86\VieLotusTIP32.dll")) {
        Write-Error "❌ Lỗi: Thiếu $binStagingDir\x86\VieLotusTIP32.dll khi đóng gói MSIX!"
        exit 1
    }

    foreach ($msixArch in @("x64", "arm64")) {
        if ((Test-Path "$binStagingDir\$msixArch\VieLotusTIP.dll") -and (Test-Path "$binStagingDir\$msixArch\VieLotusSettings.exe")) {
            Write-Host "📦 Bước 5 ($msixArch): Đóng gói Microsoft Store MSIX (VieLotus-$msixArch.msix + VieLotusTIP32.dll)..." -ForegroundColor Green
            $stageDir = "$msixStageBase\$msixArch"
            New-Item -ItemType Directory -Force -Path "$stageDir\Assets" | Out-Null
            Copy-Item "$binStagingDir\$msixArch\VieLotusTIP.dll" -Destination "$stageDir\VieLotusTIP.dll" -Force
            Copy-Item "$binStagingDir\x86\VieLotusTIP32.dll" -Destination "$stageDir\VieLotusTIP32.dll" -Force
            Copy-Item "$binStagingDir\$msixArch\VieLotusSettings.exe" -Destination "$stageDir\VieLotusSettings.exe" -Force
            Copy-Item "$windowsDir\assets\VieLotusIM.ico" -Destination "$stageDir\VieLotusIM.ico" -Force
            Copy-Item "$windowsDir\assets\*.png" -Destination "$stageDir\Assets\" -Force

            $manifestXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  xmlns:desktop="http://schemas.microsoft.com/appx/manifest/desktop/windows10"
  IgnorableNamespaces="uap rescap desktop">

  <Identity
    Name="NidoHoldings.SenVitVieLotusIM"
    Publisher="CN=BC3DBCFE-AB40-468F-8F2B-36C55BB3374C"
    Version="$MsixVersion"
    ProcessorArchitecture="$msixArch" />

  <Properties>
    <DisplayName>Sen Việt (VieLotusIM)</DisplayName>
    <PublisherDisplayName>Nido Holdings</PublisherDisplayName>
    <Logo>Assets\StoreLogo.png</Logo>
    <Description>Modern Native Windows TSF Vietnamese Input Method (Telex, VNI, Smart Bilingual — 100% Offline).</Description>
  </Properties>

  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>

  <Resources>
    <Resource Language="vi-VN" />
    <Resource Language="en-US" />
  </Resources>

  <Applications>
    <Application Id="VieLotusIM" Executable="VieLotusSettings.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements
        DisplayName="Sen Việt (VieLotusIM)"
        Description="Sen Việt (VieLotusIM) Vietnamese Input Method Settings"
        BackgroundColor="transparent"
        Square150x150Logo="Assets\Square150x150Logo.png"
        Square44x44Logo="Assets\Square44x44Logo.png">
        <uap:DefaultTile Wide310x150Logo="Assets\Wide310x150Logo.png" />
      </uap:VisualElements>
    </Application>
  </Applications>

  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
</Package>
"@
            Set-Content -Path "$stageDir\AppxManifest.xml" -Value $manifestXml -Encoding UTF8
            $outMsix = "$msixDistDir\VieLotus-$msixArch.msix"
            if (Test-Path $outMsix) { Remove-Item $outMsix -Force }
            & $makeappx pack /d $stageDir /p $outMsix /o | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Copy-Item $outMsix -Destination "$bundleInputDir\VieLotus-$msixArch.msix" -Force
                Write-Host "   ✅ Đã tạo: $outMsix"
            }
        }
    }

    $outBundle = "$msixDistDir\VieLotus_${MsixVersion}_x64_arm64.msixbundle"
    if (Test-Path $outBundle) { Remove-Item $outBundle -Force }
    & $makeappx bundle /d $bundleInputDir /p $outBundle /bv "$MsixVersion" /o | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Lỗi: makeappx bundle thất bại (exit code $LASTEXITCODE)."
        exit $LASTEXITCODE
    }
    Write-Host "✅ Đã tạo gói Microsoft Store MSIXBundle tại: $outBundle" -ForegroundColor Cyan
    Remove-Item $msixStageBase -Recurse -Force -ErrorAction SilentlyContinue
}

# 5b. Package clean offline Inno Setup 6 standalone installers (VieLotus-Setup-x64.exe & VieLotus-Setup-arm64.exe)
$issPath = "$windowsDir\VieLotus-Setup.iss"
if (Test-Path $issPath) {
    $isccExe = $null
    $isccCmd = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($isccCmd) {
        $isccExe = $isccCmd.Source
    } else {
        foreach ($cand in @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "${env:ProgramFiles}\Inno Setup 6\ISCC.exe")) {
            if (Test-Path $cand) { $isccExe = $cand; break }
        }
    }
    if (-not $isccExe) {
        Write-Error "❌ Lỗi: Không tìm thấy Inno Setup 6 (ISCC.exe) để đóng gói VieLotus-Setup-*.exe."
        exit 1
    }
    foreach ($instArch in $archesToBuild) {
        if ((Test-Path "$binStagingDir\$instArch\VieLotusTIP.dll") -and
            (Test-Path "$binStagingDir\$instArch\VieLotusSettings.exe") -and
            (Test-Path "$binStagingDir\x86\VieLotusTIP32.dll")) {
            Write-Host "📦 Bước 5b ($instArch): Đóng gói Inno Setup 6 (VieLotus-Setup-$instArch.exe)..." -ForegroundColor Green
            & $isccExe "/DMyAppVersion=$Version" "/DMyAppArch=$instArch" $issPath
            if ($LASTEXITCODE -ne 0) {
                Write-Error "❌ Lỗi: ISCC.exe thất bại cho kiến trúc $instArch (exit code $LASTEXITCODE)."
                exit $LASTEXITCODE
            }
            $outExe = "$distWindowsDir\VieLotus-Setup-$instArch.exe"
            if (-not (Test-Path $outExe) -or (Get-Item $outExe).Length -le 0) {
                Write-Error "❌ Lỗi: Không tìm thấy $outExe sau khi đóng gói Inno Setup."
                exit 1
            }
            Write-Host "   ✅ Đã tạo: $outExe ($((Get-Item $outExe).Length) bytes)" -ForegroundColor Cyan
        }
    }
}

# 6. Fetch & cryptographically verify the official Microsoft Store Signed Web Installer stub (9PF5K64GXXSH)
if ($FetchStoreStub) {
    $storeStubPath = "$distWindowsDir\VieLotus-Store-Setup.exe"
    $storeStubUrl = "https://get.microsoft.com/installer/download/9PF5K64GXXSH?ocid=badge"
    Write-Host "🔏 Bước 6: Tải & xác thực chữ ký Microsoft Corporation cho VieLotus-Store-Setup.exe..." -ForegroundColor Green
    Invoke-WebRequest -Uri $storeStubUrl -OutFile $storeStubPath -UseBasicParsing
    if (-not (Test-Path $storeStubPath) -or (Get-Item $storeStubPath).Length -lt 100000) {
        Remove-Item $storeStubPath -Force -ErrorAction SilentlyContinue
        Write-Error "❌ Lỗi: Không thể tải Microsoft Store Web Installer hợp lệ từ $storeStubUrl."
        exit 1
    }
    $sig = Get-AuthenticodeSignature -FilePath $storeStubPath
    if ($sig.Status -ne "Valid" -or -not $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notlike "*CN=Microsoft Corporation*") {
        $statusStr = "$($sig.Status)"
        $subjStr = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { "<none>" }
        Remove-Item $storeStubPath -Force -ErrorAction SilentlyContinue
        Write-Error "❌ Lỗi: Chữ ký Authenticode của VieLotus-Store-Setup.exe không hợp lệ (Status=$statusStr, Subject=$subjStr)."
        exit 1
    }
    Write-Host "✅ Xác thực thành công Microsoft Corporation Signed Web Installer: $storeStubPath ($((Get-Item $storeStubPath).Length) bytes)" -ForegroundColor Cyan
}
