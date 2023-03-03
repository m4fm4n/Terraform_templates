terraform {
  required_version = "1.3.9"
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
      version = "0.85.0"
    }
  }
}

provider "yandex" {
  service_account_key_file = file("<путь к сервисному ключу>")
  cloud_id                 = "<dloud id>"
  folder_id                = "<folder id>"
  zone                     = "ru-central1-a"
}
// Создание сервисного аккаунта
resource "yandex_iam_service_account" "sa" {
  name        = "sa-bucket"
  description = "service account to manage bucket"
}

// Назначение роли сервисному аккаунту
resource "yandex_resourcemanager_folder_iam_member" "sa-editor" {
  folder_id = "b1gp"
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.sa.id}"
}

// Создание статического ключа доступа для сервисного аккаунта
resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  service_account_id = yandex_iam_service_account.sa.id
  description        = "static access key for object storage"
}

// Создание бакета с использованием ключа
resource "yandex_storage_bucket" "start" {
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  bucket     = "start"
}
