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
				if [[ "$pkg_ver" < "$ver_in_sys" ]];then
					printf "\033[34m%d: %s was installed.(%s in Patch)\033[0m\n" "$i" "$pkg_in_sys" "$pkg"	
				else
					printf "\033[32m%d: %s was installed.(%s in Patch)\033[0m\n" "$i" "$pkg_in_sys" "$pkg"	
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
			if [[ "$pkg_ver" > "$ver_in_sys" ]];then
				printf "\033[31m%d: %s in system is older than Patch(%s).\033[0m\n" "$i" "$pkg_in_sys" "$pkg"
				RESULT="1"
			elif [[ "$pkg_ver" < "$ver_in_sys" ]];then
				if [[ "$in_must" == "1" ]];then
					printf "\033[31m%d: %s in system is newer than Patch(%s). But package is in mustinstall segment\033[0m\n" "$i" "$pkg_in_sys" "$pkg"	
					RESULT="1"
				else
					printf "\033[34m%d: %s in system is newer than Patch(%s).\033[0m\n" "$i" "$pkg_in_sys" "$pkg"	
				fi
			else
				printf "\033[32m%d: %s was installed.\033[0m\n" "$i" "$pkg_in_sys"	
			fi
		else
			continue
		fi
		i=$(($i+1))
	done
	echo ""
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

	if [ "$1" == "" ];then
		echo "This ckeck script need patch\`s path."
		echo "Example: ./check_update.sh xx/xxxx.patch"
		return
	fi

	PATCH_DIR=$(dirname "$1")"/"
	PATCH_NAME=$(basename "$1")
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
	printf "Result: "
	if [ "$RESULT" == "0" ];then
		printf "\033[32m %-20s \033[0m\n" "Success"
	else
		printf "\033[31m %-20s \033[0m\n" "Failed"
	fi
	rm -rf "$PATCH_DIR"".tmp"
}


# Start
main $@

