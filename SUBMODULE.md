# Submodule workflow

## Clone (first time)

```sh
git clone --recurse-submodules https://github.com/delleceste/open-media-drc.git
```

## After `git pull` (when the submodule pointer changed)

```sh
git pull
git submodule update --init
```

## Making changes inside `omdrc-ctrl`

Always push the submodule before updating the parent pointer:

```sh
cd omdrc-ctrl
# edit, commit ...
git push origin main

cd ..
git add omdrc-ctrl
git commit -m "Update omdrc-ctrl submodule"
git push
```

## What NOT to do

- Do not `git pull` inside the submodule without then committing the updated pointer in the parent — the parent will silently point to the old commit.
- Do not `git push` the parent before pushing the submodule — the remote will reference a commit that does not exist yet on GitHub.
