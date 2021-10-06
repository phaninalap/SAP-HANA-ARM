# HANA Single Node Setup
set -x

 # HANASID="HF2"
 # HANNUMBER="00"
 # HANAPWD="HP1nv3nt"
 HANACOMP="server, client, studio, afl"
 SAPBITSDIR="/hana/data/sapbits"
 hanapackage="51054623"
 # Uri="https://app0584storagedev.blob.core.windows.net/hanamedia" 

main::set_boot_parameters() {
  ## disable selinux
  if [[ -e /etc/sysconfig/selinux ]]; then
    sed -ie 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
  fi

  if [[ -e /etc/selinux/config ]]; then
    sed -ie 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
  fi
  ## work around for LVM boot where LVM volues are not started on certain SLES/RHEL versions
  if [[ -e /etc/sysconfig/lvm ]]; then
    sed -ie 's/LVM_ACTIVATED_ON_DISCOVERED="disable"/LVM_ACTIVATED_ON_DISCOVERED="enable"/g' /etc/sysconfig/lvm
  fi

  ## Configure cstates and huge pages
  if ! grep -q cstate /etc/default/grub ; then
    cmdline=$(grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub | head -1 | sed 's/GRUB_CMDLINE_LINUX_DEFAULT=//g' | sed 's/\"//g')
    cp /etc/default/grub /etc/default/grub.bak
    grep -v GRUBLINE_LINUX_DEFAULT /etc/default/grub.bak >/etc/default/grub
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline transparent_hugepage=never intel_idle.max_cstate=1 processor.max_cstate=1 intel_iommu=off\"" >>/etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
    echo "${HOSTNAME}" >/etc/hostname
    # exit 0
  fi
}

main::get_os_version() {
  if grep SLES /etc/os-release; then
    readonly LINUX_DISTRO="SLES"
    readonly LINUX_VERSION=$(grep VERSION_ID /etc/os-release | awk -F '\"' '{ print $2 }')
  elif grep -q "Red Hat" /etc/os-release; then
    readonly LINUX_DISTRO="RHEL"
    readonly LINUX_VERSION=$(grep VERSION_ID /etc/os-release | awk -F '\"' '{ print $2 }')
    readonly LINUX_MAJOR_VERSION=$(echo $LINUX_VERSION | awk -F '.' '{ print $1 }')
  else
    echo "Unsupported Linux distribution. Only SLES and RHEL are supported."
  fi
}

main::install_packages() {
  ## SuSE work around to avoid a startup race condition
  if [[ ${LINUX_DISTRO} = "SLES" ]]; then
    local count=0

    ## check if SuSE repos are registered
    while [[ $(find /etc/zypp/repos.d/ -maxdepth 1 | wc -l) -lt 2 ]]; do
      sleep 60s
      count=$((count +1))
      if [ ${count} -gt 30 ]; then
      echo "SuSE repositories didn't register within an acceptable time. If you are using BYOS, ensure you login to the system and apply the SuSE license within 30 minutes after deployment. If you are using a VM without external IP make sure you set up a NAT gateway to provide internet access."
      fi
    done
    sleep 10s

    ## check if zypper is still running
    while pgrep zypper; do
      sleep 10s
    done
  fi

  ## packages to install
  local sles_packages="libssh2-1 libopenssl0_9_8 libopenssl1_0_0 joe tuned krb5-32bit unrar SAPHanaSR SAPHanaSR-doc pacemaker numactl csh python-pip python-pyasn1-modules ndctl python-oauth2client python-oauth2client-gce python-httplib2 python-requests python-google-api-python-client libgcc_s1 libstdc++6 libatomic1"
  local rhel_packages="unar.x86_64 tuned-profiles-sap-hana tuned-profiles-sap-hana-2.7.1-3.el7_3.3 joe resource-agents-sap-hana.x86_64 compat-sap-c++-6 numactl-libs.x86_64 libtool-ltdl.x86_64 nfs-utils.x86_64 pacemaker pcs lvm2.x86_64 compat-sap-c++-5.x86_64 csh autofs ndctl compat-sap-c++-9 libatomic unzip libsss_autofs python2-pip langpacks-en langpacks-de glibc-all-langpacks libnsl libssh2 wget tcsh psmisc bind-utils compat-locales-sap resource-agents-sap tuned-profiles-sap vhostmd vm-dump-metrics expect gtk2 krb5-workstation krb5-libs libaio libcanberra-gtk2 libibverbs libicu openssl PackageKit-gtk3-module rsyslog sudo xpsfrogs xorg-x11-xauth tuned cairo graphviz iptraf-ng lm_sensors net-tools"

  ## install packages
  if [[ ${LINUX_DISTRO} = "SLES" ]]; then
    for package in ${sles_packages}; do
        zypper in -y "${package}"
    done
    zypper in -y sapconf saptune
    # making sure we refresh the bash env
    . /etc/bash.bashrc
    # boto.cfg has spaces in 15sp2, getting rid of them (b/172181835)
    if [[ $(tail -n 1 /etc/boto.cfg) == "  ca_certificates_file = system" ]]; then
      sed -i 's/^[ \t]*//' /etc/boto.cfg
    fi
  elif [[ ${LINUX_DISTRO} = "RHEL" ]]; then
    for package in $rhel_packages; do
        echo "install packages"
        yum -y install "${package}"
    done
    # check for python interpreter - RHEL 8 does not have "python"
    if [[ ! -f "/bin/python" ]] && [[ -f "/usr/bin/python2" ]]; then
      alternatives --set python /usr/bin/python2
    fi
    # make sure latest packages are installed 
    if ! yum update -y; then
    echo "Applying updates to packages on system failed ("yum update -y"). Logon to the VM to investigate the issue."
    fi
  fi
  rpm -Uvh https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
  yum install -y blobfuse
  yum install -y cifs-utils
}

main::limts_tmp_excludes() {
 main::errhandle_log_info 'SAP Configuration set Security Limits' 
 # SAP Configuration Security Limits
 {
   echo "[SAP Limits]" >/etc/security/limits.d/99-sap.conf
	 echo "@sapsys  hard  nofile  65536"
	 echo "@sapsys  soft  nofile  65536"
	 echo "@sapinst hard  nofile  65536"
   echo "@sapinst soft  nofile  65536"
   echo "@sdba    hard  nofile  65536"
   echo "@sdba    soft  nofile  65536"
   echo "@sapsys  hard  nproc   unlimited"
	 echo "@sapsys  soft  nproc   unlimited"
	 echo "@sapinst hard  nproc   unlimited"
   echo "@sapinst soft  nproc   unlimited"
   echo "@sdba    hard  nproc   unlimited"
   echo "@sdba    soft  nproc   unlimited"
 } >>/etc/security/limits.d/99-sap.conf
 main::errhandle_log_info 'SAP Configuration set Security Limits completed' 
 main::errhandle_log_info 'Adding systemd.tmpfiles exclusion file for SAP' 
 # systemd.tmpfiles exclude file for SAP
 # SAP software stores some important files in /tmp which should not be deleted automatically
 {
   echo "[SAP Exclude Files]" >/etc/tmpfiles.d/sap.conf
   echo "# systemd.tmpfiles exclude file for SAP"
	 echo "# SAP software stores some important files in /tmp which should not be deleted automatically"
	 echo "# Exclude SAP socket and lock files"
	 echo "x /tmp/.sap*"
	 echo "# Exclude HANA lock file"
   echo "x /tmp/.hdb*lock"
   echo "# Exclude TREX lock file"
   echo "x /tmp/.trex*lock"
 } >>/etc/tmpfiles.d/sap.conf
 main::errhandle_log_info 'Completed Adding systemd.tmpfiles exclusion file for SAP' 
}

main::set_kernel_parameters(){
  echo 'Setting Kernel Parameters' 
  {
    echo "vm.max_map_count = 2147483647"
    echo "kernel.pid_max = 4194304"
    echo "vm.pagecache_limit_mb = 0"
    echo "net.ipv4.tcp_slow_start_after_idle=0"
    echo "kernel.numa_balancing = 0"
    echo "net.ipv4.tcp_slow_start_after_idle=0"
    echo "net.core.somaxconn = 4096"
    echo "net.ipv4.tcp_tw_reuse = 1"
    echo "net.ipv4.tcp_tw_recycle = 1"
    echo "net.ipv4.tcp_timestamps = 1"
    echo "net.ipv4.tcp_syn_retries = 8"
    echo "net.ipv4.tcp_wmem = 4096 16384 4194304"
  } >> /etc/sysctl.conf
  echo 'Setting Kernel Parameters completed'

  sysctl -p
  
  echo "Change TimeZone to EDT/EST"
  timedatectl set-timezone America/New_York
  echo "TimeZone changed from UTC to EDT/EST"
  
  echo "Preparing tuned/saptune"

  if [[ "${LINUX_DISTRO}" = "SLES" ]]; then
    saptune solution apply HANA
    saptune daemon start
  else
    mkdir -p /etc/tuned/sap-hana/
    cp /usr/lib/tuned/sap-hana/tuned.conf /etc/tuned/sap-hana/
    systemctl start tuned
    systemctl enable tuned
    tuned-adm profile sap-hana
  fi
}

main::start_services(){
  echo "Starting UUID Service"
  systemctl start uuidd
  systemctl enable uuidd
}


main::reboot(){
reboot
}

main::create_swap() {

sed "s/ResourceDisk.Format=n/ResourceDisk.Format=y/g" /etc/waagent.conf
sed "s/ResourceDisk.EnableSwap=n/ResourceDisk.EnableSwap=y/g" /etc/waagent.conf

# service waagent restart
}

main::create_filesystem() {
  
  echo "creating sap directories" >> /tmp/parameter.txt
  mkdir /etc/systemd/login.conf.d
  mkdir /hana
  mkdir /hana/data
  mkdir /hana/log
  mkdir /hana/shared
  mkdir /hana/backup
  mkdir /usr/sap
  echo "sap directories created" >> /tmp/parameter.txt
  
  echo "Creating filesystem" >> /tmp/parameter.txt
  echo "Creating partitions and physical volumes" >> /tmp/parameter.txt
  pvcreate -ff -y /dev/disk/azure/scsi1/lun0   
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun1
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun2
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun3
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun4
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun5

  echo "logicalvols start" >> /tmp/parameter.txt
  #shared volume creation
  sharedvglun="/dev/disk/azure/scsi1/lun0"
  vgcreate sharedvg $sharedvglun
  lvcreate -l 100%FREE -n sharedlv sharedvg 
 
  #usr volume creation
  usrsapvglun="/dev/disk/azure/scsi1/lun1"
  vgcreate usrsapvg $usrsapvglun
  lvcreate -l 100%FREE -n usrsaplv usrsapvg

  #backup volume creation
  backupvg1lun="/dev/disk/azure/scsi1/lun2"
  vgcreate backupvg $backupvg1lun
  lvcreate -l 100%FREE -n backuplv backupvg 

  #data volume creation
  datavg1lun="/dev/disk/azure/scsi1/lun3"
  datavg2lun="/dev/disk/azure/scsi1/lun4"
#  datavg3lun="/dev/disk/azure/scsi1/lun5"
  vgcreate datavg $datavg1lun $datavg2lun
  PHYSVOLUMES=2
  STRIPESIZE=64
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n datalv datavg

  #log volume creation
  logvg1lun="/dev/disk/azure/scsi1/lun5"
  #logvg2lun="/dev/disk/azure/scsi1/lun7"
  vgcreate logvg $logvg1lun
  PHYSVOLUMES=1
  STRIPESIZE=32
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n loglv logvg
  mount -t xfs /dev/logvg/loglv /hana/log 
  echo "/dev/mapper/logvg-loglv /hana/log xfs defaults 0 0" >> /etc/fstab

  mkfs.xfs /dev/datavg/datalv
  mkfs.xfs /dev/logvg/loglv
  mkfs -t xfs /dev/sharedvg/sharedlv 
  mkfs -t xfs /dev/backupvg/backuplv 
  mkfs -t xfs /dev/usrsapvg/usrsaplv
  echo "logicalvols end" >> /tmp/parameter.txt

  echo "mounthanashared start" >> /tmp/parameter.txt
  mount -t xfs /dev/sharedvg/sharedlv /hana/shared
  mount -t xfs /dev/backupvg/backuplv /hana/backup 
  mount -t xfs /dev/usrsapvg/usrsaplv /usr/sap
  mount -t xfs /dev/datavg/datalv /hana/data
  echo "mounthanashared end" >> /tmp/parameter.txt

  echo "write to fstab start" >> /tmp/parameter.txt
  echo "/dev/mapper/datavg-datalv /hana/data xfs defaults 0 0" >> /etc/fstab
  echo "/dev/mapper/sharedvg-sharedlv /hana/shared xfs defaults 0 0" >> /etc/fstab
  echo "/dev/mapper/backupvg-backuplv /hana/backup xfs defaults 0 0" >> /etc/fstab
  echo "/dev/mapper/usrsapvg-usrsaplv /usr/sap xfs defaults 0 0" >> /etc/fstab
  echo "write to fstab end" >> /tmp/parameter.txt
  echo "filesystem creation completed" >> /tmp/parameter.txt
  
  lvextend -r -L+5G /dev/rootvg/rootlv
}

main::hana_config() {

 cd /hana/data/sapbits
 echo "hana config download start" >> /tmp/parameter.txt
 # /usr/bin/wget --quiet $Uri/SapBits/md5sums
 # /usr/bin/wget --quiet "https://raw.githubusercontent.com/phaninalap/SAP-HANA-ARM/master/hdbinst.cfg"
 echo "hana config download end" >> /tmp/parameter.txt

 date >> /tmp/testdate
 cd /hana/data/sapbits

 echo "hana prepare start" >> /tmp/parameter.txt
 cd /hana/data/sapbits

 # mkdir -p /root/.deploy

# HANASID="HF2"
# HANNUMBER="00"
# HANAPWD="HP1nv3nt"
 HANACOMP="server, client, studio, afl"

  ## create hana_install.cfg file
  {
    echo "[General]" >/hana/data/sapbits/"${HOSTNAME}"_hana_install.cfg
	echo "components=$HANACOMP"
	echo "[Server]"
	echo "sid=$HANASID"
    echo "number=$HANANUMBER"
    echo "sapadm_password=$HANAPWD"
    echo "password=$HANAPWD"
    echo "system_user_password=$HANAPWD"
  } >>/hana/data/sapbits/"${HOSTNAME}"_hana_install.cfg

 echo "hana preapre end" >> /tmp/parameter.txt

}

main::hana_media() {
#####################

mkdir /mnt/$FILESHR
chmod -R 777 /mnt/$FILESHR

if [ ! -d "/etc/smbcredentials" ]; then
mkdir /etc/smbcredentials
chmod -R 777 /etc/smbcredentials
fi
if [ ! -f "/etc/smbcredentials/$STGNAME.cred" ]; then
    bash -c 'echo "username=$STGNAME" >> /etc/smbcredentials/$STGNAME.cred'
    bash -c 'echo "password=$STGKEY" >> /etc/smbcredentials/$STGNAME.cred'
fi
chmod 777 /etc/smbcredentials/$STGNAME.cred

sudo bash -c 'echo "//$STGNAME.file.core.windows.net/$FILESHR /mnt/$FILESHR cifs nofail,vers=3.0,credentials=/etc/smbcredentials/$STGNAME.cred,dir_mode=0777,file_mode=0777,serverino" >> /etc/fstab'
sudo mount -t cifs //$STGNAME.file.core.windows.net/$FILESHR /mnt/$FILESHR -o vers=3.0,credentials=/etc/smbcredentials/$STGNAME.cred,dir_mode=0777,file_mode=0777,serverino

sleep 10

if [ ! -d "/hana/data/sapbits" ]
 then
 mkdir "/hana/data/sapbits"
 chmod -R 777 /hana/data/sapbits
fi

echo "copy and extract hana pkg"
  echo "${hanapackage}" >> /tmp/parameter.txt
  echo "hana download start" >> /tmp/parameter.txt
  cd $SAPBITSDIR
  cp /mnt/$FILESHR/linux/sap_hana/install/${hanapackage}.ZIP $SAPBITSDIR
  sleep 60
  echo "hana download start" >> /tmp/parameter.txt
  cd $SAPBITSDIR
  mkdir ${hanapackage}
  cd ${hanapackage}
  echo "hana extract start" >> /tmp/parameter.txt
  unzip $SAPBITSDIR/${hanapackage}.ZIP
  echo "hana extract end" >> /tmp/parameter.txt
  cd $SAPBITSDIR
#####################
}

main::hana_install() {

if ! $SAPBITSDIR/"$hanapackage"/DATA_UNITS/HDB_LCM_LINUX_X86_64/hdblcm --configfile=$SAPBITSDIR/"${HOSTNAME}"_hana_install.cfg -b; then
    echo "HANA Installation Failed. The server deployment is complete but SAP HANA is not deployed. Manual SAP HANA installation will be required"
  fi

}

main::hana_update() {

  echo "HANA Update media copy"
  cd $SAPBITSDIR
  cp /mnt/$FILESHR/linux/sap_hana/update/IMDB_SERVER20_056_0-80002031.SAR $SAPBITSDIR
  cp /mnt/$FILESHR/linux/sap_hana/update/IMC_STUDIO2_256_0-80000321.SAR $SAPBITSDIR
  cp /mnt/$FILESHR/linux/sap_hana/update/IMDB_AFL20_056_0-80001894.SAR $SAPBITSDIR
  cp /mnt/$FILESHR/linux/sap_hana/update/IMDB_CLIENT20_009_28-80002082.SAR $SAPBITSDIR
  echo "HANA Update media copy completed"

  if [ "$(ls $SAPBITSDIR/IMDB_SERVER*.SAR)" ]; then
    echo "An SAP HANA update was found in GCS. Performing the upgrade:"
    echo "--- Extracting HANA upgrade media"
    cd $SAPBITSDIR || echo "Unable to access /hana/shared/media. The server deployment is complete but SAP HANA is not deployed. Manual SAP HANA installation will be required."
    /usr/sap/"$HANASID"/SYS/exe/hdb/SAPCAR -xvf "*.SAR" -manifest SIGNATURE.SMF
    cd SAP_HANA_DATABASE || echo "Unable to access /hana/shared/media. The server deployment is complete but SAP HANA is not deployed. Manual SAP HANA installation will be required."
    echo "--- Upgrading Database"
    if ! ./hdblcm --configfile=$SAPBITSDIR/"${HOSTNAME}"_hana_install.cfg --action=update --ignore=check_signature_file --update_execution_mode=optimized --batch; then
        echo "SAP HANA Database revision upgrade failed to install."
    fi
  fi
}

main::set_boot_parameters
main::get_os_version
main::install_packages
main::limts_tmp_excludes
main::set_kernel_parameters
main::create_swap
main::create_filesystem
main::hana_media
main::hana_config
main::hana_install
main::hana_update
# main::reboot
