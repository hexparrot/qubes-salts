dmz_networking:
  connections:
    - port: 9090
      source_vm: 'stable-diffusion'
      target_vm: 'llm'
    # running invoke.ai
    - port: 9997
      source_vm: 'coding'
      target_vm: 'llm'
    # running xinference
