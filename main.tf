// Tags
locals {
  tags = {
    class      = var.tag_class
    instructor = var.tag_instructor
    semester   = var.tag_semester
  }
}

// Random Suffix Generator
resource "random_integer" "deployment_id_suffix" {
  min = 100
  max = 999
}

// Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.class_name}-${var.student_name}-${var.environment}-${var.location}-${random_integer.deployment_id_suffix.result}"
  location = var.location

  tags = local.tags
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.class_name}-${var.student_name}-${var.environment}-${var.location}-${random_integer.deployment_id_suffix.result}"
  address_space       = ["10.0.0.0/16"] // rubric
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = local.tags
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-${var.class_name}-${var.student_name}-${var.environment}-${var.location}-${random_integer.deployment_id_suffix.result}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"] // rubric

  // service endpoints for Storage + SQL
  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.Sql"
  ]
}

resource "azurerm_storage_account" "storage" {
  name                     = "sto${var.class_name}${var.student_name}${var.environment}${random_integer.deployment_id_suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind                     = "StorageV2"

  // Turn on hierarchical namespace (Data Lake Gen2)
  is_hns_enabled = true

  // IMPORTANT: only accessible from the VNet subnet
  network_rules {
    default_action             = "Deny"                     // block everything else
    virtual_network_subnet_ids = [azurerm_subnet.subnet.id] // allow this subnet
  }

  tags = local.tags
}

resource "azurerm_mssql_server" "sql" {
  name                = "sql-${var.class_name}-${var.student_name}-${var.environment}-${random_integer.deployment_id_suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  version             = "12.0"

  // For the lab it's fine to hard-code something simple & complex enough:
  administrator_login          = "sqladminuser"
  administrator_login_password = "P@ssword12345!"

  minimum_tls_version = "1.2"

  tags = local.tags
}

resource "azurerm_mssql_database" "db" {
  name      = "db-${var.class_name}-${var.student_name}-${var.environment}-${random_integer.deployment_id_suffix.result}"
  server_id = azurerm_mssql_server.sql.id
  sku_name  = "Basic" // rubric: Basic tier

  tags = local.tags
}

// Tie SQL server to the same subnet
resource "azurerm_mssql_virtual_network_rule" "sql_vnet_rule" {
  name      = "sql-vnet-rule-${random_integer.deployment_id_suffix.result}"
  server_id = azurerm_mssql_server.sql.id
  subnet_id = azurerm_subnet.subnet.id
}
