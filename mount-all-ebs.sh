#!/bin/bash

###########################################################################
# script to attach unmounted ebs volumes to an ec2 instance
###########################################################################
#
#   - intended to be executed from the ec2 instance either via userdata or
#     a similar mechanism such as ansible or cloud-init
#   - needs to be executed by root
#   - this script will mount a swap volume
#   - gets instance id from metadata URL
#   - gets volume data from aws cli ec2 commands and the os
#   - linux only - tested on redhat
#   - mounts UUID (to persist across restarts)
#   - updates fstab
#   - ymmv
#
###########################################################################
# ANSIBLE TASK EXAMPLE
###########################################################################
#- name: Run EBS mounting script
#  script: /root/bin/mount_ebs.sh
#  args:
#    creates: /etc/.ansible_server_init_ebs_mounts
#
###########################################################################
# dependencies
###########################################################################
#
# aws cli
# authentication
# authorization to run ec2 describe-instances and describe-volumes
#
# ebs volumes must be tagged with "mount_point"
# eg. { "mount_point": "/my-directory" }

###########################################################################

DEBUG=false
AWS_REGION=us-east-1
FS=xfs

###########################################################################
# main
###########################################################################

if [ "${DEBUG}" = true ]; then
    echo
    echo "DEBUG MODE - DEBUG MODE - DEBUG MODE - DEBUG MODE - DEBUG MODE - DEBUG MODE"
fi

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# volumes attached to this instance
for VOLUMEID in $(aws ec2 describe-instances --region ${AWS_REGION} --instance-ids ${INSTANCE_ID} --query 'Reservations[0].Instances[0].BlockDeviceMappings[].[Ebs.VolumeId]' --output text) ; do

    MOUNTPOINT=$(aws ec2 describe-volumes --region ${AWS_REGION} --volume-ids ${VOLUMEID} --query 'Volumes[0].Tags[?Key==`mount_point`].Value' --output text)
    TRIMVOLUMEID=$(echo ${VOLUMEID} | tr -d '-')

    echo
    echo VOLUMEID=${VOLUMEID};
    echo MOUNTPOINT=${MOUNTPOINT}

    # all block devices attached to this instance
    for BLOCKDEVICE in $(lsblk -o name -d -n) ; do

        FULLBLOCKDEVICE="/dev/${BLOCKDEVICE}"
        DEVICESERIAL=$(lsblk -o SERIAL -d -n ${FULLBLOCKDEVICE})

        # skip mounted root volume
        if [ "${FULLBLOCKDEVICE}" != "/dev/nvme0n1" ]; then

        # skip mounted swap volume
        SWAP=$(swapon --noheadings | awk '{print $1}')
        if [ "${FULLBLOCKDEVICE}" != "${SWAP}" ]; then

            # check this volume 
            if [ "${DEVICESERIAL}" == "${TRIMVOLUMEID}" ]; then

                UUID=$(blkid ${FULLBLOCKDEVICE} | awk '{print $2}' | tr -d '"')

                echo FULLBLOCKDEVICE=${FULLBLOCKDEVICE}
                echo ${UUID}

                 # mount devices that have not been mounted (no UUID)
                if [ "${UUID}" == "" ]; then
    
                    echo "FOUND VOLUME TO MOUNT: " ${MOUNTPOINT}

                        if [ "${MOUNTPOINT}" == "swap" ]; then
                    
                            if [ "${DEBUG}" = true ]; then
                                echo "DEBUG MODE - ENABLE SWAP - DEBUG MODE"
                                echo "mkswap ${FULLBLOCKDEVICE}"
                                echo "swapon ${FULLBLOCKDEVICE}"
                                NEWUUID=$(blkid ${FULLBLOCKDEVICE} | awk '{print $2}' | tr -d '"')
                                echo "${NEWUUID} swap swap defaults 0 0"
                            else
                                echo "ENABLE SWAP"
                                mkswap ${FULLBLOCKDEVICE}
                                swapon ${FULLBLOCKDEVICE}
                                NEWUUID=$(blkid ${FULLBLOCKDEVICE} | awk '{print $2}' | tr -d '"')
                                echo "${NEWUUID} swap swap defaults 0 0" >> /etc/fstab
                            fi
                            break;
                        else
                            if [ "${DEBUG}" = true ]; then
                                echo "DEBUG MODE - MOUNT VOLUME - DEBUG MODE"
                                echo "mkfs -t ${FS} ${FULLBLOCKDEVICE}"
                                echo "mkdir ${MOUNTPOINT}"
                                NEWUUID=$(blkid ${FULLBLOCKDEVICE} | awk '{print $2}' | tr -d '"')
                                echo "${NEWUUID} ${MOUNTPOINT} ${FS} defaults,nofail 0 2"
                            else
                                echo "MOUNT VOLUME"
                                mkfs -t ${FS} ${FULLBLOCKDEVICE}
                                mkdir ${MOUNTPOINT}
                                NEWUUID=$(blkid ${FULLBLOCKDEVICE} | awk '{print $2}' | tr -d '"')
                                echo "${NEWUUID} ${MOUNTPOINT} ${FS} defaults,nofail 0 2" >> /etc/fstab
                            fi
                            break;
                        fi;

                    fi
                fi
            fi
        fi
    done
done

if [ "${DEBUG}" != true ]; then
    echo
    echo mount all
    mount -a
    rc=$?
    touch /etc/.ansible_server_init_ebs_mounts
fi 

exit ${rc}
