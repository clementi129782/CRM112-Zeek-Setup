#! /bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# ===================================================================
# 1. Add Zeek Repository
# ===================================================================
# Register the Repository to APT.
echo "deb http://download.opensuse.org/repositories/security:/zeek/xUbuntu_24.04/ /" \
  | sudo tee /etc/apt/sources.list.d/security:zeek.list

# Trust the Repository Key.
curl -fsSL https://download.opensuse.org/repositories/security:zeek/xUbuntu_24.04/Release.key \
  | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/security_zeek.gpg

# ===================================================================
# 2. Add Filebeat Repository
# ===================================================================
# Register the Repository to APT.
echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

# Trust the Repository Key.
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch \
  | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/elastic.gpg

# ===================================================================
# 3. Update APT and Install Zeek and Filebeat.
# ===================================================================
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y zeek
sudo DEBIAN_FRONTEND=noninteractive apt install -y filebeat

# ===================================================================
# 4. Create a symbolic link to /usr/bin for Zeek.
# ===================================================================
sudo ln -sf /opt/zeek/bin/zeek /usr/local/bin/zeek

# ===================================================================
# 5. Get all active interfaces except loopback interfaces.
# ===================================================================
ACTIVE_IFACES=($(ip -o link show up | awk -F': ' '{print $2}' | grep -v '^lo$'))
echo "Active interfaces: ${ACTIVE_IFACES[@]}"

# ===================================================================
# 6. Configure Zeek to monitor all active interfaces.
# ===================================================================
NODE_CFG="/opt/zeek/etc/node.cfg"

# Commentout the default interface line.
sudo sed -i 's/^interface\s*=.*/# &/' "$NODE_CFG"

# Add new interfaces.
for IFACE in "${ACTIVE_IFACES[@]}"; do
    echo "interface=$IFACE" | sudo tee -a "$NODE_CFG" >/dev/null
done

# ===================================================================
# 7. Enable JSON logging.
# ===================================================================
LOCAL_ZEEK="/opt/zeek/share/zeek/site/local.zeek"

# Enable policy/tuning/json-logs.zeek in local.zeek.
if ! grep -q '@load policy/tuning/json-logs.zeek' "$LOCAL_ZEEK"; then
    echo '@load policy/tuning/json-logs.zeek' | sudo tee -a "$LOCAL_ZEEK" >/dev/null
fi

# ===================================================================
# 8. Restart Zeek and Filebeat.
# ===================================================================
cd /opt/zeek
sudo ./bin/zeekctl deploy
sudo filebeat modules enable system

# ===================================================================
# 9. Configure Filebeat to ship Zeek logs.
# ===================================================================
FILEBEAT_SYS_YML="/etc/filebeat/modules.d/system.yml"
FILEBEAT_ZEEK_YML="/etc/filebeat/modules.d/zeek.yml"

# Change "syslog.enabled" to "true".
sudo sed -i 's/^\(\s*enabled:\s*\)false$/\1true/' "$FILEBEAT_SYS_YML"
# Change "auth.enabled" to "false".
sudo sed -i '/^\s*auth:/!b;n;s/^\(\s*enabled:\s*\)true$/\1false/' "$FILEBEAT_SYS_YML"
# Enable zeek modules.
sudo filebeat modules enable zeek

# Download the file and update /etc/filebeat/modules.d/zeek.yml
FILEBEAT_MODULE_ZEEK_URL="https://raw.githubusercontent.com/clementi129782/CRM112-Zeek-Setup/main/filebeat-zeek.yml"
TMP_FILE=$(mktemp)
curl -fsSL "$FILEBEAT_MODULE_ZEEK_URL" -o "$TMP_FILE"
sudo cp "$TMP_FILE" /etc/filebeat/modules.d/zeek.yml
rm -f "$TMP_FILE"
sudo systemctl restart filebeat



