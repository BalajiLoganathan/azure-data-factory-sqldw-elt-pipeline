$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

function Create-ResourceGroup {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$Location
    )

    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if ($null -ne $resourceGroup) {
        Write-Information "Resource group '$($ResourceGroupName)' already exists"
    } else {
        Write-Information "Creating resource group '$($ResourceGroupName)'"
        $DebugPreference = "Continue"
        $output = New-AzResourceGroup -Name $ResourceGroupName -Location $Location 5>&1
        $DebugPreference = "SilentlyContinue"
        $lines = -join $($output | ForEach-Object {$_.Message})
        $regex = "(?:=+\sHTTP\sRESPONSE\s=+.*Body\:)(.*)(?:AzureQoSEvent\: CommandName - New-AzResourceGroup)"
        $match = [System.Text.RegularExpressions.Regex]::Match($lines, $regex, `
            [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $match.Groups[1].Captures[0].Value
    }
}

function Deploy-BuildingBlock {
    param(
        [string]$DeploymentName,
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$TemplateUri,
        [string]$TemplateParameterFile
    )

    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    $DebugPreference = "Continue"
    $output = New-AzResourceGroupDeployment -Name $DeploymentName -ResourceGroupName $ResourceGroupName `
        -TemplateUri $TemplateUri -TemplateParameterFile $TemplateParameterFile 5>&1
    $DebugPreference = "SilentlyContinue"
    $lines = -join $($output | ForEach-Object {$_.Message})
    $regex = "(?:=+\sHTTP\sRESPONSE\s=+.*Body\:)(.*)(?:AzureQoSEvent\: CommandName - New-AzResourceGroupDeployment)"
    $match = [System.Text.RegularExpressions.Regex]::Match($lines, $regex, `
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $match.Groups[1].Captures[0].Value
}

$OUTPUT_FILENAME = Join-Path -Path $PSScriptRoot `
    -ChildPath "$([System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath))-output.json"

$resourceGroups = @"
[
    {
        "subscriptionId": "a012a8b0-522a-4f59-81b6-aa0361eb9387",
        "resourceGroupName": "far-test-2",
        "location": "eastus2"
    }
]
"@ | ConvertFrom-Json

$AZ_OUTPUT = @()
$AZ_OUTPUT += $resourceGroups | ForEach-Object {
    $result = Create-ResourceGroup -SubscriptionId $_.subscriptionId -ResourceGroupName $_.resourceGroupName `
        -Location $_.location
    if ($null -ne $result) {
        $AZ_OUTPUT += $result
    }
}

Write-Information "Executing deployment 'bb-01-vnet'"
$AZ_OUTPUT += $(Deploy-BuildingBlock -DeploymentName "bb-01-vnet" -SubscriptionId "a012a8b0-522a-4f59-81b6-aa0361eb9387" -ResourceGroupName "far-test-2" -TemplateUri "https://raw.githubusercontent.com/mspnp/template-building-blocks/v2.2.0/templates/buildingBlocks/virtualNetworks/virtualNetworks.json" -TemplateParameterFile "onprem.parameters-output-01.json")
Write-Information "Executing deployment 'bb-02-vm'"
$AZ_OUTPUT += $(Deploy-BuildingBlock -DeploymentName "bb-02-vm" -SubscriptionId "a012a8b0-522a-4f59-81b6-aa0361eb9387" -ResourceGroupName "far-test-2" -TemplateUri "https://raw.githubusercontent.com/mspnp/template-building-blocks/v2.2.0/templates/buildingBlocks/virtualMachines/virtualMachines.json" -TemplateParameterFile "onprem.parameters-output-02.json")
$AZ_OUTPUT = $($AZ_OUTPUT | ForEach-Object { $_.Trim() }) -join ",$([System.Environment]::NewLine)"
Set-Content -Path $OUTPUT_FILENAME -Value "[$([System.Environment]::NewLine)$AZ_OUTPUT$([System.Environment]::NewLine)]"
Write-Information "Deployment outputs written to '$OUTPUT_FILENAME'"
