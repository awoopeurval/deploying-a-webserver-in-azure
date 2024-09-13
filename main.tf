 terraform {

   required_version = ">=1.0"

   required_providers {
     azurerm = {
       source = "hashicorp/azurerm"
       version = ">=3.0"
     }
   }
 }

provider "azurerm" {
  features {}
}

# Use the existing Resource Group
resource "azurerm_resource_group" "existing_rg" {
  name = var.resource_group_name
  location = var.location
}


# Create a Virtual Network
resource "azurerm_virtual_network" "vnet" {
    name                = "${var.prefix}-network"
    address_space       = ["${var.address_space}"]
    location            = azurerm_resource_group.existing_rg.location
    resource_group_name = azurerm_resource_group.existing_rg.name

    tags = var.tags
}


# Create a Subnet on the Virtual Network
resource "azurerm_subnet" "internal" {
    name                 = "${var.prefix}-subnet"
    resource_group_name  = azurerm_resource_group.existing_rg.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes     = ["${var.subnet_cidr}"]
}


# Create a Network Security Group
resource "azurerm_network_security_group" "nsg" {
    name                = "${var.prefix}-nsg"
    location            = azurerm_resource_group.existing_rg.location
    resource_group_name = azurerm_resource_group.existing_rg.name

    # Allow inbound traffic from other VMs on the subnet
    security_rule {
        name                       = "allow-internal-inbound"
        priority                   = 200
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "VirtualNetwork"
    }

    security_rule {
        name                       = "allow-internal-outbound"
        priority                   = 220
        direction                  = "Outbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "VirtualNetwork"
    }

    security_rule {
        name                       = "allow-internet-LB"
        priority                   = 300
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = 80
        source_address_prefix      = "Internet"
        destination_address_prefix = azurerm_public_ip.public_ip.ip_address
    }

    #Deny all inbound traffic from the internet
    security_rule {
        name                       = "deny-internet-inbound"
        priority                   = 400
        direction                  = "Inbound"
        access                     = "Deny"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "Internet"
        destination_address_prefix = "VirtualNetwork"
    }

   tags = var.tags
}

# Add security group to the network interface
resource "azurerm_subnet_network_security_group_association" "sample" {
  subnet_id                 = azurerm_subnet.internal.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}


# Create a Network Interface
resource "azurerm_network_interface" "nic" {
    count               = "${var.vm_count}"
    name                = "${var.prefix}-nic${count.index}"
    resource_group_name = azurerm_resource_group.existing_rg.name
    location            = azurerm_resource_group.existing_rg.location

    ip_configuration {
        name                          = "internal"
        subnet_id                     = azurerm_subnet.internal.id
        private_ip_address_allocation = "Dynamic"
    }

    tags = var.tags
}


# Create a Public IP address
resource "azurerm_public_ip" "public_ip" {
    name                = "loadBalancerPublicIP"
    resource_group_name = azurerm_resource_group.existing_rg.name
    location            = azurerm_resource_group.existing_rg.location
    allocation_method   = "Static"

    tags = var.tags
}


# Create a Load Balancer
resource "azurerm_lb" "lb" {
    name                = "${var.prefix}-loadBalancer"
    location            = azurerm_resource_group.existing_rg.location
    resource_group_name = azurerm_resource_group.existing_rg.name

    frontend_ip_configuration {
        name                 = "publicIPAddress"
        public_ip_address_id = azurerm_public_ip.public_ip.id
    }
    
    tags = var.tags
}

# Create a Backend Address Pool
resource "azurerm_lb_backend_address_pool" "backend_pool" {
    loadbalancer_id     = azurerm_lb.lb.id
    name                = "${var.prefix}-BackEndAddressPool"
 }

#Load Balancer probe
resource "azurerm_lb_probe" "main" {
    name            = "${var.prefix}-lb-probe"
    loadbalancer_id = azurerm_lb.lb.id
    port            = 80
}

#Load Balancer rule
resource "azurerm_lb_rule" "main" {
    name                           = "${var.prefix}-lb-rule"
    loadbalancer_id                = azurerm_lb.lb.id
    protocol                       = "Tcp"
    probe_id                       = azurerm_lb_probe.main.id
    frontend_port                  = 80
    backend_port                   = 80
    backend_address_pool_ids       = [azurerm_lb_backend_address_pool.backend_pool.id]
    frontend_ip_configuration_name = azurerm_lb.lb.frontend_ip_configuration[0].name
}


#Create a Virtual Machine Availability Set
resource "azurerm_availability_set" "vm_availability_set" {
    name                         = "${var.prefix}-vmSet"
    resource_group_name          = azurerm_resource_group.existing_rg.name
    location                     = azurerm_resource_group.existing_rg.location
    platform_fault_domain_count  = 2
    platform_update_domain_count = 2
    managed                      = true

    tags = var.tags
 }

#add Azure Image from Packer 
data "azurerm_image" "server_mage" {
    name                = "pkrserverimage"
    resource_group_name = azurerm_resource_group.existing_rg.name
}

#Modified the image ref
resource "azurerm_linux_virtual_machine" "main" {
    count                           = "${var.vm_count}"
    name                            = "${var.prefix}-vm${count.index}"
    availability_set_id             = azurerm_availability_set.vm_availability_set.id
    resource_group_name             = azurerm_resource_group.existing_rg.name
    location                        = azurerm_resource_group.existing_rg.location
    size                            = "Standard_D2s_v3"
    admin_username                  = "${var.username}"
    admin_password                  = "${var.password}"
    disable_password_authentication = false
    network_interface_ids           = [element(azurerm_network_interface.nic.*.id, count.index)]

    source_image_id = data.azurerm_image.server_mage.id

    # VM configuration
    os_disk {
        storage_account_type = "Standard_LRS"
        caching              = "ReadWrite"
    }

    tags = var.tags
}

#add Managed Disk
resource "azurerm_managed_disk" "managedDisk" {
    count                = "${var.vm_count}"
    name                 = "${var.prefix}-datadisk_${count.index}"
    location             = azurerm_resource_group.existing_rg.location
    resource_group_name  = azurerm_resource_group.existing_rg.name
    storage_account_type = "Standard_LRS"
    create_option        = "Empty"
    disk_size_gb         = 10

    tags = var.tags
}

#add Managed Disk Attachment
resource "azurerm_virtual_machine_data_disk_attachment" "diskattach" {
    count              = "${var.vm_count}"
    managed_disk_id    = element(azurerm_managed_disk.managedDisk.*.id, count.index)
    virtual_machine_id = element(azurerm_linux_virtual_machine.main.*.id, count.index)
    lun                = "1"
    caching            = "ReadWrite"
}
