# Tier 3 Gateway Reconciliation: Old Fork (v1.64.0) vs New Upstream (v1.137.0)

This document analyzes breaking changes and significant differences between the TokenEx old fork (v1.64.0) and the upstream ActiveMerchant (v1.137.0) for Tier 3 (complex) gateways. The focus is on identifying concrete API differences that would require changes in the PaymentGateway_New Sinatra wrapper.

---

## 1. Authorize.Net (`authorize_net.rb`)

**Magnitude of change: MODERATE**

### Marshal.load Usage (Old Fork)
- **`normal_refund` method (line 313):** Uses `Marshal.load(options[:payment_obj])` to deserialize the payment method for refund transactions. In the new upstream, this is completely removed. The new refund uses `card_number` from the split authorization or `options[:card_number]` / `options[:routing_number]` for bank account refunds.

### Method Signature Changes

| Method | Old Fork | New Upstream | Breaking? |
|--------|----------|-------------|-----------|
| `initialize` | `options={}` | `options = {}` | No |
| `purchase` | Same | `commit(:cim_purchase, options)` now passes options to commit | Minor |
| `authorize` | Same | `commit(:cim_authorize, options)` now passes options to commit | Minor |
| `capture` | Raises `ArgumentError` if missing auth | No longer raises (removed check) | No |
| `refund` | Returns response directly | Supports `force_full_refund_if_unsettled` option - auto-voids if unsettled | **New feature** |
| `verify` | Fixed 100 amount | `amount_for_verify(options)` - supports `options[:verify_amount]`, including $0 verify | **New feature** |
| `credit` | Uses `add_payment_source` | Uses `add_payment_method` with action param | **Breaking** |

### Options Handling Changes
- **`commit` method** now accepts `options` parameter (used for CIM delimiter support).
- **`parse` method** now accepts `options` parameter, used for CIM custom delimiters.
- **`parse_direct_response_elements`** now strips quotes from direct response and supports custom delimiter via `options[:delimiter]`.
- **`add_invoice`** now takes `transaction_type` parameter: `add_invoice(xml, transaction_type, options)` vs old `add_invoice(xml, options)`.
- **New options supported:**
  - `options[:tax]` (hash with amount/name/description)
  - `options[:duty]` (hash with amount/name/description)
  - `options[:shipping]` (hash with amount/name/description)
  - `options[:surcharge]` (hash with amount/name/description)
  - `options[:tax_exempt]`
  - `options[:po_number]`
  - `options[:summary_commodity_code]`
  - `options[:stored_credential]` (for stored credential / recurring / COF support)
  - `options[:three_d_secure]` (for 3DS data: `{eci:, cavv:}`)
  - `options[:verify_amount]`
  - `options[:force_full_refund_if_unsettled]`
  - `options[:test_request]`

### Response Parsing Changes
- New fields parsed: `full_response_code`, `network_trans_id`.
- `success_from` now accepts `FRAUD_REVIEW` as success (old only accepted `APPROVED`).
- `customer` regex changed from `/^\d+$/` to `/^\w+$/` (now allows alphanumeric customer IDs).

### Billing Address Changes
- New upstream combines `address1` and `address2` into a single `full_address` string.
- `state` defaults to `'NC'` for US/CA countries, `'n/a'` for others (old always defaulted to `'n/a'`).
- `phone` field now also checks `phone_number` key.

### Wrapper Impact
- **HIGH IMPACT:** `normal_refund` no longer uses `Marshal.load(options[:payment_obj])`. The wrapper must pass `options[:card_number]` or `options[:routing_number]` for standalone refunds instead.
- **MEDIUM IMPACT:** `add_invoice` signature change requires transaction_type parameter.
- **MEDIUM IMPACT:** Stored credential support (`add_processing_options`, `add_subsequent_auth_information`) is new.
- **LOW IMPACT:** Network token handling moved to separate `add_network_token` method with `isPaymentToken` flag.

---

## 2. Stripe (`stripe.rb`)

**Magnitude of change: LARGE**

### Marshal.load Usage (Old Fork)
- **Not used.** Stripe gateway does not use `Marshal.load` in either version.

### Architecture Change
- New upstream has **`StripePaymentIntentsGateway`** (`stripe_payment_intents.rb`) that inherits from `StripeGateway`. This is the recommended gateway for new integrations supporting SCA/3DS2.
- The base `StripeGateway` (Charges API) is preserved but marked as older version.
- New upstream sets `version '2020-08-27'` at the class level (old used `"2015-04-07"` as default).

### Method Signature Changes

| Method | Old Fork | New Upstream | Breaking? |
|--------|----------|-------------|-----------|
| `authorize` | ApplePay tokenization inline | No ApplePay tokenization; bank account check added | **Breaking** |
| `purchase` | ApplePay tokenization inline | No ApplePay tokenization; quickchip support added | **Breaking** |
| `capture` | Same basic flow | Adds `add_exchange_rate` | Minor |
| `void` | Simple | Adds `reverse_transfer`, `reason` options | Enhancement |
| `refund` | MultiResponse pattern | Direct commit; inline fee refund logic | **Changed** |
| `store` | ApplePay/StripePaymentToken support | Simplified; no Apple Pay tokenization | **Breaking** |

### Key Differences
- **Apple Pay tokenization removed:** Old fork handled `ApplePayPaymentToken` inline in authorize/purchase/store. New upstream does not. This is handled at a higher level or via Payment Intents.
- **API version:** Old `"2015-04-07"` vs new `"2020-08-27"` (or class-level `version`).
- **Supported countries expanded:** From 17 to 40+ countries.
- **Supported card types:** Added `unionpay`.
- **New error codes:** `pickup_card`, `amount_too_small`.
- **`add_creditcard` changes:** Network tokenization now maps `google_pay` source to `android_pay` tokenization method.
- **`post_data` rewrite:** Complete rewrite using `flatten_params` recursive method (supports deeply nested params).
- **`headers` method** now takes `method` parameter to prevent idempotency key on GET requests.
- **`commit` method** now validates API key, adds `success_from` with status check, new `message_from` helper.
- **New features:**
  - `add_shipping_address` for charge-level shipping data
  - `add_level_three` for Level 3 data (merchant_reference, line_items, etc.)
  - `add_connected_account` (on_behalf_of, transfer_destination)
  - `add_radar_data` (session, skip_rules)
  - `add_exchange_rate`
  - `add_statement_address`
  - `create_source` / `show_source` methods
  - Webhook endpoint management
  - Response header tracking (idempotent-replayed, stripe-should-retry)
  - `quickchip_payment?` support

### Wrapper Impact
- **HIGH IMPACT:** Apple Pay tokenization flow removed from Charges API. Must use Payment Intents gateway instead.
- **HIGH IMPACT:** API version change from 2015 to 2020 may affect response format.
- **MEDIUM IMPACT:** `refund` method signature effectively same but internal flow differs.
- **RECOMMENDATION:** Consider migrating to `StripePaymentIntentsGateway` for 3DS2/SCA compliance.

---

## 3. Braintree Blue (`braintree_blue.rb`)

**Magnitude of change: LARGE**

### Marshal.load Usage (Old Fork)
- **Not used.** Braintree Blue does not use `Marshal.load` in either version.

### Method Signature Changes

| Method | Old Fork | New Upstream | Breaking? |
|--------|----------|-------------|-----------|
| `capture` | `amount(money).to_s` | `localized_amount(money, ...)` + partial capture support | **Enhanced** |
| `purchase` | Same | Same | No |
| `refund` | Basic refund | `force_full_refund_if_unsettled` + auto-void on 91506 | **New feature** |
| `verify` | Fixed auth+void | `allow_card_verification` option for direct Braintree verify API | **New feature** |
| `store` | Basic | Bank account (Check) support + refactored flow | **Enhanced** |
| `credit` | Basic | Rejects Check payment methods | Minor |

### Key Differences
- **`setup_purchase` method added:** Returns a client token for client-side integration.
- **Braintree gem version:** Old requires `>= 2.4.0`, new requires `>= 2.0.0`.
- **`capture` supports partial capture** via `options[:partial_capture]` using `submit_for_partial_settlement`.
- **`capture` uses `localized_amount`** instead of `amount(money).to_s` for proper currency formatting.
- **`verify` redesigned:** New option `allow_card_verification: true` uses Braintree's native verify API instead of auth+void pattern.
- **`store` supports Check/bank accounts:** Bank accounts use `@braintree_gateway.us_bank_account` for nonce-based storage.
- **`refund` auto-voids unsettled:** When `force_full_refund_if_unsettled: true` and error 91506, auto-voids.
- **`authorize` rejects Check:** Returns direct error for Check payments.
- **`credit` rejects Check:** Returns direct error for Check payments.
- **Network token handling expanded:** Supports `apple_pay`, `android_pay`, and `google_pay` sources. Google Pay mapped to `android_pay_card` with additional fields.
- **New options in `create_transaction_parameters`:**
  - `options[:payment_method_nonce]` handling enhanced
  - `options[:transaction_source]` for recurring/moto/etc.
  - `options[:shipping_amount]`, `options[:discount_amount]`
  - `options[:shipping_address_id]`
  - `options[:three_d_secure]` (pass_thru support)
  - `options[:risk_data]`
  - `options[:skip_advanced_fraud_checking]`
  - `options[:venmo_sdk_payment_method_code]`
  - `options[:paypal_custom_field]`
  - Level 2/3 processing fields

### Wrapper Impact
- **HIGH IMPACT:** `capture` now uses `localized_amount` - currency-aware formatting.
- **MEDIUM IMPACT:** New `force_full_refund_if_unsettled` feature useful for wrapper.
- **LOW IMPACT:** `verify` with `allow_card_verification` is additive.
- **NOTE:** Braintree uses its own Ruby SDK, so API changes are more about SDK version than wire protocol.

---

## 4. CyberSource (`cyber_source.rb`)

**Magnitude of change: LARGE**

### Marshal.load Usage (Old Fork)
- **`build_refund_request` method (line 358):** Uses `Marshal.load(options[:payment_obj])` to deserialize the payment method for standalone refunds (when no authorization ID is provided). In the new upstream, this is completely removed. The new refund is purely reference-based using the authorization string.

### Architecture Notes
- **Both versions use SOAP API.** The CyberSource SOAP gateway class name is unchanged.
- **New upstream also has `CyberSourceRestGateway`** (`cyber_source_rest.rb`, 525 lines) - a separate REST API implementation. The SOAP version remains the primary.
- **XSD version:** Old `"1.121"` vs new `"1.201"` (test) / `"1.201"` (production).
- **File size:** Old 875 lines vs new 1440 lines - 65% larger.

### Method Signature Changes

| Method | Old Fork | New Upstream | Breaking? |
|--------|----------|-------------|-----------|
| `authorize` | Basic | `valid_payment_method?` check; enhanced NT/wallet handling | Enhanced |
| `purchase` | Basic | `valid_payment_method?` check | Enhanced |
| `refund` | `Marshal.load` or reference-based | **Reference-only** (no payment_obj) | **Breaking** |
| `verify` | Fixed 100 amount | `eligible_for_zero_auth?` for $0 auth support | Enhanced |
| `credit` | Basic | `setup_address_hash` added | Minor |
| `store` | Basic | `valid_payment_method?` check | Enhanced |
| **NEW:** `adjust` | N/A | Adjust authorization amount | New method |
| `reverse` | Exists | Removed as separate method | **Breaking** |

### Key New Features
- **3DS2 support:** Full `add_threeds_2_ucaf_data` with `ucafCollectionIndicator`, `ucafAuthenticationData` fields.
- **3DS exemptions:** `THREEDS_EXEMPTIONS` mapping for low_value, trusted_merchant, etc.
- **Apple Pay / Google Pay:** Explicit `@@wallet_payment_solution` mapping (`apple_pay: '001'`, `google_pay: '012'`).
- **Network tokens:** `NT_PAYMENT_SOLUTION` mapping per brand, `add_network_tokenization` significantly enhanced with multi-brand support.
- **ECI/brand mapping:** `ECI_BRAND_MAPPING` for automatic commerceIndicator selection.
- **Stored credentials:** Full `add_stored_credential_options` with COF, recurring, installment support.
- **`decision_codes`:** Now includes `REVIEW` as potential success alongside `ACCEPT`.
- **Supported card types expanded:** Added `diners_club`, `jcb`, `dankort`, `maestro`, `elo`, `patagonia_365`, `tarjeta_sol`.
- **Supported countries expanded:** Added `AE`, `BR`, `IN`, `PK`.
- **Partner solution ID:** Added `add_partner_solution_id` for Spreedly integration.
- **Merchant category code:** `add_merchant_category_code` support.

### Refund Changes (Critical)
**Old fork `build_refund_request`:**
```ruby
if options.include?(:payment_obj)
  check_or_credit_card = Marshal.load(options[:payment_obj])
  # ... uses deserialized card for standalone refund
else
  # reference-based refund using authorization string
end
```

**New upstream `build_refund_request`:**
```ruby
order_id, request_id, request_token = identification.split(';')
options[:order_id] = order_id
# Purely reference-based, no payment_obj support
add_purchase_data(xml, money, true, options)
add_credit_service(xml, request_id:, request_token:, ...)
```

### Wrapper Impact
- **CRITICAL:** `Marshal.load(options[:payment_obj])` removed from refund. The wrapper must ensure all refunds are reference-based (using the authorization string from the original transaction).
- **HIGH IMPACT:** New `valid_payment_method?` check may reject some payment types that were previously accepted.
- **HIGH IMPACT:** `reverse` method removed - must use `void` instead.
- **MEDIUM IMPACT:** 3DS2 data must be passed via `options[:three_d_secure]` hash.
- **MEDIUM IMPACT:** Decision codes now accept REVIEW as success.

---

## 5. Litle (`litle.rb`)

**Magnitude of change: MODERATE**

### Naming / Branding
- **Old fork:** `display_name = 'Litle & Co.'`, `homepage_url = 'http://www.litle.com/'`
- **New upstream:** `display_name = 'Vantiv eCommerce'`, `homepage_url = 'https://www.fisglobal.com/'`
- **Class name unchanged:** Still `LitleGateway` in both versions.
- **NOTE:** There are separate `VantivExpressGateway` and `VantivOnlineSystemsGateway` files in the new upstream, but those are different gateways.
- **Schema version:** Old `'9.4'` vs new `version '9.14'`.

### Marshal.load Usage (Old Fork)
- **`refund` method (line 96):** Uses `Marshal.load(options[:payment_obj])` to deserialize the payment method for standalone refunds. In the new upstream, the refund method is completely rewritten and no longer uses `Marshal.load`.

### Method Signature Changes

| Method | Old Fork | New Upstream | Breaking? |
|--------|----------|-------------|-----------|
| `initialize` | Accepts `user` alias for `login` | Requires `login` directly (no alias) | **Breaking** |
| `purchase` | Sets `kind = :echeckSales` for checks | Returns different kind: `commit(:echeckSales, ...)` vs `commit(:sale, ...)` | Refactored |
| `authorize` | Raises on eCheck | Supports eCheck via `echeckVerification` | **New feature** |
| `capture` | Raises on missing auth, `foreignRetailerIndicator` | Simplified, no `foreignRetailer` option | Minor |
| `refund` | `Marshal.load` + reference-based | **Payment object or reference-based** (no Marshal) | **Breaking** |
| `void` | Same pattern | Same pattern | No |
| `store` | Basic | eCheck token support via `echeckForToken` | Enhanced |

### Refund Changes (Critical)
**Old fork `refund`:**
```ruby
if options.include?(:payment_obj)
  payment_method = Marshal.load(options[:payment_obj])
  # Uses deserialized payment_method for standalone refund
else
  doc.litleTxnId(transaction_id)
  doc.amount(money) if money
end
```

**New upstream `refund`:**
```ruby
if payment.is_a?(String)
  transaction_id, = split_authorization(payment)
  doc.litleTxnId(transaction_id)
  doc.amount(money) if money
elsif check?(payment)
  add_echeck_purchase_params(doc, money, payment, options)
else
  add_credit_params(doc, money, payment, options)  # uses credit_card directly
end
```
The new upstream accepts the payment method directly as the second argument (not via Marshal), or falls back to reference-based refund via authorization string.

### Key New Features
- **Level 2 data:** `add_level_two_data` for Visa/Mastercard (sales_tax, customer_code, etc.).
- **Level 3 data:** `add_level_three_data` with per-brand line item detail (Visa vs Mastercard formats).
- **Stored credentials:** `add_stored_credential_params` with initial/subsequent COF, recurring, installment.
- **`postlive_url`:** New URL endpoint option.
- **Google Pay support:** `orderSource('androidpay')` for Google Pay tokens.
- **3DS support:** `cardholderAuthentication` with `cavv` and `xid` from options when `order_source` starts with `3ds`.
- **Fraud filter override:** `add_fraud_filter_override` option.
- **Success codes expanded:** Old `['000']` vs new `['000', '001', '010', '136', '470', '473']`.
- **eCheck authorize:** Now supported via `echeckVerification` instead of raising an error.
- **`check?` helper:** Centralized check detection.

### Wrapper Impact
- **CRITICAL:** `Marshal.load(options[:payment_obj])` removed from refund. The wrapper must pass the payment method directly as the second argument to `refund`, or pass the authorization string.
- **HIGH IMPACT:** `initialize` no longer aliases `:user` to `:login`. Wrapper must pass `:login` directly.
- **MEDIUM IMPACT:** eCheck authorize now works (no longer raises).
- **MEDIUM IMPACT:** New success codes (001, 010) mean some previously-failed transactions may now succeed.

---

## 6. Orbital (`orbital.rb`)

**Magnitude of change: VERY LARGE**

### Marshal.load Usage (Old Fork)
- **`refund` method (line 202):** Uses `Marshal.load(options[:payment_obj])` to deserialize payment methods for standalone (non-reference) refunds. The new upstream completely removes this pattern.

### Architecture Changes
- **File size:** Old 890 lines vs new 1400+ lines.
- **New module:** `include OrbitalCodes` extracts AVS/CVV codes to separate file.
- **API version:** Old `"5.6"` vs new `version '9.5'`.
- **`currencies_without_fractions` removed** from old (was present but defined differently).

### Method Signature Changes

| Method | Old Fork | New Upstream | Breaking? |
|--------|----------|-------------|-----------|
| `authorize` | `build_new_order_xml` with block | `build_new_auth_purchase_order` - separate method | **Refactored** |
| `purchase` | `build_new_order_xml` with block | `build_new_auth_purchase_order` + force_capture support | Enhanced |
| `refund` | `Marshal.load` + reference-based | `options[:payment_method]` directly | **Breaking** |
| `credit` | Deprecated alias for refund | Standalone credit method (builds new order) | **New method** |
| `void` | Same pattern | Same pattern | No |
| `verify` | Fixed 100 amount | `verify_amount` option + zero-auth by brand | Enhanced |
| **NEW:** `store` | N/A | Uses `authorize(0, ...)` with `GET_TOKEN` flag | **New method** |

### Refund Changes (Critical)
**Old fork `refund`:**
```ruby
if options.include?(:payment_obj)
  payment_method = Marshal.load(options[:payment_obj])
  add_payment(xml, payment_method, options)
  add_address(xml, payment_method, options)
else
  raise ArgumentError unless authorization.present?
end
```

**New upstream `refund`:**
```ruby
payment_method = options[:payment_method]
order = build_new_order_xml(REFUND, money, payment_method, options.merge(authorization:)) do |xml|
  add_payment_source(xml, payment_method, options)
  # ...
end
```
Uses `options[:payment_method]` directly (a CreditCard or Check object).

### Key New Features
- **SafeTech tokenization:** `GET_TOKEN` / `USE_TOKEN` flags for token-based transactions.
- **`store` method:** Zero-auth with token generation.
- **`credit` method:** Standalone credit (not just deprecated alias).
- **3DS support:** `add_eci`, `add_cavv`, `add_xid`, `add_aav` methods for 3D Secure data from `options[:three_d_secure]` hash.
- **Level 2 data:** `add_level2_tax`, `add_level2_advice_addendum`.
- **Network tokenization:** `add_dpan`, `add_digital_wallet` methods.
- **eCheck enhancements:** `add_echeck` with more options, `force_capture_with_echeck?` handling.
- **Retry logic enhanced:** `@use_secondary_url` state tracking.
- **MIT/CIT indicators:** `add_mit_stored_credentials`, `add_managed_billing_mit` for stored credential flows.
- **Verify with zero-auth:** Brand-specific zero-auth support (Discover excluded).
- **Payment source refactored:** `add_payment_source` replaces direct `add_payment` + handles tokens.

### Wrapper Impact
- **CRITICAL:** `Marshal.load(options[:payment_obj])` removed. The wrapper must pass `options[:payment_method]` as a CreditCard/Check object for standalone refunds.
- **HIGH IMPACT:** `authorize`/`purchase` now use `build_new_auth_purchase_order` instead of inline block pattern. The payment source handling is refactored.
- **HIGH IMPACT:** API version jump from 5.6 to 9.5 - significant protocol changes.
- **MEDIUM IMPACT:** New `store` method available.
- **MEDIUM IMPACT:** `commit` signature changed - now accepts `options` hash instead of `trace_number`.

---

## 7. Worldpay (`worldpay.rb`)

**Magnitude of change: VERY LARGE**

### Marshal.load Usage (Old Fork)
- **Not used.** Worldpay gateway does not use `Marshal.load` in either version.

### Architecture Changes
- **File size:** Old 398 lines vs new 1400+ lines - a 3.5x increase.
- **Supported countries:** Expanded from ~30 to 200+ countries.
- **Supported card types:** Added `elo`, `naranja`, `cabal`, `unionpay`, `patagonia_365`, `tarjeta_sol`.
- **Currencies expanded:** Added `currencies_with_three_decimal_places` support.
- **Builder changed:** Old uses `Builder::XmlMarkup`, new uses `Nokogiri::XML::Builder` in some places.

### Method Signature Changes

| Method | Old Fork | New Upstream | Breaking? |
|--------|----------|-------------|-----------|
| `purchase` | Auth + capture MultiResponse | Same pattern + `skip_capture` option | Enhanced |
| `authorize` | Basic | `payment_details` pre-processing + AFT support | Enhanced |
| `capture` | Inquire + capture | Also accepts 'CAPTURED' in inquiry | Minor |
| `void` | Inquire + cancel | Same | No |
| `refund` | Inquire + refund | `force_full_refund_if_unsettled` + more status codes | Enhanced |
| `credit` | N/A | Full credit/payout support (fast_fund, AFT) | **New method** |
| `verify` | Fixed 100 | `eligible_for_0_auth?` for zero-auth | Enhanced |
| **NEW:** `store` | N/A | Token-based storage via `tokenScope` | **New method** |
| **NEW:** `inquire` | N/A | Public inquiry method | **New method** |

### Key New Features
- **Network tokens:** `NETWORK_TOKEN_TYPE` mapping for Apple Pay, Google Pay, generic network tokens.
- **3DS2 support:** Full 3DS2 data handling in authorization (`add_three_ds`, `add_3ds_flex` methods).
- **Stored credentials:** `add_stored_credentials` with `schemeTransactionIdentifier`, `transactionRiskData`.
- **`store` method:** Creates token-based payment profiles.
- **`credit` method:** Full payout support including fast fund credits and Account Funding Transactions (AFT).
- **`inquire` method:** Public order inquiry.
- **AVS/CVC code mapping:** `AVS_CODE_MAP` and `CVC_CODE_MAP` translate Worldpay codes to standard codes (old had no mapping).
- **Authorization format changed:** New upstream returns `"orderCode|@]|paymentId"` format vs old which returned just the order code.
- **`order_id_from_authorization` helper:** Extracts order ID from new compound authorization format.
- **Risk data:** `add_risk_data` with shopper info, device session.
- **FraudSight:** `add_fraud_sight_data` support.
- **Instalments:** `add_instalments` support.
- **HCG/Additional data:** Enhanced `add_additional_data` method.
- **Sub-merchant data:** `add_sub_merchant_data` for payment facilitator model.
- **Token details:** `add_token_details` for tokenized transactions.
- **`commit` method refactored:** Now takes `options` parameter, uses `Nokogiri` for XML building in some paths.
- **`eligible_for_0_auth?`:** Brand-specific zero-auth support.
- **Merchant code:** No longer falls back to `@options[:merchant_id]`; uses `@options[:login]` directly.

### Wrapper Impact
- **HIGH IMPACT:** Authorization format changed from simple `orderCode` to compound `"orderCode|@]|paymentId"`. The wrapper must handle both formats or be updated.
- **HIGH IMPACT:** `payment_details` pre-processing step added to `authorize` - handles network tokens, stored credentials extraction.
- **MEDIUM IMPACT:** `commit` method now takes an `options` hash parameter.
- **MEDIUM IMPACT:** `refund` now supports `force_full_refund_if_unsettled` (auto-voids unsettled).
- **LOW IMPACT:** AVS/CVC code mapping now produces standard codes.
- **NOTE:** `scrub` method renamed from `supports_scrubbing` (returning true) - method name unchanged but was already a method, not attribute.

---

## Summary: Marshal.load Removal Impact

| Gateway | Old Fork Method | New Upstream Replacement | Wrapper Change Required |
|---------|-----------------|-------------------------|------------------------|
| **authorize_net** | `normal_refund` via `options[:payment_obj]` | Use `options[:card_number]` or authorization-embedded card number | Pass card number in options |
| **cyber_source** | `build_refund_request` via `options[:payment_obj]` | Reference-only refunds via authorization string | Ensure all refunds are reference-based |
| **litle** | `refund` via `options[:payment_obj]` | Pass payment method object directly as 2nd arg | Pass CreditCard/Check object directly |
| **orbital** | `refund` via `options[:payment_obj]` | Pass payment method via `options[:payment_method]` | Pass CreditCard/Check in options hash |
| **stripe** | Not used | N/A | No change needed |
| **braintree_blue** | Not used | N/A | No change needed |
| **worldpay** | Not used | N/A | No change needed |

## Summary: New Gateway Files in Upstream

| File | Description |
|------|-------------|
| `stripe_payment_intents.rb` | Stripe Payment Intents API (inherits from StripeGateway) - for 3DS2/SCA |
| `cyber_source_rest.rb` | CyberSource REST API (separate from SOAP version) |
| `vantiv_express.rb` | Vantiv Express (different from Litle/Vantiv eCommerce) |
| `vantiv_online_systems.rb` | Vantiv Online Systems (may overlap with old fork's custom gateway) |

## Priority Ranking for Wrapper Updates

1. **CyberSource** - Marshal.load removal + 65% larger file + 3DS2 + stored credentials
2. **Orbital** - Marshal.load removal + API version 5.6->9.5 + refactored auth/purchase
3. **Litle** - Marshal.load removal + initialize change + refund rewrite
4. **Authorize.Net** - Marshal.load removal + many new options + billing address changes
5. **Worldpay** - Authorization format change + 3.5x file size increase + many new features
6. **Stripe** - API version change + Apple Pay removal + consider Payment Intents migration
7. **Braintree Blue** - Mostly additive changes; localized_amount in capture
