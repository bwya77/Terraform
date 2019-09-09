# Configure the Azure Provider
provider "azurerm" {
  # While version is optional, we /strongly recommend/ using it to pin the version of the Provider being used
  version = "=1.33"
}

locals {
  virtual_machine_name  = "${local.prefix}"
  admin_username        = "bwyatt"
  admin_password        = "ThisNeeds2BeChanged!"
  prefix                = "lazyadmin"
  location              = "North Central US"
  virtual_network       = "10.0.0.0/16"
  internal_subnet       = "10.0.2.0/24"
  office_wan            = "182.171.161.241"
  nsg_name              = "adds"
}

resource "azurerm_resource_group" "addsrg" {
  name     = "rg-${local.prefix}-resources"
  location = "${local.location}"
}

resource "azurerm_virtual_network" "addsvn" {
  name                = "${local.prefix}-network"
  address_space       = ["${local.virtual_network}"]
  location            = "${azurerm_resource_group.addsrg.location}"
  resource_group_name = "${azurerm_resource_group.addsrg.name}"
}

resource "azurerm_subnet" "addssubnet" {
  name                       = "sn-internal"
  resource_group_name        = "${azurerm_resource_group.addsrg.name}"
  virtual_network_name       = "${azurerm_virtual_network.addsvn.name}"
  address_prefix             = "${local.internal_subnet}"
}

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-${local.nsg_name}"
  location            = "${azurerm_resource_group.addsrg.location}"
  resource_group_name = "${azurerm_resource_group.addsrg.name}"
}

resource "azurerm_network_security_rule" "allowrdpoffice" {
   name                        = "allow-rdp-from-main-office"
   priority                    = 100
   direction                   = "Inbound"
   access                      = "Allow"
   protocol                    = "Tcp"
   source_port_range           = "3389"
   destination_port_range      = "3389"
   source_address_prefix       = "${local.office_wan}"
   destination_address_prefix  = "*"
   resource_group_name = "${azurerm_resource_group.addsrg.name}"
   network_security_group_name = "${azurerm_network_security_group.nsg.name}"
}

resource "azurerm_network_security_rule" "denyrdpall" {
   name                        = "deny-rdp-all"
   priority                    = 200
   direction                   = "Inbound"
   access                      = "Deny"
   protocol                    = "Tcp"
   source_port_range           = "3389"
   destination_port_range      = "3389"
   source_address_prefix       = "*"
   destination_address_prefix  = "*"
   resource_group_name = "${azurerm_resource_group.addsrg.name}"
   network_security_group_name = "${azurerm_network_security_group.nsg.name}"
}

resource "azurerm_subnet_network_security_group_association" "sga" {
  subnet_id                 = "${azurerm_subnet.addssubnet.id}"
  network_security_group_id = "${azurerm_network_security_group.nsg.id}"
}

resource "azurerm_public_ip" "addspip" {
  name                = "pip-${local.prefix}"
  resource_group_name = "${azurerm_resource_group.addsrg.name}"
  location            = "${azurerm_resource_group.addsrg.location}"
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "addsnic" {
  name                = "${local.prefix}-nic"
  location            = "${azurerm_resource_group.addsrg.location}"
  resource_group_name = "${azurerm_resource_group.addsrg.name}"

  ip_configuration {
    name                          = "configuration"
    subnet_id                     = "${azurerm_subnet.addssubnet.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.addspip.id}"
  }
}

resource "azurerm_virtual_machine" "addsvm" {
  name                  = "vm-${local.virtual_machine_name}"
  location              = "${azurerm_resource_group.addsrg.location}"
  resource_group_name   = "${azurerm_resource_group.addsrg.name}"
  network_interface_ids = ["${azurerm_network_interface.addsnic.id}"]
  vm_size               = "Standard_F2"

  # This means the OS Disk will be deleted when Terraform destroys the Virtual Machine
  # NOTE: This may not be optimal in all cases.
  delete_os_disk_on_termination = true

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }

  storage_os_disk {
    name              = "disk-${local.prefix}-os"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "${local.virtual_machine_name}"
    admin_username = "${local.admin_username}"
    admin_password = "${local.admin_password}"
  }

  os_profile_windows_config {
    provision_vm_agent        = true
    enable_automatic_upgrades = true
  }
}