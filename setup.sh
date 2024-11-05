#!/bin/bash

echo "In loving memory of my father, Richard 'Rick' Wilson."
echo "--------------------------------------"
echo " PXE Boot & HPC Cluster Setup Script"
echo "--------------------------------------"
echo "Created by: ChatGPT for user’s customized high-performance cluster setup."
echo "This script will configure PXE boot, Rocks OS, and a Beowulf-style cluster setup on RockyOS 9.4 in VirtualBox."
echo ""
echo "Let's get started with the setup!"

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root. Exiting..."
   exit 1
fi

# Install required packages
echo "Installing required packages..."
dnf install -y dhcp-server tftp-server httpd syslinux nfs-utils wget

# Interactive user inputs
read -p "Enter the path to your Rocks OS ISO (e.g., /path/to/rocks.iso): " ROCKS_ISO_PATH
if [[ ! -f "$ROCKS_ISO_PATH" ]]; then
    echo "ISO file not found. Exiting..."
    exit 1
fi

# Prompt for password, encryption, and timezone
read -s -p "Enter a root password for PXE clients: " ROOT_PASSWORD
ROOT_PASSWORD_HASH=$(openssl passwd -1 "$ROOT_PASSWORD")
TIMEZONE=$(timedatectl | grep "Time zone" | awk '{print $3}')

# Create directories for PXE and HTTP
echo "Setting up directories for PXE boot and HTTP..."
PXE_DIR="/var/lib/tftpboot"
HTTP_DIR="/var/www/html/rocks"
mkdir -p "$PXE_DIR" "$HTTP_DIR"

# Copy Rocks OS kernel and initrd to PXE directory
echo "Extracting and copying kernel and initrd for PXE boot..."
mount -o loop "$ROCKS_ISO_PATH" /mnt
cp /mnt/isolinux/vmlinuz "$PXE_DIR"
cp /mnt/isolinux/initrd.img "$PXE_DIR"

# Generate PXE configuration file
echo "Creating PXE configuration..."
cat > "$PXE_DIR/pxelinux.cfg/default" << EOF
DEFAULT rocks
LABEL rocks
  KERNEL vmlinuz
  APPEND initrd=initrd.img ks=http://$(hostname -I | awk '{print $1}')/rocks/ks.cfg
EOF

# Copy Rocks OS ISO contents to HTTP directory
echo "Copying Rocks OS contents to HTTP directory. This may take some time..."
rsync -a /mnt/ "$HTTP_DIR"
umount /mnt

# Create Kickstart file
echo "Creating Kickstart configuration (ks.cfg)..."
cat > "$HTTP_DIR/ks.cfg" << EOF
# Kickstart configuration for Rocks OS
auth --enableshadow --passalgo=sha512
rootpw --iscrypted $ROOT_PASSWORD_HASH
timezone $TIMEZONE --isUtc
url --url=http://$(hostname -I | awk '{print $1}')/rocks
keyboard us
clearpart --all --initlabel
autopart
bootloader --location=mbr
text
firstboot --disable
services --disabled firewalld,sshd
%packages
@Core
nfs-utils
openmpi
openblas
EOF

# Configuring DHCP
echo "Configuring DHCP server..."
cat > /etc/dhcp/dhcpd.conf << EOF
subnet $(hostname -I | awk '{print $1}' | cut -d"." -f1-3).0 netmask 255.255.255.0 {
  range $(hostname -I | awk '{print $1}' | cut -d"." -f1-3).50 $(hostname -I | awk '{print $1}' | cut -d"." -f1-3).100;
  option routers $(hostname -I | awk '{print $1}');
  option domain-name-servers 8.8.8.8;
  filename "pxelinux.0";
  next-server $(hostname -I | awk '{print $1}');
}
EOF

# Enable and start services
echo "Enabling and starting services..."
systemctl enable dhcpd httpd tftp
systemctl start dhcpd httpd tftp

# Optional: LLM and MPI tools installation
echo "Installing optional packages for HPC and local LLM support..."
dnf install -y openmpi openblas

# Setup NFS (Network File System) for shared storage
echo "Configuring NFS shared storage..."
echo "$HTTP_DIR *(rw,sync,no_root_squash)" >> /etc/exports
exportfs -a
systemctl enable nfs-server
systemctl start nfs-server

# Basic System Hardening
echo "Applying basic system hardening..."
dnf install -y fail2ban
systemctl enable fail2ban
systemctl start fail2ban
echo "Root login via SSH is disabled for enhanced security."
echo "PermitRootLogin no" >> /etc/ssh/sshd_config
systemctl restart sshd

# Display completion message with AI-style progress bars
echo "------------------------"
echo " PXE Setup Complete! "
echo "------------------------"
for i in {1..10}; do
    echo -ne "Loading... ["
    for ((j=0; j<i; j++)); do echo -ne "🧠"; done
    echo -ne "] $((i * 10))%\r"
    sleep 0.5
done
echo -e "\nAll systems are ready for PXE boot and Rocks OS deployment."

echo "To start deploying bare-metal nodes, boot them from PXE (network boot) mode. They will connect to this server, load Rocks OS, and join your HPC cluster!"
