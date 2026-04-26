# fan

A native macOS CLI tool for Apple Silicon fan control using private IOKit/AppleSMC access.

## Warning
This tool utilizes private, undocumented macOS hardware interfaces. It is intended for power users and developers. Misuse may interfere with system-managed thermal regulation. Use at your own risk.

## Features
- View current fan status (temperature, RPM, min, max, mode)
- Enable automatic system fan control
- Force maximum fan speed
- Set manual fan speed as a percentage of maximum RPM

## Requirements
- macOS on Apple Silicon (M4 Pro-class tested)
- Requires `sudo` for write operations

## Build
The project is built as an Xcode command-line tool.
```bash
# Navigate to the project root
cd /path/to/fan
# Build using xcodebuild
xcodebuild -scheme fan -configuration Release
```
The resulting binary will be located in the `.build` directory.

## Usage
All operations that modify hardware settings require `sudo`.

```bash
# View current fan status
sudo ./fan status

# Revert to automatic system control
sudo ./fan auto

# Force maximum fan speed
sudo ./fan max

# Set fans to 75% of max RPM
sudo ./fan set 75
```

## Verifying Status Output
Running `sudo ./fan status` provides a breakdown of detected fans:

```text
Service: AppleSMC
Fans: 2
Writable: yes
Temperature: 48.3 C
Notes:
  - Ftst diagnostic unlock is available.
[0] Fan 0: current=2641 RPM min=2317 RPM max=7000 RPM mode=auto target=2637 RPM
[1] Fan 1: current=2844 RPM min=2317 RPM max=7000 RPM mode=auto target=2847 RPM
```

## Safety Notes
- The `fan set <percent>` command clamps inputs to the hardware-reported minimum and maximum RPM values.
- Manual mode persists until explicitly reset via the `auto` command.

## Optional Symlink
For convenience, you may symlink the binary to a location in your PATH:

```bash
sudo ln -s /path/to/fan/.build/Release/fan /usr/local/bin/fan
```
