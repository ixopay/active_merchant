# Tier 1 Gateway Reconciliation Report

Comparison of old fork (v1.64.0) vs new upstream fork (v1.137.0) for simple gateways.

**Legend:**
- OLD = `/Users/lsmith/Documents/GitHub/ActiveMerchant_old/lib/active_merchant/billing/gateways/`
- NEW = `/Users/lsmith/Documents/GitHub/active_merchant/lib/active_merchant/billing/gateways/`

**Marshal.load Summary:** None of the 7 Tier 1 gateways use `Marshal.load(options[:payment_obj])`. The merchant_e_solutions gateway has `options.delete(:payment_obj)` in `refund` and `void` (cleanup only, not deserialization).

---

## 1. NMI (`nmi.rb`)

**Both versions exist. Significant changes in upstream.**

### Initialize
- **OLD:** `requires!(options, :login, :password)`
- **NEW:** Supports alternative auth via `:security_key`. If `options.has_key?(:security_key)`, only that is required; otherwise `:login, :password` are required.
- **Wrapper impact:** None if wrapper continues to pass `:login` and `:password`. New option available if needed.

### Method Signatures
All public method signatures are identical: `purchase`, `authorize`, `capture`, `void`, `refund`, `credit`, `verify`, `store`.

### New Features in Upstream
1. **Network tokenization support** (`supports_network_tokenization?` returns `true`). New `add_network_token_fields` method handles Apple Pay, Google Pay, and generic network tokens.
2. **Stored credentials** (`add_stored_credential`): Supports `options[:stored_credential]` with `initiator`, `reason_type`, `initial_transaction`, `network_transaction_id`.
3. **3D Secure** (`add_three_d_secure`): Supports `options[:three_d_secure]` with `cavv`, `xid`, `version`, `ds_transaction_id`, `authentication_response_status`.
4. **Level 3 fields** (`add_level3_fields`): `tax`, `shipping`, `ponumber` from options.
5. **Vendor data** (`add_vendor_data`): `vendor_id`, `processor_id` from options.
6. **Customer vault data** (`add_customer_vault_data`): `customer_vault`, `customer_vault_id` from options.
7. **Surcharge support** in `add_invoice`: `options[:surcharge]`.
8. **Industry indicator**: `options[:industry_indicator]`.
9. **Descriptor fields**: `options[:descriptors]` hash with `descriptor`, `descriptor_phone`, etc.
10. **Shipping name splitting**: Upstream splits `shipping_address[:name]` into `shipping_firstname`/`shipping_lastname`.
11. **Shipping email**: `options[:shipping_email]`.

### URL Change
- **OLD:** `https://secure.nmi.com/api/transact.php`
- **NEW:** `https://secure.networkmerchants.com/api/transact.php`
- **Wrapper impact: BREAKING.** Different endpoint URL. Verify this is the correct production URL for your merchant account.

### Supported Countries
- **OLD:** `['US']`
- **NEW:** `%w[US CA]` (added Canada)

### Response Handling Changes
- **OLD:** `commit` maps Auth.net emulator response fields (e.g., `response[:response_code_nmi]`, `response[:response_code]`, `response[:transaction_id]`, etc.) for backward compatibility. Success message: `"This transaction has been approved"`.
- **NEW:** `commit` does NOT do this Auth.net emulator mapping. Response hash contains raw NMI fields only. Success message: `"Succeeded"`.
- **Wrapper impact: BREAKING if wrapper reads mapped fields** like `response[:response_code]`, `response[:transaction_id]`, `response[:authorization_code]`, etc. These fields no longer exist in the response hash.

### Authorization Format
- **OLD:** `authorization_from(response, payment_type)` returns `"transactionid#payment_type"`.
- **NEW:** `authorization_from(response, payment_type, action)` -- for `add_customer` action, returns `"customer_vault_id#payment_type"` instead of `"transactionid#payment_type"`.
- **Wrapper impact:** Store operations will return a different authorization string (customer_vault_id instead of transactionid).

### Capture Change
- **OLD:** Raises `ArgumentError` if authorization missing.
- **NEW:** Does NOT raise ArgumentError (removed the guard).

### Refund Change
- **OLD:** Raises `ArgumentError` if authorization missing.
- **NEW:** Does NOT raise ArgumentError (removed the guard).

### Scrubbing
- **NEW** adds scrubbing for `security_key`, `cavv`, and `cryptogram` fields.

### Payment Method (String Token)
- **OLD:** `post[:customer_vault_id] = payment_method` (full string).
- **NEW:** Splits the authorization first: `customer_vault_id, = split_authorization(payment_method)` then uses just the ID portion.
- **Wrapper impact:** If wrapper passes raw vault IDs (not authorization strings with `#`), this should still work since split on `#` returns the original string if no `#` is present.

---

## 2. BluePay (`blue_pay.rb`)

**Both versions exist. Moderate changes in upstream.**

### Initialize
Identical: `requires!(options, :login, :password)`.

### Method Signatures
All public method signatures identical. No changes to `authorize`, `purchase`, `capture`, `void`, `refund`, `credit`, `recurring`, `status_recurring`, `update_recurring`, `cancel_recurring`.

### New Features in Upstream
1. **Stored credentials** (`add_stored_credential`): New method supports `options[:stored_credential]` with `initiator` (M/C) and `reason_type` (scheduled Y/N). Added to `authorize` and `purchase`.
2. **Customer IP**: `commit` now accepts `options` as 4th parameter and sends `CUSTOMER_IP` if `options[:ip]` present.
3. **Customer data fields**: `CUSTOM_ID` and `CUSTOM_ID2` are now sent (were commented out in old).
4. **REBILL_FIELD_MAP**: Added `'CUST_TOKEN' => :cust_token`.

### Breaking Changes

#### `commit` Method Signature
- **OLD:** `commit(action, money, fields)` (3 args)
- **NEW:** `commit(action, money, fields, options = {})` (4 args)
- All callers (authorize, purchase, capture, void, refund, credit) now pass `options` as 4th arg.
- **Wrapper impact:** Internal change only; not a public API change.

#### `add_version` Removed
- **OLD:** `add_version(post, options)` called in authorize, purchase, capture, void, refund.
- **NEW:** Method removed. `version` is set in `post_data` as `post[:version] = '1'` (hardcoded).
- **Wrapper impact:** `options[:version]` is no longer respected. Always sends version '1'.

#### Invoice Field Names
- **OLD:** `post[:INVOICE_ID] = options[:invoice_number]`
- **NEW:** `post[:INVOICE_ID] = options[:invoice]`, plus adds `post[:invoice_num] = options[:order_id]` and `post[:description] = options[:description]`.
- **Wrapper impact: BREAKING if wrapper passes `:invoice_number`.** Must change to `:invoice`.

#### Duplicate Override
- **OLD:** `post[:DUPLICATE_OVERRIDE] = options[:user_data_1]`
- **NEW:** `post[:DUPLICATE_OVERRIDE] = options[:duplicate_override]`
- **Wrapper impact: BREAKING if wrapper passes `:user_data_1` for duplicate override.** Must change to `:duplicate_override`.

#### Refund `DOC_TYPE` Option
- **OLD:** `post[:DOC_TYPE] = options[:option_flags] if options[:option_flags]`
- **NEW:** `post[:DOC_TYPE] = options[:doc_type] if options[:doc_type]`
- **Wrapper impact: BREAKING if wrapper passes `:option_flags`.** Must change to `:doc_type`.

#### Check Account Type
- **OLD:** `check.account_type.to_s.downcase` -- extra `.to_s.downcase`
- **NEW:** `check.account_type` -- no conversion
- **Wrapper impact:** Minor; check objects should already have string account types.

#### `supports_check?` Removed
- **OLD:** Has `supports_check?` method.
- **NEW:** Removed.
- **Wrapper impact:** If wrapper calls `gateway.supports_check?`, it will raise NoMethodError.

---

## 3. Sage (`sage.rb`)

**Both versions exist. Minimal changes.**

### Initialize
Identical: `requires!(options, :login, :password)`.

### Method Signatures
All public method signatures identical.

### Changes
1. **`supports_check?` removed** in upstream. Replaced by `supports_scrubbing?` (which was already present in old as well, just differently named -- old had it too).
2. **Scrubbing enhanced**: NEW adds scrubbing for `C_rte`, `C_acct`, and `C_ssn` fields (check routing/account numbers and SSN).
3. Minor style changes (symbol syntax, string quoting) throughout. No functional impact.

### Breaking Changes
- **`supports_check?` removed.** If wrapper calls this, it will fail.
- No other breaking changes. This gateway is essentially unchanged functionally.

---

## 4. iATS Payments (`iats_payments.rb`)

**Both versions exist. Significant changes in upstream.**

### Initialize
Functionally identical. NEW makes the deprecation warning for `:login` active (old had it commented out).

### Method Signatures
- `purchase`, `refund`, `store`, `unstore`: Signatures identical.
- No `authorize`, `capture`, or `void` in either version.

### New Features in Upstream
1. **Purchase with customer code**: NEW adds `purchase_customer_code` action type. If payment is a String, uses `ProcessCreditCardWithCustomerCode` action. OLD only supported Check vs CreditCard.
   - **Wrapper impact:** If wrapper passes a stored customer code string to `purchase`, OLD would have tried to use it as a credit card (likely erroring). NEW correctly routes to the customer code action.
2. **Customer details**: NEW adds `add_customer_details(post, options)` which sends `options[:email]`.
3. **Phone, email, country in address**: NEW adds `phone`, `email`, `country` from billing address.

### Breaking Changes

#### API Action Names (Version-less vs Versioned)
- **OLD actions:**
  - `ProcessCreditCardV1`, `ProcessACHEFTV1`, `ProcessCreditCardRefundWithTransactionIdV1`, `CreateCreditCardCustomerCodeV1`, `DeleteCustomerCodeV1`
- **NEW actions:**
  - `ProcessCreditCard`, `ProcessACHEFT`, `ProcessCreditCardRefundWithTransactionId`, `CreateCreditCardCustomerCode`, `DeleteCustomerCode`
- **Wrapper impact: BREAKING.** The SOAP action names have changed (removed `V1` suffix). This means the API endpoint URLs are different.

#### Endpoint Paths
- **OLD:** `ProcessLink.asmx`, `CustomerLink.asmx`
- **NEW:** `ProcessLinkv3.asmx`, `CustomerLinkv3.asmx`
- **Wrapper impact: BREAKING.** Different endpoint file paths. This is a newer API version.

#### Region Comparison
- **OLD:** `@options[:region].to_s.downcase == 'uk'`
- **NEW:** `@options[:region] == 'uk'` (no `.to_s.downcase`)
- **Wrapper impact:** Minor. If wrapper passes region as symbol `:uk`, it will no longer match in NEW.

#### Authorization Validation
- **OLD `refund`:** `raise ArgumentError.new("Missing required parameter: authorization") unless authorization.present?`
- **NEW `refund`:** No such guard.
- **Wrapper impact:** Errors will propagate differently for missing authorizations.

#### `successful_result_message?`
- **OLD:** `response[:authorization_result].start_with?('OK')` -- can raise NoMethodError if nil.
- **NEW:** `response[:authorization_result] ? response[:authorization_result].start_with?('OK') : false` -- nil-safe.

#### `supports_check?` Removed
- **OLD:** Has `supports_check?`.
- **NEW:** Removed.

#### Check Account Type
- **OLD:** `payment.account_type.to_s.upcase`
- **NEW:** `payment.account_type.upcase` (no `.to_s`)

---

## 5. Merchant e-Solutions (`merchant_e_solutions.rb`)

**Both versions exist. Moderate changes in upstream.**

### Initialize
Identical: `requires!(options, :login, :password)`.

### Method Signatures
All public method signatures identical, plus NEW adds `verify` method.

### Marshal.load / payment_obj
- **OLD:** Has `options.delete(:payment_obj)` in `refund` and `void` methods (cleanup, not deserialization).
- **NEW:** `options.delete(:payment_obj)` REMOVED from both `refund` and `void`.
- **Wrapper impact:** If the PaymentGateway_New wrapper passes `:payment_obj` in options, NEW will pass it through to the commit/post_data (previously it was deleted). This could cause unexpected form fields in the POST. Wrapper should stop sending `:payment_obj` in options.

### New Features in Upstream
1. **`verify` method**: NEW adds `verify(credit_card, options)` that commits action `'A'` with amount 0. Supports `store_card` option.
2. **Stored credentials** (`add_stored_credentials`): Supports `client_reference_number`, `moto_ecommerce_ind`, `recurring_pmt_num`, `recurring_pmt_count`, `card_on_file`, `cit_mit_indicator`, `account_data_source`.
3. **`store` method reworked**: OLD does a simple `commit('T', nil, post)`. NEW uses `MultiResponse.run` to do a temporary store followed by a verify with `store_card: 'y'`.

### Breaking Changes

#### Success Code Constant Name
- **OLD:** `SUCCESS_CODES = ["000", "085"].freeze`
- **NEW:** `SUCCESS_RESPONSE_CODES = %w(000 085)`
- **Wrapper impact:** None unless wrapper references the constant directly.

#### `store` Method Behavior
- **OLD:** Single `commit('T', nil, post)` call.
- **NEW:** Two-step: `temporary_store` (commit 'T') then `verify` (commit 'A' with store_card: 'y'). Returns a `MultiResponse`.
- **Wrapper impact: POTENTIALLY BREAKING.** The store response is now a `MultiResponse` object. The authorization comes from the verify step, not the store step. The wrapper may need to handle this differently.

#### `authorize` and `purchase` Customer Reference
- **OLD:** `post[:client_reference_number] = options[:customer]` and `post[:moto_ecommerce_ind] = options[:moto_ecommerce_ind]` set directly.
- **NEW:** These are set via `add_stored_credentials` which checks for `options[:client_reference_number]` (not `options[:customer]`).
- **Wrapper impact: BREAKING if wrapper passes `:customer` for client_reference_number.** The `options[:customer]` mapping for authorize/purchase is removed. Must use `options[:client_reference_number]` instead. Note: `capture` still uses `options[:customer]`.

#### `options.delete(:payment_obj)` Removal
- **OLD `refund`:** Deletes `:customer`, `:billing_address`, `:payment_obj`, `:amount` from options before merge.
- **NEW `refund`:** Deletes `:customer`, `:billing_address` only. Does NOT delete `:payment_obj` or `:amount`.
- **OLD `void`:** Same deletions as refund.
- **NEW `void`:** Same as new refund (no `:payment_obj`/`:amount` deletion).
- **Wrapper impact:** If wrapper sends `:payment_obj` or `:amount` in options, these will leak into the POST data in NEW. The `amount` leak could cause issues if the void/refund amount is controlled elsewhere.

#### Authorization From Response
- **OLD:** Always returns `response["transaction_id"]`.
- **NEW:** Returns `response["card_id"]` if present, otherwise `response["transaction_id"]`.
- **Wrapper impact:** Store operations will return `card_id` as the authorization instead of `transaction_id`.

#### Success Message
- **OLD:** Returns `"This transaction has been approved"` for any success code (000 or 085).
- **NEW:** Returns `"This transaction has been approved"` only for code `"000"`. For `"085"` (or other success codes), returns `response["auth_response_text"]`.

#### Scrubbing
- **OLD:** No `supports_scrubbing?` method.
- **NEW:** Adds `supports_scrubbing?` returning true, plus `scrub` method.

---

## 6. maxiPago (`maxipago.rb`)

**Both versions exist. Minimal changes.**

### Initialize
Identical: `requires!(options, :login, :password)`.

### Method Signatures
All public method signatures identical.

### Changes

#### `add_processor_id`
- **OLD:** `add_processor_id(xml, options)` -- accepts options, uses `options[:processor]` for live.
- **NEW:** `add_processor_id(xml)` -- no options param, uses `@options[:processor_id]` for live.
- **Wrapper impact: BREAKING if wrapper passes `:processor` in per-transaction options.** Must now pass `:processor_id` in gateway initialization options instead.

#### Capture Guard Removed
- **OLD:** `raise ArgumentError.new("Missing required parameter: authorization") unless authorization.present?`
- **NEW:** No guard.

#### Refund Guard Removed
- **OLD:** Same ArgumentError guard.
- **NEW:** No guard.

#### Commit Method
- **OLD:** `commit(action) { |doc| yield(doc) }`
- **NEW:** `commit(action, &block)` -- uses explicit block passing.
- **Wrapper impact:** None; functionally identical.

### Breaking Changes
- `add_processor_id` option key change: `:processor` (per-transaction) to `:processor_id` (gateway-level `@options`).
- Everything else is cosmetic/style changes only.

---

## 7. PaymentExpress (`payment_express.rb`)

**Both versions exist. Moderate changes in upstream.**

### Initialize
Identical: `requires!(options, :login, :password)`.

### Method Signatures
- `purchase`, `authorize`, `capture`, `store`, `credit`: Identical.
- `refund`: **NEW requires `options[:description]`** (`requires!(options, :description)`). OLD had this commented out.
- `void`: **REMOVED in NEW.** The TRANSACTIONS hash no longer includes `:void`.
- **NEW adds `verify`**: `verify(payment_source, options)` which does a validate transaction for $1.

### URL Changes
- **OLD live:** `https://sec.paymentexpress.com/pxpost.aspx`
- **NEW live:** `https://sec.windcave.com/pxpost.aspx`
- **OLD test:** `https://uat.paymentexpress.com/pxpost.aspx`
- **NEW test:** `https://uat.windcave.com/pxpost.aspx`
- **Wrapper impact:** URLs changed due to PaymentExpress rebranding to Windcave. Should be functionally equivalent (likely redirects in place), but worth noting.

### Breaking Changes

#### `void` Removed
- **OLD:** Has `void(authorization, options)` method and `:void => 'Void'` in TRANSACTIONS.
- **NEW:** `void` method completely removed. TRANSACTIONS hash does not include `:void`.
- **Wrapper impact: BREAKING.** If wrapper calls `void`, it will raise NoMethodError. Must handle void operations differently (possibly via refund).

#### `refund` Requires Description
- **OLD:** `options[:description]` is optional (requires! line was commented out).
- **NEW:** `requires!(options, :description)` is active.
- **Wrapper impact: BREAKING if wrapper does not pass `:description`.** Will raise ArgumentError.

#### Optional Elements Option Keys
- **OLD:** `normalized_client_type(options[:moto_ecommerce_ind])` and `options[:user_data_1]`, `options[:user_data_2]`, `options[:user_data_3]` for TxnData fields.
- **NEW:** `normalized_client_type(options[:client_type])` and `options[:txn_data1]`, `options[:txn_data2]`, `options[:txn_data3]`.
- **Wrapper impact: BREAKING.** Option key names changed:
  - `:moto_ecommerce_ind` -> `:client_type`
  - `:user_data_1` -> `:txn_data1`
  - `:user_data_2` -> `:txn_data2`
  - `:user_data_3` -> `:txn_data3`

#### IP Address Support
- **OLD:** No IP address forwarding.
- **NEW:** `add_ip(result, options)` sends `options[:ip]` as `ClientInfo` XML element. Added to purchase, authorize, capture, refund, store.

#### AVS Data Options
- **OLD:** `EnableAvsData` and `AvsAction` hardcoded to `1`.
- **NEW:** `EnableAvsData` uses `options[:enable_avs_data] || 1` and `AvsAction` uses `options[:avs_action] || 1`.
- **Wrapper impact:** New override capability, backward compatible (defaults to 1).

#### Start Date / Issue Number Removed
- **OLD:** `add_credit_card` checks `requires_start_date_or_issue_number?` and adds `DateStart` and `IssueNumber`.
- **NEW:** Removed. No support for start dates or issue numbers.
- **Wrapper impact:** Minor; these fields were for legacy card types (Maestro, Solo).

#### Authorization from Validate
- **OLD:** `response[:billing_id] || response[:dps_billing_id]`
- **NEW:** `response[:billing_id] || response[:dps_billing_id] || response[:dps_txn_ref]`
- **Wrapper impact:** Fallback to `dps_txn_ref` if no billing tokens available. More robust.

#### PaymentExpressResponse Token
- **OLD:** `@params["billing_id"] || @params["dps_billing_id"]`
- **NEW:** `@params['billing_id'] || @params['dps_billing_id'] || @params['dps_txn_ref']`
- **Wrapper impact:** Same fallback pattern as authorization.

#### Scrubbing
- **NEW** adds scrubbing for `PostPassword` field (was not scrubbed in OLD).

#### Display Name / Homepage
- **OLD:** `'PaymentExpress'` / `'http://www.paymentexpress.com/'`
- **NEW:** `'Windcave (formerly PaymentExpress)'` / `'https://www.windcave.com/'`

---

## Summary: Wrapper Impact Matrix

| Gateway | Breaking Changes | Severity | Key Actions Needed |
|---------|-----------------|----------|--------------------|
| **NMI** | URL change, response field mapping removed, auth format for store, success message text | HIGH | Update response field access; verify URL; handle new auth format for store |
| **BluePay** | Invoice option key, duplicate override key, doc_type key, add_version removed, supports_check? removed | MEDIUM | Update option key names; remove supports_check? calls |
| **Sage** | supports_check? removed | LOW | Remove supports_check? calls |
| **iATS** | API action names changed (V1 removed), endpoint paths (v3), supports_check? removed | HIGH | Likely transparent to wrapper (internal URL routing), but verify connectivity |
| **MerchantESolutions** | store is now MultiResponse, customer option key change, payment_obj no longer deleted, auth from store returns card_id | HIGH | Update store handling; change :customer to :client_reference_number for auth/purchase; stop passing :payment_obj |
| **maxiPago** | processor option moved from per-txn to gateway init | LOW | Move :processor to :processor_id in gateway init |
| **PaymentExpress** | void REMOVED, refund requires description, option keys renamed, URLs changed to Windcave | HIGH | Remove void calls; always pass description for refund; update option key names |
