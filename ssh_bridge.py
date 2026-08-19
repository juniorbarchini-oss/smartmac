import sys
import subprocess
import json
import re

if len(sys.argv) < 2:
    print(json.dumps({"error": "Missing action (discover or scan)"}))
    sys.exit(1)

action = sys.argv[1]

# Fixed connection credentials based on environment logs and vault
i7_ip = "192.168.100.46"
i7_user = "hbarchini"
i7_pass = "Paraguay1900"

nas_ip = "192.168.100.14"
nas_user = "root"
nas_pass = "paraguay"

def run_ssh_bridge(remote_cmd):
    # macOS command using sshpass to connect to i7server, then running Docker Alpine to connect to NAS
    docker_cmd = f"docker run --rm alpine:3.12 sh -c 'apk add --no-cache openssh-client sshpass && sshpass -p \"{nas_pass}\" ssh -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-dss {nas_user}@{nas_ip} \"{remote_cmd}\"'"
    full_cmd = ["sshpass", "-p", i7_pass, "ssh", "-o", "StrictHostKeyChecking=no", f"{i7_user}@{i7_ip}", docker_cmd]
    
    res = subprocess.run(full_cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise Exception(res.stderr or f"SSH Bridge command failed with code {res.returncode}")
    return res.stdout

if action == "discover":
    try:
        stdout = run_ssh_bridge("ls -d /dev/sd[a-z]")
        lines = stdout.splitlines()
        paths = []
        for line in lines:
            line = line.strip()
            if line.startswith("/dev/sd"):
                paths.append(line)
        print(json.dumps(paths))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)

elif action == "scan":
    if len(sys.argv) < 3:
        print(json.dumps({"error": "Missing device path"}))
        sys.exit(1)
    dev_path = sys.argv[2]
    try:
        stdout = run_ssh_bridge(f"smartctl -a {dev_path}")
        
        model = None
        serial = None
        firmware = None
        passed = True
        temp = None
        power_hours = None
        power_cycles = None
        table = []
        
        lines = stdout.splitlines()
        in_attributes = False
        
        for line in lines:
            line = line.strip()
            
            if "Device Model:" in line:
                model = line.split("Device Model:", 1)[1].strip()
            elif "Serial Number:" in line:
                serial = line.split("Serial Number:", 1)[1].strip()
            elif "Firmware Version:" in line:
                firmware = line.split("Firmware Version:", 1)[1].strip()
            elif "SMART overall-health self-assessment test result:" in line:
                result_str = line.split("SMART overall-health self-assessment test result:", 1)[1].strip()
                passed = (result_str == "PASSED")
            elif "ID# ATTRIBUTE_NAME" in line:
                in_attributes = True
                continue
            
            if in_attributes:
                if not line:
                    continue
                # ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
                parts = line.split()
                if len(parts) >= 10 and parts[0].isdigit():
                    attr_id = int(parts[0])
                    attr_name = parts[1]
                    try:
                        val = int(parts[3])
                        worst = int(parts[4])
                        thresh = int(parts[5])
                    except:
                        val, worst, thresh = None, None, None
                    
                    raw_val_str = parts[-1]
                    try:
                        raw_val = int(re.findall(r'^\d+', raw_val_str)[0])
                    except:
                        raw_val = 0
                        
                    table.append({
                        "id": attr_id,
                        "name": attr_name,
                        "value": val,
                        "worst": worst,
                        "threshold": thresh,
                        "raw": {
                            "value": raw_val,
                            "string": raw_val_str
                        }
                    })
                    
                    if attr_id == 194 or attr_name.lower().startswith("temp") or attr_name.lower() == "temperature_celsius":
                        temp = raw_val
                    elif attr_id == 9 or attr_name.lower().startswith("power_on_hours"):
                        power_hours = raw_val
                    elif attr_id == 12 or attr_name.lower().startswith("power_cycle_count") or attr_name.lower() == "power_cycle_count":
                        power_cycles = raw_val
                        
        response = {
            "model_name": model,
            "serial_number": serial,
            "firmware_version": firmware,
            "device": {
                "name": dev_path,
                "protocol": "SATA"
            },
            "smart_status": {
                "passed": passed
            },
            "temperature": {
                "current": temp if temp is not None else 30
            },
            "power_cycle_count": power_cycles if power_cycles is not None else 0,
            "power_on_time": {
                "hours": power_hours if power_hours is not None else 0
            },
            "ata_smart_attributes": {
                "table": table
            }
        }
        print(json.dumps(response))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
