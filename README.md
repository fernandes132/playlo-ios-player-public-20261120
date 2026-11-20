# Public Playlo iOS build repository

Public app sources explicitly approved by the owner. No website deployment.

This repository exposes the iOS app source and the entire embedded client bundle (34 games, Studio, Music). Backend/server source, credentials, signing keys, user accounts and cloud databases are excluded. The website is not deployed. The unsigned IPA is kept in an unpublished draft release for the owner.

The workflow uses only standard public macOS runners, no paid or larger runners, no Actions artifact storage, no cache, no Git LFS and no Apple signing account. GitHub documents standard public runners as free. Releases have no total size or bandwidth quota. The build requires explicit workflow_dispatch.

https://docs.github.com/en/actions/concepts/billing-and-usage
https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases

This is a genuine native rebuild, not a resource patch of an older IPA. Native YouTube view code is new and still requires Xcode compilation and runtime verification.
