#echo 'deb http://download.opensuse.org/repositories/home:/opcm/Debian_Unstable/ /' | sudo tee /etc/apt/sources.list.d/home:opcm.list
#curl -fsSL https://download.opensuse.org/repositories/home:opcm/Debian_Unstable/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_opcm.gpg > /dev/null
#sudo apt update
#sudo apt install pcm

echo 'deb http://download.opensuse.org/repositories/home:/opcm/Debian_10/ /' | sudo tee /etc/apt/sources.list.d/home:opcm.list
curl -fsSL https://download.opensuse.org/repositories/home:opcm/Debian_10/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_opcm.gpg > /dev/null
sudo apt update
sudo apt install pcm
