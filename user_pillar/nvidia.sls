nvidia:
  driver_dom0_path: "/home/willy/nvidia.run"
  driver_filename: "nvidia.run"

  templates:
    - name: cudatemplate
      source_template: debian-13-xfce
      distro: debian
      label: orange
      memory: 4092
      maxmem: 0
      vcpus: 2
      private_storage: 20GiB
