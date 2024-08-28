whisper_server:
  name: whisper-server
  class: StandaloneVM
  template: f40-service
  label: orange
  memory: 4092
  maxmem: 4092
  vcpus: 2
  audiosrc: disp1509
  audiodestport: 8001

whisper_server_gpu:
  name: whisper-server-gpu
  class: StandaloneVM
  template: cuda-template-main
  label: orange
  memory: 8192
  maxmem: 8192
  vcpus: 4
  audiosrc: disp1509
  audiodestport: 8001
