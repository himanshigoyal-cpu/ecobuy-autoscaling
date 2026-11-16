terraform {
  required_providers { azurerm = { source = "hashicorp/azurerm", version = "~> 3.100" } }
}
provider "azurerm" { features {} }

variable "location"       { default = "eastus" }
variable "alert_email"    { description = "Email for alerts" }
variable "admin_password" {
  description = "VM admin password (12+ chars, upper, lower, number, symbol)"
  sensitive   = true
}

locals { tags = { Project = "EcoBuy", Env = "dev", Owner = "student" } }

resource "azurerm_resource_group" "rg" {
  name     = "ecobuy-rg"
  location = var.location
  tags     = local.tags
}

# ---------- Network ----------
resource "azurerm_virtual_network" "vnet" {
  name                = "ecobuy-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}
resource "azurerm_subnet" "web" {
  name                 = "web"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}
resource "azurerm_network_security_group" "nsg" {
  name                = "ecobuy-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  tags = local.tags
}
resource "azurerm_subnet_network_security_group_association" "a" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# ---------- Load balancer ----------
resource "azurerm_public_ip" "lb" {
  name                = "ecobuy-lb-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "ecobuy-${substr(md5(azurerm_resource_group.rg.id), 0, 6)}"
  tags                = local.tags
}
resource "azurerm_lb" "lb" {
  name                = "ecobuy-lb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.lb.id
  }
  tags = local.tags
}
resource "azurerm_lb_backend_address_pool" "pool" {
  loadbalancer_id = azurerm_lb.lb.id
  name            = "web-pool"
}
resource "azurerm_lb_probe" "health" {
  loadbalancer_id     = azurerm_lb.lb.id
  name                = "health-probe"
  protocol            = "Http"
  port                = 80
  request_path        = "/health"
  interval_in_seconds = 15
  number_of_probes    = 2
}
resource "azurerm_lb_rule" "http" {
  loadbalancer_id                = azurerm_lb.lb.id
  name                           = "http"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "public"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.pool.id]
  probe_id                       = azurerm_lb_probe.health.id
}

# ---------- Scale set ----------
resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                            = "ecobuy-vmss"
  location                        = azurerm_resource_group.rg.location
  resource_group_name             = azurerm_resource_group.rg.name
  sku                             = "Standard_B1s"
  instances                       = 2
  admin_username                  = "azureuser"
  admin_password                  = var.admin_password
  disable_password_authentication = false
  upgrade_mode                    = "Manual"
  zones                           = ["1", "2"]
  custom_data                     = base64encode(replace(file("${path.module}/user_data.sh"), "__APP_PY__", file("${path.module}/app.py")))

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }
  identity { type = "SystemAssigned" }
  network_interface {
    name    = "nic"
    primary = true
    ip_configuration {
      name                                   = "ipconfig"
      primary                                = true
      subnet_id                              = azurerm_subnet.web.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.pool.id]
      public_ip_address { name = "vm-pip" }   # gives instances outbound internet for apt/pip
    }
  }
  tags       = local.tags
  depends_on = [azurerm_lb_rule.http]
  lifecycle { ignore_changes = [instances, extension] }
}

# ---------- Autoscale ----------
resource "azurerm_monitor_autoscale_setting" "auto" {
  name                = "ecobuy-autoscale"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.vmss.id
  profile {
    name = "cpu-based"
    capacity {
      default = 2
      minimum = 2
      maximum = 6
    }
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 50
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "2"
        cooldown  = "PT5M"
      }
    }
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
  tags = local.tags
}

# ---------- Monitoring and logging ----------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "ecobuy-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}
resource "azurerm_monitor_data_collection_rule" "dcr" {
  name                = "ecobuy-dcr"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.law.id
      name                  = "law"
    }
  }
  data_flow {
    streams      = ["Microsoft-Syslog", "Microsoft-Perf"]
    destinations = ["law"]
  }
  data_sources {
    syslog {
      name           = "app-logs"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["local0"]
      log_levels     = ["Debug", "Info", "Notice", "Warning", "Error", "Critical", "Alert", "Emergency"]
    }
    performance_counter {
      name                          = "perf"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers            = ["\\Processor Information(_Total)\\% Processor Time", "\\Memory\\% Used Memory"]
    }
  }
  tags = local.tags
}
resource "azurerm_virtual_machine_scale_set_extension" "ama" {
  name                         = "AzureMonitorLinuxAgent"
  virtual_machine_scale_set_id = azurerm_linux_virtual_machine_scale_set.vmss.id
  publisher                    = "Microsoft.Azure.Monitor"
  type                         = "AzureMonitorLinuxAgent"
  type_handler_version         = "1.0"
  auto_upgrade_minor_version   = true
}
resource "azurerm_monitor_data_collection_rule_association" "assoc" {
  name                    = "ecobuy-dcr-assoc"
  target_resource_id      = azurerm_linux_virtual_machine_scale_set.vmss.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.dcr.id
  depends_on              = [azurerm_virtual_machine_scale_set_extension.ama]
}

resource "azurerm_monitor_action_group" "ag" {
  name                = "ecobuy-alerts"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "ecobuy"
  email_receiver {
    name          = "admin"
    email_address = var.alert_email
  }
  tags = local.tags
}
resource "azurerm_monitor_metric_alert" "cpu" {
  name                = "ecobuy-cpu-high"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_linux_virtual_machine_scale_set.vmss.id]
  frequency           = "PT1M"
  window_size         = "PT5M"
  severity            = 2
  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachineScaleSets"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 70
  }
  action { action_group_id = azurerm_monitor_action_group.ag.id }
  tags = local.tags
}
resource "azurerm_monitor_metric_alert" "health" {
  name                = "ecobuy-backend-unhealthy"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_lb.lb.id]
  frequency           = "PT1M"
  window_size         = "PT5M"
  severity            = 1
  criteria {
    metric_namespace = "Microsoft.Network/loadBalancers"
    metric_name      = "DipAvailability"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
  }
  action { action_group_id = azurerm_monitor_action_group.ag.id }
  tags = local.tags
}

output "app_url" { value = "http://${azurerm_public_ip.lb.fqdn}" }
