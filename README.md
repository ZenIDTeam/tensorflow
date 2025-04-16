# The build patches are in the tags

## How to check out a build patch
- `git clone --depth=20 git@github.com:ZenIDTeam/tensorflow.git`
- `git fetch --tags --depth=1 origin`
- `git checkout v2.12.0-custom-ops`

## How to add a new build patch for tflite:

1. fetch a TF tag from upstream tf repo (with depth=1)
 - `git clone --depth=20 git@github.com:ZenIDTeam/tensorflow.git`
 - `git remote add upstream https://github.com/tensorflow/tensorflow.git`
 - `git fetch origin tag v2.12.0 --no-tags`
 - `git checkout v2.12.0`
2. add your commits on top
3. tag it and push the tag to this repo
   **Make sure you don't have extra random tags from upstream repo at this point!**
 - `git tag v2.12.0-custom-ops`
 - `git push --tags origin v2.12.0-custom-ops`
