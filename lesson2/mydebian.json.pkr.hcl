source "yandex" "debian_docker" {
  disk_type            = "network-hdd"
  folder_id            = "b1gsa2kcqehoccjns0kd"
  image_description    = "my custom debian with docker"
  image_name           = "debian-11-docker"
  source_image_family  = "debian-11"
  ssh_username         = "debian"
  subnet_id            = "e2lrleoki0nfi3u5v8pr"
  token                = "XXXXXXX"
  use_ipv4_nat         = true
  zone                 = "ru-central1-b"
}

build {
  sources = ["source.yandex.debian_docker"]

  provisioner "shell" {
    inline = [
      "sudo cloud-init status --wait || true",
      "sleep 15",
      "sudo rm -rf /var/lib/apt/lists/*",
      "sudo apt-get clean",
      "sudo apt-get update -y",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl",
      "sudo install -m 0755 -d /etc/apt/keyrings",
      "sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc",
      "sudo chmod a+r /etc/apt/keyrings/docker.asc",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "for i in 1 2 3 4 5; do sudo apt-get update -y && break || sleep 10; done",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o Acquire::Retries=5 --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends htop tmux",
      "sudo docker --version",
      "sudo docker compose version"
    ]
  }
}
