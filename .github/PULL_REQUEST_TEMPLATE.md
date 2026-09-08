## What this changes

<!-- One or two sentences. What is different after this is merged? -->

## Why

<!-- The problem it solves. Link an issue if there is one. -->

## How it was verified

<!-- Adapters can only be trusted when someone with that tool installed has run
     them. Say which account you tested against, and how the numbers compared to
     what the provider's own page reported. -->

- [ ] `swift build` and `swift test` pass
- [ ] Checked against a real account, not only fixtures
- [ ] New logic in `BrimCore` has tests, including the failure cases

## The rules that keep the numbers honest

<!-- See CONTRIBUTING.md. Tick what applies. -->

- [ ] No invented numbers. A missing value is unknown, not zero
- [ ] No product's metering presented as another's
- [ ] Every reading carries the time it was taken
- [ ] Anything estimated is labelled as an estimate
- [ ] Nothing writes to another app's files
