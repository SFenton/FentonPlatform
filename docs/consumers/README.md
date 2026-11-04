# Consumers

Consumer adoption is opt-in and separate from this bootstrap. Compatibility
records under [`integrations/consumers/`](../../integrations/consumers/) are
operator-recorded metadata, not trusted admission receipts or grants.

Each record uses `schema_version` `1` and records:

- `repo`, `base`, `proposal`, and the immutable `shared_revision`;
- the adopted `surfaces`;
- local evidence status, exact selectors, counts, fixture origin and build
  outcome;
- independent `review`, `ci`, and `promotion` status.

Records must pin source revisions and shared artifacts without credentials,
private endpoints, local user paths, process IDs, or production configuration.
They must not turn a draft proposal, local run, or review result into admission
authority. Consumer code and dependencies are changed only in the consumer
repositories.

Current records:

- [Festival Native Apps](../../integrations/consumers/festival-native-apps.json):
  final local privacy/AX5 pilot evidence, draft PR, not merged or promotion
  qualified.
- [HASS Native](../../integrations/consumers/hass-native.json): current
  candidate proof pending; evidence from the divergent historical base is
  explicitly excluded.
