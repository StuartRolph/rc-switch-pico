# RcSwitch
A port of the brilliant [RC-Switch](https://github.com/sui77/rc-switch) library to the raspberry pi pico.

It allows you to send and recieve radio signals from 433/315Mhz devices like radio controlled power sockets, using cheap radio modules.

This works for both recieving and transmitting. Check out the examples for code for both of these.

## Hardware

Both examples need a cheap 433/315 MHz module wired to a GPIO:

| Example  | GPIO | Module `DATA` pin |
| -------- | ---- | ----------------- |
| Receive  | 17   | receiver          |
| Transmit | 16   | transmitter       |

## Building

The project uses CMake with the **Ninja** generator. CMake >= 3.12, Ninja and the Pico SDK 2.x are required.

### With the Raspberry Pi Pico VS Code extension

Open this folder as a workspace. The extension supplies CMake, Ninja, the ARM toolchain and the Pico SDK, and configures the project automatically. Use the **Compile** button in the status bar.

### Manually

Configure once, out of source, into a separate `build/` directory:

```bash
cmake -S . -B build -G Ninja
```

Then build the example you want:

```bash
ninja -C build receive      # or: ninja -C build transmit
```

The firmware is written to `build/examples/Receive/receive.uf2` (or `build/examples/Transmit/transmit.uf2`).

> **Do not run `cmake .` in the repository root.** That configures in-source: it scatters `CMakeCache.txt`, `CMakeFiles/` and `cmake_install.cmake` through the source tree, and a second run fails because the generator does not match. If you already did this, delete those files.

## Flashing

Put the board into BOOTSEL mode so it mounts as a USB mass-storage device named `RPI-RP2`, then copy the `.uf2` onto it. The board reboots into the new firmware as soon as the copy finishes.

The usual way in is to hold the **BOOTSEL** button while plugging in the USB cable.

### Without the BOOTSEL button

`flash-nobutton.ps1` (Windows) never touches the button. It asks the running firmware to reboot into BOOTSEL, then copies the UF2:

```powershell
.\flash-nobutton.ps1                     # flashes receive
.\flash-nobutton.ps1 -Target transmit
.\flash-nobutton.ps1 -Uf2 C:\path\to\custom.uf2
```

It tries, in order:

1. the device is already in BOOTSEL mode;
2. `picotool reboot -f -u`, which works for any firmware built with `pico_stdio_usb` (both examples are);
3. `machine.bootloader()` over the serial REPL, for a board running MicroPython.

It flashes by **copying to the `RPI-RP2` volume rather than using `picotool load`**. On Windows, `picotool load` needs a WinUSB driver bound to the BOOTSEL-mode PICOBOOT interface; without one the command fails with exit code `-7`. Binding that driver (see [Zadig](https://github.com/raspberrypi/picotool#zadig)) also enables the VS Code extension's **Run** button.

## Seeing the output

Both examples send `std::cout` over **USB serial (CDC)**. UART is disabled in both `CMakeLists.txt` files, so there is no UART output. Use any serial monitor — for example the VS Code **Serial Monitor** extension — at any baud rate, since USB CDC ignores it.

**Gotcha:** the Pico SDK treats the CDC connection as established only while the host asserts **DTR**. A monitor that leaves DTR low shows a silent port that looks exactly like a broken build. VS Code's Serial Monitor asserts DTR; a custom reader must do so explicitly (in .NET, `SerialPort.DtrEnable = true`).

Because USB CDC discards output while no host is attached, the receive example reprints its `receive: up, listening on GPIO 17` banner every 3 seconds instead of only once at startup.

## Reading the receive output

```
VALUE RECEIVED: 14066724
PROTOCOL RECEIVED: 1
BIT LENGTH RECEIVED: 24
PULSELENGTH RECEIVED: 302
```

| Field         | Meaning |
| ------------- | ------- |
| `VALUE`       | the decoded code as a number (here `0xD6A424`) |
| `BIT LENGTH`  | how many bits that number occupies |
| `PROTOCOL`    | which entry of the timing table in `radio-switch.cc` matched |
| `PULSELENGTH` | base pulse length **measured** from the transmission, in microseconds |

`PROTOCOL` identifies the pulse *encoding*, not the device. Protocol 1 is duty-cycle coding, used by the PT2260/PT2262 family:

```
{ 350, { 1, 31 }, { 1, 3 }, { 3, 1 }, false }
```

following the `{pulselength, Sync bit, "0" bit, "1" bit, invertedSignal}` format documented above the table: a `1` bit is 3 units high and 1 low, a `0` bit is 1 unit high and 3 low, and a sync of 1 high plus 31 low separates packets. Both bit shapes are 4 units wide, so only the duty cycle carries data.

`PULSELENGTH` is derived from the sync gap of the actual transmission (`timings[0] / 31` for protocol 1), so it is usually *not* the nominal 350 microseconds from the table. Use the measured value when transmitting, or you will send a different pulse width from the original remote.

## Reproducing a remote

1. Flash `receive`, wire up a receiver module, and open a serial monitor.
2. Press each button on the remote and note the four values it prints.
3. Enter them in `examples/Transmit/Transmit.cc`:

```cpp
const uint PULSE_LENGTH = 302;       // PULSELENGTH RECEIVED
const uint PROTOCOL     = 1;         // PROTOCOL RECEIVED
const uint BIT_LENGTH   = 24;        // BIT LENGTH RECEIVED
const uint ON_CODE      = 14066724;  // VALUE RECEIVED for one button
const uint OFF_CODE     = 0;         // VALUE RECEIVED for another button
```

4. Flash `transmit` and check that the device responds.

The 24 bits are the encoder's payload, and the library reports them as an opaque number rather than decoding them. To find which bits differ per button, compare the values printed for each button — usually the upper bits stay fixed as an address while a few lower bits change.

## Issues
If you experience an error while using this library, please raise an issue here on Github and I'll try to help out. Pull requests are also very welcome!