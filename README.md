how it's going

```none
jason@jason-latitude:odin-archs :) ./run.sh --arch="arm64 native" odin run src -vet -strict-style

RUN arm64 [_odin 14 run src -vet -strict-style]

'clang' -> '/usr/bin/clang-14'
["/home/odinist/vol/src.bin"]
running tests...
Expecting Error: file-that-does-not-exist.txt: file does not exist
Expecting Error: (broken) link.txt: file does not exist
Expecting Error: dir-no-exist: file does not exist
tests pass !!

RUN native [_odin 14 run src -vet -strict-style]

["/home/jason/dev/odin-archs/src.bin"]
running tests...
Expecting Error: file-that-does-not-exist.txt: file does not exist
Expecting Error: (broken) link.txt: file does not exist
Expecting Error: dir-no-exist: file does not exist
tests pass !!
jason@jason-latitude:odin-archs :)
```
