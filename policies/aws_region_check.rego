package terraform.analysis

import rego.v1

# Define the ONLY allowed region
allowed_region := "ap-south-1"

# Rule: Deny if AWS Provider is not set to ap-south-1
deny contains msg if {
    # 1. Find the AWS provider configuration in the plan
    # Using 'input' directly is standard
    provider := input.configuration.provider_config[name]
    
    # 2. Check if the provider name contains "aws"
    # Note: internal functions work fine alongside keywords
    contains(name, "aws")

    # 3. Extract the defined region
    region := provider.expressions.region.constant_value

    # 4. Compare with allowed region
    region != allowed_region

    # 5. Error Message
    msg := sprintf("COMPLIANCE ALERT: Provider '%v' is set to '%v'. All App resources MUST be in '%v' (Mumbai).", [name, region, allowed_region])
}

# Rule: Deny if Region is missing entirely (Defaults to us-east-1)
deny contains msg if {
    provider := input.configuration.provider_config[name]
    contains(name, "aws")
    
    # Check if 'region' key is missing from config
    not provider.expressions.region

    msg := sprintf("COMPLIANCE ALERT: Provider '%v' has no region defined. You must explicitly set it to '%v'.", [name, allowed_region])
}