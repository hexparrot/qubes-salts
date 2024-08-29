.# Qubes OS Salt Recipes

This repository contains a collection of SaltStack recipes designed specifically for managing and automating various tasks within Qubes OS.

Examine all the states yourself and understand what they do. Use at your own risk.

Tested and built against Qubes OS 4.2.

## Table of Contents
- [Usage](#usage)
- [License](#license)
- [Contact](#contact)

## Usage

Here's a brief overview of the available recipes:

### Intra-Qube TCP Port Forwarding

This salt state helps automate the configuration of intra-VM networking. From the `<source_vm>`, activates `qubes.ConnectTCP` allowing direct access to the `<target_vm>:<port>`.

Define one or more connections in `user_pillar/dmz_networking.sls`:

```dmz_networking:
  connections:
    - port: 9090
      source_vm: 'stable-diffusion'
      target_vm: 'llm'
    # running invoke.ai
```
Per the above example, this would allow connections initiated on `stable-diffusion` to reach `llm:<port>` via `localhost:<port>`.

### NVIDIA/CUDA-enabled Debian 12 Qube

Prepare a TemplateVM by creating a standalone VM with the necessary dracut/grub changes to support GPU acceleration.

Instructions:

1. Download nvidia linux driver, copy it to dom0.
2. Update `/user_pillar/nvidia.sls` to update `nvidia_dom0_path` to match the location of step #1.
3. (dom0) `sudo qubesctl state.apply nvidia-dom0-prep saltenv=user`

At this point, `cudatemplate` is updated and prepped, and turned off.
Use this opportunity to ADD devices to VM in Qube settings.
Be sure to bring along the audio device with the vga device.
Turn off memory balancing, adjust other values like memory and storage now.

4. Turn on `cudatemplate` VM.
5. Run and install nvidia driver manually within `cudatemplate` domU:
`sudo ./nvidia-installer --no-nouveau-check --no-disable-nouveau --no-rebuild-initramfs --allow-installation-with-running-driver --no-peermem --no-x-check --install-compat32-libs --install-libglvnd --ui=none --systemd -e -q`

Finish configuration of grub and initrd for use into a template:
 
6. (dom0) `sudo qubesctl --skip-dom0 --targets=cudatemplate state.sls nvidia-domu-finalize saltenv=user`
7. `reboot` `cudatemplate` again and your GPU should now be detected by CUDA Toolkit! You can verify this with `nvidia-smi`. Also `lsmod` should show `nvidia*` and no longer `nouveau`.

### Faster-Whisper-Server CPU/GPU Qube

Use the CUDA-enabled TemplateVM to create realtime Speech-to-Text (STT) transcriptions. Included are salt states `whisper` and `whisper-gpu`, though only the latter is feasible for realtime.

Instructions:

1. Examine the pillar `/user_pillar/whisper_server.sls` and make desired changes including the `<AUDIOSRC>`.
2. Create the whisper-server VM and set up the `audiosrc` port forwarding:
`sudo qubesctl --targets=<AUDIOSRC>,whisper-server-gpu state.sls whisper-gpu saltenv=user`
3. Forward the qubes audio sink (the VM audio output) to the whisper server from the `<AUDIOSRC>` terminal:
`ffmpeg -f pulse -i qubes-sink.monitor -acodec pcm_s16le -f wav - | socat -u - TCP:localhost:8001`
4. The transcriptions are found in the whisper-server at `/home/user/sr.log`

In some cases, step #3 may immediately fail with a pipe broken error. If this happens, restart the service providing port 8001 within `whisper-server`/`-gpu` with `systemctl restart stream_receiver`.

## License

This project is licensed under the MIT License.

## Contact

For any questions or suggestions, feel free to reach out via [wdchromium@gmail.com](mailto:wdchromium@gmail.com) or open an issue in this repository.
