function Export-AzAccessToken {
    [cmdletbinding()]
    [OutputType([string])] # Declares that the function can return a string
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $false)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("MSGraph", "ResourceManager", "KeyVault", "Storage", "Synapse", "OperationalInsights", "Batch", IgnoreCase = $true)]
        [array]$ResourceTypeNames = @("MSGraph", "ResourceManager", "KeyVault", "Storage", "Synapse", "OperationalInsights", "Batch"),

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputFile = "accesstokens.json",

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [switch]$Publish
    )

    begin {
        Write-Host "🚀 Starting function $($MyInvocation.MyCommand.Name)" -ForegroundColor Cyan
        Write-Verbose "Starting function $($MyInvocation.MyCommand.Name)"
    }

    process {
        try {
            Write-Host "🔐 Requesting access tokens for specified audiences" -ForegroundColor Yellow
            Write-Verbose "Requesting access tokens for specified audiences"
            
            $tokens = @()
            $jobs = @()

            Write-Host "🔄 Starting parallel processing for $($ResourceTypeNames.Count) resource types..." -ForegroundColor Magenta
            
            # Start background jobs for each resource type
            foreach ($resourceTypeName in $ResourceTypeNames) {
                Write-Host "🚀 Starting job for $resourceTypeName..." -ForegroundColor Blue
                
                $job = Start-Job -ScriptBlock {
                    param($resourceType)

                    try {
                        # Import required modules in the job context
                        Import-Module Az.Accounts -Force

                        $accessToken = (Get-AzAccessToken -ResourceTypeName $resourceType -AsSecureString)
                        $plainToken = ($accessToken.token | ConvertFrom-SecureString -AsPlainText)

                        # Basic JWT parsing without external dependencies
                        $tokenParts = $plainToken.Split('.')
                        if ($tokenParts.Count -ge 2) {
                            try {
                                # Decode the payload (second part of JWT)
                                $payload = $tokenParts[1]
                                # Add padding if needed
                                while ($payload.Length % 4) { $payload += "=" }
                                $payloadBytes = [System.Convert]::FromBase64String($payload)
                                $payloadJson = [System.Text.Encoding]::UTF8.GetString($payloadBytes)
                                $tokenContent = $payloadJson | ConvertFrom-Json

                                $tokenObject = [PSCustomObject]@{
                                    Resource = $resourceType
                                    UPN      = if ($tokenContent.upn) { $tokenContent.upn } else { "N/A" }
                                    Audience = if ($tokenContent.aud) { $tokenContent.aud } else { "N/A" }
                                    Roles    = if ($tokenContent.roles) { $tokenContent.roles } else { "N/A" }
                                    Scope    = if ($tokenContent.scp) { $tokenContent.scp } else { "N/A" }
                                    Tenant   = if ($tokenContent.tid) { $tokenContent.tid } else { "N/A" }
                                    Token    = $plainToken
                                    Status   = "Success"
                                }
                            }
                            catch {
                                # Fallback if JWT parsing fails
                                $tokenObject = [PSCustomObject]@{
                                    Resource = $resourceType
                                    UPN      = "N/A"
                                    Audience = "N/A"
                                    Roles    = "N/A"
                                    Scope    = "N/A"
                                    Tenant   = "N/A"
                                    Token    = $plainToken
                                    Status   = "Success (Limited Parsing)"
                                }
                            }
                        } else {
                            # Invalid JWT format
                            $tokenObject = [PSCustomObject]@{
                                Resource = $resourceType
                                UPN      = "N/A"
                                Audience = "N/A"
                                Roles    = "N/A"
                                Scope    = "N/A"
                                Tenant   = "N/A"
                                Token    = $plainToken
                                Status   = "Success (No Parsing)"
                            }
                        }

                        return $tokenObject
                    }
                    catch {
                        return [PSCustomObject]@{
                            Resource = $resourceType
                            Error = $_.Exception.Message
                            Status = "Failed"
                        }
                    }
                } -ArgumentList $resourceTypeName

                $jobs += [PSCustomObject]@{
                    Job = $job
                    ResourceType = $resourceTypeName
                }
            }

            Write-Host "⏳ Waiting for jobs to complete..." -ForegroundColor Yellow

            # Wait for all jobs and collect results
            foreach ($jobInfo in $jobs) {
                Write-Host "⚡ Processing results for $($jobInfo.ResourceType)..." -ForegroundColor Blue

                $result = Receive-Job -Job $jobInfo.Job -Wait
                Remove-Job -Job $jobInfo.Job

                if ($result.Status -eq "Failed") {
                    Write-Host "❌ Failed to get access token for $($jobInfo.ResourceType): $($result.Error)" -ForegroundColor Red
                    Write-Error "Failed to get access token for resource type $($jobInfo.ResourceType): $($result.Error)"
                } else {
                    $tokens += $result
                    Write-Host "✅ Successfully retrieved token for $($jobInfo.ResourceType)" -ForegroundColor Green
                }
            }

            Write-Host "📊 Successfully retrieved $($tokens.Count) tokens" -ForegroundColor Green

            if ($Publish) {
                Write-Host "🌐 Publishing tokens to secure sharing service..." -ForegroundColor Cyan
                $requestParam = @{
                    Uri         = 'https://us.onetimesecret.com/api/v1/share'
                    Method      = 'POST'
                    Body        = @{
                        secret = $tokens | ConvertTo-Json -Depth 10
                        ttl    = 3600
                    }
                }

                $response = Invoke-RestMethod @requestParam
                $secretUrl = "https://us.onetimesecret.com/secret/$($response.secret_key)"
                Write-Host "🔗 Tokens published successfully: $secretUrl" -ForegroundColor Green
                return $secretUrl

            } else {
                Write-Host "💾 Exporting tokens to file: $OutputFile" -ForegroundColor Cyan
                Write-Verbose "Exporting tokens to file $OutputFile"
                $tokens | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputFile
                Write-Host "✅ Tokens exported successfully to $OutputFile" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "💥 An error occurred in function $($MyInvocation.MyCommand.Name): $($_.Exception.Message)" -ForegroundColor Red
            Write-Error "An error occurred in function $($MyInvocation.MyCommand.Name): $($_.Exception.Message)"
        }
    }

    end {
        Write-Host "🎉 Function $($MyInvocation.MyCommand.Name) completed successfully!" -ForegroundColor Green
        Write-Verbose "Function $($MyInvocation.MyCommand.Name) completed"
    }
    <#
    .SYNOPSIS
        Exports access tokens for specified Azure resource types using parallel processing.

    .DESCRIPTION
        The Export-AzAccessToken-Parallel function retrieves access tokens for specified Azure resource types and exports them to a JSON file.
        It uses PowerShell background jobs for parallel processing to avoid module loading conflicts.
        It supports publishing the tokens to a secure sharing service (onetimesecret.com) or saving them locally.
        The function retrieves tokens for each specified resource type, extracts token information including UPN, Audience, Roles, Scope, and the actual token.
        It handles errors gracefully and provides verbose logging for better traceability.
        When using the Publish parameter, it returns a secure URL where the tokens can be accessed once.

    .PARAMETER ResourceTypeNames
        An optional array of strings specifying the Azure resource types for which to request access tokens.
        Supported values are "MSGraph", "ResourceManager", "KeyVault", "Storage", "Synapse", "OperationalInsights", and "Batch".
        The default value includes all supported resource types.

    .PARAMETER OutputFile
        An optional string specifying the path to the file where the tokens will be exported.
        The default value is "accesstokens.json".

    .PARAMETER Publish
        An optional switch parameter. If specified, the tokens will be published to a secure sharing service
        (https://us.onetimesecret.com) instead of being saved to a file. The function will return a URL to access the shared tokens.

    .EXAMPLE
        Export-AzAccessToken-Parallel -ResourceTypeNames @("MSGraph", "ResourceManager") -OutputFile "AccessTokens.json"
        Exports access tokens for "MSGraph" and "ResourceManager" resource types and saves them to "AccessTokens.json".

    .EXAMPLE
        Export-AzAccessToken-Parallel -Publish
        Exports access tokens for all default resource types and publishes them to a secure sharing service.
        Returns a URL to access the shared tokens.

    .NOTES
        This function requires the Azure PowerShell module to be installed and authenticated.
        Uses PowerShell background jobs for true parallel processing without module conflicts.
    #>
}
