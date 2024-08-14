# Qubes OS Salt Recipes

This repository contains a collection of SaltStack recipes designed specifically for managing and automating various tasks within Qubes OS.
Examine all the states yourself and understand what they do. Use at your own risk.

## Table of Contents
- [Requirements](#requirements)
- [Usage](#usage)
- [Recipes Overview](#recipes-overview)
- [License](#license)
- [Contact](#contact)

## Requirements

- **Qubes OS version**: Tested and built against Qubes OS 4.2.
- **SaltStack**: Installed by default on your Qubes OS installation.
- **Qubes-dom0-update**: Ensure your dom0 is updated regularly to avoid compatibility issues.

## Usage

Here's a brief overview of the available recipes:

- **`portforward.sls`**: Automates the configuration of VM networking.

In user_pillar/dmz_networking.sls:

```dmz_networking:
  connections:
    - port: 9090
      source_vm: 'stable-diffusion'
      target_vm: 'llm'
    # running invoke.ai
```
Each stanza can be used to set up a separate secure channel between <source_vm> and <target_vm>. This is implemented through qvm-connect-tcp.

- **`nvidia-dom0-prep.sls`**: Based on Debian-12 Qubes template, prepare the vm by creating a standalone VM with the necessary dracut/grub changes.

Instructions:

1. Download nvidia linux driver, copy it to dom0
2. Update /user_pillar/nvidia.sls to update nvidia_dom0_path to match the location of step #1
3. (dom0) sudo qubesctl state.apply nvidia-dom0-prep saltenv=user

At this point, `cudatemplate` is updated and prepped, and turned off.
Use this opportunity to ADD devices to VM in Qube settings.
Be sure to bring along the audio device with the vga device.
Turn off memory balancing, adjust other values now.

4. Turn on `cudatemplate` VM
5. Run and install nvidia driver manually within `cudatemplate` domU:
`sudo ./nvidia-installer --no-nouveau-check --no-disable-nouveau --no-rebuild-initramfs --allow-installation-with-running-driver --no-peermem --no-x-check --install-compat32-libs --install-libglvnd --ui=none --systemd -e -q`

- - **`nvidia-domu-finalize.sls`**: Finishes configuration of grub and initrd for use into a template.
 
6. (dom0) `sudo qubesctl --skip-dom0 --targets=cudatemplate state.sls nvidia-domu-finalize saltenv=user`
7. `reboot` `cudatemplate` once again and your nvidia device should work! You can verify this with `nvidia-smi`. Also `lsmod` should show no `nouveau`, only `nvidia*`.

## License

This project is licensed under the MIT License.

## Contact

For any questions or suggestions, feel free to reach out via [wdchromium@gmail.com](mailto:wdchromium@gmail.com) or open an issue in this repository.
