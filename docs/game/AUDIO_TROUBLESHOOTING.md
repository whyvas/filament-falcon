# Filament Falcon audio
## Audio troubleshooting (garbled / choppy sound)

1. Run the game without the intercom: `./run.sh --no-ics`. Clean sound here means the intercom helper is the problem.
2. Check the server rate (should be 48000): `pactl info | grep -i 'sample spec'`
3. Read the intercom log: `tail -n 40 ~/.local/share/filament-falcon/ics.log`. Look for underruns/xruns.
4. Look for leftover sinks from a crash: `pactl list short modules | grep -i falcon`. To clear them: `pactl list short modules | awk '/falcon/{print $1}' | xargs -r -n1 pactl unload-module`
5. Measure the delay through a headset: `python3 tools/falcon_ics.py --latency-test pilot`

The intercom runs at a fixed 48 kHz with 10 ms blocks and about 30 ms of buffer (around 50-60 ms end to end). PulseAudio/PipeWire resample any headset that runs at 44.1 kHz. When the helper stops, the game moves its audio back to the default output.
