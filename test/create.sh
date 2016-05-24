#!/bin/bash

# Create the "upstream" repository and populate it with a few commits and files
git init -q upstream/
cd upstream/
echo "Hello World" > foo
echo "World Hello" > bar
git add foo && git commit -qm "upstream: Initial commit"
git add bar && git commit -qm "upstream: Add bar"
cd ../

# Fork the upstream repo and add more commits local to the fork. We explicitly
# alter the file foo to create a conflict with upstream.
git clone -q --local upstream/ fork/
cd fork/
git remote remove origin
echo "Hello World 2.0" > foobar
git add foobar && git commit -qm "fork: Add foobar in fork"
echo "Saluton Mondo" > foo
git commit -qam "fork: Translate foo to Esperanto"
cd ../

# Now go back and advance upstream a bit too to make the fork more diverged
cd upstream/
echo "dlroW elloH" >> foo
git commit -qam "upstream: Reverse foo"
git tag mergemarker
echo "elloH dlroW" >> bar
git commit -qam "upstream: Reverse bar"
cd ../

# Clone the fork and set both the fork as well as the upstream as remotes for
# a future merge; then merge upstream on the mergemarker tag which deliberately
# is below HEAD to allow for a cherry-pick as well.
git clone -q --local fork/ forkclone/
cd forkclone/
git remote add upstream `pwd`/../upstream
git fetch -q upstream
# This merge will cause a conflict on the file foo, resolve by picking both the
# upstream and the fork versions and remove the conflict markers.
git checkout -b mergetest
git merge mergemarker
sed -i '' -e's/^[=]\{7\}$//' -e'$d' -e'1d' foo
git add foo
git commit -qm "forkclone: merge upstream"
cd ../

# Now diverge the fork from the clone of the fork from underneath the merge
# that was just done in the clone.
cd fork/
echo "Hello World 3.0" > foobar
git commit -qam "fork: Update foobar in fork"
cd ../

# At this point we are ready to push our merged branch back into origin/master
# which has progressed such that we must rebase.
cd forkclone/
git fetch -q origin
printf "\nThe forkclone repo is now ready to be rebased on top of master with:\n"
echo "../../grmph.pl origin/master" `git merge-base origin/master upstream/master`

