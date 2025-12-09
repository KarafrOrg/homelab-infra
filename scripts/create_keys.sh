#!/usr/bin/env bash
set -xeuo pipefail

REMOTE_HOSTS="$1"
REMOTE_SSH_USER="$2"
shift 2

IFS=',' read -ra HOST_ARRAY <<< "$REMOTE_HOSTS"

KEYS_DIR="./generated_keys"
mkdir -p "$KEYS_DIR"

echo "📁 Storing keys in: $KEYS_DIR"
echo

for USERNAME in "$@"; do
    KEYFILE="${KEYS_DIR}/${USERNAME}_id_rsa"
    PUBFILE="${KEYFILE}.pub"

    echo "🔑 Generating SSH keypair for user: $USERNAME"
    ssh-keygen -t rsa -b 4096 -N "" -f "$KEYFILE" -C "${USERNAME}@local"

    for REMOTE_HOST in "${HOST_ARRAY[@]}"; do
        echo "📤 Uploading key and setting up on server $REMOTE_HOST..."

        scp "$PUBFILE" "$REMOTE_SSH_USER@$REMOTE_HOST:/tmp/${USERNAME}.pub"

        ssh "$REMOTE_SSH_USER@$REMOTE_HOST" bash <<EOF
set -e
sudo useradd -m -s /bin/bash "$USERNAME" 2>/dev/null || true
sudo mkdir -p /home/$USERNAME/.ssh
sudo sh -c "cat /tmp/${USERNAME}.pub > /home/$USERNAME/.ssh/authorized_keys"
sudo chmod 700 /home/$USERNAME/.ssh
sudo chmod 600 /home/$USERNAME/.ssh/authorized_keys
sudo chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USERNAME > /dev/null
sudo chmod 440 /etc/sudoers.d/$USERNAME
sudo rm -f /tmp/${USERNAME}.pub
EOF

        echo "✔ Installed key for user '$USERNAME' on $REMOTE_HOST"
        ssh -i "$KEYFILE" -o BatchMode=yes -o ConnectTimeout=5 "$USERNAME@$REMOTE_HOST" 'echo "✅ SSH login successful for user: $USERNAME"' \
            || echo "❌ ERROR: SSH login failed for user: $USERNAME on $REMOTE_HOST"
    done

    echo "   → Private Key: $KEYFILE"
    echo "   → Public Key : $PUBFILE"
    echo
done

echo "🎉 All keys generated and successfully installed!"
