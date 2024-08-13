### STAGE 2: CONCRETIFY DRIVER IN INITRD/GRUB

## adjustments to 40_custom
cudatemplate--grub_menu_truncate:
  cmd.run:
    - name: sed -i '6,$d' /etc/grub.d/40_custom

cudatemplate--grub_menu_process:
  cmd.run:
    - name: |
        awk '
        BEGIN { inside_block = 0 }
        /^menuentry / {
            if (inside_block == 0) {
                inside_block = 1
            }
        }
        inside_block == 1 {
            if (/^submenu /) {
                exit
            }
            if ($0 ~ /^menuentry '\''Debian GNU\/Linux'\''/) {
                sub(/^menuentry '\''Debian GNU\/Linux'\''/, "menuentry '\''Debian w/Nvidia'\''")
            }

            print
        }
        ' /boot/grub/grub.cfg >> /etc/grub.d/40_custom

cudatemplate--nvidia_enable_modesetting:
  cmd.run:
    - name: |
        sed -i '14{
          /nvidia-drm.modeset=1/! s/$/ nvidia-drm.modeset=1/
        }' /etc/grub.d/40_custom
    - shell: /bin/bash

cudatemplate--nouveau_blacklist_drv:
  cmd.run:
    - name: |
        sed -i '14{
          /rd.driver.blacklist=nouveau/! s/$/ rd.driver.blacklist=nouveau/
        }' /etc/grub.d/40_custom
    - shell: /bin/bash

## end adjustments to 40_custom

cudatemplate--nouveau_modprobe_block:
  file.managed:
    - name: /etc/modprobe.d/blacklist-nouveau.conf
    - contents: |
        install nouveau /bin/false
    - mode: '0644'
    - user: root
    - group: root

cudatemplate--nvidia_enable_moduleload:
  file.managed:
    - name: /etc/modules-load.d/nvidia.conf
    - contents: |
        nvidia
        nvidia-modeset
        nvidia-drm
        nvidia-uvm
    - mode: '0744'
    - user: root
    - group: root

## dracut changes

## install nvidia driver

# test for /extra and second pass install if /extra present
cudatemplate--nvidia_drv_install_total:
  cmd.run:
    - name: >
        /home/user/nvidia/nvidia-installer
        --no-rebuild-initramfs
        --allow-installation-with-running-driver
        --no-peermem
        --no-x-check
        --install-compat32-libs
        --install-libglvnd
        --ui=none
        --systemd
        --expert
        --no-questions

cudatemplate--nvidia_append_dracut_drv:
  file.managed:
    - name: /etc/dracut.conf.d/nvidia.conf
    - contents: |
        add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "
    - mode: '0644'
    - user: root
    - group: root

cudatemplate--nvidia_kernel_object_dir:
  file.directory:
    - name: /lib/modules/{{ salt['cmd.run']('uname -r') }}/extra
    - mode: '0755'
    - makedirs: True

cudatemplate--nvidia_copy_ko_files:
  cmd.run:
    - name: cp /home/user/nvidia/kernel/*.ko /lib/modules/{{ salt['cmd.run']('uname -r') }}/extra/

cudatemplate--nvidia_update_systemd_unitlist:
  cmd.run:
    - name: systemctl daemon-reload

cudatemplate--nvidia_depmod_a:
  cmd.run:
    - name: depmod -a

cudatemplate--nvidia_dracut:
  cmd.run:
    - name: dracut --force

## end dracut changes

cudatemplate--grub_update_default:
  file.replace:
    - name: /etc/default/grub
    - pattern: '^GRUB_DEFAULT=0'
    - repl: 'GRUB_DEFAULT="Debian w/Nvidia"'
    - show_changes: True

cudatemplate--grub_regenerate_entries:
  cmd.run:
    - name: update-grub

cudatemplate--shutdown:
  cmd.run:
    - name: shutdown now

