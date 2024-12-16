provider "azurerm" {
  features {}
  subscription_id = "subscription_id"
}

variable "resource_group_name" {
  default = "example-rg"
}

variable "location" {
  default = "uksouth"
}

variable "vnet_name" {
  default = "example-vnet"
}

variable "vnet_address_space" {
  default = ["10.0.0.0/16"]
}

variable "subnet_name" {
  default = "private-endpoint-subnet"
}

variable "subnet_address_prefix" {
  default = ["10.0.1.0/24"]
}

resource "azurerm_resource_group" "example" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "example" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = azurerm_resource_group.example.name
  address_space       = var.vnet_address_space
}

resource "azurerm_subnet" "private_endpoint" {
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = var.subnet_address_prefix

  service_endpoints = ["Microsoft.Storage"]
}

resource "random_id" "unique_suffix" {
  byte_length = 8
}

resource "random_id" "app_service_suffix" {
  byte_length = 4
}

resource "azurerm_storage_account" "example" {
  name                     = "examplestorageacct${substr(lower(random_id.unique_suffix.hex), 0, 6)}"
  resource_group_name      = azurerm_resource_group.example.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_private_endpoint" "storage_account" {
  name                = "example-private-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.example.name
  subnet_id           = azurerm_subnet.private_endpoint.id

  private_service_connection {
    name                           = "example-storage-connection"
    private_connection_resource_id = azurerm_storage_account.example.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }
}

resource "azurerm_private_dns_zone" "storage" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "vnet_link" {
  name                  = "example-dns-link"
  resource_group_name   = azurerm_resource_group.example.name
  private_dns_zone_name = azurerm_private_dns_zone.storage.name
  virtual_network_id    = azurerm_virtual_network.example.id
}

resource "azurerm_private_dns_a_record" "example" {
  name                = azurerm_storage_account.example.name
  zone_name           = azurerm_private_dns_zone.storage.name
  resource_group_name = azurerm_resource_group.example.name
  ttl                 = 300

  records = [
    azurerm_private_endpoint.storage_account.private_service_connection[0].private_ip_address
  ]
}

resource "azurerm_storage_account_network_rules" "example" {
  storage_account_id         = azurerm_storage_account.example.id
  default_action             = "Deny"
  bypass                     = ["AzureServices"]
  virtual_network_subnet_ids = [azurerm_subnet.private_endpoint.id]
}

resource "azurerm_service_plan" "example" {
  name                = "example-service-plan"
  location            = var.location
  resource_group_name = azurerm_resource_group.example.name
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_app_service" "example" {
  name                = "example-app-service-${random_id.app_service_suffix.hex}"
  location            = var.location
  resource_group_name = azurerm_resource_group.example.name
  app_service_plan_id = azurerm_service_plan.example.id
}
