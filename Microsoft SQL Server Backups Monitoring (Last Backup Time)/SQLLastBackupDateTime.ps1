#######################################################################################
# Name: SQLLastBackupTime.ps1
# Description: queries sql server to get las backup time and compare to threshold
# Dependances: Powershell 2.0 must be installed, SQL 2005, 2008 or 2008 R2
# Variables: sqlinstance = SQL Instance name (no server name). if the instance is not
#                          provided, it will default to MSSQLSERVER
#            dbname = database name. if the variable is not provided, it will compare 
#                     all to the threshold and return an error if any of them is above it
#            maxage = maximum backup age in hours. if the variable is not provided, it will
#                     default to 24hrs
# Usage: SQLLastBackupTime.psq -sqlinstance instancename -dbname reportserver -maxage 24
# Compatibility (OS) : Windows XP, vista, 7, Server 2003(r2), Server 2008(r2)
# Compatiblity (SQL) : Microsoft SQL Server 2005, 2008, 2008R2
# Version: 1.0
# Author: Marc-Andre Tanguay @ N-able Technologies
#######################################################################################

 
# Version History

# 1.0 - Initial Release (Sept 28 2012)


Param(
  [int]$maxage
)

cls

$ns=[wmiclass]'__namespace'
$sc=$ns.CreateInstance()
$sc.Name='ncentral'
$sc.Put()
$file="c:\temp\file1.txt"
$oldestage = get-date
$oldestdbname = ""
$oldestinstance = ""
$oldestbackupok = 0

$InstanceID = 0

# VALIDATE THE MAXAGE. IF ITS NULL OR BLANK, SET TO 24HRS

if (!$maxage)
{
    $maxage=24
}
elseif($maxage -gt 1)
{
}
else
{
    $maxage=24
}
$maxdate=get-date
$maxdate=$maxdate.AddHours(-$maxage)

    if ((get-wmiobject -namespace "root/cimv2/ncentral" -list -EV namespaceError) | ? {$_.name -match "SQLBackupData"})
    {
        ##  Deletes the old Instances of the Class SQLBackupData
   
        $dbcount = New-Object system.Collections.ArrayList
        ## checking for the Class in root/nable namespace
        $testfolder=Get-WMIObject -namespace root/cimv2/ncentral -query "Select * From SQLBackupData"
        $rr=0;
        Get-WMIObject -namespace root/cimv2/ncentral -query "Select * From SQLBackupData" | foreach {$dbcount.Insert($rr, $_);$rr++ }

        $dbcnt=$dbcount.count
        if($dbcount.count -ge '1')
        {
            $testfolder | Remove-WMIObject
        }  

    }
    else
    {


        if( ![string]::IsNullOrEmpty( $namespaceError[0] ) )
        {
    	    add-content $file "ERROR accessing namespace: $namespaceError[0]"
    	    RETURN
        }

        try 
        {

            $newClass = New-Object System.Management.ManagementClass `
            ("root\cimv2\ncentral", [String]::Empty, $null); 
            $newClass["__CLASS"] = "SQLBackupData"; 

            $newClass.Qualifiers.Add("Static", $true)

            $newClass.Properties.Add("LastBackupDate", [System.Management.CimType]::String, $false)
            $newClass.Properties.Add("BackupOK", [System.Management.CimType]::UInt32, $false)
            $newClass.Properties.Add("DbName", [System.Management.CimType]::String, $false)
            $newClass.Properties.Add("SQLInstance", [System.Management.CimType]::String, $false)
            $newClass.Properties.Add("ResultDetails", [System.Management.CimType]::String, $false)


            $newClass.Properties["LastBackupDate"].Qualifiers.Add("key", $true)
            $newClass.Properties["BackupOK"].Qualifiers.Add("key", $true)
            $newClass.Properties["DbName"].Qualifiers.Add("key", $true)
            $newClass.Properties["SQLInstance"].Qualifiers.Add("key", $true)
            $newClass.Properties["ResultDetails"].Qualifiers.Add("key", $true)

            $newClass.Put()
        }
        catch
        {
            add-content $file "ERROR creating WMI class: $_"
        }
        ######################################
    
    }


$SQLInstanceList = (get-itemproperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server').InstalledInstances


while($SQLInstanceList.Count -gt $InstanceID)
{

#set instance name to the next one in the array
$sqlinstance = $SQLInstanceList[$InstanceID]

#set name to valid name for querying in SMO
    if (!$sqlinstance)
    {
        $sqlinstance=""
    
    }
    else
    {
        $sqlinstance=$sqlinstance.ToLower()
        $sqlinstancefullname=$sqlinstance.ToLower()
        if ($sqlinstance -eq "mssqlserver")
        {
            $sqlinstance=""
        }
        else
        {
            $sqlinstance="\$sqlinstance"
        }
    }
    $DbServer="localhost$sqlinstance"
#    $DbServer




    # GET SQL DB BACKUP TIME INFO

    [System.Reflection.Assembly]::LoadWithPartialName(‘Microsoft.SqlServer.SMO’) | Out-Null
    $server = New-Object (‘Microsoft.SqlServer.Management.Smo.Server’) “$DBServer”
    $DbList=$server.databases | select Name, LastBackupDate 
    $row = 0

    while($DbList.Count -gt $row)
    {
        $strresult=$DbList[$row].Name + " - " + $DbList[$row].LastBackupDate + " ### "

        $dbname = $DbList[$row].name
        $bkpage=$DbList[$row].LastBackupDate

        if($maxdate -gt $DbList[$row].LastBackupDate)
        {
            $boolok=0
        }
        else
        {
            $boolok = 1
        }
        if($oldestage -gt $DbList[$row].LastBackupDate)
        {
           "OLD " + $dbname
            $oldestage = $bkpage
            $oldeststrresult = "Oldest Backup database : " + $sqlinstancefullname + " \ " + $dbname
            $oldestbackupok = $boolok
        }

        
#        try 
#        {
            $wmicls = ([wmiclass]"root/cimv2/ncentral:SQLBackupData").CreateInstance()

            $wmicls.LastBackupDate = $bkpage
            $wmicls.BackupOK = $boolok
            $wmicls.DbName=$dbname
            $wmicls.ResultDetails=$strresult
            $wmicls.SQLInstance=$sqlinstancefullname + "\" + $dbname

#            $wmicls |FL
            $wmicls.Put() 
#        }
#        catch
#        {
#            "ERROR creating a new instance: $_"
#        }

#        "dbname : " + $dbname
#        "Instance: " + $sqlinstance
#        "Result : " + $strresult
#        "maxage : " + $maxage
#        "maxdate : " + $maxdate.tostring()
#        "Oldest : " + $bkpage.tostring()
#        "BACKUP OK : " + $boolok

        $row=$row+1
}

$InstanceID = $InstanceID + 1 

}


#SUMMARY ENTRY

        try 
        {
            $wmicls = ([wmiclass]"root/cimv2/ncentral:SQLBackupData").CreateInstance()

            $wmicls.LastBackupDate = $oldestage
            $wmicls.BackupOK = $oldestbackupok
            $wmicls.DbName="SUMMARY"
            $wmicls.ResultDetails=$oldeststrresult
            $wmicls.SQLInstance="SUMMARY"

            $wmicls.Put() 
        }
        catch
        {
            add-content $file "ERROR creating a new instance: $_"
        }
