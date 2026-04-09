# Contributing to IXOPAY ActiveMerchant Fork

## Branch Naming

- IXOPAY gateway work: `ixopay/gateway-name` (e.g., `ixopay/vantiv-online-systems`)
- Bug fixes: `fix/description`
- Upstream sync: `upstream-sync/YYYY-MM-DD`

## PR Checklist

Before submitting a PR, verify:

- [ ] All unit tests pass: `bundle exec rake test:units`
- [ ] IXOPAY safety net passes: `bundle exec rake test:safety_net`
- [ ] Sensitive data scrubbed: `supports_scrubbing?` returns `true`, `scrub()` filters credentials
- [ ] RuboCop passes: `bundle exec rubocop`
- [ ] CHANGELOG updated (if applicable)
- [ ] No `Marshal.load` usage in gateway code
- [ ] Standard error codes mapped via `STANDARD_ERROR_CODE`

## Gateway Contribution Process

### Adding a New IXOPAY-Only Gateway

1. Create gateway file in `lib/active_merchant/billing/gateways/`
2. Follow upstream conventions:
   - 2-space indentation
   - Declare `self.supported_countries`, `self.supported_cardtypes`, `self.money_format`
   - Use constants (not class variables `@@`)
   - Implement `supports_scrubbing?` and `scrub()`
   - Map error codes to `STANDARD_ERROR_CODE`
3. Create unit test in `test/unit/gateways/`
4. Create remote test template in `test/remote/gateways/`
5. Add fixture entry in `test/fixtures.yml`
6. Run full test suite

### Reconciling a Shared Gateway

1. Start with the upstream version as base
2. Port IXOPAY-specific parameters on top
3. Ensure behavioral baseline tests still pass
4. Document all behavioral differences

## Upstream Contribution

To contribute an IXOPAY gateway upstream:

1. Ensure gateway follows all upstream conventions
2. Remove any IXOPAY-specific parameters
3. Create a fork of `activemerchant/active_merchant`
4. Submit PR following upstream contribution guidelines
5. Include unit tests and remote test template

## Testing

```bash
# Run all unit tests
bundle exec rake test:units

# Run IXOPAY safety net (TokenEx-only + baselines)
bundle exec rake test:safety_net

# Run behavioral baselines only
bundle exec rake test:baselines

# Run a specific test file
ruby -Itest test/unit/gateways/tsys_test.rb

# Run with debug logging
DEBUG_ACTIVE_MERCHANT=true ruby -Itest test/unit/gateways/tsys_test.rb
```

## Code Style

- Follow existing upstream ActiveMerchant conventions
- 2-space indentation (no tabs)
- Use `freeze` on constant hashes and arrays
- Prefer `raise ArgumentError, 'message'` over `raise ArgumentError.new('message')`
- Use symbol keys for option hashes: `{ key: value }` not `{ :key => value }`
