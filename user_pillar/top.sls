# vim: set syntax=yaml ts=2 sw=2 sts=2 et :
#

# ===== User Defined Salt Pillars =============================================

user:
  '*':
    - dmz_networking
  'dom0':
    - nvidia
