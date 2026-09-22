<#
.SYNOPSIS
    Flash a Pico over USB without pressing the BOOTSEL button.

.DESCRIPTION
    For boards where the BOOTSEL button is physically unreachable. It requests
    BOOTSEL mode in software, trying in order:

      1. The device is already in BOOTSEL mode -> skip ahead
      2. picotool reboot -f -u                   -> any firmware built with pico_stdio_usb
      3. machine.bootloader() over the REPL      -> a board running MicroPython

    Flashing is then done by copying the UF2 onto the RPI-RP2 mass-storage volume.
    This deliberately avoids 'picotool load', which needs a WinUSB (Zadig) driver
    bound to the BOOTSEL-mode PICOBOOT interface and fails without one.

    Note: copying a UF2 erases whatever is currently on the board (including
    MicroPython). Nothing is erased until the copy actually starts.

.PARAMETER Target
    Which example to flash: receive or transmit. Used to derive the default UF2 path.

.PARAMETER Uf2
    Explicit path to a .uf2 file. Overrides -Target.

.PARAMETER Picotool
    Path to picotool.exe. Defaults to the Pico VS Code extension's copy.

.PARAMETER TimeoutSeconds
    How long to wait for the device to appear/disappear. Default 30.

.EXAMPLE
    .\flash-nobutton.ps1
    .\flash-nobutton.ps1 -Target transmit
    .\flash-nobutton.ps1 -Uf2 C:\firmware\custom.uf2
#>
[CmdletBinding()]
param(
    [ValidateSet('receive', 'transmit')]
    [string]$Target = 'receive',

    [string]$Uf2,

    [string]$Picotool = (Join-Path $env:USERPROFILE '.pico-sdk\picotool\2.3.1\picotool\picotool.exe'),

    [int]$TimeoutSeconds = 30
)

function Get-BootselVolume {
    Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.FileSystemLabel -eq 'RPI-RP2' } |
        Select-Object -First 1
}

function Wait-BootselVolume([int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $v = Get-BootselVolume
        if ($v) { return $v }
        Start-Sleep -Milliseconds 400
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Get-PicoPorts {
    # RP-series USB serial ports (VID 2E8A). Works for both MicroPython and the SDK's stdio USB.
    Get-PnpDevice -Class Ports -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_2E8A' } |
        ForEach-Object { if ($_.FriendlyName -match '\((COM\d+)\)') { $Matches[1] } }
}

function Invoke-MicroPythonBootloader([string]$PortName) {
    # Confirms the port really is a MicroPython raw REPL before sending the command.
    $sp = New-Object System.IO.Ports.SerialPort $PortName, 115200, 'None', 8, 'One'
    try {
        $sp.ReadTimeout = 500
        $sp.DtrEnable = $true
        $sp.Open()
        $sp.DiscardInBuffer()
        $sp.Write([char]3)                       # Ctrl-C: interrupt the running script
        Start-Sleep -Milliseconds 300
        $sp.Write([char]1)                       # Ctrl-A: enter raw REPL
        Start-Sleep -Milliseconds 500
        try { $banner = $sp.ReadExisting() } catch { $banner = '' }
        if ($banner -notmatch 'raw REPL') { return $false }
        $sp.Write("import machine`nmachine.bootloader()`n" + [char]4)
        Start-Sleep -Milliseconds 500
        return $true
    } catch {
        return $false
    } finally {
        if ($sp.IsOpen) { $sp.Close() }
        $sp.Dispose()
    }
}

# --- resolve the UF2 -------------------------------------------------------------
if (-not $Uf2) {
    $dir = (Get-Culture).TextInfo.ToTitleCase($Target)   # receive -> Receive
    $Uf2 = Join-Path $PSScriptRoot "build\examples\$dir\$Target.uf2"
}
if (-not (Test-Path -LiteralPath $Uf2)) {
    throw "UF2 not found: $Uf2`nBuild it first, e.g. ninja -C build $Target"
}
Write-Host ("UF2   : {0} ({1:N0} bytes)" -f $Uf2, (Get-Item -LiteralPath $Uf2).Length)

# --- 1. get into BOOTSEL mode ----------------------------------------------------
$vol = Get-BootselVolume
if ($vol) {
    Write-Host ("[1/3] already in BOOTSEL mode ({0}:)" -f $vol.DriveLetter)
} else {
    Write-Host "[1/3] requesting BOOTSEL mode..."

    $rebooted = $false
    if (Test-Path -LiteralPath $Picotool) {
        $null = & $Picotool reboot -f -u 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $rebooted = $true
            Write-Host "      picotool reboot -f -u -> ok"
        } else {
            Write-Host ("      picotool reboot -f -u -> failed (exit {0})" -f $LASTEXITCODE)
        }
    } else {
        Write-Host "      picotool not found at $Picotool"
    }

    if (-not $rebooted) {
        $ports = @(Get-PicoPorts)
        if ($ports.Count -eq 0) { Write-Host "      no RP-series serial ports found" }
        foreach ($p in $ports) {
            Write-Host "      trying MicroPython on $p..."
            if (Invoke-MicroPythonBootloader $p) {
                $rebooted = $true
                Write-Host "      machine.bootloader() -> ok"
                break
            }
        }
    }

    if (-not $rebooted) {
        throw "Could not enter BOOTSEL mode. If the running firmware is hung, you need a debug probe or physical access to the BOOTSEL button."
    }

    $vol = Wait-BootselVolume $TimeoutSeconds
    if (-not $vol) { throw "Device did not enumerate as RPI-RP2 within $TimeoutSeconds s." }
    Write-Host ("[2/3] in BOOTSEL mode ({0}:)" -f $vol.DriveLetter)
}

# --- 2. flash by copying the UF2 -------------------------------------------------
$dest = Join-Path ($vol.DriveLetter + ':\') (Split-Path -Leaf $Uf2)
Write-Host "[3/3] copying to $dest"
try {
    Copy-Item -LiteralPath $Uf2 -Destination $dest -Force
    Write-Host "      copy completed"
} catch {
    # Expected: the device disconnects the instant it has the whole file.
    Write-Host "      volume went away mid-copy (normal - the Pico reboots once the file is complete)"
}

# --- 3. verify the device left BOOTSEL mode --------------------------------------
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline -and (Get-BootselVolume)) {
    Start-Sleep -Milliseconds 400
}

Write-Host ""
if (Get-BootselVolume) {
    Write-Host "WARNING: device is still in BOOTSEL mode - the copy may not have completed." -ForegroundColor Yellow
    exit 1
}
Write-Host "Done. Device left BOOTSEL mode." -ForegroundColor Green
$ports = @(Get-PicoPorts)
if ($ports.Count -gt 0) { Write-Host ("Serial port(s): {0}" -f ($ports -join ', ')) }
