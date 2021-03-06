clear
<#
Get Permit Issuance Data (JSON) & Store PSObj (Online)/(Offline) -Outputs files containing list of PSObjs
    -Get BIN# (Can have 2 addresses)
    -Residential = YES
    -Filing status = INITIAL = Permit sequence 01
    -Job Doc# = 01 (Omit and it will return multiple job numbers
    -Job Type = A1 (Conversion), A2 (Construction), NV (New Building)
    **Aligns with HTML Page
    **2017 records only to start
    -Work Type is  = EQ (Construction Equipment), OT/GC (General Consctruction)

FIX
    -Match-RecordsToFile returns duplicate matches

Source Name: DOB Permit Issuance (738k Records)
URL: http://data.cityofnewyork.us/resource/83x8-shf7.json

Source Name: DOB Job Application Filings (283k Records)
URL: https://data.cityofnewyork.us/resource/rvhx-8trz.json

#>

#--Settings--
$RootDataDir = "E:\OfflineObjects\Permit"
#------------

function Get-JsonDataToFile {
Param($RootDataDir,
    [switch]$AppFiling,
    [switch]$Issuance
)
	#Get NYC DOB Permit Data
	$Limit = 1000				#Number of records to get in a single API call
	$Offset = 1					#Record number to start at, used for paging
	$c = 1
    If($AppFiling){
        Write-Host "--Fetch Application Filing Data & Write to File--"
        $IssuanceObjAppFilings = @()		#Complete list of records returned after paging
	    Do{
		    $Uri = 'http://data.cityofnewyork.us/resource/rvhx-8trz.json?$Limit=' + $Limit + '&$Offset=' + $Offset + '&$Order=job__&$where=proposed_occupancy%20in%20("R-1","R2","RES","J-1","J-2")'
		    $WebResponseAppFilings = Invoke-RestMethod -Method Get -Uri $Uri -Headers @{"app_token"="HvnZBMv83YRn1RjWnam2qOegT"}
		    $WebResponseAppFilings | Export-Clixml "$RootDataDir\AppFilings\$c"
		    $c
            $Offset = $Offset + $Limit
            $c++
        }
	        Until($WebResponseAppFilings.count -eq 0)
    
    }

    If($Issuance){
        Write-Host "--Fetch Issuance Data & Write to File--"
        $IssuanceData = @()		#Complete list of records returned after paging
	    Do{
		    $Uri = 'http://data.cityofnewyork.us/resource/83x8-shf7.json?$Limit=' + $Limit + '&$Offset=' + $Offset + '&$Order=job__&filing_status=INITIAL'
		    $WebResponseIssuance = Invoke-RestMethod -Method Get -Uri $Uri -Headers @{"app_token"="HvnZBMv83YRn1RjWnam2qOegT"}
		    $WebResponseIssuance | Export-Clixml "$RootDataDir\Issuance\$c"
		    $c
		    $Offset = $Offset + $Limit
            $c++
	    }
	    Until($WebResponseIssuance.count -eq 0)
    }
}


function Index-IssuanceData {
Param($RootDataDir
)
    Write-Host '--Indexing Issuance Jobs'
    $IssuanceFileList = Get-ChildItem "$RootDataDir\Issuance"
    $IndexIssuanceObjs = @()

    #Record a list of all unique job numbers in each file and which file it's located 
    Foreach($IssuanceFile in $IssuanceFileList){
        $IssuanceObjs = Import-Clixml $IssuanceFile.FullName
        
        #FILTER BY FILING DATE
        $IssuanceObjs = $IssuanceObjs | ?{$_.filing_date -imatch "2017"}

        #Select unique job numbers to reduce index size
        $FileName = $IssuanceFile.Name
        $IssuanceObjsUnique = $IssuanceObjs.job__ | Select -Unique

        If($IssuanceObjsUnique.count -ge 1){
            Foreach($IssuanceObj in $IssuanceObjsUnique){
                    $IndexIssuanceObj = New-Object PSObject
                    $IndexIssuanceObj | Add-Member NoteProperty JobNum $IssuanceObj
                    $IndexIssuanceObj | Add-Member NoteProperty FileName $FileName
                    $IanceObjndexIssus += $IndexIssuanceObj
            }

            Write-Host 'Writing Index File:' $FileName '| Found:' $IssuanceObjsUnique.count
            $IndexIssuanceObjs | Export-Clixml "$RootDataDir\IndexIssuance\$FileName"
            $IndexIssuanceObjs = @()
        }
    }

    
}


function Match-RecordsToFile {
Param($RootDataDir,
[Switch]$LoadIndex
)
     
    Write-Host 'Loading Indices to Memory'
    #Load App Filing Index to Memory
    $IndexAppObj = @()
    $IndexAppFileList = Get-ChildItem "$RootDataDir\IndexApp"

    Foreach($IndexAppFile in $IndexAppFileList){
        $IndexApp = Import-Clixml $IndexAppFile.FullName
        $IndexAppObj += $IndexApp
    }


    #Load Issuance Index to Memory
    $IndexIssuanceObj = @()
    $IndexIssuanceFileList = Get-ChildItem "$RootDataDir\IndexIssuance"

    Foreach($IndexIssuanceFile in $IndexIssuanceFileList){
        $IndexIssuance = Import-Clixml $IndexIssuanceFile.FullName
        $IndexIssuanceObj += $IndexIssuance
    }
    $IndexIssuanceObj.count
    

    Write-Host '--Merging Common Records & Writing to File'
    #List of Files
    $AppFilingFileList = Get-ChildItem "$RootDataDir\AppFilings"
    $IssuanceFileList = Get-ChildItem "$RootDataDir\Issuance"
    
    $RecordCount = 3
    $FileNum = 1
    $c = 0
    $MergedDataSetList = @()
    $k = 1
    $AppFilingFileListCount = $AppFilingFileList.count

    Foreach($AppFilingFile in $AppFilingFileList){
        Write-Host "($k of $AppFilingFileListCount)"
        $AppFilingObjs = Import-Clixml $AppFilingFile.FullName
        
        Foreach($AppFilingObj in ($AppFilingObjs )){
            #If(!(Test-Path "$RootDataDir\MergedPsObjs\$JobNu")){
                    If($IndexIssuanceObj.JobNum -icontains $AppFilingObj.job__){
                        Write-Host 'Matched Job Number:' $AppFilingObj.job__
                        
                        #Retreive specific file containing job number & Break loop after finding it
                        Foreach($Obj in $IndexIssuanceObj){
                            If($Obj.JobNum -imatch $AppFilingObj.job__){
                                $IndexIssuanceFileName = $Obj.FileName
                                BREAK
                            }
                        }

                       $IssuanceObjs = Import-Clixml "$RootDataDir\Issuance\$IndexIssuanceFileName"

                        Foreach($IssuanceObj in ($IssuanceObjs)){

                            If($IssuanceObj.job__ -eq $AppFilingObj.job__ -and $IssuanceObj.job_doc___ -eq $AppFilingObj.doc__ -and $IssuanceObj.permit_sequence__ -eq '01'){
                                $JobNum = $IssuanceObj.job__
                                $DocNum = $IssuanceObj.job_doc___

                                #Merge data sets into a new PSObject
                                $MergedDataSet = New-Object PSObject
                                $MergedDataSet | Add-Member NoteProperty Bin $IssuanceObj.bin__
                                $MergedDataSet | Add-Member NoteProperty Job_Num $IssuanceObj.job__
                                $MergedDataSet | Add-Member NoteProperty Doc_Num $IssuanceObj.job_doc___
                                $MergedDataSet | Add-Member NoteProperty Permit_Seq_Num $IssuanceObj.permit_sequence__
                                $MergedDataSet | Add-Member NoteProperty Bld_Num $IssuanceObj.house__
		                        $MergedDataSet | Add-Member NoteProperty Bld_Street_Name $IssuanceObj.street_name
		                        $MergedDataSet | Add-Member NoteProperty Bld_City $IssuanceObj.city
		                        $MergedDataSet | Add-Member NoteProperty Bld_Borough $IssuanceObj.borough
		                        $MergedDataSet | Add-Member NoteProperty Bld_Zip $IssuanceObj.zip_code
		                        $MergedDataSet | Add-Member NoteProperty Bld_State $IssuanceObj.state
                                $MergedDataSet | Add-Member NoteProperty Proposed_Num_Units $AppFilingObj.proposed_dwelling_units
                                $MergedDataSet | Add-Member NoteProperty Proposed_Num_Stories $AppFilingObj.proposed_no_of_stories
                                $MergedDataSet | Add-Member NoteProperty Proposed_Occupancy $AppFilingObj.proposed_occupancy
		                        $MergedDataSet | Add-Member NoteProperty Owners_Business_Name $IssuanceObj.owner_s_business_name
		                        $MergedDataSet | Add-Member NoteProperty Owners_First_Name $IssuanceObj.owner_s_first_name
		                        $MergedDataSet | Add-Member NoteProperty Owners_Last_Name $IssuanceObj.owner_s_last_name
		                        $MergedDataSet | Add-Member NoteProperty Owners_House_Number $IssuanceObj.owner_s_house__
		                        $MergedDataSet | Add-Member NoteProperty Owners_Street $IssuanceObj.owner_s_house_street_name
		                        $MergedDataSet | Add-Member NoteProperty Owners_Zip $IssuanceObj.owner_s_zip_code
		                        $MergedDataSet | Add-Member NoteProperty Owners_Phone $IssuanceObj.owner_s_phone__
		                        $MergedDataSet | Add-Member NoteProperty Permittees_Business $IssuanceObj.permittee_s_business_name
		                        $MergedDataSet | Add-Member NoteProperty Permittees_First_Name $IssuanceObj.permittee_s_first_name
		                        $MergedDataSet | Add-Member NoteProperty Permittees_Last_Name $IssuanceObj.permittee_s_last_name
		                        $MergedDataSet | Add-Member NoteProperty Permittees_Lic_Type $IssuanceObj.permittee_s_license_type
		                        $MergedDataSet | Add-Member NoteProperty Permittees_Phone $IssuanceObj.permittee_s_phone__
		                        $MergedDataSet | Add-Member NoteProperty Permit_Status $IssuanceObj.permit_status
		                        $MergedDataSet | Add-Member NoteProperty Work_Type $IssuanceObj.work_type
                                $MergedDataSet | Add-Member NoteProperty Job_Desc $AppFilingObj.job_description
                                $MergedDataSet | Add-Member NoteProperty Issuance_Date $IssuanceObj.issuance_date
                                $MergedDataSet | Add-Member NoteProperty Filing_Date $IssuanceObj.filing_date
                            
                                #Store data in a variable, then write to file once RecordCount is hit
                                $MergedDataSetList += $MergedDataSet

                            }
                        }
                        $MergedDataSetList | Export-Clixml "$RootDataDir\MergedPsObjs\$($AppFilingObj.job__)"
                        $MergedDataSetList = @()
                    }
            #}
            
        }

        $k++
    }
}


function Get-RawHtmlContent {
Param($RootDataDir
)
    #List of Files
    $MergedPsObjsFileList = Get-ChildItem "$RootDataDir\MergedPsObjs"
    Write-Host "--Writing Raw Html to File:"
    Foreach($MergedPsObjsFile in $MergedPsObjsFileList){
        $MergedPsObjs = Import-Clixml $MergedPsObjsFile.FullName

        Foreach($MergedPsObj in $MergedPsObjs){
            $JobNum = $MergedPsObj.Job_Num
            $DocNum = $MergedPsObj.Doc_Num
            If(!(Test-Path "$RootDataDir\Html\$JobNum-$DocNum")){
                    Write-Host "$JobNum-$DocNum"

                Do{
                    $Uri = "http://a810-bisweb.nyc.gov/bisweb/JobsQueryByNumberServlet?requestid=2&passjobnumber=$JobNum&passdocnumber=$DocNum"
                    $WebResponse = Invoke-WebRequest -Uri $Uri 
                    $WebResponse = $WebResponse.RawContent
                    $WebResponseParsed = ([regex]::Matches($WebResponse,'(?<=>)(.*?)(?=<)')).Value -replace "(^[\s\t\r\n]*)","" -replace "&nbsp;","" | ?{$_ -notmatch "^[\s\t\r\n]*$"}
                
                    #Retry if the following string is found
                    $Verify = $true
                    Foreach($Line in $WebResponseParsed){
                        If($Line -imatch "Just a moment"){
                            $Verify = $false
                            Write-Host 'Retry' -ForegroundColor Red
                            Start-Sleep -Milliseconds 500
                        }
                    }                   
                }
                Until($Verify -eq $true)
                $WebResponse | Out-File "$RootDataDir\Html\$JobNum-$DocNum"
            }
        }
    }
}


function Output-Data {
Param($RootDataDir
)
    Write-Host '--Output to CSV'
    $MergedPsObjsFileList = Get-ChildItem "$RootDataDir\MergedPsObjs"
    Foreach($MergedPsObjsFile in $MergedPsObjsFileList){
        $MergedPsObjs = Import-Clixml $MergedPsObjsFile.FullName

        Foreach($MergedPsObj in $MergedPsObjs){
            $JobNum = $MergedPsObj.Job_Num
            $DocNum = $MergedPsObj.Doc_Num

            $JobNum
            $FilePath = "$RootDataDir\Html\" + $JobNum + "-" + $DocNum
            $HtmlRawData = Get-Content $FilePath
                
            $HtmlParsedData = ([regex]::Matches($HtmlRawData,'(?<=>)(.*?)(?=<)')).Value -replace "(^[\s\t\r\n]*)","" -replace "&nbsp;","" | ?{$_ -notmatch "^[\s\t\r\n]*$"}
		
		    #Get Owner's Information Section
		    $OwnerInfoLineNum = ($HtmlParsedData | Select-String -Pattern "Owner's Information").LineNumber-1
		    $OwnerInfoEndLineNum = ($HtmlParsedData | Select-String -Pattern "Non Profit" -CaseSensitive).LineNumber-1
		    $OwnerInfoSection = $HtmlParsedData[$OwnerInfoLineNum..$OwnerInfoEndLineNum]
		
		    #Capture Owner's Email Address
		    $OwnersEmailAddress = ($OwnerInfoSection | Select-String -Pattern "@").Line
            $MergedPsObj | Add-Member NoteProperty OwnersEmail $OwnersEmailAddress

            $MergedPsObj | Export-CSV "$RootDataDir\Permit.csv" -Append

        }

    }

}


function Index-AppData {
Param($RootDataDir
)
    Write-Host '--Indexing App Jobs'
    $AppFilingFileList = Get-ChildItem "$RootDataDir\AppFilings"
    $IndexAppObjs = @()

    #Record a list of all unique job numbers in each file and which file it's located 
    Foreach($AppFilingFile in $AppFilingFileList){
        $AppFilingObjs = Import-Clixml $AppFilingFile.FullName
        $FileName = $AppFilingFile.Name
        $AppFilingObjsUnique = $AppFilingObjs.job__ | Select-Object -Unique

        Foreach($AppFilingObj in $AppFilingObjsUnique){
            $IndexAppObj = New-Object PSObject
            $IndexAppObj | Add-Member NoteProperty JobNum $AppFilingObj
            $IndexAppObj | Add-Member NoteProperty FileName $FileName
            $IndexAppObjs += $IndexAppObj
        }
        Write-Host 'Writing Index File:' $FileName '| Found:' $AppFilingObjsUnique.count
        $IndexAppObjs | Export-Clixml "$RootDataDir\IndexApp\$FileName"
        $IndexAppObjs = @()
    }

    
}




#--Get Json Data Online--
#Get-JsonDataToFile -RootDataDir $RootDataDir -AppFiling
#Get-JsonDataToFile -RootDataDir $RootDataDir -Issuance

#--Index Data
#Index-AppData -RootDataDir $RootDataDir
#Index-IssuanceData -RootDataDir $RootDataDir

#--Get Json Data Offline
#Match-RecordsToFile -RootDataDir $RootDataDir -LoadIndex

#--Get Raw HTML Content
#Get-RawHtmlContent -RootDataDir $RootDataDir

#--Combine Data & Write to CSV
#Output-Data -RootDataDir $RootDataDir