#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./generate_and_upload_keys.sh <remote_host> <ssh_user> <username1> <username2> ...
#
# Example:
#   ./generate_and_upload_keys.sh 192.168.1.10 ubuntu ansible automation

REMOTE_HOST="$1"
REMOTE_SSH_USER="$2"
shift 2

KEYS_DIR="./generated_keys"
mkdir -p "$KEYS_DIR"

echo "📁 Storing keys in: $KEYS_DIR"
echo

for USERNAME in "$@"; do
    KEYFILE="${KEYS_DIR}/${USERNAME}_id_rsa"
    PUBFILE="${KEYFILE}.pub"

    echo "🔑 Generating SSH keypair for user: $USERNAME"

    # Generate key locally
    ssh-keygen -t rsa -b 4096 -N "" -f "$KEYFILE" -C "${USERNAME}@local"

    echo "📤 Uploading key and setting up on server..."

    # Create the user + SSH folder on server
    ssh "$REMOTE_SSH_USER@$REMOTE_HOST" bash <<EOF
set -e

if ! id "$USERNAME" &>/dev/null; then
    sudo useradd -m -s /bin/bash "$USERNAME"
fi

sudo mkdir -p /home/$USERNAME/.ssh
sudo touch /home/$USERNAME/.ssh/authorized_keys
sudo chmod 700 /home/$USERNAME/.ssh
sudo chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
EOF

    # Upload public key to a temp file
    scp "$PUBFILE" "$REMOTE_SSH_USER@$REMOTE_HOST:/tmp/${USERNAME}.pub"

    # Append it to authorized_keys
    ssh "$REMOTE_SSH_USER@$REMOTE_HOST" bash <<EOF
set -e
sudo sh -c "cat /tmp/${USERNAME}.pub >> /home/$USERNAME/.ssh/authorized_keys"
sudo chmod 600 /home/$USERNAME/.ssh/authorized_keys
sudo chown $USERNAME:$USERNAME /home/$USERNAME/.ssh/authorized_keys
sudo rm -f /tmp/${USERNAME}.pub
EOF

    echo "✔ Installed key for user '$USERNAME'"
    echo "   → Private Key: $KEYFILE"
    echo "   → Public Key : $PUBFILE"
    echo
done

echo "🎉 All keys generated and successfully installed!"
