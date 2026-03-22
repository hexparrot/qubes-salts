{# nvidia-domu-finalize.sls - Stage 2: Concretify driver in initrd/grub
   Run: qubesctl --skip-dom0 --targets=newcuda state.sls nvidia-domu-finalize saltenv=user
   DO NOT add to top.sls or run via highstate #}

{%- set vm = grains['id'] %}
{%- set kernel_release = salt['cmd.run']('uname -r') %}

{%- if vm == 'dom0' %}

nvidia-stage2-dom0-guard:
  test.fail_without_changes:
    - name: "nvidia-domu-finalize must NOT run on dom0."

{%- else %}

## --- Adjustments to /etc/grub.d/40_custom ---

{{ vm }}--grub_menu_truncate:
  cmd.run:
    - name: sed -i '6,$d' /etc/grub.d/40_custom

{{ vm }}--grub_menu_process:
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
                sub(/^menuentry '\''Debian GNU\/Linux'\''/, "menuentry '\''Debian w\/Nvidia'\''")
            }
            print
        }
        ' /boot/grub/grub.cfg >> /etc/grub.d/40_custom
    - require:
      - cmd: {{ vm }}--grub_menu_truncate

{{ vm }}--nvidia_enable_modesetting:
  cmd.run:
    - name: |
        sed -i '14{
          /nvidia-drm.modeset=1/! s/$/ nvidia-drm.modeset=1/
        }' /etc/grub.d/40_custom
    - shell: /bin/bash
    - require:
      - cmd: {{ vm }}--grub_menu_process

{{ vm }}--nouveau_blacklist_drv:
  cmd.run:
    - name: |
        sed -i '14{
          /rd.driver.blacklist=nouveau/! s/$/ rd.driver.blacklist=nouveau/
        }' /etc/grub.d/40_custom
    - shell: /bin/bash
    - require:
      - cmd: {{ vm }}--nvidia_enable_modesetting

## --- End adjustments to 40_custom ---

{{ vm }}--nouveau_modprobe_block:
  file.managed:
    - name: /etc/modprobe.d/blacklist-nouveau.conf
    - contents: |
        install nouveau /bin/false
    - mode: '0644'
    - user: root
    - group: root
    - require:
      - cmd: {{ vm }}--nouveau_blacklist_drv

{{ vm }}--nvidia_enable_moduleload:
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
    - require:
      - file: {{ vm }}--nouveau_modprobe_block

{{ vm }}--nvidia_drv_install_total:
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
    - require:
      - file: {{ vm }}--nvidia_enable_moduleload

{{ vm }}--nvidia_append_dracut_drv:
  file.managed:
    - name: /etc/dracut.conf.d/nvidia.conf
    - contents: |
        add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "
    - mode: '0644'
    - user: root
    - group: root
    - require:
      - cmd: {{ vm }}--nvidia_drv_install_total

{{ vm }}--nvidia_kernel_object_dir:
  file.directory:
    - name: /lib/modules/{{ kernel_release }}/extra
    - mode: '0755'
    - makedirs: True
    - require:
      - file: {{ vm }}--nvidia_append_dracut_drv

{{ vm }}--nvidia_copy_ko_files:
  cmd.run:
    - name: cp /home/user/nvidia/kernel-open/*.ko /lib/modules/{{ kernel_release }}/extra/
    - require:
      - file: {{ vm }}--nvidia_kernel_object_dir

{{ vm }}--nvidia_update_systemd_unitlist:
  cmd.run:
    - name: systemctl daemon-reload
    - require:
      - cmd: {{ vm }}--nvidia_copy_ko_files

{{ vm }}--nvidia_depmod_a:
  cmd.run:
    - name: depmod -a
    - require:
      - cmd: {{ vm }}--nvidia_update_systemd_unitlist

{{ vm }}--nvidia_dracut:
  cmd.run:
    - name: dracut --force
    - require:
      - cmd: {{ vm }}--nvidia_depmod_a

{{ vm }}--grub_update_default:
  file.replace:
    - name: /etc/default/grub
    - pattern: '^GRUB_DEFAULT=0'
    - repl: 'GRUB_DEFAULT="Debian w/Nvidia"'
    - show_changes: True
    - require:
      - cmd: {{ vm }}--nvidia_dracut

{{ vm }}--grub_regenerate_entries:
  cmd.run:
    - name: update-grub
    - require:
      - file: {{ vm }}--grub_update_default

{{ vm }}--shutdown:
  cmd.run:
    - name: shutdown now
    - require:
      - cmd: {{ vm }}--grub_regenerate_entries

{%- endif %}

