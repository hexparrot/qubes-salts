### STAGE 1: CREATE VM, INSTALL DEPENDENCIES, DOWNLOAD SOURCE

cudatemplate--create-vm:
  qvm.vm:
    - name: cudatemplate
    - present:
      - class: StandaloneVM
      - label: orange
      - template: debian-12
    - prefs:
      - include-in-backups: False
      - kernel: ''
      - kernelopts: ''
      - memory: 2096
      - maxmem: 4092
      - vcpus: 4
      - virt-mode: hvm
    - features:
      - enable:
        - no-default-kernelopts

cudatemplate--copy_nvidia_drv:
  cmd.run:
    - name: qvm-copy-to-vm cudatemplate {{ salt['pillar.get']('nvidia_dom0_path') }}
    - unless: qvm-run cudatemplate 'test -f /home/user/QubesIncoming/dom0/nvidia.run'

cudatemplate--apt-update:
  cmd.run:
    - name: qvm-run -u root cudatemplate "apt update"

cudatemplate--apt-install:
  cmd.run:
    - name: qvm-run -u root cudatemplate "apt-get install -y make gcc dracut linux-headers-amd64"

cudatemplate--nvidia_drv_exec:
  cmd.run:
    - name: qvm-run cudatemplate "chmod +x /home/user/QubesIncoming/dom0/nvidia.run"

# take note, this extracts the src to /home/user/
cudatemplate--extract_nvidia_drv_src:
  cmd.run:
    - name: qvm-run -u user cudatemplate "/home/user/QubesIncoming/dom0/nvidia.run --no-x-check --ui=none --keep --extract-only"
    - require:
      - cmd: cudatemplate--nvidia_drv_exec
    - unless: qvm-run -u user cudatemplate "test -d /home/user/nvidia"

cudatemplate--rename_nvidia_drv_src:
  cmd.run:
    - name: qvm-run -u user cudatemplate "mv /home/user/NVIDIA* /home/user/nvidia"
    - require:
      - cmd: cudatemplate--extract_nvidia_drv_src
    - unless: qvm-run -u user cudatemplate "test -d /home/user/nvidia"

cudatemplate--reboot-for-kernel:
  qvm.shutdown:
    - name: cudatemplate
    - flags:
      - quiet
      - wait
    - require:
      - cmd: cudatemplate--rename_nvidia_drv_src
