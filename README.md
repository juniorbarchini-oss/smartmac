# SmartMac

⚡ **SmartMac** is a native macOS storage diagnostic utility and S.M.A.R.T. telemetry dashboard. It is designed to inspect, monitor, and export health analytics of local drives (internal and external USB enclosures) as well as remote network servers (NAS, Linux hosts) under a single, cohesive interface.

Designed with an **on-demand philosophy**, SmartMac runs only when you need it, leaving zero persistent daemons or background processes to consume your Mac's CPU, RAM, or battery.

---

## Features

- **Apple Silicon SSD Lifespan Projections:** Estimator algorithm that projects remaining lifespan in years and TBW (Terabytes Written) based on actual power-on hours and write wear, with smart calibration to prevent false anomalies on new drives.
- **Hierarchical Sidebar (Finder-Style):** Organizes local and remote physical storage devices by host.
- **Consolidated Export Sheets:** Generate comprehensive diagnostic reports in a single file:
  - **Markdown (.md)** for easy Obsidian indexing.
  - **Word Document (.doc)** styled with HTML templates.
  - **Excel/CSV (.csv)** consolidating all selected metrics.
  - **PDF Document (.pdf)** rendering a multi-page, high-resolution vector layout page-by-page.
- **Agentless Remote Monitoring:** Inspect servers, NAS units, or Linux hosts securely over SSH using system bridges.
- **Dynamic USB Mounting Support:** Automatically registers when a USB drive is plugged in or safely ejected, updating the sidebar in real time.
- **Dynamic Path Resolution:** Automatically locates `smartctl` binaries on both **Apple Silicon** (Homebrew `/opt/homebrew`) and **Intel** (Homebrew `/usr/local`) macOS architectures.
- **Dark Mode & Appearance:** Toggle between Light Mode, Dark Mode, or Automatic System Theme.

---

## Requirements

### Local Drive Scanning
To read local S.M.A.R.T. telemetry on macOS, the application requires the `smartctl` utility. You can install it easily using Homebrew:
```bash
brew install smartmontools
```

### Remote Server Scanning
No local installation is required on your Mac to scan remote servers. The remote host (e.g., Ubuntu, Debian, TrueNAS) simply needs SSH enabled and `smartctl` installed:
```bash
# Ubuntu / Debian
sudo apt install smartmontools
```

---

## Compilation & Installation

You can compile the Swift source code into a native macOS application bundle (`.app`) without opening Xcode.

1. **Clone the Repository:**
   ```bash
   git clone https://github.com/juniorbarchini-oss/smartmac.git
   cd smartmac
   ```

2. **Run the Build Script:**
   ```bash
   chmod +x build.sh
   ./build.sh
   ```

3. **Launch the App:**
   The compiled bundle will be created at the root directory as `SmartMac.app`. Run it by typing:
   ```bash
   open SmartMac.app
   ```

---

## Project Structure

- `main.swift`: Monolithic Swift source file containing the SwiftUI layouts, SSH execution bridges, and CoreGraphics PDF rendering engines.
- `Info.plist`: Key-value application property configuration file containing version identifiers and target SDK requirements.
- `AppIcon.icns`: Compiled macOS high-resolution icon bundle.
- `build.sh`: Shell script to compile, structure, and package the binary into a native Apple application bundle.

---

## Credits

- **Concept, Design & Development:** Humberto Barchini (HB) & Antigravity (AGY)
- **License:** Open Source under the MIT License.

---

## 🌟 Support & Donations

If you find SmartMac useful, you can support the project in two ways:

1. **Star the Repository:** Click the ⭐ button at the top right of this page to show your support and make the project more visible to other administrators.
2. **Buy Me a Coffee:** If the tool saved you time or database diagnostic headaches, feel free to support our work:

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Donate-orange?style=for-the-badge&logo=buy-me-a-coffee&logoColor=white)](https://www.buymeacoffee.com/YOUR_USERNAME)

