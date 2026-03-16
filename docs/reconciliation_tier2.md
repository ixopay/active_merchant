# Tier 2 Gateway Reconciliation Report

Comparison of OLD fork (v1.64.0) vs NEW upstream (v1.137.0) for medium-complexity gateways.

Focus: API differences that require PaymentGateway_New wrapper changes.

---

## 1. Element Gateway

**Class name:** `ElementGateway` (unchanged)
**File:** `element.rb`

### Marshal.load Usage

**None** in old fork. Element gateway does NOT use `Marshal.load(options[:payment_obj])`.

### Initialize - BREAKING CHANGE

| Aspect | Old Fork | New Upstream |
|--------|----------|--------------|
| Required options | `:acctid, :password, :merchant_id` | `:account_id, :account_token, :application_id, :acceptor_id, :application_name, :application_version` |
| TokenEx defaults | Hard-coded `TOKENEX_ID`, `TOKENEX_APP`, `TOKENEX_VER` as fallback application_id/name/version | **Removed** -- all six params are now required |

**Impact:** The wrapper must change credential key names:
- `:acctid` --> `:account_id`
- `:password` --> `:account_token`
- `:merchant_id` --> `:acceptor_id`
- Must now explicitly pass `:application_id`, `:application_name`, `:application_version` (no longer auto-populated with TokenEx constants)

The old fork had TokenEx-specific constants (`TOKENEX_ID = '7714'`, `TOKENEX_APP = 'TokenEx'`, `TOKENEX_VER = '2.0'`). These are completely removed in upstream.

### Method Signature Changes

| Method | Old Fork | New Upstream | Breaking? |
|--------|----------|--------------|-----------|
| `purchase` | `(money, payment, options={})` | `(money, payment, options={})` | No |
| `authorize` | `(money, payment, options={})` | `(money, payment, options={})` | No |
| `capture` | `(money, authorization, options={})` | `(money, authorization, options={})` | No |
| `refund` | `(money, authorization, options={})` | `(money, authorization, options={})` | No |
| `void` | `(authorization, options={})` | `(authorization, options={})` | Behavior change (see below) |
| `store` | `(payment, options={})` | `(payment, options={})` | No |
| `verify` | `(credit_card, options={})` | `(credit_card, options={})` | Behavior change (see below) |
| `credit` | N/A | `(money, payment, options={})` | New method |
| `reverse` | `(money, authorization, payment, options)` | N/A | Removed |

### Void - BREAKING BEHAVIORAL CHANGE

- **Old:** Uses `CreditCardVoid` SOAP action.
- **New:** Uses `CreditCardReversal` SOAP action with `reversal_type: 'Full'`. This is a fundamentally different API call to the Element processor.
- The old fork had a separate `reverse` method; upstream merged reversal into `void`.

### Verify - BEHAVIORAL CHANGE

- **Old:** Uses `authorize(100)` + `void`, a two-step MultiResponse pattern.
- **New:** Uses `CreditCardAVSOnly` SOAP action as a single-step $0 verification.
- The wrapper behavior is simpler (single call), but the transaction type is different.

### New Features in Upstream

1. **`credit` method** -- Unreferenced credit via `CreditCardCredit` action.
2. **Network tokenization (Apple Pay / Google Pay)** -- `NetworkTokenizationCreditCard` support with `NETWORK_TOKEN_TYPE` mapping and `add_network_tokenization_card` method.
3. **Lodging data** -- `add_lodging(xml, options)` support on purchase/authorize via `options[:lodging]`.
4. **Enhanced transaction options** -- `merchant_supplied_transaction_id`, `payment_type`, `submission_type`, `duplicate_check_disable_flag`, `duplicate_override_flag`, `merchant_descriptor`.
5. **MarketCode** -- Old: always defaults to `"ECommerce"`. New: defaults to `"Default"` and conditionally included.

### Terminal/Options Changes

| Aspect | Old | New |
|--------|-----|-----|
| `add_terminal` signature | `(xml, options, payment = nil)` | `(xml, options)` -- payment param removed |
| CVV presence code | Dynamically checks `payment.verification_value` | Always `'UseDefault'` |
| Default CardPresentCode | `"NotPresent"` | `"UseDefault"` |
| Default CardholderPresentCode | `"ECommerce"` | `"UseDefault"` |
| Default CardInputCode | `"ManualKeyed"` | `"UseDefault"` |
| Default TerminalCapabilityCode | `"KeyEntered"` | `"UseDefault"` |
| Default TerminalEnvironmentCode | `"ECommerce"` | `"UseDefault"` |
| TerminalType | Always set, defaults to `"ECommerce"` | Only set if explicitly passed |
| PartialApprovedFlag | N/A | Supported |

### Address/Phone Field Name Changes

- Old: `address[:phone]` for billing, `shipping_address[:phone_number]` for shipping
- New: `address[:phone_number]` for both billing and shipping

### Response Parsing Changes

- Old: Fault handling code present -- parses SOAP Fault and constructs `expressresponsemessage` from faultcode/faultstring.
- New: Fault handling removed. Only parses `//response/*` and `//Response/*`.
- Old: `parse_element` was a separate method; New: inlined into `parse`.
- Old: Uses `begin/rescue ResponseError`; New: No rescue in commit.

### Cardholder Name

- Old: `payment.name` (single field)
- New: `"#{payment.first_name} #{payment.last_name}"` (explicit concat)

### eCheck Account Type

- Old: `payment.account_type if payment.account_type` (optional, raw)
- New: `payment.account_type.capitalize` (always set, capitalized)

### Service Live URL

- Old: `https://service.elementexpress.com/express.asmx`
- New: `https://services.elementexpress.com/express.asmx` (note the 's')

---

## 2. Elavon Gateway

**Class name:** `ElavonGateway` (unchanged)
**File:** `elavon.rb`

### Marshal.load Usage - PRESENT IN OLD FORK

- **`capture` method (line 122-125):** `Marshal.load(options[:payment_obj])` to get credit card for force-capture
- **`refund` method (line 156-159):** `Marshal.load(options[:payment_obj])` to get credit card, then delegates to `credit` method

### Initialize

No change in required params: `:login, :password`. The `:user` option remains optional.

### Protocol Change - MAJOR BREAKING CHANGE

- **Old:** Key-value pair POST with `process.do` endpoint, ASCII result format.
- **New:** XML-based POST with `processxml.do` endpoint, XML response parsing via Nokogiri.

This is a fundamental protocol change. The old fork uses simple form-encoded data; the new fork sends and receives XML.

### New Features in Upstream

1. **`ssl_vendor_id`** -- New required/optional field sent on every transaction.
2. **Network tokenization (Apple Pay / Google Pay)** -- `add_network_token` method handles `NetworkTokenizationCreditCard` via `ssl_applepay_web` / `ssl_google_pay`.
3. **Stored credentials** -- `add_stored_credential` with `ssl_oar_data`, `ssl_ps2000_data`, network transaction ID handling.
4. **`network_transaction_id`** in Response -- Built from `oar_data|ps2000_data`.
5. **Verify action** -- Old: `authorize(100) + void` two-step. New: Dedicated `CCVERIFY` transaction type (single step).
6. **Multi-currency support** -- `add_currency` method with `ssl_transaction_currency`.
7. **Level 3 data** -- `add_level_3_fields` with line items support.
8. **Custom fields** -- Arbitrary fields via `options[:custom_fields]`.
9. **Installment fields** -- `ssl_payment_number`, `ssl_payment_count`.
10. **Merchant initiated unscheduled** -- `ssl_merchant_initiated_unscheduled`.
11. **Scrubbing support** -- Added in upstream (not in old fork).
12. **`error_code`** -- New: `errorCode` field in Response.
13. **`money_format`** -- New: set to `:dollars`.
14. **`default_currency`** -- New: set to `'USD'`.
15. **Supported countries** -- Added `'MX'`.

### Capture - BREAKING CHANGE

- **Old:** Two code paths: with `payment_obj` (force capture) or without (completion). Uses `Marshal.load`.
- **New:** Two code paths: with `options[:credit_card]` (force capture) or without (completion). No `Marshal.load`.
- **Wrapper must change:** Instead of passing `options[:payment_obj]` (marshaled), pass `options[:credit_card]` (CreditCard object directly).

### Refund - BREAKING CHANGE

- **Old:** If `options[:payment_obj]` present, unmarshals and calls `credit`. Otherwise, uses transaction ID for `CCRETURN`.
- **New:** Always uses `CCRETURN` with transaction ID. No `payment_obj` path.
- **Wrapper must change:** Remove `payment_obj` marshaling. Use standard `refund(money, identification)`.

### Purchase - SIGNATURE CHANGE

- **Old `authorize`:** Always calls `add_creditcard`, does not support tokens.
- **New `authorize`:** Calls `add_payment(xml, payment_method, options)` which supports tokens, network tokens, and credit cards.

### Response Parsing

- **Old:** Plain text, pipe-delimited, keys stripped of `ssl_` prefix as strings.
- **New:** XML-parsed, keys as symbols with `ssl_` prefix stripped, values HTML-decoded.
- Response hash keys change from string to symbol (e.g., `response['result']` -> `response[:result]`).

### Authorization Format

- **Old:** `"approval_code;txn_id"` (always)
- **New:** For store actions, returns token directly. Otherwise `"approval_code;txn_id"` (same).

### Creditcard Method Signature

- **Old:** `add_creditcard(form, creditcard)` -- two params
- **New:** `add_creditcard(xml, creditcard, options)` -- three params (options for CVV handling)

---

## 3. FirstData E4 Gateway

**Class name:** `FirstdataE4Gateway` (unchanged)
**File:** `firstdata_e4.rb`

**Note:** Upstream also has `firstdata_e4_v27.rb` (a newer v27/v28 API version) and `payeezy.rb` (Payeezy JSON API). These are separate gateway classes, not replacements.

### Marshal.load Usage - PRESENT IN OLD FORK

- **`build_capture_or_credit_request` (line 201-203):** `Marshal.load(options[:payment_obj])` to add credit card data on capture/credit operations.
- **`refund` method (line 103):** Checks `options.include?(:payment_obj)` to choose `:open_credit` vs `:credit` action.

### Initialize

No change: `:login, :password` required.

### Method Changes

| Method | Old Fork | New Upstream | Notes |
|--------|----------|--------------|-------|
| `authorize` | Zero-amount redirects to `verify` | Direct call, no $0 redirect | Old: `if money == 0 then verify`. New: always authorization. |
| `refund` | Checks `options[:payment_obj]` for `:open_credit` vs `:credit` | Always `:credit` | `payment_obj` path removed |
| `build_capture_or_credit_request` | Has `Marshal.load(options[:payment_obj])` + `add_credit_card` | No payment_obj, no add_credit_card on capture/credit | Major change |

### Authorize - BEHAVIORAL CHANGE

- **Old:** `authorize(0, card)` automatically redirects to `verify` method.
- **New:** `authorize(0, card)` sends a $0 authorization. No implicit redirect.

### Refund - BREAKING CHANGE

- **Old:** If `options[:payment_obj]` present, uses `:open_credit` (unreferenced credit). Otherwise `:credit` (referenced).
- **New:** Always uses `:credit` (referenced). No unreferenced credit path.
- **Wrapper must change:** Remove `payment_obj` option. If unreferenced credits needed, handle differently.

### Build Request - NAMESPACE ADDED

- **Old:** `xml.tag! "Transaction" do` (no namespace)
- **New:** `xml.tag! 'Transaction', xmlns: 'http://secure2.e-xact.com/vplug-in/transaction/rpc-enc/encodedTypes' do`

### Credit Card ECI Handling - NEW

- **New:** `add_credit_card_eci` method added. Handles ECI for all cards (not just network tokens).
- Default ECI: `'07'`
- Special handling for Discover + Apple Pay (ECI forced to `'04'`)
- ECI is now always sent via `Ecommerce_Flag`.

### Credit Card Verification Strings

- **Old:** If network token, calls `add_network_tokenization_credit_card`. If CVV present, sends CVD. Also sends `add_card_authentication_data`.
- **New:** Same pattern, but `add_card_authentication_data` is only sent for non-network-token cards. ECI is set separately via `add_credit_card_eci`.

### Network Tokenization

- **Old:** Visa/Mastercard: sends XID + CAVV. Amex: splits cryptogram.
- **New:** Amex: same split. All others (not just Visa/MC): sends XID + CAVV. Simplified with `else` clause.

### Credit Card Token - OPTIONS ADDED

- **Old:** `add_credit_card_token(xml, store_authorization)` -- two params
- **New:** `add_credit_card_token(xml, store_authorization, options)` -- three params, also calls `add_card_authentication_data(xml, options)`

### Build Capture/Credit Request

- **Old:** Has `add_identification` (conditional on `identification.present?`), then `add_amount`, `add_customer_data`, `add_invoice`, `add_card_authentication_data`, then `Marshal.load` path.
- **New:** Has `add_identification` (unconditional), `add_amount`, `add_customer_data`, `add_card_authentication_data`. No `add_invoice`, no `Marshal.load`.

### Amount Handling - BREAKING CHANGE

- **Old:** Only sends Currency if `options[:currency]` is explicitly set. Defaults to `amount(money)` without currency.
- **New:** Always sends Currency (defaults to `default_currency`). Always uses `localized_amount`.

### Scrubbing

- **Old:** Scrubs Card_Number and VerificationStr2 only.
- **New:** Also scrubs Password, CAVV, and Card Number patterns in error responses.

### Address Handling

- **Old:** `add_credit_card_verification_strings` uses `[:address1, :zip, :city, :state, :country]` with `to_s` join.
- **New:** Same keys but strips `\r\n` characters: `address[part].to_s.tr("\r\n", ' ').strip`.

### Related: Payeezy Gateway (Separate Class)

The upstream `payeezy.rb` is a completely different gateway (`PayeezyGateway`) using:
- JSON API (not XML)
- Different credentials: `:apikey, :apisecret, :token`
- Different authorization format: `"transaction_id|transaction_tag|method|amount"`
- Different endpoint: `api.payeezy.com`
- Supports 3DS, stored credentials, eCheck

This is NOT a replacement for FirstdataE4Gateway but rather an alternative modern API.

### Related: FirstdataE4V27Gateway (Separate Class)

The upstream `firstdata_e4_v27.rb` is a v27/v28 API version with JSON instead of XML. Different credential model (HMAC-based auth). This is also a separate class, not a replacement.

---

## 4. Moneris Gateway

**Class name:** `MonerisGateway` (unchanged)
**File:** `moneris.rb`

### Marshal.load Usage

**None** in old fork's `moneris.rb`. However, the old fork's `moneris_us.rb` DOES use `Marshal.load(options[:payment_obj])` in `refund`.

### Initialize

| Aspect | Old Fork | New Upstream |
|--------|----------|--------------|
| crypt_type default | `options = { :crypt_type => 7 }.merge(options)` | `options[:crypt_type] = 7 unless options.has_key?(:crypt_type)` |

Functionally equivalent but different implementation. The new version won't overwrite an explicit `nil` value.

### Authorize/Purchase - CHANGES

- **Old:** Action selected by `post[:cavv]` presence. Passes `commit(action, post)`.
- **New:** Action selected by `post[:cavv] || options[:three_d_secure]`. Passes `commit(action, post, options)`.
- **New:** Adds `add_external_mpi_fields(post, options)`, `add_stored_credential(post, options)`, `add_cust_id(post, options)`.
- **New:** `post[:order_id]` uses `format_order_id(post[:wallet_indicator], options[:order_id])` for wallet truncation.

### Verify - BREAKING CHANGE

- **Old:** `authorize(100) + void` two-step MultiResponse.
- **New:** Dedicated `card_verification` or `res_card_verification_cc` action (single step). Requires `:order_id`.

### Store - NEW FEATURES

- **New:** Supports temporary tokens via `options[:duration]` using `res_temp_add` action.
- **New:** Supports address and stored credentials on store.

### New Features in Upstream

1. **3DS2 support** -- `add_external_mpi_fields` with `threeds_version`, `threeds_server_trans_id`, `ds_trans_id`, `cavv`. Overrides `crypt_type` with ECI.
2. **Stored credentials (COF)** -- `add_stored_credential` with `payment_indicator`, `payment_information`, `issuer_id` via `cof_info` XML element.
3. **Wallet indicators** -- Apple Pay (`APP`), Google Pay (`GPP`), Android Pay (`ANP`) via `wallet_indicator` method.
4. **Network tokenization** -- Sends `wallet_indicator` and `crypt_type` from ECI.
5. **CAVV result code validation** -- `successful?` now checks `cavv_result_code == '2'` for 3DS transactions.
6. **Order ID formatting** -- Wallet transactions truncate order_id to 100 characters.
7. **`cof_info` element** -- Credential-on-file XML element for purchase/preauth/store/verify/update actions.

### Commit - SIGNATURE CHANGE

- **Old:** `commit(action, parameters = {})`
- **New:** `commit(action, parameters = {}, options = {})` -- accepts options for 3DS handling.

### Success Check - CHANGED

- **Old:** `successful?(response)` -- checks response_code, complete, 0..49 range.
- **New:** `successful?(action, response, threed_ds_transaction = false)` -- additional CAVV result code check for 3DS.

### Actions Hash - EXPANDED

New actions added:
- `card_verification` -- for verify
- `res_temp_add` -- for temporary vault tokens
- `res_card_verification_cc` -- for token-based verify
- Actions now include `:cof_info` element in ordering

### MonerisUS Gateway - OLD FORK ONLY

The old fork has `moneris_us.rb` (separate US gateway) with `Marshal.load` in `refund`. The new upstream does NOT have `moneris_us.rb` -- it was removed. If the wrapper uses MonerisUS, this is a significant gap.

---

## 5. Payflow Gateway

**Class name:** `PayflowGateway` (unchanged)
**File:** `payflow.rb` + `payflow/payflow_common_api.rb`

### Marshal.load Usage

**None** in old fork. Payflow does NOT use `Marshal.load(options[:payment_obj])`.

### Initialize

No change in required params: `:login, :password` (via PayflowCommonAPI).

### Verify - BEHAVIORAL CHANGE

- **Old:** Always `authorize(0, payment, options)`.
- **New:** For Amex cards, uses `authorize(100) + void` MultiResponse. Non-Amex: `authorize(0)`.

### Store - NEW (sort of)

- **New:** `store` method exists but raises `ArgumentError, 'Store is not supported on Payflow gateways'`.

### Credit Card Handling - CHANGES

- **Old:** `add_credit_card` includes `BuyerAuthResult` block for `options[:three_d_secure]` AND a separate `options[:cavv]` block. Start date/issue number handling for Switch/Solo cards.
- **New:** `add_credit_card` calls `add_three_d_secure(options, xml)` for 3DS. No start date/issue number (Switch/Solo removed from CARD_MAPPING). No `options[:cavv]` fallback block.

### 3DS Handling - MAJOR CHANGES

**Old fork (inline in add_credit_card):**
- Reads from `options[:three_d_secure]` hash with keys: `:status, :authentication_id, :pareq, :acs_url, :eci, :cavv, :xid`
- Also has separate `options[:cavv]` + `options[:eci]` + `options[:xid]` fallback

**New upstream (two separate paths):**

1. **`add_three_d_secure`** (inside Card/BuyerAuthResult): Handles both 3DS1 and 3DS2 with `ThreeDSVersion`, `DSTransactionID`, `AuthenticationStatus`, `authentication_response_status`, `directory_response_status`.
2. **`add_mpi_3ds`** (ExtData-based MPI, outside Card): Alternative MPI path using `AUTHENTICATION_ID`, `AUTHENTICATION_STATUS`, `CAVV`, `ECI`, `XID`, `THREEDSVERSION`, `DSTRANSACTIONID` as ExtData elements.

**Impact:** If the wrapper passes 3DS data, the key names and structure differ.

### Stored Credentials - NEW

- **New:** `add_stored_credential(xml, options[:stored_credential])` method. Sends `CardOnFile` (MIT/CIT + reason) and `TxnId` (network_transaction_id).
- Called in `build_credit_card_request`, `build_reference_sale_or_authorization_request`, `build_check_request`, and `recurring`.

### New Features in Upstream

1. **Stored credentials** -- COF support as described above.
2. **3DS2 support** -- Full 3DS 2.x with directory server transaction ID, version field.
3. **MPI 3DS** -- Separate ExtData-based 3DS path for external MPI.
4. **Level 2/3 data** -- `add_level_two_three_fields` using Nokogiri XML manipulation with JSON field input.
5. **Scrubbing** -- `supports_scrubbing?` and `scrub` methods added.
6. **OrderDesc** -- New `options[:order_desc]` field.
7. **MerchDescr** -- New `options[:merch_descr]` (merchant descriptor) on both reference and credit card requests.
8. **Email** -- New `options[:email]` in credit card request Invoice.
9. **BUTTONSOURCE** -- Application ID sent as ExtData on all transactions.
10. **CAPTURECOMPLETE** -- New capture-complete flag in reference requests.
11. **Street2** -- Address now supports `:address2` via `Street2` element.
12. **PayPal NVP** -- `use_paypal_nvp` class attribute for direct PayPal routing with `PAYPAL-NVP` header.

### PayflowCommonAPI Changes

| Aspect | Old | New |
|--------|-----|-----|
| CARD_MAPPING | Includes `:switch` and `:solo` | Removed Switch/Solo |
| `build_reference_request` | Basic invoice (TotalAmt, Description, Comment, Comment2) | Also adds `MerchDescr` and `CAPTURECOMPLETE` ExtData |
| `add_address` | No Street2 | Adds `Street2` for address2 |
| `build_headers` | Fixed headers | Adds conditional `PAYPAL-NVP` header |

### Invoice Fields - EXPANDED

New options in credit card and reference requests:
- `options[:order_desc]` -> `OrderDesc`
- `options[:merch_descr]` -> `MerchDescr`
- `options[:email]` -> `EMail` (credit card request)
- `options[:capture_complete]` -> `CAPTURECOMPLETE` ExtData (reference request)

---

## Summary: Wrapper Impact Matrix

| Gateway | Marshal.load in Old? | Credential Changes? | Protocol Changes? | 3DS Added? | Stored Creds? | Verify Changed? |
|---------|---------------------|--------------------|--------------------|------------|---------------|-----------------|
| Element | No | **YES - key names** | No (still SOAP) | Network tokens | No | Yes (AVS-only) |
| Elavon | **YES** (capture, refund) | No | **YES (KV->XML)** | Apple/Google Pay | Yes | Yes (CCVERIFY) |
| FirstData E4 | **YES** (capture/credit) | No | Namespace added | Enhanced NTK | No | Behavior change |
| Moneris | No (but MonerisUS YES) | Minor | No | 3DS2, wallets | Yes (COF) | Yes (dedicated) |
| Payflow | No | No | No | 3DS2, MPI | Yes (COF) | Amex special |

### Priority Actions for PaymentGateway_New Wrapper

1. **Elavon:** Remove `Marshal.load` from capture/refund. Change capture to pass `options[:credit_card]` directly. Refund no longer needs payment_obj path. Update to XML protocol.

2. **FirstData E4:** Remove `Marshal.load` from `build_capture_or_credit_request`. Remove `:open_credit` path from refund. Handle new namespace in request XML.

3. **Element:** Update credential key mapping (`:acctid` -> `:account_id`, etc.). Remove TokenEx-specific constants. All six credential fields now required.

4. **Moneris:** Update `commit` call signature (add options parameter). If using MonerisUS, note it's been removed from upstream. Update verify to pass `:order_id`.

5. **Payflow:** Mostly backward-compatible. Watch for Amex verify behavior change. Update 3DS option keys if passing 3DS data.
