-- Admin KYC review needs a distinct "needs re-upload" outcome, separate from an outright
-- rejection: the admin is asking for a corrected/clearer document, not closing the case out.
ALTER TYPE kyc_status ADD VALUE IF NOT EXISTS 'needs_reupload';
