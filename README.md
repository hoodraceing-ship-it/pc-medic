# PC Medic

PC Medic is a local Windows 10/11 diagnostic and guided-repair dashboard. It
uses Windows' own servicing and diagnostic tools and does not upload telemetry.

## Install

1. Extract the ZIP.
2. Right-click `Install-PCMedic.ps1` and choose **Run with PowerShell**.
3. If Windows asks, approve the administrator prompt.

If startup fails, PC Medic now keeps the error on screen and opens the saved
log automatically. Startup logs are stored under `%ProgramData%\PCMedic\Logs`.

The installer adds **PC Medic** to the Start menu and desktop. The application
requests administrator rights because DISM, SFC, disk, Defender, and driver
checks need them.

PC Medic launches silently without leaving a PowerShell or Command Prompt
window open. On the Health Check page, select any warning or failure to see a
plain-language explanation and a button for the matching repair or Windows
management screen.

When a repair starts, PC Medic switches to the Repairs page and shows the
current stage, a live progress bar, and a plain-language description of what
Windows is doing. DISM, SFC, and CHKDSK report numeric progress; tools that do
not expose a percentage use an animated working indicator. Repair buttons are
temporarily locked to prevent two repairs from running at the same time.

After a full scan, **Fix all safe issues** runs every applicable built-in repair
in one sequence. It creates a restore point when available and can repair
Windows files, scan the disk, rescan devices, restore update services, enable
Defender, and reset networking. Hardware replacement, low-space cleanup,
third-party driver installation, and application removal remain manual so the
button cannot make unsafe guesses or delete personal data.

## What it checks

- Windows version, activation/licensing service, pending restart, and uptime
- System file corruption with DISM and SFC verification
- Disk health, free space, file-system state, and SMART warnings
- Device/driver errors and old third-party drivers
- Recent critical crashes, bugchecks, WHEA hardware errors, and reliability
- Application crashes and hangs, grouped by event source and error ID
- Disk, storage-controller, NTFS, driver-loading, and service failure events
- Windows Update failures, Defender detections, and protection-disabled events
- Windows Memory Diagnostic results
- Microsoft Defender, firewall profiles, and Windows Update services
- RAM totals, recent memory-test results, and page-file configuration
- Internet, DNS, gateway, adapters, and high-error network interfaces
- Startup applications and unusually heavy processes
- Battery health (when Windows can generate a battery report)

## Hardware dashboard

The Hardware tab automatically inventories the CPU, motherboard, BIOS/UEFI,
graphics adapters, individual RAM modules, storage, physical network adapters,
audio devices, monitors, and battery. CPU, memory, system-drive, and supported
GPU telemetry refreshes every two seconds.

Windows does not provide a universal CPU-temperature API. PC Medic displays
ACPI thermal readings when the motherboard exposes them and uses NVIDIA's
installed driver utility for NVIDIA GPU temperature, utilization, and VRAM.
An unavailable temperature is reported honestly rather than estimated.

## Updates

PC Medic checks `hoodraceing-ship-it/PC-Medic` GitHub Releases once per day.
The About page also provides a manual check. A release must include a ZIP and
a `.sha256` or `.sha256.txt` checksum asset. Unverified packages are rejected.
Reports and logs under `%ProgramData%\PCMedic` are preserved during updates.
GitHub Actions builds each release ZIP and matching checksum from the source.

## Repair policy

PC Medic does not automatically download third-party drivers, edit BIOS/UEFI,
delete personal files, clean the registry, disable security, or suppress event
logs. Each repair is opt-in. Create a restore point before servicing Windows.

## Files and logs

- Reports: `%ProgramData%\PCMedic\Reports`
- Logs: `%ProgramData%\PCMedic\Logs`
- Uninstaller: Start menu shortcut or `Uninstall-PCMedic.ps1`

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1
- Administrator account for full diagnostics and repairs
