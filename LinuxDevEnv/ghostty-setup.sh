# Ghostty has no official Ubuntu package; this is the community PPA.
# Note: Ubuntu 24.04 support upstream stops at Ghostty 1.3.1.
if command -v ghostty >/dev/null 2>&1; then
  echo "Ghostty already installed: $(ghostty --version | head -1)"
  exit 0
fi

sudo add-apt-repository -y ppa:mkasberg/ghostty-ubuntu
sudo apt update
sudo apt install -y ghostty
