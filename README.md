# SmartMacApp

A native macOS storage diagnostic dashboard designed to centralize the health, S.M.A.R.T. statistics, and performance of local internal drives, external USB enclosures, and remote network hosts (via SSH) with **on-demand scans** and zero persistent background overhead.

## Philosophy

*   **On-Demand:** Runs only when opened, avoiding continuous CPU/battery drain.
*   **Agentless Remote Scanning:** Direct SSH connections using Swift's native Citadel library to execute commands on remote servers (NAS, Linux hosts) without local agent installations.
*   **Dynamic Theme Selection:** Settings options to choose between Light Mode, Dark Mode, or Automatic (System Default).

## How to Compile & Run

We have prepared a light build script that compiles the Swift code using your local macOS SDK and packages it as a native `.app` bundle, which you can run immediately without opening Xcode.

1.  Open your Terminal.
2.  Navigate to this project folder:
    ```bash
    cd "/Users/hbarchini/Documents/desarrollo/smartmac-app"
    ```
3.  Compile the application:
    ```bash
    ./build.sh
    ```
4.  Open and run the compiled application:
    ```bash
    open SmartMac.app
    ```

## Project Files

*   `main.swift`: The single-entry Swift source code implementing the SwiftUI user interface, mock models, and data sheets.
*   `Info.plist`: Key-value application property list identifying the executable and system version targets.
*   `build.sh`: Automated terminal script to build, compile, and structure the native macOS application bundle.
