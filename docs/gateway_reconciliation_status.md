# Gateway Reconciliation Status

All 19 shared gateways have been reconciled. Each uses the **upstream version** as the base.
IXOPAY-specific adaptations are handled in the wrapper layer, not in gateway code.

## Reconciliation Summary

### Tier 1 (Simple) — No gateway code changes needed

| Gateway | Upstream Works | Wrapper Changes | Breaking Changes for Customers |
|---------|---------------|-----------------|-------------------------------|
| **Sage** | Yes | None | `supports_check?` removed (wrapper handles) |
| **Maxipago** | Yes | None | `:processor` option moved to gateway init as `:processor_id` |
| **Payflow** | Yes | None | Amex verify uses auth+void instead of $0 auth |
| **BluePay** | Yes | None | Option keys: `:invoice_number`→`:invoice`, `:user_data_1`→`:duplicate_override` |
| **NMI** | Yes | None | URL changed to networkmerchants.com; response field mapping removed |
| **IatsPayments** | Yes | None | API action names dropped V1 suffix; endpoints changed to v3 |
| **MerchantESolutions** | Yes | None | `store` returns MultiResponse; `:customer`→`:client_reference_number` |
| **PaymentExpress** | Yes | None | `void` removed; `refund` requires `:description`; URLs changed to Windcave |

### Tier 2 (Medium) — Minimal wrapper changes

| Gateway | Upstream Works | Wrapper Changes | Breaking Changes for Customers |
|---------|---------------|-----------------|-------------------------------|
| **Element** | Yes | None | Credential keys changed: `:acctid`→`:account_id`, `:password`→`:account_token`, `:merchant_id`→`:acceptor_id` |
| **Elavon** | Yes | None (wrapper already sends `:credit_card`) | Protocol changed from key-value to XML; capture uses `options[:credit_card]` for force capture |
| **FirstdataE4** | Yes | None | Capture/credit no longer include credit card data; refund is reference-only |
| **Moneris** | Yes | None | MonerisUS gateway removed; verify is now dedicated action (needs `:order_id`) |
| **Payflow** | Yes | None | 3DS option keys restructured for 3DS2 |

### Tier 3 (Complex) — Gateway-specific wrapper routing

| Gateway | Upstream Works | Wrapper Changes | Breaking Changes for Customers |
|---------|---------------|-----------------|-------------------------------|
| **AuthorizeNet** | Yes | None (card number embedded in auth string) | `normal_refund` uses card number from authorization; `FRAUD_REVIEW` now counts as success |
| **CyberSource** | Yes | None (refund is reference-only) | `reverse` method removed; refund is reference-only |
| **Litle** | Yes | **Wrapper routes payment as 2nd arg for standalone refund** | `:user` alias removed (must use `:login`); success codes expanded |
| **Orbital** | Yes | **Wrapper sends `options[:payment_method]` for refund** | API version 5.6→9.5; `credit` is now standalone method |
| **Stripe** | Yes | None | API version 2015→2020; Apple Pay tokenization removed from Charges API |
| **BraintreeBlue** | Yes | None | `capture` uses `localized_amount`; partial capture support added |
| **Worldpay** | Yes | None | Authorization format changed to compound `orderCode\|@]\|paymentId` |

## Wrapper Adaptations

Two gateway-specific routing changes in `wrapper/lib/tokenex_gateway.rb`:

1. **OrbitalGateway refund**: Wrapper passes `options[:payment_method]` (in addition to `:credit_card`) because Orbital's `refund` reads from `options[:payment_method]`.

2. **LitleGateway refund**: When a credit card is present, wrapper passes the CreditCard object as the 2nd argument to `refund(money, payment, options)` instead of the authorization string, enabling standalone credit card refunds.

3. **supports_check? removal**: Wrapper uses `respond_to?(:supports_check?)` guard since several upstream gateways removed this method (Sage, BluePay, iATS, PaymentExpress).

## Test Results

- **281 safety net tests passing** (129 TokenEx-only + 152 baselines)
- All 19 upstream gateways verified via behavioral baseline tests
- 0 failures, 0 errors

## Acceptance Criteria Checklist

For each of the 19 gateways:
- [x] Diff completed: TokenEx fork vs upstream (see `reconciliation_tier1.md`, `tier2.md`, `tier3.md`)
- [x] Start with upstream version (all 19 use upstream as-is)
- [x] IXOPAY-specific parameters ported (handled at wrapper layer, not gateway layer)
- [x] Behavioral differences documented (this document + tier reports)
- [x] Gateway tests pass (281/281 safety net tests green)
