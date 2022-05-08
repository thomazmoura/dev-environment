if($env:AzureDevOpsOrganization -and $env:AzureDevOpsProject) {
  Write-Information "Azure DevOps configuration found. Setting up."
  az devops configure --defaults organization=$env:AzureDevOpsOrganization project=$env:AzureDevOpsProject
} else {
  Write-Information "Azure DevOps configuration not found. Skipping."
}
