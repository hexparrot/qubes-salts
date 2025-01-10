#!/bin/bash

id=$(xprop -root _NET_ACTIVE_WINDOW | cut -d " " -f5 | cut -d"," -f1)
vm=$(xprop -id $id | grep '_QUBES_VMNAME(STRING)')
vm=${vm#*\"}
vm=${vm%\"*}

xfce4-terminal --hold -e "jot -q $vm head"
