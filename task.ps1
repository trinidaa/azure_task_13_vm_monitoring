$linuxUser = "azur11"
$linuxPassword = "SecurePassword1235!" | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($linuxUser, $linuxPassword)
$location = "ukwest"
$resourceGroupName = "mate-azure-task-13" #+ (Get-Random -Minimum 100 -Maximum 999)
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
$dcrName = "MetricsCollection" + (Get-Random -Minimum 100 -Maximum 999)
$SubscriptionId = (Get-AzSubscription).Id
Set-AzContext -SubscriptionId $SubscriptionId
# Регистрируем поставщик ресурсов Microsoft.Insights
Register-AzResourceProvider -ProviderNamespace "Microsoft.Insights" | Out-Null

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
  -SystemAssignedIdentity | Out-Null

Write-Host "`nInstalling the TODO web app..." -ForegroundColor Cyan
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

# Создаём Log Analytics Workspace
Write-Host "Creating Log Analytics Workspace..." -ForegroundColor Cyan
$workspace = New-AzOperationalInsightsWorkspace `
    -ResourceGroupName $resourceGroupName `
    -Name "monitor-workspace" `
    -Location $location `
    -Sku "PerGB2018"
$workspaceResourceId = $workspace.ResourceId

# Создаем определение DCR в формате JSON
$dcrDefinition = @{
    location   = $location
    properties = @{
        description = $description
        dataSources = @{
            syslog = @(
                @{
                    name         = "syslogDataSource"
                    streams      = @("Microsoft-Syslog")
                    facilityNames = @("auth", "syslog")
                    logLevels    = @("Error", "Critical", "Alert")
                }
            )
        }
        destinations = @{
            logAnalytics = @(
                @{
                    name               = "LogAnalyticsDestination"
                    workspaceResourceId = $workspaceResourceId
                    workspaceId       = $workspace.Name
                }
            )
        }
        dataFlows    = @(
            @{
                streams      = @("Microsoft-Syslog")
                destinations = @("LogAnalyticsDestination")
            }
        )
    }
}

# Конвертируем в JSON и сохраняем во временный файл
$tempJsonFile = [System.IO.Path]::GetTempFileName()
$dcrDefinition | ConvertTo-Json -Depth 6 | Out-File $tempJsonFile -Encoding utf8

# Создаем правило сбора данных DCR
try {
    Write-Host "Creating DCR $dcrName..." -ForegroundColor Cyan
    $dcr = New-AzDataCollectionRule -ResourceGroupName $resourceGroupName `
                                   -Name $dcrName `
                                   -JsonFilePath $tempJsonFile `
                                   -ErrorAction Stop

    Write-Host "DCR $dcrName created successfully." -ForegroundColor Green
    $dcr | Format-List -Property Name,Location,ResourceGroupName,ProvisioningState
}
catch {
    Write-Host "Error creating DCR:" -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}
finally {
    # Удаляем временный файл
    Remove-Item $tempJsonFile -ErrorAction SilentlyContinue
}

# Для привязки ко всем VM в resource group:
$vms = Get-AzVM -ResourceGroupName $resourceGroupName
foreach ($vm in $vms) {
    $associationName = "dcr-association-$($vm.Name)"
    # Проверяем, существует ли уже ассоциация
    $existingAssociation = Get-AzDataCollectionRuleAssociation -TargetResourceId $vm.Id -AssociationName $associationName -ErrorAction SilentlyContinue
    if (-not $existingAssociation) {
        $association = New-AzDataCollectionRuleAssociation -TargetResourceId $vm.Id `
            -AssociationName $associationName `
            -RuleId $dcr.Id
        Write-Host "Successfully associated DCR to VM $($vm.Name)" -ForegroundColor Green
    } else {
        Write-Host "Association already exists for VM $($vm.Name)" -ForegroundColor Yellow
    }
}

Write-Host "Deployment completed!" -ForegroundColor Green