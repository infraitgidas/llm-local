# Proxmox Basics — VM and Container Management

## Creating Virtual Machines

### Creating a VM from the Command Line

To create a virtual machine with Proxmox, use the `qm create` command:

```bash
# Create a VM with 2 cores and 4GB RAM
qm create 100 --cores 2 --memory 4096 --net0 virtio,bridge=vmbr0

# Create a VM with specific storage and OS
qm create 101 --cores 4 --memory 8192 --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci --scsi0 local-lvm:32

# Set boot order
qm set 100 --boot order=scsi0;net0
```

### VM Configuration Options

- `--cores`: Number of CPU cores (1-32)
- `--memory`: RAM in MB (512-262144)
- `--net0`: Network adapter (virtio, e1000, rtl8139) with bridge
- `--scsi0`: SCSI disk (storage:size)
- `--sockets`: CPU sockets (default: 1)
- `--ostype`: OS type (l26, win10, etc.)

### Starting and Stopping VMs

```bash
# Start a VM
qm start 100

# Stop a VM (ACPI shutdown)
qm stop 100

# Force stop a VM
qm stop 100 --skiplock

# Reboot a VM
qm reboot 100

# Get VM status
qm status 100
```

### Creating VMs from Templates

```bash
# Clone from template
qm clone 9000 200 --name web-server --full 1

# Convert VM to template
qm template 9000
```

## Creating Containers (CT)

### Creating a Container

```bash
# Create a container with Ubuntu 22.04
pct create 300 local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \
  --cores 2 --memory 2048 --net0 name=eth0,bridge=vmbr0,ip=dhcp

# Create with root password
pct create 301 local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
  --cores 1 --memory 1024 --password "secure-password" \
  --storage local-lvm
```

### Container Management Commands

```bash
# Start container
pct start 300

# Stop container
pct stop 300

# Enter container shell
pct enter 300

# Show container config
pct config 300

# Set container resources
pct set 300 --cores 4 --memory 4096

# List containers
pct list
```

## Storage Management

### Storage Configuration

```bash
# List storage
pvesm status

# Add storage
pvesm add dir backup --path /backup --content backup

# Add NFS storage
pvesm add nfs nas --server 192.168.1.100 --export /volume1/proxmox \
  --content images,rootdir

# Check disk usage
df -h
pvesm status | grep -E "local|backup"
```

### Backup and Restore

```bash
# Backup a VM
vzdump 100 --compress zstd --mode snapshot --storage backup

# Backup all VMs
for vmid in $(qm list | awk 'NR>1{print $1}'); do
  vzdump $vmid --compress zstd --mode snapshot --storage backup
done

# Restore a VM from backup
qmrestore /backup/dump/vzdump-qemu-100-2024_01_15-00_00_00.vma.zst 100
```

## Network Configuration

### Bridge Networking

```bash
# Create a Linux bridge
pvesh create /network --type bridge --iface vmbr1 --bridge_ports eth1

# Show network config
cat /etc/network/interfaces

# Restart networking
systemctl restart networking
```

### Firewall Rules

```bash
# Enable firewall on node
pvesh set /nodes/proxmox/firewall/options --enable 1

# Add firewall rule for a VM
pvesh create /nodes/proxmox/qemu/100/firewall/rules \
  --action ACCEPT --proto tcp --dport 80,443 --source 192.168.1.0/24
```

## Cluster Management

```bash
# Create cluster
pvecm create mycluster

# Join cluster
pvecm add 192.168.1.10

# Check cluster status
pvecm status

# Remove node from cluster
pvecm delnode proxmox-node2
```

## Common Administration Commands

- `systemctl status pvestatd` — Check Proxmox VE status daemon
- `journalctl -u pvedaemon` — Check Proxmox daemon logs
- `pveversion` — Show Proxmox version
- `pvesh get /cluster/resources` — List all cluster resources
- `cat /etc/pve/datacenter.cfg` — Show datacenter configuration
