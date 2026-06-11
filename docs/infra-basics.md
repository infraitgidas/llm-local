# Linux Infrastructure Basics

## System Monitoring

### CPU and Memory Monitoring

```bash
# Real-time process overview
top

# Better process viewer
htop

# Memory usage
free -h

# Memory in megabytes
free -m

# Disk usage
df -h

# Disk usage per directory
du -sh /var/log

# I/O statistics
iostat -x 1
```

### Service Management with systemd

```bash
# Check service status
systemctl status sshd

# Start a service
sudo systemctl start nginx

# Stop a service
sudo systemctl stop nginx

# Enable service at boot
sudo systemctl enable nginx

# Disable service at boot
sudo systemctl disable nginx

# Restart service
sudo systemctl restart nginx

# Reload config without restart
sudo systemctl reload nginx

# List all running services
systemctl list-units --type=service --state=running

# View service logs
journalctl -u nginx

# Follow service logs in real-time
journalctl -u nginx -f
```

### Network Diagnostics

```bash
# Show listening ports
ss -tlnp

# Show network interfaces
ip addr show

# Show routing table
ip route show

# DNS resolution test
nslookup google.com

# Network connectivity test
ping -c 4 8.8.8.8

# Trace route
traceroute google.com

# Bandwidth test
iperf3 -c server-ip

# Check if port is open
nc -zv 192.168.1.1 22
```

## File System Operations

### File Permissions

```bash
# Change file permissions
chmod 755 script.sh
chmod 644 config.json

# Change owner
chown user:group file.txt

# Recursive permission change
chmod -R 755 /var/www

# Set setuid/setgid
chmod u+s /usr/bin/program
chmod g+s /shared/directory
```

### Disk Management

```bash
# List block devices
lsblk

# Show disk partitions
fdisk -l

# Mount filesystem
sudo mount /dev/sdb1 /mnt/data

# Mount with options
sudo mount -o noexec,nosuid /dev/sdb1 /mnt/data

# Unmount
sudo umount /mnt/data

# Check filesystem
sudo fsck /dev/sdb1

# Create filesystem
sudo mkfs.ext4 /dev/sdb1

# Check disk SMART status
sudo smartctl -a /dev/sda
```

### LVM Management

```bash
# List physical volumes
pvs

# List volume groups
vgs

# List logical volumes
lvs

# Create logical volume
sudo lvcreate -L 10G -n myvolume vg_main

# Extend logical volume
sudo lvextend -L +5G /dev/vg_main/myvolume
sudo resize2fs /dev/vg_main/myvolume
```

## Process Management

```bash
# List processes
ps aux

# Process tree
ps auxf

# Kill by PID
kill -15 1234

# Force kill
kill -9 1234

# Kill by name
pkill -f "process-name"

# Find process by name
pgrep -l ssh

# Nice value (priority)
nice -n 10 ./my-program
renice -n 5 -p 1234
```

## Log Management with journalctl

```bash
# Show all logs
journalctl

# Show logs since last boot
journalctl -b

# Logs in last hour
journalctl --since "1 hour ago"

# Kernel messages
journalctl -k

# Follow new log entries
journalctl -f

# Show logs by priority
journalctl -p err -b
```

## Bash Scripting Basics

### Safe Script Template

```bash
#!/bin/bash
# script.sh — Description of what this script does
#
# Usage: ./script.sh [options]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
    echo "Usage: $0 [options]"
    echo "  -h, --help     Show this help"
    echo "  -d, --dry-run  Show what would be done"
    exit 1
}

# Parse arguments
DRY_RUN=false
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage ;;
        -d|--dry-run) DRY_RUN=true; shift ;;
        *) error "Unknown option: $1"; usage ;;
    esac
done

# Main logic
if [ "$DRY_RUN" = true ]; then
    echo "[DRY-RUN] Would execute: command arg1 arg2"
else
    echo "[INFO] Executing: command arg1 arg2"
    # Actual command here
fi
```

### Common Bash Patterns

```bash
# Check if command exists
command -v curl &>/dev/null || { echo "curl is required"; exit 1; }

# Check if file exists
if [ -f "/path/to/file" ]; then
    echo "File exists"
fi

# Loop through items
for item in "${list[@]}"; do
    echo "$item"
done

# Read file line by line
while IFS= read -r line; do
    echo "$line"
done < "input.txt"

# Function definition
my_function() {
    local arg1="$1"
    echo "Argument: $arg1"
}
```
