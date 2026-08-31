#!/usr/bin/env bash
# Roll back to SSH commit signing via 1Password (the config as of 2026-08-28).
set -euo pipefail
git config --global gpg.format ssh
git config --global user.signingkey 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMtrAKKhfARh/V7BSCnbB5ZXcrSBOmKoquP2k4TUE23J'
git config --global gpg.ssh.program '/Applications/1Password.app/Contents/MacOS/op-ssh-sign'
git config --global commit.gpgsign true
echo "restored SSH signing via 1Password:"
git config --global --get-regexp 'gpg|signingkey|gpgsign'
