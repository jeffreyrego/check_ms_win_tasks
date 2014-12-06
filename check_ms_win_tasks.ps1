# Script name:   	check_ms_win_tasks.ps1
# Version:			2.14.12.06
# Created on:    	01/02/2014																			
# Author:        	D'Haese Willem
# Purpose:       	Checks Microsoft Windows scheduled tasks excluding defined folders and defined 
#					task patterns, returning state of tasks with name, author, exit code and 
#					performance data to Nagios.
# On Github:		https://github.com/willemdh/check_ms_win_tasks
# On OutsideIT:		http://outsideit.net/check_ms_win_tasks
# History:       	
#	11/04/2014 => Added [int] to prevent decimal numbers
#	24/04/2014 => Used ' -> ' to split failed and running tasks
# 	05/05/2014 => Test script fro better handling and checking of parameters, does not work yet...
#	18/08/2014 => Made parameters non mandatory, working with TaskStruct object and default values, argument handling
#	06/12/2014 => Better error handling, better parameter checking, object instead of hashtable, excluded disabled tasks
# Copyright:
#	This program is free software: you can redistribute it and/or modify it under the terms of the
# 	GNU General Public License as published by the Free Software Foundation, either version 3 of 
#   the License, or (at your option) any later version.
#   This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; 
#	without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
# 	See the GNU General Public License for more details.You should have received a copy of the GNU
#   General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

#Requires –Version 2.0

$TaskStruct = New-Object PSObject -Property @{
    Hostname = [string]"localhost";
    ExclFolders = [string[]]@();
    ExclTasks = [string[]]@();
    FolderRef = [string]"";
	AllValidFolders = [string[]]@();
    ExitCode = [int]3;
	TasksOk = [int]0;
	TasksNotOk = [int]0;
	TasksRunning = [int]0;
	TasksTotal = [int]0;
	TasksDisabled = [int]0;
    OutputString = [string]"UNKNWON: Error processing, no data returned"
}
	
	
#region Functions

# Function to for illegal arguments

Function Process-Args {
    Param ( 
        [Parameter(Mandatory=$True)]$Args
    )
	
    try {
        For ( $i = 0; $i -lt $Args.count; $i++ ) { 
		    $CurrentArg = $Args[$i].ToString()
            if ($i -lt $Args.Count-1) {
				$Value = $Args[$i+1];
				If ($Value.Count -ge 2) {
					foreach ($Item in $Value) {
						Check-Strings $Item | Out-Null
					}
				}
				else {
	                $Value = $Args[$i+1];
					Check-Strings $Value | Out-Null
				}	                             
            } else {
                $Value = ""
            };

            switch -regex -casesensitive ($CurrentArg) {
                "^(-H|--Hostname)$" {
                    $TaskStruct.Hostname = $Value
                    $i++
                }
				"^(-EF|--Excl-Folders)$" {
					If ($Value.Count -ge 2) {
						foreach ($Item in $Value) {
		                		$TaskStruct.ExclFolders+=$Item
		            		}
					}					
					else {
		                $TaskStruct.ExclFolders = $Value  
					}	
                    $i++
                };	
				"^(-ET|--Excl-Tasks)$" {
					If ($Value.Count -ge 2) {
						foreach ($Item in $Value) {
		                		$TaskStruct.ExclTasks+=$Item
		            		}
					}					
					else {
		                $TaskStruct.ExclTasks = $Value  
					}	
                    $i++
                };
                "^(-w|--Warning)$" {
                    if (($value -match "^[\d]+$") -and ([int]$value -lt 100)) {
                        $TaskStruct.WarningTreshold = $value
                        $TaskStruct.UseSharepointWarningLimit = $false
                    } else {
                        throw "Warning treshold should be numeric and less than 100. Value given is $value"
                    }
                    $i++
                }
                "^(-c|--Critical)$" {
                    if (($value -match "^[\d]+$") -and ([int]$value -lt 100)) {
                        $TaskStruct.CriticalTreshold = $value
                    } else {
                        throw "Critical treshold should be numeric and less than 100. Value given is $value"
                    }
                    $i++
                 }
                "^(-h|--Help)$" {
                    Write-Help
                }
                default {
                    throw "Illegal arguments detected: $_"
                 }
            }
        }
    } catch {
		Write-Host "UNKNOWN: $_"
        Exit $TaskStruct.ExitCode
	}	
}

# Function to check strings for invalid and potentially malicious chars

Function Check-Strings {
    Param ( [Parameter(Mandatory=$True)][string]$String )
    # `, `n, |, ; are bad, I think we can leave {}, @, and $ at this point.
    $BadChars=@("``", "|", ";", "`n")

    $BadChars | ForEach-Object {

        If ( $String.Contains("$_") ) {
            Write-Host "Unknown: String contains illegal characters."
            Exit $TaskStruct.ExitCode
        }
    }
    Return $true
} 

# Function to get all task subfolders

function Get-AllTaskSubFolders {
    if ($RootFolder) {
        $TaskStruct.AllValidFolders+=$TaskStruct.FolderRef
		return
    } 
	else {
        $TaskStruct.AllValidFolders+=$TaskStruct.FolderRef	     
        if(($folders = $TaskStruct.FolderRef.getfolders(1)).count -ge 1) {
            foreach ($folder in $folders) {
				if ($TaskStruct.ExclFolders -notcontains $folder.Name) {     
                	if(($folder.getfolders(1).count -ge 1)) {
						$TaskStruct.FolderRef=$folder
                    	Get-AllTaskSubFolders
                	}
					else {
							$TaskStruct.AllValidFolders+=$folder
					}							
				}
			}
			return
        }
    }
	return
}


# Function to check a string for patterns

function Check-Array ([string]$str, [string[]]$patterns) {
    foreach($pattern in $patterns) { 
		if($str -match $pattern) {
			return $true; 
		} 
	}
    return $false;
}

# Function to write help output

Function Write-Help {
	Write-Host @"
check_ms_win_tasks.ps1:
This script is designed to check check Windows 2008 or higher scheduled tasks and alert in case tasks failed in Nagios style output.
Arguments:
    -H  | --Hostname     => Optional hostname of remote system, default is localhost, not yet tested on remote host.
    -EF | --Excl-Folders => Name of folders to exclude from monitoring.
    -ET | --Excl-Tasks   => Name of task patterns to exclude from monitoring.
    -h  | --Help         => Print this help output.
"@
    Exit $TaskStruct.ExitCode;
} 

#endregion Functions

# Main function to kick off functionality

Function Check-MS-Win-Tasks { 

	# Try connecting to schedule service COM object
	
	try {
		$schedule = new-object -com("Schedule.Service") 
	} 
	catch {
		Write-Host "UNKNWON: Schedule.Service COM Object not found, this script requires this object"
		Exit $TaskStruct.ExitCode
	} 
	
	$Schedule.connect($TaskStruct.Hostname) 
	$TaskStruct.FolderRef = $Schedule.getfolder("\")
	
	Get-AllTaskSubFolders
	
	$BadTasks = @()
	$GoodTasks = @()
	$RunningTasks = @()
	$DisabledTasks = @()
	$OutputString = ""

	foreach ($Folder in $TaskStruct.AllValidFolders) {		
		    if (($Tasks = $Folder.GetTasks(0))) {
		        $Tasks | Foreach-Object {$ObjTask = New-Object -TypeName PSCustomObject -Property @{
			            'Name' = $_.name
		                'Path' = $_.path
		                'State' = $_.state
		                'Enabled' = $_.enabled
		                'LastRunTime' = $_.lastruntime
		                'LastTaskResult' = $_.lasttaskresult
		                'NumberOfMissedRuns' = $_.numberofmissedruns
		                'NextRunTime' = $_.nextruntime
		                'Author' =  ([xml]$_.xml).Task.RegistrationInfo.Author
		                'UserId' = ([xml]$_.xml).Task.Principals.Principal.UserID
		                'Description' = ([xml]$_.xml).Task.RegistrationInfo.Description
						'Cmd' = ([xml]$_.xml).Task.Actions.Exec.Command 
						'Params' = ([xml]$_.xml).Task.Actions.Exec.Arguments
		            }
				if ($ObjTask.LastTaskResult -eq "0" -and $ObjTask.Enabled) {
					if(!(Check-Array $ObjTask.Name $TaskStruct.ExclTasks)){
						$GoodTasks += $ObjTask
						$TaskStruct.TasksOk += 1
						}
					}
				elseif ($ObjTask.LastTaskResult -eq "0x00041301" -and $ObjTask.Enabled) {
					if(!(Check-Array $ObjTask.Name $TaskStruct.ExclTasks)){
						$RunningTasks += $ObjTask
						$TaskStruct.TasksRunning += 1
						}
					}
				elseif ($ObjTask.Enabled) {
					if(!(Check-Array $ObjTask.Name $TaskStruct.ExclTasks)){
						$BadTasks += $ObjTask
						$TaskStruct.TasksNotOk += 1
						}
					}
				else {
					if(!(Check-Array $ObjTask.Name $TaskStruct.ExclTasks)){
						$DisabledTasks += $ObjTask
						$TaskStruct.TasksDisabled += 1
					}
				}
		    }
		}
	} 
	$TaskStruct.TasksTotal = $TaskStruct.TasksOk + $TaskStruct.TasksNotOk + $TaskStruct.TasksRunning
	if ($TaskStruct.TasksNotOk -gt "0") {
		$OutputString += "$($TaskStruct.TasksNotOk) / $($TaskStruct.TasksTotal) tasks failed! Check tasks: "
		foreach ($BadTask in $BadTasks) {
			$OutputString += " -> Task $($BadTask.Name) by $($BadTask.Author) failed with exitcode $($BadTask.lasttaskresult) "
		}
		foreach ($RunningTask in $RunningTasks) {
			$OutputString += " -> Task $($RunningTask.Name) by $($RunningTask.Author), exitcode $($RunningTask.lasttaskresult) is still running! "
		}
		$OutputString +=  " | 'Total Tasks'=$($TaskStruct.TasksTotal), 'OK Tasks'=$($TaskStruct.TasksOk), 'Failed Tasks'=$($TaskStruct.TasksNotOk), 'Running Tasks'=$($TaskStruct.TasksRunning)"
		
		$TaskStruct.ExitCode = 2
	}	
	else {
		$OutputString +=  "$($TaskStruct.TasksOk) / $($TaskStruct.TasksTotal) tasks ran succesfully! "
		foreach ($RunningTask in $RunningTasks) {
			$OutputString +=  " -> Task $($RunningTask.Name) by $($RunningTask.Author), exitcode $($RunningTask.lasttaskresult), is still running! "
		}
		$OutputString +=  " | 'Total Tasks'=$($TaskStruct.TasksTotal), 'OK Tasks'=$($TaskStruct.TasksOk), 'Failed Tasks'=$($TaskStruct.TasksNotOk), 'Running Tasks'=$($TaskStruct.TasksRunning)"
		$TaskStruct.ExitCode = 0
	}
	Write-Host "$outputString"
	exit $TaskStruct.ExitCode
}

# Main block

# Reuse threads

if ($PSVersionTable){$Host.Runspace.ThreadOptions = 'ReuseThread'}

# Main function

if($Args.count -ge 1){Process-Args $Args}
	
Check-MS-Win-Tasks