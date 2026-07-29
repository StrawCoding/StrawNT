# Self-contained prefix (pc1)

Placeholder for `$STRAWWU_PREFIX` layout produced by `make portable-prefix`
(or equivalent). Expected sketch:

```
$STRAWWU_PREFIX/
  bin/strawwu
  lib/          # bundled shared objects + rpath
  share/        # optional docs / desktop files
```

pc0 only scaffolds this directory; binaries are not built here yet.
