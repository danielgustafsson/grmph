# grmph.pl - Git Rebase with Merges Preserved Helper

Little helper script to rebase a merge commit while preserving the merge even
when `git rerere` wasn't enabled during the merging (or if it was, make life
still a little easier..). Any changes performed as part of the merge that aren't
conflict resolutions needs to be manually extracted and re-applied after the
process.

## Usage

	grmph.pl <target branch> [rerere point]

`target branch` is the branch to rebase the merge on top of and `rerere point`
is the commit sha in history where to start the recording of the conflict
resolutions (it can be any arbitrary sha as long as it's before the merge
commit in question.

## Requirements

* A Git version with `git rerere` support
* `rerere-train.sh` Git contrib script
* interdiff (from patchutils)
* Term::ReadKey Perl module

## License

See head section of `grmph.pl`.
