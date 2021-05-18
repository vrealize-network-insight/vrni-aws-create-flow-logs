# AWS Create Flow Logs for all VPCs
#
# This script will add flow logging to all available VPCs in all AWS regions that your AWS account has access to.
# vRealize Network Insight needs flow logs enabled on VPCs, before it can get the traffic details from AWS. This
# script is an easy way to quickly enable
#
# Be sure to set AWS credentials before running this script, something similar like this:
#
# > Set-AWSCredential -AccessKey AKrestofyouraccesskey -SecretKey 'yourverysecretkey' -StoreAs AWS-Creds
# > Set-AWSCredential -ProfileName AWS-Creds
#
# Martijn Smit (@smitmartijn)
# msmit@vmware.com
# Version 1.0
#
# Copyright 2021 VMware, Inc.
# SPDX-License-Identifier: BSD-2-Clause
#Requires -Version 6

#####
### Start configuration
####
# Would you like me to be verbose ($True), or just mention if I create something ($False) ?
$global:VerboseOutput = $True
# This logGroupPrefix will be put in front of the log group name. The last part will be the
# VPC ID, so this will result in a log group called "vRNI-FlowLogs_vpc-ewqenjnr3298ru3"
$global:logGroupPrefix = "vRNI-FlowLogs_"
# 1 day retention for the flow logs is plenty
$global:logGroupRetention = 1
# This has to be a role that has access to write to the Cloud Watch log groups
$global:awsPermissionsArn = "arn:aws:iam::000000000000:role/vRNI-Flow-Logs-Role"
# Regions to skip (if any). Example: $global:skipRegions = @('eu-west-1', 'us-east-1')
$global:skipRegions = @()

#####
### End configuration
####

. .\functions.ps1

My-Logger -textcolor "yellow" -message "Before continuing, please make sure you've configured the top part of this script correctly and have loaded AWS credentials using Set-AWSCredential"
Read-Host "Press enter to start, ctrl+c to abort"

$creds = Get-AWSCredentials
if(!$creds) {
    throw "Please set AWS credentials with Set-AWSCredential first!"
}

function getVPCList(
    [string]$Region
)
{
    # First, get a list of all VPCs and store them in an array for future reference (array[$vpc_id] = $vpc_name)
    foreach ($vpc in Get-EC2Vpc -Region $Region)
    {
        $vpc_id = $vpc.VpcId
        $vpc_name = $vpc.VpcId
        # see if there's a name
        foreach($tag in $vpc.Tags) {
            if($tag.Key -eq "Name") {
                $vpc_name = $tag.Value
            }
        }

        $global:existing_vpcs.Add($vpc_id, $vpc_name)
        My-Logger -textcolor "gray" -message "Found VPC: $($vpc_id), with name: $($vpc_name), in region: $($Region)" -Verbose $True
    }
}

function getVPCFlowLogList(
    [string]$Region
)
{
    # Then, get a list of all flow logs and their associated VPCs and store them in an array for future reference (array[$vpc_id] = $flowlogobject)
    foreach ($flowlog in Get-EC2FlowLogs -Region $Region)
    {
        $fl_id    = $flowlog.FlowLogId
        $vpc_name = "unknown"
        $vpc_id   = $flowlog.ResourceId
        if($existing_vpcs.ContainsKey($vpc_id)) {
            $vpc_name = $existing_vpcs[$vpc_id];
        }
        My-Logger -textcolor "gray" -message "Found Flow Log: $($fl_id), with destination: $($flowlog.LogDestination), name: $($flowlog.LogGroupName), and VPC: $($vpc_name)" -Verbose $True

        $global:existing_flow_logs.Add($vpc_id, $flowlog)
    }
}

# Loop through all regions
foreach($region in Get-EC2Region)
{
    $region_name = $region.RegionName
    # Skip this region, if configured at the top
    if($skipRegions.Contains($region_name)) {
        continue
    }

    # Storage for the VPCs and Flow Logs, to compare later on
    $global:existing_flow_logs = @{}
    $global:existing_vpcs = @{}

    My-Logger -message "------ Switching to region: $($region_name) ------"
    My-Logger -message "Retrieving VPCs.." -Verbose $True

    # Get a list of all VPCs in this region
    getVPCList -Region $region_name

    # Skip regions with no VPCs
    if(!$global:existing_vpcs) {
        continue
    }

    # Get a list of all Flow Logs in this region
    getVPCFlowLogList -Region $region_name

    My-Logger -message "Comparing VPCs with configured Flow Logs:" -Verbose $True

    # Compare the VPC list with the list of VPCs where Flow Logs are created.
    # The result will be VPCs that do not have Flow Logs enabled, which we want to correct by creating them!
    $vpcs_without_flow_logs = Compare-Hashtable -ReferenceObject $global:existing_vpcs -DifferenceObject $global:existing_flow_logs

    # This is good: no difference means that all VPCs have Flow Logs enabled
    if(!$vpcs_without_flow_logs) {
        My-Logger -message "All VPCs in $($region_name) have Flow Logs enabled!"
        continue
    }

    # Run through the differences; meaning a list of VPCs with
    foreach($vpc in $vpcs_without_flow_logs) {
        $vpc_name = $vpc.ReferenceValue
        $vpc_id   = $vpc.InputPath

        My-Logger -textcolor "yellow" -message "No Flows Logs enabled in VPC: $($vpc_name), with ID: $($vpc_id)"

        $lg_name = "$($global:logGroupPrefix)$($vpc_id)"
        try {
            # First, create the CloudWatch Log Group
            $tmp = New-CWLLogGroup -LogGroupName $lg_name -Region $region_name
            # Then set it to a 1 day retention
            $tmp = Write-CWLRetentionPolicy -LogGroupName $lg_name -RetentionInDays $global:logGroupRetention -Region $region_name
            # Last, create the Flow Log on the VPC, referring to the previously created Log Group
            $tmp = New-EC2FlowLog -ResourceId $vpc_id -LogGroupName "$($global:logGroupPrefix)$($vpc_id)" -DeliverLogsPermissionArn $global:awsPermissionsArn -LogDestinationType "cloud-watch-logs" -ResourceType "VPC" -TrafficType "ALL" -Region $region_name
            My-Logger -message "Added Flow Logs & CloudWatch LogGroup '$($lg_name)' for VPC '$($vpc_name)' in region $($region_name)"
        }
        catch {
            My-Logger -textcolor "red" -message "Error adding Flow Logs & CloudWatch LogGroup '$($lg_name)' for VPC '$($vpc_name)' in region $($region_name): $($_.Exception.Message)"
        }
    }
}