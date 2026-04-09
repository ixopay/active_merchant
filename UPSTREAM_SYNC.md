# Upstream Sync Process

## Overview

The IXOPAY fork of ActiveMerchant maintains compatibility with the upstream `activemerchant/active_merchant` repository while adding IXOPAY-specific gateways and modifications.

## Automated Sync

A GitHub Actions workflow (`upstream-sync.yml`) runs weekly on Monday at 9 AM UTC:

1. Fetches `upstream/master`
2. Attempts automatic merge
3. Runs full test suite on merge result
4. Creates a PR (clean merge) or an Issue (conflict)

## Manual Sync

```bash
# Add upstream remote (one-time)
git remote add upstream https://github.com/activemerchant/active_merchant.git

# Fetch latest upstream
git fetch upstream master

# Create sync branch
git checkout -b upstream-sync/$(date +%Y-%m-%d)

# Merge upstream
git merge upstream/master

# Resolve any conflicts (see below)
# ...

# Run tests
bundle exec rake test:units
bundle exec rake test:safety_net

# Push and create PR
git push origin upstream-sync/$(date +%Y-%m-%d)
```

## Conflict Resolution Priorities

| File Type | Priority | Action |
|-----------|----------|--------|
| Non-IXOPAY gateways | Upstream | Accept upstream changes |
| IXOPAY-only gateways (tsys, firstdata_compass, chase_net_connect, vantiv_online_systems) | IXOPAY | Keep IXOPAY version |
| Reconciled shared gateways | Review | Prefer upstream for bug fixes, keep IXOPAY parameters |
| Test files | Merge | Keep both upstream and IXOPAY tests |
| CI/CD workflows | IXOPAY | Keep IXOPAY CI additions |
| Gemspec, Gemfile, Rakefile | Merge | Keep IXOPAY additions alongside upstream changes |

## IXOPAY-Specific Files

These files exist only in the IXOPAY fork and should never conflict:

- `lib/active_merchant/billing/gateways/tsys.rb`
- `lib/active_merchant/billing/gateways/firstdata_compass.rb`
- `lib/active_merchant/billing/gateways/chase_net_connect.rb`
- `lib/active_merchant/billing/gateways/vantiv_online_systems.rb`
- `test/unit/gateways/tsys_test.rb`
- `test/unit/gateways/firstdata_compass_test.rb`
- `test/unit/gateways/chase_net_connect_test.rb`
- `test/unit/gateways/vantiv_online_systems_test.rb`
- `test/unit/gateways/behavioral_baselines/`
- `CONTRIBUTING_IXOPAY.md`
- `UPSTREAM_SYNC.md`
- `.github/workflows/upstream-sync.yml`

## Post-Merge Validation

After merging upstream changes:

1. `bundle exec rake test:units` - All upstream + IXOPAY tests pass
2. `bundle exec rake test:safety_net` - IXOPAY safety net passes
3. `bundle exec rubocop` - No new linting issues
4. Review any behavioral differences in reconciled gateways
