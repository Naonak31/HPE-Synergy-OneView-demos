# -------------------------------------------------------------------------------------------------------
#   by lionel.jullien@hpe.com
#   August 2017
#
#   Script to create a Server Profile Template using the HPE Image Streamer 
#   with OSDeploymentPlanAttributes and required iSCSI Network connections
#        
#   OneView administrator account is required. 
#   
#   Latest OneView POSH Library must be used.
# 
# --------------------------------------------------------------------------------------------------------
   
#################################################################################
#                   New-ESXiserverprofiletemplate.ps1                           #
#                                                                               #
#        (C) Copyright 2017 Hewlett Packard Enterprise Development LP           #
#################################################################################
#                                                                               #
# Permission is hereby granted, free of charge, to any person obtaining a copy  #
# of this software and associated documentation files (the "Software"), to deal #
# in the Software without restriction, including without limitation the rights  #
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell     #
# copies of the Software, and to permit persons to whom the Software is         #
# furnished to do so, subject to the following conditions:                      #
#                                                                               #
# The above copyright notice and this permission notice shall be included in    #
# all copies or substantial portions of the Software.                           #
#                                                                               #
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR    #
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,      #
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE   #
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER        #
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, #
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN     #
# THE SOFTWARE.                                                                 #
#                                                                               #
#################################################################################




#################################################################################
#                                Global Variables                               #
#################################################################################


$serverprofiletemplate = "ESXi for I3S OSDEPLOYMENT2"

$OSDeploymentplan = 'ESXi - deploy with multiple management NIC HA config+FCoE'

# This can be found using Get-HPOVServerHardwareTypes
$ServerHardwareType = "SY 480 Gen9 1"

# Datastore must be present, managed by OneView (get-hpovstoragevolume)
$datastore = "vSphere-datastore"




# OneView Credentials
$username = "Administrator" 
$password = "password" 
$IP = "192.168.1.110" 


#################################################################################



# Import the OneView 3.10 library

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -Confirm:$False

    if (-not (get-module HPOneview.310)) 
    {  
    Import-module HPOneview.310
    }

   
# Connection to the Synergy Composer

If ($connectedSessions -and ($connectedSessions | ?{$_.name -eq $IP}))
{
    Write-Verbose "Already connected to $IP."
}

Else
{
    Try 
    {
        Connect-HPOVMgmt -appliance $IP -UserName $username -Password $password | Out-Null
    }
    Catch 
    {
        throw $_
    }
}

        
        $SY460SHT = Get-HPOVServerHardwareTypes -name $ServerHardwareType
        $enclosuregroup = Get-HPOVEnclosureGroup  

        $ManagementURI = Get-HPOVNetwork | ? {$_.purpose -match "Management" -and $_.SubnetUri -ne $Null} | % Uri -Confirm:$False

        $OSDP = Get-HPOVOSDeploymentPlan -name $OSDeploymentplan
        $osCustomAttributes = Get-HPOVOSDeploymentPlan -name $OSDeploymentplan -ErrorAction Stop | Get-HPOVOSDeploymentPlanAttribute
        
        $OSDeploymentPlanAttributes = $osCustomAttributes 


         # An IP address is required here if 'ManagementNIC.constraint' = 'userspecified'
        ($OSDeploymentPlanAttributes | ? name -eq 'ManagementNIC.ipaddress').value = ''   

         # 'Auto' to get an IP address from the OneView IP pool or 'Userspecified' to assign a static IP or 'DHCP' to a get an IP from an external DHCP Server
        ($OSDeploymentPlanAttributes | ? name -eq 'ManagementNIC.constraint').value = 'auto' 
        
         # 'True' must be used here if 'ManagementNIC.constraint' = 'DHCP'
        ($OSDeploymentPlanAttributes | ? name -eq 'ManagementNIC.dhcp').value = 'False'
        
         # '3' corresponds to the third connection ID number in the server profile connections
        ($OSDeploymentPlanAttributes | ? name -eq 'ManagementNIC.connectionid').value = '3'
        
        ($OSDeploymentPlanAttributes | ? name -eq 'ManagementNIC2.dhcp').value = 'False'
        
        ($OSDeploymentPlanAttributes | ? name -eq 'ManagementNIC2.connectionid').value = '4'
        
        ($OSDeploymentPlanAttributes | ? name -eq 'SSH').value = 'enabled'
        
        ($OSDeploymentPlanAttributes | ? name -eq 'Password').value = 'password'
     
        # We are using here the 'profile' token. The server will get its hostname from the server Profile name
        ($OSDeploymentPlanAttributes | ? name -eq 'Hostname').value = "{profile}"

        ($OSDeploymentPlanAttributes | ? name -eq 'ManagementNIC.networkuri').value = $ManagementURI
        
        ($OSDeploymentPlanAttributes | ? name -eq 'ManagementNIC2.networkuri').value = $ManagementURI

                      
        $ISCSINetwork = Get-HPOVNetwork | ? {$_.purpose -match "ISCSI" -and $_.SubnetUri -ne $Null} 

        $IscsiParams1 = @{
               ConnectionID                  = 1;
               Name                          = "ImageStreamer Connection 1";
               ConnectionType                = "Ethernet";
               Network                       = $ISCSINetwork;
               Bootable                      = $true;
               Priority                      = "Primary";
               IscsiIPv4AddressSource        = "SubnetPool"
                         }

        $ImageStreamerBootConnection1 = New-HPOVServerProfileConnection @IscsiParams1
        
        $IscsiParams2 = @{
               ConnectionID                  = 2;
               Name                          = "ImageStreamer Connection 2";
               ConnectionType                = "Ethernet";
               Network                       = $ISCSINetwork;
               Bootable                      = $true;
               Priority                      = "Secondary";
               IscsiIPv4AddressSource        = "SubnetPool"
                         }

        $ImageStreamerBootConnection2 = New-HPOVServerProfileConnection @IscsiParams2

        
        $con3 = Get-HPOVNetwork | ? {$_.purpose -match "Management" -and $_.SubnetUri -ne $Null} | New-HPOVServerProfileConnection -connectionId 3
        $con4 = Get-HPOVNetwork | ? {$_.purpose -match "Management" -and $_.SubnetUri -ne $Null}  | New-HPOVServerProfileConnection -connectionId 4
        $con5 = Get-HPOVNetwork | ? fabricType -match "FabricAttach" | select -Index 0 |  New-HPOVServerProfileConnection -ConnectionID 5 -ConnectionType FibreChannel 
        $con6 = Get-HPOVNetwork | ? fabricType -match "FabricAttach" | select -Index 1 | New-HPOVServerProfileConnection -ConnectionID 6 -ConnectionType FibreChannel
        $volume1 = Get-HPOVStorageVolume -Name $datastore | New-HPOVServerProfileAttachVolume # -LunIdType Manual -LunID 0
  

  
        $params = @{
            Name                = $serverprofiletemplate;
            Description         = "Server Profile Template for HPE Synergy 480 Gen9 Compute Module using the Image Streamer";
            ServerHardwareType  = $SY460SHT;
            Affinity            = "Bay";
            Enclosuregroup      = $enclosuregroup;
            Connections         = $ImageStreamerBootConnection1, $ImageStreamerBootConnection2, $con3, $con4, $con5, $con6;
            Manageboot          = $True;
            BootMode            = "UEFIOptimized";
            BootOrder           = "HardDisk";
            HideUnusedFlexnics  = $True;
            SANStorage          = $True;
            OS                  = 'VMware';
            StorageVolume       = $volume1;
            OSDeploymentplan    = $OSDP;
            OSDeploymentPlanAttributes = $OSDeploymentPlanAttributes;
           
             }


      try
          {
       
          New-HPOVServerProfileTemplate @params -ErrorAction Stop | Wait-HPOVTaskComplete
          Write-Output "Server Profile Template $serverprofiletemplate using Image Streamer has been created"
          }

      catch  
         {
       
         $error[0] | fl * -force 
               
         }
   
      
