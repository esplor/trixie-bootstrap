# Getting the repo onto a minimal install

A minimal trixie install has no git and no CA certificates, so the clone fails before it
starts. `ca-certificates` is a Recommends of both `git` and `libcurl3t64-gnutls` (git's
HTTPS transport), never a Depends, so with `--no-install-recommends` it has to be named or
the clone dies with `server certificate verification failed. CAfile: none`:

```sh
sudo apt update && sudo apt install --no-install-recommends ca-certificates git openssh-client
```

Or skip the clone and copy the one script over from another machine: `scp bootstrap.sh user@host:`.
