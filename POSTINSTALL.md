# Qdrant is installed

## Get your API key

Qdrant requires an API key on every request. This package generated one admin key and one
read-only key on first start. To see them, open a Terminal for this app in the Cloudron
dashboard (or run `cloudron exec`) and read the keys file:

    cat /app/data/.secrets/keys.env

Keep the admin key secret: it grants full read and write access. The read-only key grants read
access only. Either can be sent as an `api-key` header or as an `Authorization: Bearer` token.

## Dashboard

<sso>
Open $CLOUDRON-APP-ORIGIN/dashboard and sign in with your Cloudron account. The dashboard is on
your primary domain behind Cloudron login, so only your Cloudron users can reach it. After
signing in, paste the admin key into the dashboard's API key field to manage collections.
</sso>
<nosso>
Open $CLOUDRON-APP-ORIGIN/dashboard. Single sign-on is not enabled for this install, so the
dashboard is reachable directly. Paste the admin key into the dashboard's API key field to manage
collections.
</nosso>

## Connecting clients (REST and gRPC)

The data plane is not behind Cloudron login, because automated clients cannot complete an
interactive sign-in. It is protected by the API key instead.

- REST, on your app domain:

      curl $CLOUDRON-APP-ORIGIN/collections -H "api-key: <admin-key>"

- gRPC, on the host and port shown for this app's "Qdrant gRPC API" port (under the app's
  Location settings). This is what the Rust `rig-qdrant` client uses. The gRPC port is plain TCP
  and is not TLS-terminated by Cloudron; see the README security section.

## Scoped tokens (JWT)

JWT and role-based access control are enabled. From the dashboard "Access Tokens" panel you can
mint read-only or per-collection tokens, signed by the admin key, to hand to integrators.
Rotating the admin key revokes every issued token.

## Memory and large collections

The default memory limit is 2 GB. Qdrant is configured to reject writes, while staying alive and
serving reads, when it approaches the limit, rather than being killed into a restart loop. For
larger collections, raise the memory limit in the app's Resources settings, store vectors on
disk, or use TurboQuant quantization. See the README and docs/INTEGRATIONS.md.
