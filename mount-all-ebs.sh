#!/bin/bash

###########################################################################
# script to attach unmounted ebs volumes (including swap) to ec2 instances
###########################################################################

###########################################################################
# dependencies
###########################################################################

# aws cli
# authentication
# authorization to run ec2 describe-instances and describe-volumes

# ebs volumes must be tagged with erp:mount_point
# eg. { "erp:mount_point": "/my-directory" }

# jq
yum install jq -y

AWS_REGION=us-east-1
FS=xfs

###########################################################################
# main
###########################################################################

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# volumes attached to this instance
for VOLUMEID in $(aws ec2 describe-instances --region ${AWS_REGION} --instance-ids ${INSTANCE_ID} --query 'Reservations[0].Instances[0].BlockDeviceMappings[].[Ebs.VolumeId]' --output text) ; do 

    echo
    echo VOLUMEID=${VOLUMEID};

    VOLUMENAME=$(aws ec2 describe-volumes --region ${AWS_REGION} --volume-ids ${VOLUMEID} --query 'Volumes[0].Attachments[].Device' --output text)
    MOUNTPOINT=$(aws ec2 describe-volumes --region ${AWS_REGION} --volume-ids ${VOLUMEID} --query 'Volumes[0].Tags[?Key==`erp:mount_point`].Value' --output text)

    echo VOLUMENAME=${VOLUMENAME}
    echo MOUNTPOINT=${MOUNTPOINT}

    # devices that have not been mounted (no UUID) and not the root volume (nvme0n1)
    for BLOCKDEVICE in $(lsblk -o +UUID -J | jq '.blockdevices[] | select(.uuid == null) | select(.name != "nvme0n1") | .name') ; do

        BLOCKDEVICE=$(echo ${BLOCKDEVICE} | tr -d '"')
        VOLUMEDEVICE=$(readlink ${VOLUMENAME})

        echo BLOCKDEVICE=${BLOCKDEVICE}
        echo VOLUMEDEVICE=${VOLUMEDEVICE}

        # if the attached volume is a device that needs to be mounted
        if [ "${VOLUMEDEVICE}" == "${BLOCKDEVICE}" ]; then

            if [ "${MOUNTPOINT}" == "swap" ]; then

                echo "enable swap"
                mkswap ${VOLUMENAME}
                swapon ${VOLUMENAME}
                UUID=$(blkid | grep ${BLOCKDEVICE} | awk '{print $2}' | tr -d '"')
                echo "${UUID} swap swap defaults 0 0" >> /etc/fstab
                break;

            else

                echo "prepare volume mount"
                mkfs -t ${FS} ${VOLUMENAME}
                mkdir ${MOUNTPOINT}
                UUID=$(blkid | grep ${BLOCKDEVICE} | awk '{print $2}' | tr -d '"')
                echo "${UUID} ${MOUNTPOINT} ${FS} defaults,nofail 0 2" >> /etc/fstab
                break;
            fi;
        fi

    done
done

echo
echo mount all
mount -a

exit $?

