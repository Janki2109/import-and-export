-- BUG FIX (C12): document_handler.go / order_documents_screen.dart offer 6 document types
-- (commercial_invoice, packing_list, certificate_of_origin, bill_of_lading, air_waybill,
-- shipping_invoice) but the document_type enum (002_rfq_quotation_documents.sql) only had the
-- first 3, so generating any of the other 3 types failed at insert with an invalid-enum-value
-- error. Purely additive — existing values and rows are untouched.
ALTER TYPE document_type ADD VALUE IF NOT EXISTS 'bill_of_lading';
ALTER TYPE document_type ADD VALUE IF NOT EXISTS 'air_waybill';
ALTER TYPE document_type ADD VALUE IF NOT EXISTS 'shipping_invoice';
