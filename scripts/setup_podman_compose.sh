#!/bin/bash

# Function to display usage instructions
usage() {
    echo "Usage: $0 -e EMAIL -p PROJECT_NAME -g GITHUB_USERNAME"
    echo "  -e EMAIL            Your email address for SSH key generation"
    echo "  -p PROJECT_NAME     The name of your project on GitHub"
    echo "  -g GITHUB_USERNAME  Your GitHub username"
    exit 1
}

die() {
  echo "$1"
  exit 1
}

pause() {
    read -p "Press Enter to continue..."
}

# Parse command line arguments
while getopts ":e:p:g:" opt; do
  case $opt in
    e) EMAIL=$OPTARG ;;
    p) PROJECT_NAME=$OPTARG ;;
    g) GITHUB_USERNAME=$OPTARG ;;
    *) usage ;;
  esac
done

# Check if email and project name are provided
# Check if any required arguments are missing
if [ -z "$EMAIL" ] || [ -z "$PROJECT_NAME" ] || [ -z "$GITHUB_USERNAME" ]; then
    usage
fi

echo "Does the following information look correct?"
echo "Email: $EMAIL"
echo "Project Name: $PROJECT_NAME"
echo "GitHub Username: $GITHUB_USERNAME"
read -p "Continue? y/n: " -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Update and install necessary packages
echo "Updating package list and installing necessary packages..."
sudo apt update
sudo apt install -y podman python3-pip python3-venv git dbus slirp4netns zsh dbus-x11

# Install omz
echo "Installing oh-my-zsh..."
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended


# change shell to zsh
echo "Changing shell to zsh..."
sudo chsh -s $(which zsh) $USER


# Create and activate the virtual environment
echo "Creating and activating virtual environment for Podman Compose..."
python3 -m venv ~/podman_env
source ~/podman_env/bin/activate


# Install Podman Compose
echo "Installing Podman Compose..."
pip install podman-compose


# Verify Podman Compose installation
echo "Verifying Podman Compose installation..."
podman-compose --version || die "Podman Compose installation failed"


# https://stackoverflow.com/questions/71081234/podman-builds-and-runs-containers-extremely-slow-compared-to-docker
echo "Checking if podman is using vfs instead of fuse-overlayfs..."
echo "You can ignore warnings about cgroupv2 and lingering"
podman info --debug | grep graphDriverName | grep -q vfs
if [ $? -eq 0 ]; then
  echo "podman is using vfs instead of fuse-overlayfs. Switching to fuse-overlayfs..."
  sudo apt install fuse-overlayfs
  /usr/bin/fuse-overlayfs --version || die "fuse-overlayfs installation failed"
  sudo mkdir -p /etc/containers
  sudo echo -e "[storage]\ndriver = \"overlay\"\n\n[storage.options]\nmount_program = \"/usr/bin/fuse-overlayfs\"" | sudo tee /etc/containers/storage.conf
  podman system reset
fi


# Automatically activate the virtual environment on SSH
echo "Configuring shell to automatically activate the virtual environment on SSH login..."

# For Bash
if [ -f ~/.bashrc ]; then
    echo "source ~/podman_env/bin/activate" >> ~/.bashrc
    source ~/.bashrc
fi


# For Zsh
if [ -f ~/.zshrc ]; then
    echo "source ~/podman_env/bin/activate" >> ~/.zshrc
    # https://stackoverflow.com/questions/73077938/how-to-correctly-setup-plugin-nvm-for-oh-my-zsh
    # add zstyle ':omz:plugins:nvm' autoload true to ~/.zshrc
    # to make nvm work with oh-my-zsh
    sed -i '/source $ZSH\/oh-my-zsh.sh/a\  zstyle '\'':omz:plugins:nvm'\'' autoload true' ~/.zshrc
    # don't need to source since running a bash program anyway
fi


# Generate SSH key
echo "Generating SSH key..."
ssh-keygen -t ed25519 -C "$EMAIL" -f ~/.ssh/id_ed25519 -N ""
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519


# Add SSH key to GitHub account manually
echo "Copy the following SSH key and add it to your GitHub account as a repo deploy key:"
cat ~/.ssh/id_ed25519.pub
read -p "Press enter after adding the SSH key to GitHub..."

# Create a directory in /etc/ for the project
echo "Creating directory in /etc/ for the project..."
sudo mkdir -p /etc/$PROJECT_NAME
sudo chown $USER:$USER /etc/$PROJECT_NAME


# Pull code from GitHub
echo "Pulling code from GitHub..."
cd /etc/$PROJECT_NAME
git clone "git@github.com:$GITHUB_USERNAME/$PROJECT_NAME.git" .


# Install NVM and Node.js
echo "Installing NVM and Node.js..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

# Add NVM initialization to shell config files
echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >> ~/.bashrc
echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion' >> ~/.bashrc

# Also add to zshrc since we're using zsh
echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.zshrc
echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >> ~/.zshrc
echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion' >> ~/.zshrc

# Source the NVM initialization for the current session
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

echo "Installing Node.js..."
nvm install --lts || die "nvm installation failed"


echo "Verifying Node.js installation..."
node -v || die "Node.js installation failed"
npm -v || die "npm installation failed"


# Configure default registries for Podman
echo "Configuring default registries for Podman..."
sudo bash -c 'cat > /etc/containers/registries.conf << EOF
[registries.search]
registries = ["docker.io", "quay.io", "registry.fedoraproject.org"]
EOF'


# Install Hasura CLI
echo "Installing Hasura CLI..."
curl -L https://github.com/hasura/graphql-engine/raw/stable/cli/get.sh | bash


# Verify Hasura CLI installation
echo "Verifying Hasura CLI installation..."
hasura version || die "Hasura CLI installation failed"


# Modify net.ipv4.ip_unprivileged_port_start to allow rootless users to bind to ports 80 and 443
echo "Modifying /etc/sysctl.conf to allow rootless users to bind to ports 80 and 443..."
sudo bash -c 'echo "net.ipv4.ip_unprivileged_port_start=80" >> /etc/sysctl.conf'
sudo sysctl -p


# Enable lingering for the user
echo "Enabling lingering for the user..."
sudo loginctl enable-linger $USER


# Enable and start Podman service for the user
echo "Enabling and starting Podman service for the user..."
systemctl --user enable podman
systemctl --user start podman


# WARNING: dbus service is not turned on by default. Should we run it or is there something else at play? 
# systemctl --user start dbus

# Configure Podman to use cgroupfs as the cgroup manager
echo "Configuring Podman to use cgroupfs as the cgroup manager..."
mkdir -p ~/.config/containers
cat > ~/.config/containers/containers.conf << EOF
[engine]
cgroup_manager = "cgroupfs"
EOF


# Set default ssh login shell directory to the code repo
echo "Setting default ssh login shell directory to the code repo..."
echo "cd /etc/$PROJECT_NAME" >> ~/.bashrc
echo "cd /etc/$PROJECT_NAME" >> ~/.zshrc


echo "Setting some nice aliases..."
echo "alias p='podman'" >> ~/.bashrc
echo "alias p='podman'" >> ~/.zshrc
echo "alias pc='podman-compose'" >> ~/.bashrc
echo "alias pc='podman-compose'" >> ~/.zshrc


# Print completion message
echo "Setup complete! You are now ready to use Podman Compose on your Debian instance."
echo "Don't forget to add your SSH key to your GitHub account if you haven't already."
pause