using namespace System.Management.Automation

# used for auto-generating the valid values for the AppRoleName parameter
class appRoleNames : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {
        return ($script:SessionVariables.appRoleIds.Permission)
    }
}

function Get-AppRolePermission {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ErrorMessage = "It does not match expected GUID pattern")]
        [string]$appRoleId,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet( [appRoleNames] )]
        [string]$appRoleName,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateSet( 'Application', 'Delegated' )]
        [string]$Type = 'Application'

    )

    begin {
        Write-Verbose "🚀 Starting function $($MyInvocation.MyCommand.Name)"
        $MyInvocation.MyCommand.Name | Invoke-BlackCat
    }

    process {

        try {

            Write-Verbose "🔍 Searching for App Role permissions"

            if ($appRoleName) {
                Write-Host "  🎯 Looking up App Role by name: '$appRoleName' (Type: $Type)" -ForegroundColor Cyan
                $object = ($script:SessionVariables.appRoleIds | Where-Object Permission -eq $appRoleName | Where-Object Type -eq $Type)
                
                if ($object) {
                    Write-Host "    ✅ Found App Role permission: $($object.Permission)" -ForegroundColor Green
                } else {
                    Write-Host "    ❌ No App Role found with name '$appRoleName' and type '$Type'" -ForegroundColor Red
                }
            } else {
                Write-Host "  🔑 Looking up App Role by ID: $appRoleId" -ForegroundColor Cyan
                $object = ($script:SessionVariables.appRoleIds | Where-Object appRoleId -eq $appRoleId)
                
                if ($object) {
                    Write-Host "    ✅ Found App Role permission: $($object.Permission)" -ForegroundColor Green
                } else {
                    Write-Host "    ❌ No App Role found with ID '$appRoleId'" -ForegroundColor Red
                }
            }

            if ($object) {
                Write-Host "    📋 Permission: $($object.Permission)" -ForegroundColor Yellow
                Write-Host "    🏷️  Type: $($object.Type)" -ForegroundColor Yellow
                Write-Host "    🆔 App Role ID: $($object.appRoleId)" -ForegroundColor Yellow
            }

            return $object
        }
        catch {
            Write-Host "  ❌ Error retrieving App Role permission: $($_.Exception.Message)" -ForegroundColor Red
            Write-Message -FunctionName $($MyInvocation.MyCommand.Name) -Message $($_.Exception.Message) -Severity 'Error'
        }
    }
<#
.SYNOPSIS
Retrieves the permissions for a specified Microsoft App Role.

.DESCRIPTION
The Get-AppRolePermission function retrieves the permissions associated with a specified Microsoft App Role.
It can filter permissions based on the App Role ID or App Role Name and Type. The function provides enhanced
output with emoji indicators and colorful progress messages for better user experience.

Features:
- Emoji-enhanced progress indicators and status messages
- Detailed success and error reporting with visual feedback
- Color-coded output for easy identification of results
- Support for both Application and Delegated permission types
- Pipeline support for processing multiple app role IDs

.PARAMETER appRoleId
The unique identifier (GUID) of the App Role. Must match the expected GUID pattern.

.PARAMETER appRoleName
The name of the App Role. Valid values are auto-generated from the session variables.

.PARAMETER Type
The type of the App Role. Valid values are 'Application' and 'Delegated'. Default is 'Application'.

.EXAMPLE
Get-AppRolePermission -appRoleId "12345678-1234-1234-1234-1234567890ab"

.EXAMPLE
Get-AppRolePermission -appRoleName "User.Read" -Type "Delegated"

.EXAMPLE
Get-MsServicePrincipalsPermissions | Get-AppRolePermission

.NOTES
This function uses session variables to retrieve the App Role permissions. Ensure that the session variables are properly initialized before calling this function.

#>
}