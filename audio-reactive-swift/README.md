# Audio Reactive

Native macOS Swift/Metal foundation for an autonomous audio-reactive visual performance.

## Ableton routing

Install BlackHole 2ch or Loopback. In Ableton, set the Master output to the virtual device. In macOS Audio MIDI Setup, create an Aggregate or Multi-Output Device if you need to hear the set while sending it to the visualizer. Set the virtual device as the Mac input before launching the app. The visualizer reads that digital stream through `AVAudioEngine`; it does not use a microphone.

## Run

```sh
swift run
```

The current target is the audio-analysis foundation and Metal view shell. The next production layer should add a `MTKViewDelegate` renderer with several visual scenes, beat/flux event routing, scene crossfades, deterministic seeded noise, and a time-based scene scheduler so a 30-minute set evolves without manual interaction.
