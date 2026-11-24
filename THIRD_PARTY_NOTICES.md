# Third-party notices

## ottypes/json0 — JSON0 and text0

Semantic reference and algorithm port: [ottypes/json0](https://github.com/ottypes/json0), npm `ot-json0@1.1.0`, commit [83222f417762be0e8672adb16657f0b8ba514d0d](https://github.com/ottypes/json0/tree/83222f417762be0e8672adb16657f0b8ba514d0d).

Copyright 2011 ottypes library contributors

Jeremy Apthorp wrote the original JSON type. Joseph Gentle and the ottypes contributors maintained it.

The published README explicitly declares the MIT license. The published package metadata instead labels the license ISC. Both facts are retained here. The README license text is reproduced verbatim in [LICENSES/ot-json0-1.1.0.txt](LICENSES/ot-json0-1.1.0.txt), including its original wording. This notice preserves upstream attribution independently of the Git author identity used for the MoonBit implementation.

JSON0 operation semantics, component transformation and text0 behavior are implemented in MoonBit, with typed paths, structured errors and explicit UTF-16 handling. Upstream deterministic tests and generated operation scenarios are used for verification. The [provenance map](docs/provenance.md) identifies the affected source files, test data and generation commands.

## ottypes/fuzzer — test tooling and generated cases

Development-only reference: [ottypes/fuzzer](https://github.com/ottypes/fuzzer), npm `ot-fuzzer@1.3.1`, fixed by [test/oracle/package-lock.json](https://github.com/sbqrre/opgrain/blob/e127d3bab7dd2b68f297f26412af2e06438620dc/test/oracle/package-lock.json).

Copyright 2011-2014 ottypes library contributors

The published README declares MIT; package metadata labels it ISC. The original README license text is retained in [LICENSES/ot-fuzzer-1.3.1.txt](LICENSES/ot-fuzzer-1.3.1.txt). The fuzzer runs only in the Node test environment; its JavaScript implementation is not part of the MoonBit runtime library.

## Distribution

The root [LICENSE](LICENSE) covers opgrain's own contributions. The upstream notices and full license copies remain applicable to referenced or adapted material. Generated fixtures and generated MoonBit interfaces are identified in [docs/provenance.md](docs/provenance.md); they are excluded from handwritten core line counts. Node development dependencies retain their own notices in installed packages, and are not bundled into the published MoonBit library.
