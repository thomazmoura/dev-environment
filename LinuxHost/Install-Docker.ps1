Write-Information "`n->> Installing Docker requirements"
sudo apt-get update
sudo apt-get install `
    ca-certificates `
    curl `
    gnupg `
    lsb-release

Write-Information "`n->> Adding Docker official GPG key"
sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

Write-Information "`n->> Settings up the repository"
echo `
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

Write-Information "`n->> Installing docker"
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

Write-Information "`n->> Starting Docker"
sudo service docker start

Write-Information "`n->> Testing installation"
sudo docker run hello-world

