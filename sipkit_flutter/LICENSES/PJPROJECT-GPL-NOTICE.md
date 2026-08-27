# PJSIP/pjproject GPL notice

Native artifacts produced by `tool/build_android_pjsua2_aar.sh` or
`tool/build_ios_pjsua2_xcframework.sh` incorporate PJSIP/pjproject. The
artifact is built from upstream pjproject commit
`08578e86eea120c5ab2ab1af5a18b7840120d87b`.

PJSIP/pjproject is available from Teluu under its GPL version 2 licensing
option (and a separate commercial licensing option). When distributing an
artifact built under the GPL option, distribute it under **GPL version 2 or
any later version**, retain the upstream copyright and license notices, and
provide the complete corresponding source. The canonical upstream source and
license are available at <https://github.com/pjsip/pjproject>.

Run `tool/package_gpl_source.sh` from the same committed SipKit source revision
to create the corresponding-source archive. It contains this package's source,
the exact upstream pjproject source, and the build scripts/configuration needed
to reproduce the artifact. Do not describe a binary as GPL-compliant unless
that archive (or an equally complete source offer) is made available to every
binary recipient for the GPL-required period.

This repository deliberately does not vendor pjproject source. Fetching it by
immutable commit in the scripts reduces duplication while keeping the source
distribution deterministic.