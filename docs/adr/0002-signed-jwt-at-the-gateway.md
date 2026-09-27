# ADR 0002 — API Gateway trusts JWTs signed by one service account, not any Google ID token

**Status:** accepted

The first attempt used `gcloud auth print-identity-token --impersonate-service-account=sop-client --audiences=sop-orders-api`. API Gateway rejected it with `Jwt issuer is not configured`: Google **ID tokens** carry `iss: https://accounts.google.com`. Configuring that issuer would work but is weak — anyone with *any* Google identity can mint an ID token with any audience, so the audience alone would be the only gate.

Instead the OpenAPI spec sets `x-google-issuer: sop-client@…` and `x-google-jwks_uri` to that service account's public keys. Only a JWT **signed by that service account** (`gcloud iam service-accounts sign-jwt`, i.e. the IAM `signJwt` API, gated by `serviceAccountTokenCreator`) passes. Proven live: a signed JWT → 202; the operator's own Google ID token → 401 *issuer is not configured*; a correctly signed JWT for another audience → 403 *Audiences in Jwt are not allowed*; no token → 401.

**Trade-off:** clients need `signJwt` permission (or the SA key, which this repo refuses to create). For end-user auth put Identity Platform / an OIDC issuer in the spec instead.
