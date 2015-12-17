#########################################################################
# File Name: check_update.sh
# Author: tolimit
# mail: 348958453@qq.com
# Created Time: Mon 14 Dec 2015 03:50:27 PM CST
#########################################################################
#!/bin/bash

if [ -e /etc/redos-release ]; then
	CURRENT_REDOS_VER_SYS=`cat /etc/redos-release`
else
	CURRENT_REDOS_VER_SYS=""
fi

SHOW_ALL="0"
CHECK_ISO="0"
CHECK_PATCH="0"
PATCH_DIR=""
PATCH_NAME=""
PATCH_FILE=""
PATCH_CONFIG=""
REDOS_VER_PATCH=""

REDOS_VER=""
DELRPMS=""
ADDRPMS=""
UPDATERPMS=""
MUSTINST=""

l_del=0
l_add=0
l_update=0
length=0

RESULT="0"

check_install()
{
	if [ "$1" == "" ];then
		echo "0"
	else
		rpm -q $1 >> /dev/null
		echo "$?"
	fi
}

# Return:
#	0 - $1 < $2
#	1 - $1 = $2
#	2 - $1 > $2
is_newer()
{
	if [ "$1" == "" ] && [ "$2" == "" ];then
		echo "1"
	fi
	if [ "$1" == "" ];then
		echo "0"
	fi
	if [ "$2" == "" ];then
		echo "2"
	fi

	ver1="$1"
	ver2="$2"
	ver1_big=`echo "$ver1" | cut -d '.' -f 1`
	ver1_mid=`echo "$ver1" | cut -d '.' -f 2`
	ver1_little=`echo "$ver1" | cut -d '.' -f 3`
	ver2_big=`echo "$ver2" | cut -d '.' -f 1`
	ver2_mid=`echo "$ver2" | cut -d '.' -f 2`
	ver2_little=`echo "$ver2" | cut -d '.' -f 3`

	# 0: $1 < $2
	# 2: $1 > $2
	# 1: $1 = $2
	# -gt : >
	# -lt : <
	res_big=`expr $ver1_big - $ver2_big`
	if [ $res_big -gt 0 ];then
		echo "2"
	elif [ $res_big -lt 0 ];then
		echo "0"
	else
		res_mid=`expr $ver1_mid - $ver2_mid`
		if [ $res_mid -gt 0 ];then
			echo "2"
		elif [ $res_mid -lt 0 ];then
			echo "0"
		else
			if [ "$ver1_little" != "" ] && [ "$ver2_little" != "" ];then
				res_little=`expr $ver1_little - $ver2_little`
				if [ $res_little -gt 0 ];then
					echo "2"
				elif [ $res_little -lt 0 ];then
					echo "0"
				else
					echo "1"
				fi
			fi
			if [ "$ver1_little" == "" ] && [ "$ver2_little" == "" ];then
				echo "1"
			fi
			if [ "$ver1_little" == "" ];then
				echo "0"
			fi
			if [ "$ver2_little" == "" ];then
				echo "2"
			fi
		fi
	fi
}

check_in_mustinst()
{
	if [ "$1" == "" ];then
		echo "0"
	else
		echo "$MUSTINST" | grep "\\$1" >> /dev/null
		if [ $? -eq 0 ];then
			echo "1"
		else
			echo "0"
		fi
	fi

}

check_in_deny()
{
	if [ "$1" == "" ];then
		echo "1"
	else
		echo "$DENYRPMS" | grep "\\$1" >> /dev/null
		if [ $? -eq 0 ];then
			echo "1"
		else
			echo "0"
		fi
	fi
}

get_rpm_ver()
{
	if [ "$1" == "" ];then
		echo ""
	else
		rpm_ver=`rpm -q --qf "%{VERSION}" $1`
		if [ $? -eq 0 ];then
			echo "$rpm_ver"
		else
			echo ""
		fi
	fi
}

check_ver ()
{
	echo "Version check..."
	if [ "$CURRENT_REDOS_VER_SYS" == "" ] || [ "$REDOS_VER" == "" ] || [ "$CURRENT_REDOS_VER_SYS" != "$REDOS_VER" ];then
		printf "\033[31mVersion is not matching\033[0m\n"
		printf "\033[31mSystem\`s version is $CURRENT_REDOS_VER_SYS in /etc/redos-release\033[0m\n"
		printf "\033[31mBut patch update system\`s version to $REDOS_VER\033[0m\n"
		RESULT="1"
	else
		printf "\033[32mVersion is correct.\033[0m\n"
	fi

	echo ""
}

check_add ()
{
	echo "ADD segment check..."
	pkg=""
	if [ "$l_add" == "0" ];then
		echo "Patch don\`t have this segment(ADD)"
		return
	fi
	echo "In this segment, if system don\`t install this package, Patch will install it,"
	echo "but if system installed this package with any version, Patch will ignore it."
	qemu=`check_install "qemu-img"`
	i=1
	for pkg in $ADDRPMS; 
	do
		in_deny=`check_in_deny "$pkg"`
		if [ "$in_deny" == "1" ];then
			continue
		fi
		in_must=`check_in_mustinst "$pkg"`
		pkg_name=`echo $pkg | awk -F'-[0-9.]*-' '{print $1}'`
		pkg_ver=`echo $pkg | grep -o "\-[0-9\.]*\-" | grep -o "[0-9\.]*"`
		res=`check_install "$pkg_name"`
		if [ "$res" == "0" ];then
			pkg_in_sys=`rpm -q "$pkg_name"`
			ver_in_sys=`get_rpm_ver "$pkg_name"`
			if [ "$in_must" == "1" ] && [[ "$pkg_ver" != "$ver_in_sys" ]];then
				printf "\033[31m%d: %s was not installed, System have %s but this package in mustinstall segment in Patch. \033[0m\n" "$i" "$pkg" "$pkg"
				RESULT="1"
			else
				compare_ver=`is_newer "$pkg_ver" "$ver_in_sys"`
				if [ "$compare_ver" == "0" ];then
					printf "\033[34m%d: %s was installed.(%s in Patch)\033[0m\n" "$i" "$pkg_in_sys" "$pkg"	
				else
					if [ "$SHOW_ALL" == "1" ];then
						printf "\033[32m%d: %s was installed.(%s in Patch)\033[0m\n" "$i" "$pkg_in_sys" "$pkg"	
					else
						continue
					fi
				fi
			fi
		else
			spice_policy_gperftools=`echo "$pkg" | grep -E "spice|policy|gperftools-libs"`
			if [ "$qemu" == "0" ] && [ "$spice_policy_gperftools" != "" ];then
				printf "\033[31m%d: %s was not installed, Patch install %s fail. \033[0m\n" "$i" "$pkg_name" "$pkg"
				RESULT="1"
			else
				continue
			fi
		fi
		i=$(($i+1))
	done
	echo ""
}

check_update ()
{
	echo "UPDATE segment check..."
	if [ "$l_update" == "0" ];then
		echo "Patch don\`t have this segment(UPDATE)"
		return
	fi

	echo "In this segment, if system don\`t install this package, Patch will ignore it,"
	echo "if system has package with old version, Patch will update it,"
	echo "if package\`version is newer than package in patch, Patch will prompt whether install it."

	i=1
	for pkg in $UPDATERPMS;
	do
		in_deny=`check_in_deny "$pkg"`
		if [ "$in_deny" == "1" ];then
			continue
		fi

		in_must=`check_in_mustinst "$pkg"`
		pkg_name=`echo $pkg | awk -F'-[0-9.]*-' '{print $1}'`
		pkg_ver=`echo $pkg | grep -o "\-[0-9\.]*\-" | grep -o "[0-9\.]*"`

		res=`check_install "$pkg_name"`
		if [ "$res" == "0" ];then
			pkg_in_sys=`rpm -q "$pkg_name"`
			ver_in_sys=`get_rpm_ver "$pkg_name"`
			compare_ver=`is_newer "$pkg_ver" "$ver_in_sys"`
			if [ "$compare_ver" == "2" ];then
				printf "\033[31m%d: %s in system is older than Patch(%s).\033[0m\n" "$i" "$pkg_in_sys" "$pkg"
				RESULT="1"
			elif [ "$compare_ver" == "0" ];then
				if [ "$in_must" == "1" ];then
					printf "\033[31m%d: %s in system is newer than Patch(%s). But package is in mustinstall segment\033[0m\n" "$i" "$pkg_in_sys" "$pkg"	
					RESULT="1"
				else
					printf "\033[34m%d: %s in system is newer than Patch(%s).\033[0m\n" "$i" "$pkg_in_sys" "$pkg"	
				fi
			else
				if [ "$SHOW_ALL" == "1" ];then
					printf "\033[32m%d: %s was installed.\033[0m\n" "$i" "$pkg_in_sys"	
				else
					continue
				fi
			fi
		else
			continue
		fi
		i=$(($i+1))
	done
	echo ""
}

check_in_iso()
{
	echo "Check rpms in system\`s ISO"

	i=1
	for pkg in $ISORPMS;
	do
		pkg_name=`echo $pkg | awk -F'-[0-9.]*-' '{print $1}'`
		pkg_ver=`echo "$pkg" | grep -o "\-[0-9\.]*\-" | grep -o "[0-9\.]*"`
		res=`check_install "$pkg_name"`
		if [ "$res" == "0" ];then
			pkg_in_sys=`rpm -q "$pkg_name"`
			ver_in_sys=`get_rpm_ver "$pkg_name"`
			compare_ver=`is_newer "$pkg_ver" "$ver_in_sys"`
			if [ "$compare_ver" == "2" ];then
				printf "\033[31m%d: %s in system is older than ISO(%s).\033[0m\n" "$i" "$pkg_in_sys" "$pkg"
				RESULT="1"
			elif [ "$compare_ver" == "0" ];then
				printf "\033[34m%d: %s in system is newer than ISO(%s).\033[0m\n" "$i" "$pkg_in_sys" "$pkg"	
			else
				if [ "$SHOW_ALL" == "1" ];then
					printf "\033[32m%d: %s was installed.\033[0m\n" "$i" "$pkg_in_sys"	
				else
					continue
				fi
			fi
		else
			continue
		fi
		i=$(($i+1))
	done
}

get_config_data()
{
	REDOS_VER_PATCH=`awk -F "=" '$1=="redos_patch_ver" {print $2}' $PATCH_CONFIG`

	REDOS_VER=`awk -F "=" '$1=="redos_release"{print $2}' $PATCH_CONFIG`
	DELRPMS=`awk 'BEGIN{RS="ADD:|UPDATE:|DEL:|MUSTINST:|DENY:|OPTIONS:|PREPATCH:|POSTPATCH:"}NR==4' $PATCH_CONFIG | sed '/^ *$/d;/^#/d'`
	ADDRPMS=`awk 'BEGIN{RS="ADD:|UPDATE:|DEL:|MUSTINST:|DENY:|OPTIONS:|PREPATCH:|POSTPATCH:"}NR==2' $PATCH_CONFIG | sed '/^ *$/d;/^#/d'`
	UPDATERPMS=`awk 'BEGIN{RS="ADD:|UPDATE:|DEL:|MUSTINST:|DENY:|OPTIONS:|PREPATCH:|POSTPATCH:"}NR==3' $PATCH_CONFIG | sed '/^ *$/d;/^#/d'`
	MUSTINST=`awk 'BEGIN{RS="ADD:|UPDATE:|DEL:|MUSTINST:|DENY:|OPTIONS:|PREPATCH:|POSTPATCH:"}NR==5' $PATCH_CONFIG | sed '/^ *$/d;/^#/d'`
	OPTIONS=`awk 'BEGIN{RS="ADD:|UPDATE:|DEL:|MUSTINST:|DENY:|OPTIONS:|PREPATCH:|POSTPATCH:"}NR==7' $PATCH_CONFIG | sed '/^ *$/d;/^#/d'`
	PREPATCH=`awk 'BEGIN{RS="ADD:|UPDATE:|DEL:|MUSTINST:|DENY:|OPTIONS:|PREPATCH:|POSTPATCH:"}NR==8' $PATCH_CONFIG | sed '/^ *$/d;/^#/d'`
	POSTPATCH=`awk 'BEGIN{RS="ADD:|UPDATE:|DEL:|MUSTINST:|DENY:|OPTIONS:|PREPATCH:|POSTPATCH:"}NR==9' $PATCH_CONFIG | sed '/^ *$/d;/^#/d'`
	DENYRPMS=`awk 'BEGIN{RS="ADD:|UPDATE:|DEL:|MUSTINST:|DENY:|OPTIONS:|PREPATCH:|POSTPATCH:"}NR==6' $PATCH_CONFIG | sed '/^ *$/d;/^#/d'`

	l_del=`echo $DELRPMS | awk '{print NF}'`
	l_add=`echo $ADDRPMS | awk '{print NF}'`
	l_update=`echo $UPDATERPMS | awk '{print NF}'`
	length=`expr $l_del + $l_add + $l_update` 
}

main ()
{
	if [ "$CHECK_ISO" == "1" ];then
		check_in_iso
	fi

	if [ "$CHECK_PATCH" == "1" ];then
		PATCH_FILE="$PATCH_DIR""$PATCH_NAME"
		if [ ! -f "$PATCH_FILE" ];then
			echo "Patch is not exist."
			return
		fi
		chmod +x "$PATCH_FILE"
		echo "Start checking..."
		$PATCH_FILE -debug
		echo ""
		config_dir_name=`echo "$PATCH_NAME" | awk -F'.patch' '{print $1}'`	
		PATCH_CONFIG="$PATCH_DIR"".tmp/""$config_dir_name""/redospatch.cfg"
		if [ ! -f "$PATCH_CONFIG" ];then
			echo "Patch\`s config is not exist.($PATCH_CONFIG)"
			return
		fi

		get_config_data

		check_ver
		check_add
		check_update
	fi
	printf "Result: "
	if [ "$RESULT" == "0" ];then
		printf "\033[32m %-20s \033[0m\n" "Success"
	else
		printf "\033[31m %-20s \033[0m\n" "Failed"
	fi
	rm -rf "$PATCH_DIR"".tmp"
}

usage()
{
	echo -e "Usage:check_update.sh [Options]"
	echo -e ""
	echo -e "Options:"
	printf "\t%-40s%-20s\n" "-h" "Show this help message and exit"
	printf "\t%-40s%-20s\n" "-a" "Show all info in checking."
	printf "\t%-40s%-20s\n" "-i <iso/Packages>" "Check local system\`s rpms and ISO\`s rpms"
	printf "\t%-40s%-20s\n" "-p <patch_file>" "Check local system\`s rpms and patch\`s rpms."
	exit 0
}
# Start
while getopts "ai:hp:" arg 
do
	case $arg in
		a)
			SHOW_ALL="1"
			;;
		h)
			usage
			;;
		i)
			if [ ! -d "$OPTARG" ]; then
				echo -e "$OPTARG is not exist."
				exit 1
			fi
			CHECK_ISO="1"
			ISO_PACK_DIR="$OPTARG"
			if [ "${ISO_PACK_DIR: -1}" != "/" ];then
				ISO_PACK_DIR="$ISO_PACK_DIR""/"
			fi
			ISORPMS=`ls "$ISO_PACK_DIR"`
			SYSRPMS=`rpm -qa`
			;;
		p)
			if [ ! -f "$OPTARG" ]; then
				echo -e "$OPTARG is not exist."
				exit 1
			fi
			CHECK_PATCH="1"
			PATCH_DIR=$(dirname "$OPTARG")"/"
			PATCH_NAME=$(basename "$OPTARG")
			;;
		?)
			echo "unkonw argument"
			usage
			;;
	esac
done
main

