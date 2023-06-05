# The build patches are in the tags

## How to add a new build patch for tflite:

1. fetch a TF tag from upstream tf repo (with depth=1)
 - `git clone --depth=20 git@github.com:ZenIDTeam/tensorflow.git`
 - `git remote add upstream https://github.com/tensorflow/tensorflow.git`
 - `git fetch --depth=1 upstream v2.12.0`
 - `git checkout v2.12.0`
2. add your commits on top
3. tag it and push the tag to this repo
 - `git tag v2.12.0-custom-ops`
 - `git push --tags origin v2.12.0-custom-ops`
