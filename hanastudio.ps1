param (
    
        [string]$baseUri
    )
    
    #Get the bits for the HANA installation and copy them to C:\SAPbits\SAP_HANA_STUDIO\
    $baseURI = "https://sapmedia.blob.core.windows.net/hanamedia"
    $hanadest = "C:\SapBits"
    $sapcarUri = $baseUri + "/sapcar.exe" 
    $hanastudioUri = $baseUri + "/IMC_STUDIO2_255_0-80000323.SAR" 
    $jreUri = $baseUri + "/serverjre-9.0.4_windows-x64_bin.tar.gz"
    $puttyUri = "https://the.earth.li/~sgtatham/putty/latest/w64/putty-64bit-0.76-installer.msi"
    $7zUri = "https://www.7-zip.org/a/7z1900-x64.msi"
    $sapcardest = "C:\SapBits\SAP_HANA_STUDIO\sapcar.exe"
    $hanastudiodest = "C:\SapBits\SAP_HANA_STUDIO\IMC_STUDIO2_255_0-80000323.SAR"
    $jredest = "C:\Program Files\serverjre-9.0.4_windows-x64_bin.tar.gz"
    $puttydest = "C:\SapBits\SAP_HANA_STUDIO\putty-64bit-0.76-installer.msi"
    $7zdest = "C:\Program Files\7z.msi"
    $jrepath = "C:\Program Files"
    $hanapath = "C:\SapBits\SAP_HANA_STUDIO"
    if((test-path $hanadest) -eq $false)
    {
        New-Item -Path $hanadest -ItemType directory
        New-item -Path $hanapath -itemtype directory
    }
    write-host "downloading files"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest $jreUri -OutFile $jredest
    Invoke-WebRequest $7zUri -OutFile $7zdest
    Invoke-WebRequest $puttyUri -OutFile $puttydest
    Invoke-WebRequest $sapcarUri -OutFile $sapcardest
    Invoke-WebRequest $hanastudioUri -OutFile $hanastudiodest
    
    write-host "installing 7zip and extracting JAVA"
    cd $jrepath
    .\7z.msi /quiet
    Start-Sleep -s 120
    cd "C:\Program Files\7-Zip\"
    .\7z.exe e "C:\Program Files\serverjre-9.0.4_windows-x64_bin.tar.gz" "-oC:\Program Files"
    .\7z.exe x -y "C:\Program Files\serverjre-9.0.4_windows-x64_bin.tar" "-oC:\Program Files"
    Start-Sleep -s 60
    
    cd $hanapath
    write-host "installing PuTTY"
    .\putty-64bit-0.76-installer.msi /quiet
    Start-Sleep -s 60
    
    write-host "extracting and installing HANA Studio"
    .\sapcar.exe -xvf IMC_STUDIO2_255_0-80000323.SAR
    Start-Sleep -s 60
    
    set PATH=%PATH%C:\Program Files\jdk-9.0.4\bin;
    set HDB_INSTALLER_TRACE_FILE=C:\Users\testuser\Documents\hdbinst.log
    cd C:\SAPbits\SAP_HANA_STUDIO\SAP_HANA_STUDIO\
    .\hdbinst.exe -a C:\SAPbits\SAP_HANA_STUDIO\SAP_HANA_STUDIO\studio -b --path="C:\Program Files\sap\hdbstudio"
