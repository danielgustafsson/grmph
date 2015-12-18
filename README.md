# grmph - Git Rebase with Merges Preserved Helper

Little helper script to rebase a merge commit while preserving the merge
even when `git rerere` wasn't enabled during the merging (or if it was,
make life still a little easier..).

## Requirements

Since grmph uses rerere and the `rerere-train.sh` Git contrib script
internally it requires a Git installation with these present.
