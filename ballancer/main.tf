terraform {
  required_version = "1.3.9"
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.85.0"
    }
  }
// Подключаем хранилище для файла tfstate
  backend "s3" {
    endpoint   = "storage.yandexcloud.net"
    bucket     = "start"
    region     = "ru-central1"
    key        = "bucket/terraform.tfstate"
    access_key = "<открытый ключ>"
    secret_key = "<закрытый ключ, добывается из web>"

    skip_region_validation      = true
    skip_credentials_validation = true
  }
}

provider "yandex" {
  service_account_key_file = file("<путь к ключу>")
  cloud_id                 = "id"
  folder_id                = "id"
}
// Создаём виртуальный интернет
resource "yandex_vpc_network" "terra" {
  name = "terranet"
}
// Создаём виртуальную локальную сеть 1 в одном регионе..
resource "yandex_vpc_subnet" "subterra1" {
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.terra.id  
  v4_cidr_blocks = ["192.168.10.0/24"]
  name           = "subterra1"
}
// Создаём сеть 2 в другом регионе
resource "yandex_vpc_subnet" "subterra2" {
  name           = "subterra2"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.terra.id
  v4_cidr_blocks = ["192.168.11.0/24"]
}
// Поиск образов установки
data "yandex_compute_image" "lemp" {
  family = "lemp"
}

data "yandex_compute_image" "lamp" {
  family = "lamp"
}
// Описываем ВМ. Одна в одной сети и регионе, другая в другом
resource "yandex_compute_instance" "vm_1" {
  name = "terraform-vm-1"
  zone = "ru-central1-a"

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.lemp.id
      size     = 15
      type     = "network-hdd"
  }
}
// Прерываемая ВМ
  scheduling_policy {
    preemptible = true
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subterra1.id
    nat       = true
  }
// Передаём свой открытый ключ в authorized_key ВМ
  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
}

resource "yandex_compute_instance" "vm_2" {
  name = "terraform-vm-2"
  zone = "ru-central1-b" 

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
}

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.lamp.id
      size     = 15
      type     = "network-hdd"
  }  
}

  scheduling_policy {
    preemptible = true
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subterra2.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
}
// Создаём балансировщик двух ВМ
resource "yandex_lb_network_load_balancer" "balancer" {
  name = "my-network-load-balancer"

  listener {
    name = "my-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = "${yandex_lb_target_group.targro.id}"

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}

resource "yandex_lb_target_group" "targro" {
  name      = "my-target-group"
  region_id = "ru-central1"

  target {
    subnet_id = "${yandex_vpc_subnet.subterra1.id}"
    address   = "${yandex_compute_instance.vm_1.network_interface.0.ip_address}"
  }

  target {
    subnet_id = "${yandex_vpc_subnet.subterra2.id}"
    address   = "${yandex_compute_instance.vm_2.network_interface.0.ip_address}"
  }
}
