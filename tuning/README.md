# GPU tuning: power cap + fan curve at every boot

`gpu-tuning.sh` sets the power cap and a 5-point fan curve on every Radeon AI PRO R9700
(`0x7551`), selected by PCI ID — not by `cardN`, which changes across reboots.
`gpu-tuning.service` runs it at boot, before the model server and monitoring.

Requires `amdgpu.ppfeaturemask` with bit `0x4000` (overdrive) on the kernel command line —
see [`../findings/fan-control-requires-overdrive.md`](../findings/fan-control-requires-overdrive.md).

```bash
sudo install -m 0755 gpu-tuning.sh /usr/local/sbin/gpu-tuning.sh
sudo install -m 0644 gpu-tuning.service /etc/systemd/system/gpu-tuning.service
sudo systemctl daemon-reload && sudo systemctl enable --now gpu-tuning
/usr/local/sbin/gpu-tuning.sh status     # preview changes: gpu-tuning.sh dry-run
```

Edit `POWER_W` and `CURVE` at the top of the script; `sudo systemctl restart gpu-tuning` applies.
