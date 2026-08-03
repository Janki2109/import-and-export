-- Journey 2 (KYC): Razorpay Fund Account creation on approval needs a bank account (account
-- number + IFSC + holder name) to link payouts to — this was never captured anywhere. Purely
-- additive columns on the existing kyc_details table; nullable, so every existing row and every
-- existing read/write path keeps working exactly as before.
ALTER TABLE kyc_details ADD COLUMN IF NOT EXISTS bank_account_holder_name VARCHAR(200);
ALTER TABLE kyc_details ADD COLUMN IF NOT EXISTS bank_account_number VARCHAR(34);
ALTER TABLE kyc_details ADD COLUMN IF NOT EXISTS bank_ifsc VARCHAR(11);
