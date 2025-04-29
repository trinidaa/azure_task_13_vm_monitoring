$linuxUser = "azur11"
$linuxPassword = "YourSecurePassword123!" | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($linuxUser, $linuxPassword)
$location = "uksouth"
$resourceGroupName = "mate-azure-task-13" + (Get-Random -Minimum 100 -Maximum 999)
$networkSecurityGroupName = "defaultnsg"
$virtualNetworkName = "vnet"
$subnetName = "default"
$vnetAddressPrefix = "10.0.0.0/16"
$subnetAddressPrefix = "10.0.0.0/24"
$sshKeyName = "linuxboxsshkey"
$publicIpAddressName = "linuxboxpip"
$vmName = "matebox"
$vmImage = "Ubuntu2204"
$vmSize = "Standard_B1s"
$dnsLabel = "matetask" + (Get-Random -Count 1)
$keyPath = "$HOME\.ssh\$linuxUser"

if (-not (Test-Path "$HOME\.ssh\$linuxUser.pub")) {
    Write-Host "SSh key not found. Generating SSH key..." -ForegroundColor Cyan
    ssh-keygen -t rsa -b 4096 -f $keyPath -N "" | Out-Null
}

$sshKeyPublicKey = (Get-Content "$HOME\.ssh\$linuxUser.pub" -Raw).Trim()

# 1. Создание Resource Group
Write-Host "Creating a resource group $resourceGroupName ..." -ForegroundColor Cyan
New-AzResourceGroup -Name $resourceGroupName -Location $location | Out-Null

# 2. Создание Network Security Group
Write-Host "Creating a network security group $networkSecurityGroupName ..." -ForegroundColor Cyan
$nsgRuleSSH = New-AzNetworkSecurityRuleConfig -Name SSH -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22 -Access Allow
$nsgRuleHTTP = New-AzNetworkSecurityRuleConfig -Name HTTP -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 8080 -Access Allow
New-AzNetworkSecurityGroup -Name $networkSecurityGroupName -ResourceGroupName $resourceGroupName -Location $location -SecurityRules $nsgRuleSSH, $nsgRuleHTTP | Out-Null

# 3. Создание Virtual Network
Write-Host "Creating a virtual network ..." -ForegroundColor Cyan
$subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetAddressPrefix
New-AzVirtualNetwork -Name $virtualNetworkName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $vnetAddressPrefix -Subnet $subnet | Out-Null

# 4. Создание SSH Key
Write-Host "Creating a SSH key ..." -ForegroundColor Cyan
New-AzSshKey -Name $sshKeyName -ResourceGroupName $resourceGroupName -PublicKey $sshKeyPublicKey | Out-Null

# 5. Создание Public IP
Write-Host "Creating a Public IP Address ..." -ForegroundColor Cyan
New-AzPublicIpAddress -Name $publicIpAddressName -ResourceGroupName $resourceGroupName -Location $location -Sku Basic -AllocationMethod Dynamic -DomainNameLabel $dnsLabel | Out-Null

# 6. Создание VM с System-Assigned Identity
Write-Host "Creating a VM with System-Assigned Identity..." -ForegroundColor Cyan
New-AzVm `
  -ResourceGroupName $resourceGroupName `
  -Name $vmName `
  -Location $location `
  -Image $vmImage `
  -Credential $credential `
  -Size $vmSize `
  -SubnetName $subnetName `
  -VirtualNetworkName $virtualNetworkName `
  -SecurityGroupName $networkSecurityGroupName `
  -SshKeyName $sshKeyName `
  -PublicIpAddressName $publicIpAddressName `
  -SystemAssignedIdentity

Write-Host "Installing the TODO web app..." -ForegroundColor Cyan
$Params = @{
    ResourceGroupName = $resourceGroupName
    VMName = $vmName
    Name = 'CustomScript'
    Publisher = 'Microsoft.Azure.Extensions'
    ExtensionType = 'CustomScript'
    TypeHandlerVersion = '2.1'
    Settings = @{
        fileUris = @('https://raw.githubusercontent.com/mate-academy/azure_task_13_vm_monitoring/main/install-app.sh')
        commandToExecute = './install-app.sh'
    }
}
Set-AzVMExtension @Params

# Создаём Log Analytics Workspace
Write-Host "Creating Log Analytics Workspace..." -ForegroundColor Cyan
New-AzOperationalInsightsWorkspace `
    -ResourceGroupName $resourceGroupName `
    -Name "monitor-workspace" `
    -Location $location `
    -Sku "PerGB2018"

# Устанавливаем Azure Monitor Agent
Write-Host "Installing Azure Monitor Agent..." -ForegroundColor Cyan
Set-AzVMExtension `
    -ResourceGroupName $resourceGroupName `
    -VMName $vmName `
    -Name 'AzureMonitorLinuxAgent' `
    -Publisher 'Microsoft.Azure.Monitor' `
    -ExtensionType 'AzureMonitorLinuxAgent' `
    -TypeHandlerVersion '1.9' `
    -Location $location

Write-Host "Deployment completed!" -ForegroundColor Gree