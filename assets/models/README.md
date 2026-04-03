Place the offline model files here before running the app.

Expected files for the current pipeline:

- `assets/models/sensevoice/model.int8.onnx`
- `assets/models/sensevoice/tokens.txt`
- `assets/models/silero_vad.onnx`

The app copies these bundled assets to a writable runtime directory before
initializing `sherpa_onnx`, since the library expects filesystem paths.
