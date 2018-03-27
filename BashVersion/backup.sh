#!/bin/bash

#####################################
#
# oVIRT_Simple_Backup
# Version: 0.3.6 for oVirt 4.2.x
# Date: 01/29/2018
#
# Simple Script to backup VMs running on oVirt to Export Storage
#
# Script on github.com
# https://github.com/zipurman/oVIRT_Simple_Backup
#
# Author: zipur (www.zipur.ca)
# IRC: irc.oftc.net #ovirt
#
# Required Packages: scsitools, curl, xmlstarlet, lsscsi, pv, dialog
#
# Tested on: Debian8
#
# Warning !!! Use script at your own risk !!!
# There is no guarantee the script will work
# for your environment. It is recommended that
# you test this script in a NON PRODUCTION
# environment with your setup to make sure
# it works as expected. 
#
# *** NOTE: You cannot take snapshots of disks that are marked as shareable or that are based on direct LUN disks.
#
#####################################


#backup.cfg is old and will be alerted if still exists
if [ -f "backup.cfg" ]; then source backup.cfg; fi

obuversion="0.3.6"
obutitle="\Zb\Z3oVirt\ZB\Zn - \Zb\Z1Simple Backup\ZB\Zn - \Zb\Z0Version ${obuversion}\ZB\Zn"
obutext=""
headless="0"
menutmpfile=".backup.menu"
menupositionfile=".backup.position.menu"
menusettings=".backup.settings.menu"
vmconfigfilephp="/var/www/html/.automated_backups_vmlist";

#required for cronjob
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR
export TERM=xterm




#start check packages
packagesokay=1
if ! [ -x "$(command -v lsscsi)" ]; then
    echo "Package: lsscsi - missing and is required for this script."
    packagesokay=0
fi
if ! [ -x "$(command -v xmlstarlet)" ]; then
    echo "Package: xmlstarlet - missing and is required for this script."
    packagesokay=0
fi
if ! [ -x "$(command -v curl)" ]; then
    echo "Package: curl - missing and is required for this script."
    packagesokay=0
fi
if ! [ -x "$(command -v pv)" ]; then
    echo "Package: pv - missing and is required for this script."
    packagesokay=0
fi
if ! [ -x "$(command -v dialog)" ]; then
    echo "Package: dialog - missing and is required for this script."
    packagesokay=0
fi
if ! [ -x "$(command -v fsarchiver)" ]; then
    echo "Package: fsarchiver - missing and is required for this script."
    packagesokay=0
fi
if ! [ -x "$(command -v chroot)" ]; then
    echo "Package: chroot - missing and is required for this script."
    packagesokay=0
fi
if [ $packagesokay -eq 0 ];then
    exit 0
fi
#end check packages



#init the setting file
if [ ! -f $menusettings ]; then
    for filedata in {1..100}; do echo -e "\n" >> $menusettings; done
    obusettings_write "!!! DO NOT EDIT THIS FILE DIRECTLY!!!" 1
fi

if [ -f "backup.cfg" ]; then
    dialog --colors --backtitle "${obutitle}" --title " ALERT! " --cr-wrap --msgbox '\n\nThis version no longer requires your backup.cfg file. \n\nPlease edit that file and make a note of the settings.\n\nThen rename the file and restart this script to enter each of the values into the settings area.'  20 40
    exit 0
fi

source src/functions.sh


obuloadsettings
obuconfirminstall

while test $# -gt 0; do
    case "$1" in
    --headless)
        headless="1"
        break
        ;;
    -h|--help)
        shift
        echo -e "\n\toVirt Simple Backup Ver: ${obuversion}\n\n\t$0 [options]\n\n\toptions:\n"
        echo -e "\t\t-h, --help\t\tshow brief help\n\n\t\t--headless=HEADLESS\tuse for bypassing menu ie:cron\n"
        shift
        exit
        ;;
    *)
        break
        ;;
    esac
done

if [ $headless -eq 0 ]
then
    #load menu
    source src/menu/base.sh
elif [[ $vmlisttobackup == '' ]]
then
    echo -e "Subject: oVirt Backup Skipped\nFrom: ${email}\nTo: ${email}\n\noVirt Backup Skipped. No VMs tagged for backup." | sendmail -t
else
    #skip menu
    if [ -n "$email" ] && [ "$email" != "" ]
    then
        echo -e "Subject: oVirt Backup Start\nFrom: ${email}\nTo: ${email}\n\noVirt Backup Started. A log will be sent once backup is completed" | sendmail -t
    fi

    ### CURL - GET - VM LIST
    obuapicall "GET" "vms"
    vmslist="${obuapicallresult}"
    #Count total VMs in oVirt
    countedvms=`echo $vmslist | xmlstarlet sel -t -v "count(/vms/vm)"`
    obutext="${obutext}There are currently $countedvms VMs in your environment\n\n"
    obudialog "${obutitle}" "${obutext}" ""
    #Get List of all VMs
    vmlist=`echo $vmslist | xmlstarlet sel -T -t -m /vms/vm -s D:N:- "@id" -v "concat(@id,'|',name,';')"`
    #Get number of backups targeted by script
    numofbackups=`echo $vmlisttobackup | sed 's/\[/\n&\n/g' | grep -cx '\['`
    obutext="${obutext}You are targeting a total of $numofbackups VMs for backup\n\n"
    obudialog "${obutitle}" "${obutext}" ""
    obulog "${obutext}" 1

    obucheckoktostart

    sleep 5
    obutitle="${obutitle} - Backing up \Zb\Z1${numofbackups}\ZB\Zn VM(s) of total \Zb\Z1${countedvms}\ZB\Zn VM(s)"

    #loop VM list
    for i in ${vmlist//\;/ }
    do
        vmdataarray=(${i//|/ })
        vmname="${vmdataarray[1]}"
        vmuuid="${vmdataarray[0]}"
        obulog "${vmname}"

        if [ $vmname = "HostedEngine" ]
        then
            #SKIP HOSTED ENGINE FROM BACKUP
            sleep 1
            obutext=" - VM: ($vmuuid)\n"
            obutext="${obutext} - VM Name: \Zb\Z4HostedEngine VM\ZB\Zn - Cannot Backup\n\n(SKIPPING)\n\n"
            obudialog "${obutitle}" "${obutext}" "HostedEnginge"
            obulog "${obutext}"
            sleep 2
        else
            sleep 1
            obutext=" - VM: ($vmuuid)"
            obudialog "${obutitle}" "${obutext}" "${vmname}"
            obulog "${obutext}"
            if [[ $vmlisttobackup == *"[$vmname]"* ]]; then
                #BACKUP THIS VM
                obubackup $vmname $vmuuid 0
                obutext="VM Name: \Zb\Z4${vmname}\ZB\Zn - (** BACKING UP **)\n\n"
                obulog "${obutext}"
            else
                #SKIP IF NOT IN LIST
                obutext=" - VM Name: \Zb\Z4${vmname}\ZB\Zn - Skipping - (Not in list)\n\n"
                obudialog "${obutitle}" "${obutext}" "${vmname}"
                obulog "${obutext}"
                sleep 2
            fi
        fi
    done

    #retention period enforce
    obucleanupoldbackups
    obulog "\n\n* Cleaning up based on retention period of ${backupretention} backup(s) per VM *\n\n"

    #only required if in 4.2 and disks not releasing devices
    if [ $incrementdiskdevices -eq 1 ]
    then
        obutext="*** Shutting Down Backup Appliance in 10 seconds *** ctrl-c to cancel\n\n"
        obudialog "${obutitle}" "${obutext}"
        obulog "${obutext}"
        for number in {9..0}
        do
            obutext="*** Shutting Down Backup Appliance in 10 seconds *** ctrl-c to cancel\n\n"
            percentage=$((number * 10))
             echo $percentage | dialog --colors --backtitle "${obutitle}" --title "${vmname}" --gauge "${obutext}" 22 80 0
            sleep 1
        done
        clear
        echo "Shutting Down"
        #reboot must come from API call or drives are not released
        obuapicall "POST" "vms/${thisbackupvmuuid}/shutdown/" "<action/>"
    else
        clear
        echo "Backups Completed"
    fi
    BUDATE=`date "+%Y-%m-%d %H:%M:%S"`
    obulog "\n\nBackup Completed At: ${BUDATE}\n\n"
    if [ -n "$email" ] && [ "$email" != "" ]
    then

        echo -e "Subject: oVirt Backup Complete\nFrom: ${email}\nTo: ${email}\n\n" > .emailalert.backup

        cat $backuplog >> .emailalert.backup

        cat .emailalert.backup | /usr/sbin/sendmail -t

    fi
fi


exit 0