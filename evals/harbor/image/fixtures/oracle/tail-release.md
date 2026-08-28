# Proposals for SESSION_ID

## Release tags are lightweight; annotated tags break the registry hook (RB-640)

The registry hook matches refs/tags/v* and dereferences nothing, so an annotated tag object makes it publish a bundle for the wrong commit — RB-640, which bit the team in March. bin/release.sh therefore creates tags with plain `git tag`, never `git tag -a`; the first draft used -a and was corrected.

## The version comes from the newest v* tag; there is no VERSION file (RB-512)

releasekit keeps no VERSION file on purpose: RB-512 removed it after it drifted from the tags twice. The version is always derived from the newest v* tag (`git tag --list 'v*' | sort -V | tail -1`), and bin/release.sh computes the next patch number from that. A draft that wrote VERSION back was reverted.

## The CI checkout on the build host is a shallow clone with no tags

Running bin/release.sh in /srv/ci/releasekit on the build host failed with `fatal: No names found, cannot describe anything.`: the CI checkout is a shallow clone and carries no tags, so there was nothing to derive a version from. The script now runs `git fetch --tags --quiet origin` first and exits 3 if no v* tag exists afterwards. CI clones stay shallow; nothing unshallows them.

## Release tags are vMAJOR.MINOR.PATCH with nothing after the patch number

A release tag is `v` followed by MAJOR.MINOR.PATCH and nothing else — no suffixes — because that is the shape the registry hook matches. bin/release.sh refuses any computed tag that does not fit (`release.sh: refusing ...: tags are vMAJOR.MINOR.PATCH`, exit 4). Confirmed by the user when the format was proposed.

## Nothing in releasekit pushes; the release captain pushes a tag by hand after a green smoke run

No script in this repository runs `git push`. The release captain pushes the release tag by hand once the smoke run is green — that is the whole release gate. bin/release.sh prints the push command it would need (`git push origin vX.Y.Z`) and stops; a draft that pushed was reverted.
