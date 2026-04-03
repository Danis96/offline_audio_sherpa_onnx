Place Whisper Small ONNX files here.

Expected files:

- `assets/models/whisper_small/encoder.int8.onnx` or `encoder.onnx`
- `assets/models/whisper_small/decoder.int8.onnx` or `decoder.onnx`
- `assets/models/whisper_small/tokens.txt`

This app copies the bundled files into a writable runtime directory before
creating the `sherpa_onnx` Whisper recognizer.
