-- Bank verification can now rest on an uploaded document (cancelled cheque / passbook /
-- statement) alone rather than requiring account number + IFSC to be typed in — see
-- kyc_screen.dart. Purely additive, nullable column.
ALTER TABLE kyc_details ADD COLUMN IF NOT EXISTS bank_doc_url TEXT;
